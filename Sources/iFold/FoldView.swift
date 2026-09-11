import AppKit
import QuartzCore
import CoreVideo

/// The motion the desktop performs as the lid comes down. Each is a different
/// geometry for the same strip renderer; the spring, motion blur and frost
/// apply to all of them, so they share one feel.
enum FoldStyle: String, CaseIterable, Identifiable {
    case fold, curl, genie, notch, cube, scale, fade
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .fold:  return "Leans away from the hinge, like a sheet folding shut."
        case .curl:  return "The top edge rolls over and away, like a page curling toward the hinge."
        case .genie: return "Drawn down into the hinge, the way windows minimize into the Dock."
        case .notch: return "Pulled up into the notch — and back out when you open the lid."
        case .cube:  return "One face of a cube, turning with the lid."
        case .scale: return "Shrinks toward the hinge and settles into the dark."
        case .fade:  return "Dims and drains of colour, like a display drifting to sleep."
        }
    }
}

/// Everything the renderer needs for one frame.
struct FoldPose {
    var style: FoldStyle = .fold
    /// Degrees the picture leans away from the viewer at the top edge (Fold);
    /// the other styles read it as progress, 0 … `FoldPose.fullTilt`.
    var tilt: Double = 0
    /// 0 = rigid plank hinged at the bottom, 1 = flat at the hinge, curling to `tilt` at the top.
    var bend: Double = 0.5
    /// Strength of the lighting falloff on parts facing away (0–1).
    var shade: Double = 0.6
    /// Strength of the specular sweep (0–1).
    var sheen: Double = 1
    /// Vertical motion-blur radius in points (velocity driven).
    var motionBlur: Double = 0
    /// Static gaussian blur radius in points ("frost").
    var frost: Double = 0

    static let flat = FoldPose()
    /// Tilt at which every style has reached its final shape.
    static let fullTilt: Double = 80
    var progress: Double { min(1, max(0, tilt / Self.fullTilt)) }

    func isVisuallyEqual(to o: FoldPose) -> Bool {
        style == o.style && abs(tilt - o.tilt) < 0.004 && abs(bend - o.bend) < 0.001 && abs(shade - o.shade) < 0.001
            && abs(sheen - o.sheen) < 0.001 && abs(motionBlur - o.motionBlur) < 0.05 && abs(frost - o.frost) < 0.05
    }
}

/// Full-screen view that renders the captured desktop as a flexible sheet
/// anchored at the hinge (bottom edge of the screen).
///
/// Layer tree:
///   root (near-black void)
///     └ container         — perspective in sublayerTransform; motion blur / frost filters
///         └ strip × N     — horizontal slices of the desktop (IOSurface + contentsRect),
///             ├ shade       chained end-to-end and rotated progressively to form the bend
///             └ sheen
///
/// Filters live on the container so the blur is applied to the projected,
/// composited sheet — seams between strips never show and the smear is in
/// screen space like a real motion blur. (Don't put CIAffineClamp anywhere in
/// this chain: CA then draws IOSurface contents at ~40% size.)
final class FoldView: NSView {
    private let container = CALayer()
    private var strips: [Strip] = []
    /// Cube: the face that swings into view under the desktop as the cube turns.
    private let cubeFace = CAGradientLayer()
    private let motionBlur = CIFilter(name: "CIMotionBlur")!
    private let frostBlur = CIFilter(name: "CIGaussianBlur")!
    private let tone = CIFilter(name: "CIColorControls")! // Fade: desaturation
    private let pinch = CIFilter(name: "CIPinchDistortion")! // Notch: per-pixel pull toward the notch
    private var installedFilters = 0
    private var currentBuffer: CVPixelBuffer?
    private(set) var pose = FoldPose.flat

    /// Layers are allocated for the finest style; each style uses only what it
    /// needs (every active strip is re-fed on every captured frame, so fewer is
    /// cheaper): Curl and Genie bend sharply and need fine slicing, Fold is a
    /// gentle curve, the rigid styles only need enough strips for their shading.
    static let stripCount = 64
    private var activeCount = 18
    private static func stripCount(for style: FoldStyle) -> Int {
        switch style {
        case .curl, .genie, .notch: return 64
        case .fold: return 18
        case .cube, .scale, .fade: return 8
        }
    }
    private var currentSurface: IOSurfaceRef?
    /// Width of the display's notch in points (Notch style pulls the desktop
    /// into exactly that opening); a plausible default on notch-less Macs.
    private var notchWidth: CGFloat = 180

    private struct Strip {
        let layer = CALayer()
        let shade = CAGradientLayer()
        let sheen = CAGradientLayer()
    }

    var onClick: (() -> Void)?

    /// Eye distance in points. Larger = flatter perspective.
    var perspectiveDistance: CGFloat = 1800 {
        didSet { updatePerspective() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.backgroundColor = NSColor(white: 0.02, alpha: 1).cgColor

        container.anchorPoint = CGPoint(x: 0.5, y: 0.55) // eye sits a touch above centre
        layer?.addSublayer(container)

        motionBlur.name = "mblur"
        motionBlur.setValue(0, forKey: kCIInputRadiusKey)
        motionBlur.setValue(Double.pi / 2, forKey: kCIInputAngleKey) // smear along the fold direction
        frostBlur.name = "frost"
        frostBlur.setValue(0, forKey: kCIInputRadiusKey)
        tone.name = "tone"
        tone.setValue(1, forKey: kCIInputSaturationKey)
        pinch.name = "pinch"
        pinch.setValue(0, forKey: kCIInputScaleKey)

        cubeFace.anchorPoint = CGPoint(x: 0.5, y: 0)
        cubeFace.startPoint = CGPoint(x: 0.5, y: 0)
        cubeFace.endPoint = CGPoint(x: 0.5, y: 1)
        cubeFace.colors = [NSColor(white: 0.16, alpha: 1).cgColor, NSColor(white: 0.03, alpha: 1).cgColor]
        cubeFace.isHidden = true
        container.addSublayer(cubeFace) // behind the strips

        for _ in 0..<Self.stripCount {
            let s = Strip()
            s.layer.contentsGravity = .resize
            s.layer.masksToBounds = true
            s.layer.edgeAntialiasingMask = [] // hard edges so abutting strips don't leave hairlines
            s.layer.anchorPoint = CGPoint(x: 0.5, y: 0)

            for g in [s.shade, s.sheen] {
                g.startPoint = CGPoint(x: 0.5, y: 0)
                g.endPoint = CGPoint(x: 0.5, y: 1)
                s.layer.addSublayer(g)
            }
            s.shade.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
            s.sheen.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
            s.sheen.compositingFilter = "screenBlendMode"

            container.addSublayer(s.layer)
            strips.append(s)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        withoutAnimation {
            container.frame = bounds
            let scale = window?.backingScaleFactor ?? 2
            container.contentsScale = scale
            layoutStrips()
            if let screen = window?.screen,
               let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, r.minX > l.maxX {
                notchWidth = r.minX - l.maxX
            } else {
                notchWidth = bounds.width * 0.12
            }
            cubeFace.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            cubeFace.position = CGPoint(x: bounds.midX, y: 0)
            cubeFace.contentsScale = scale
            updatePerspective()
            applyPose(pose)
        }
    }

    /// Slices the desktop into `activeCount` strips; the rest are hidden and
    /// receive no frames.
    private func layoutStrips() {
        let scale = window?.backingScaleFactor ?? 2
        let n = CGFloat(activeCount)
        let h = bounds.height / n
        for (i, s) in strips.enumerated() {
            let active = i < activeCount
            s.layer.isHidden = !active
            guard active else { continue }
            // Overlap each strip a hair into the next so rounding never opens a gap.
            let overlap: CGFloat = i == activeCount - 1 ? 0 : 0.5
            s.layer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: h + overlap)
            s.layer.position = CGPoint(x: bounds.midX, y: 0)
            s.layer.contentsRect = CGRect(x: 0, y: CGFloat(i) / n, width: 1, height: (h + overlap) / bounds.height)
            s.layer.contentsScale = scale
            s.layer.contents = currentSurface
            for g in [s.shade, s.sheen] {
                g.frame = s.layer.bounds
                g.contentsScale = scale
            }
        }
    }

    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private func updatePerspective() {
        var t = CATransform3DIdentity
        t.m34 = -1 / max(perspectiveDistance, 200)
        container.sublayerTransform = t
    }

    // MARK: Frames

    func display(_ buffer: CVPixelBuffer) {
        guard let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return }
        currentBuffer = buffer
        currentSurface = surface
        withoutAnimation { for s in strips.prefix(activeCount) { s.layer.contents = surface } }
    }

    var hasFrame: Bool { currentBuffer != nil }

    func clearFrame() {
        currentBuffer = nil
        currentSurface = nil
        withoutAnimation { for s in strips { s.layer.contents = nil } }
    }

    // MARK: Pose

    func setPose(_ p: FoldPose) {
        // Skip the commit when nothing perceptible changed — at rest the only
        // traffic to the window server should be new capture frames.
        guard !pose.isVisuallyEqual(to: p) || !appliedOnce else { return }
        pose = p
        appliedOnce = true
        withoutAnimation { applyPose(p) }
    }
    private var appliedOnce = false

    /// Lean angle (radians) of the Fold sheet at normalised height u ∈ [0, 1].
    private func lean(at u: Double, pose p: FoldPose) -> Double {
        let profile = (1 - p.bend) + p.bend * pow(u, 1.4)
        return p.tilt * profile * .pi / 180
    }

    /// Curl: the roll tightens toward the top, so the sheet starts as a page
    /// curl and ends rolled up like a scroll behind itself.
    private func curl(at u: Double, pose p: FoldPose) -> Double {
        let tiltRad = p.tilt * .pi / 180
        return tiltRad * (0.2 * u + 2.6 * pow(u, 2.4))
    }

    private func applyPose(_ p: FoldPose) {
        let wanted = Self.stripCount(for: p.style)
        if wanted != activeCount {
            activeCount = wanted
            layoutStrips()
        }
        let n = activeCount
        let H = Double(bounds.height)
        let h = H / Double(n)
        let prog = p.progress
        let tiltRad = p.tilt * .pi / 180

        // Per-style geometry: the facing angle at height u (drives shading and
        // the sheen), extra darkening at u, and the strip transforms.
        var phiAt: (Double) -> Double = { _ in 0 }
        var dimAt: (Double) -> Double = { _ in 0 }
        var transforms: [CATransform3D] = []
        transforms.reserveCapacity(n)

        switch p.style {
        case .fold, .curl:
            phiAt = p.style == .fold ? { self.lean(at: $0, pose: p) } : { self.curl(at: $0, pose: p) }
            var y = 0.0, z = 0.0
            for i in 0..<n {
                let phi = phiAt((Double(i) + 0.5) / Double(n))
                var t = CATransform3DMakeTranslation(0, CGFloat(y), CGFloat(z))
                t = CATransform3DRotate(t, -CGFloat(phi), 1, 0, 0) // negative: top edge recedes
                transforms.append(t)
                y += h * cos(phi)
                z -= h * sin(phi)
            }

        case .genie, .notch:
            // Pulled through an opening: the hinge (Genie) or the notch (Notch).
            // Strips compress toward the opening and the whole sheet narrows
            // uniformly — both continuous, so nothing steps — while a per-pixel
            // pinch centred on the opening (installed below) does the funnel.
            let toTop = p.style == .notch
            let through = smoothstep(0.35, 1, prog)
            let height = 1 - 0.985 * smoothstep(0.2, 1, prog)   // fraction of the screen still occupied
            let sx = 1 - 0.85 * through
            let phi = tiltRad * (toTop ? 0.12 : 0.3)
            phiAt = { _ in phi }
            dimAt = { u in 0.4 * prog * (toTop ? u : 1 - u) }
            let weights = (0..<n).map { i -> Double in
                let u = (Double(i) + 0.5) / Double(n)
                return 1 - 0.6 * through * (toTop ? u : 1 - u)   // nearest the opening compresses most
            }
            let wsum = weights.reduce(0, +)
            let sys = weights.map { height * Double(n) * $0 / wsum }
            var y = toTop ? H - sys.reduce(0) { $0 + h * $1 * cos(phi) } : 0
            var z = 0.0
            for i in 0..<n {
                let sy = sys[i]
                var t = CATransform3DMakeTranslation(0, CGFloat(y), CGFloat(z))
                t = CATransform3DRotate(t, -CGFloat(phi), 1, 0, 0)
                t = CATransform3DScale(t, CGFloat(sx), CGFloat(sy), 1)
                transforms.append(t)
                y += h * sy * cos(phi)
                z -= h * sy * sin(phi)
            }

        case .cube:
            // Rigid rotation about the cube's centre (half a screen behind the
            // glass), shrunk a little mid-turn so the face stays on screen.
            let theta = tiltRad
            let s = 1 - 0.22 * sin(theta)
            phiAt = { _ in theta }
            dimAt = { u in 0.15 * prog * u }
            var base = CATransform3DMakeTranslation(0, CGFloat(H / 2), CGFloat(-H / 2))
            base = CATransform3DScale(base, CGFloat(s), CGFloat(s), CGFloat(s))
            base = CATransform3DRotate(base, -CGFloat(theta), 1, 0, 0)
            base = CATransform3DTranslate(base, 0, CGFloat(-H / 2), CGFloat(H / 2))
            for i in 0..<n {
                transforms.append(CATransform3DTranslate(base, 0, CGFloat(Double(i) * h), 0))
            }
            // The cube's underside: the same square, folded 90° back from the hinge edge.
            cubeFace.transform = CATransform3DRotate(base, -.pi / 2, 1, 0, 0)

        case .scale:
            let s = 1 - 0.78 * prog
            let phi = tiltRad * 0.18
            phiAt = { _ in phi }
            dimAt = { _ in 0.5 * prog }
            for i in 0..<n {
                let y = Double(i) * h * s
                var t = CATransform3DMakeTranslation(0, CGFloat(y * cos(phi)), CGFloat(-y * sin(phi)))
                t = CATransform3DRotate(t, -CGFloat(phi), 1, 0, 0)
                t = CATransform3DScale(t, CGFloat(s), CGFloat(s), 1)
                transforms.append(t)
            }

        case .fade:
            let phi = tiltRad * 0.1
            phiAt = { _ in phi }
            dimAt = { u in min(1, prog * (0.25 + 0.95 * u)) }
            for i in 0..<n {
                let y = Double(i) * h
                var t = CATransform3DMakeTranslation(0, CGFloat(y * cos(phi)), CGFloat(-y * sin(phi)))
                t = CATransform3DRotate(t, -CGFloat(phi), 1, 0, 0)
                transforms.append(t)
            }
        }

        cubeFace.isHidden = !(p.style == .cube && prog > 0.001)

        for (i, s) in strips.prefix(n).enumerated() {
            let u0 = Double(i) / Double(n), u1 = Double(i + 1) / Double(n)
            s.layer.transform = transforms[i]
            s.shade.colors = [shadeColor(phi: phiAt(u0), u: u0, dim: dimAt(u0), pose: p),
                              shadeColor(phi: phiAt(u1), u: u1, dim: dimAt(u1), pose: p)]
            s.sheen.colors = [sheenColor(phi: phiAt(u0), pose: p), sheenColor(phi: phiAt(u1), pose: p)]
        }

        // Filters live on the container; install only what this frame needs.
        let wantBlur = p.motionBlur > 0.25 || p.frost > 0.25
        let wantTone = p.style == .fade && prog > 0.01
        let wantPinch = (p.style == .genie || p.style == .notch) && prog > 0.001
        let key = (wantBlur ? 1 : 0) | (wantTone ? 2 : 0) | (wantPinch ? 4 : 0)
        if key != installedFilters {
            var f: [CIFilter] = []
            if wantPinch { f.append(pinch) } // warp first, then blur the warped picture
            if wantBlur { f += [motionBlur, frostBlur] }
            if wantTone { f.append(tone) }
            container.filters = f.isEmpty ? nil : f
            installedFilters = key
        }
        if wantBlur {
            container.setValue(p.motionBlur, forKeyPath: "filters.mblur.inputRadius")
            container.setValue(p.frost, forKeyPath: "filters.frost.inputRadius")
        }
        if wantTone {
            container.setValue(1 - 0.9 * prog, forKeyPath: "filters.tone.inputSaturation")
        }
        if wantPinch {
            // Centre on the opening; the radius reaches the far corners so the
            // whole sheet is inside the pull.
            let W = Double(bounds.width)
            let cy = p.style == .notch ? H : 0
            container.setValue(CIVector(x: CGFloat(W / 2), y: CGFloat(cy)), forKeyPath: "filters.pinch.inputCenter")
            container.setValue(hypot(W / 2, H) * 1.05, forKeyPath: "filters.pinch.inputRadius")
            container.setValue(min(1, 1.1 * pow(prog, 0.8)), forKeyPath: "filters.pinch.inputScale")
        }
    }

    /// Lambert-ish falloff: the further a slice turns away, the darker; plus a
    /// gentle distance fade so the far edge sits back in the void. Strips that
    /// have rolled past edge-on (Curl) show their back, dimmed like paper.
    private func shadeColor(phi: Double, u: Double, dim: Double, pose p: FoldPose) -> CGColor {
        let facing = min(1, max(0, 1 - cos(phi)))     // 0 flat … 1 edge-on or beyond
        let a = min(1, p.shade * min(1, facing * 1.6 + 0.35 * u * sin(phi)) + dim)
        return NSColor.black.withAlphaComponent(a).cgColor
    }

    /// A soft highlight band that lives where the surface leans ~28° toward
    /// the light, so it sweeps along the sheet as it bends.
    private func sheenColor(phi: Double, pose p: FoldPose) -> CGColor {
        let deg = phi * 180 / .pi
        let band = exp(-pow((deg - 28) / 16, 2))
        let a = 0.14 * p.sheen * band * min(1, p.tilt / 12)
        return NSColor.white.withAlphaComponent(a).cgColor
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    var stateDescription: String {
        let bw = currentBuffer.map { CVPixelBufferGetWidth($0) } ?? 0
        let bh = currentBuffer.map { CVPixelBufferGetHeight($0) } ?? 0
        return "view=\(bounds.size) style=\(pose.style.rawValue) tilt=\(pose.tilt) bend=\(pose.bend) mblur=\(pose.motionBlur) frost=\(pose.frost) shade=\(pose.shade) filters=\(installedFilters) strips=\(activeCount) buffer=\(bw)x\(bh)"
    }

    // MARK: Input — a click pauses the effect until the lid opens again.

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Borderless window that sits above everything on the built-in display and is
/// invisible to screen capture (so the desktop stream never shows the overlay).
final class FoldWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none // excluded from ScreenCaptureKit / screen recording
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
