import AppKit
import QuartzCore
import CoreVideo

/// Everything the renderer needs for one frame.
struct FoldPose {
    /// Degrees the picture leans away from the viewer at the top edge.
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

    func isVisuallyEqual(to o: FoldPose) -> Bool {
        abs(tilt - o.tilt) < 0.004 && abs(bend - o.bend) < 0.001 && abs(shade - o.shade) < 0.001
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
    private let motionBlur = CIFilter(name: "CIMotionBlur")!
    private let frostBlur = CIFilter(name: "CIGaussianBlur")!
    private var filtersInstalled = false
    private var currentBuffer: CVPixelBuffer?
    private(set) var pose = FoldPose.flat

    static let stripCount = 18

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
            let n = CGFloat(Self.stripCount)
            let h = bounds.height / n
            for (i, s) in strips.enumerated() {
                // Overlap each strip a hair into the next so rounding never opens a gap.
                let overlap: CGFloat = i == strips.count - 1 ? 0 : 0.5
                s.layer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: h + overlap)
                s.layer.position = CGPoint(x: bounds.midX, y: 0)
                s.layer.contentsRect = CGRect(x: 0, y: CGFloat(i) / n, width: 1, height: (h + overlap) / bounds.height)
                s.layer.contentsScale = scale
                for g in [s.shade, s.sheen] {
                    g.frame = s.layer.bounds
                    g.contentsScale = scale
                }
            }
            updatePerspective()
            applyPose(pose)
        }
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
        withoutAnimation { for s in strips { s.layer.contents = surface } }
    }

    var hasFrame: Bool { currentBuffer != nil }

    func clearFrame() {
        currentBuffer = nil
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

    /// Lean angle (radians) of the sheet at normalised height u ∈ [0, 1].
    private func lean(at u: Double, pose p: FoldPose) -> Double {
        let profile = (1 - p.bend) + p.bend * pow(u, 1.4)
        return p.tilt * profile * .pi / 180
    }

    private func applyPose(_ p: FoldPose) {
        let n = strips.count
        let h = Double(bounds.height) / Double(n)
        var y = 0.0, z = 0.0
        for (i, s) in strips.enumerated() {
            let u0 = Double(i) / Double(n), u1 = Double(i + 1) / Double(n)
            let phi = lean(at: (u0 + u1) / 2, pose: p)

            var t = CATransform3DMakeTranslation(0, CGFloat(y), CGFloat(z))
            t = CATransform3DRotate(t, -CGFloat(phi), 1, 0, 0) // negative: top edge recedes
            s.layer.transform = t
            y += h * cos(phi)
            z -= h * sin(phi)

            s.shade.colors = [shadeColor(u: u0, pose: p), shadeColor(u: u1, pose: p)]
            s.sheen.colors = [sheenColor(u: u0, pose: p), sheenColor(u: u1, pose: p)]
        }

        let wantFilters = p.motionBlur > 0.25 || p.frost > 0.25
        if wantFilters != filtersInstalled {
            container.filters = wantFilters ? [motionBlur, frostBlur] : nil
            filtersInstalled = wantFilters
        }
        if wantFilters {
            container.setValue(p.motionBlur, forKeyPath: "filters.mblur.inputRadius")
            container.setValue(p.frost, forKeyPath: "filters.frost.inputRadius")
        }
    }

    /// Lambert-ish falloff: the further a slice turns away, the darker; plus a
    /// gentle distance fade so the far edge sits back in the void.
    private func shadeColor(u: Double, pose p: FoldPose) -> CGColor {
        let phi = lean(at: u, pose: p)
        let facing = 1 - cos(phi)                    // 0 flat … 1 edge-on
        let a = p.shade * min(1, facing * 1.6 + 0.35 * u * sin(phi))
        return NSColor.black.withAlphaComponent(a).cgColor
    }

    /// A soft highlight band that lives where the surface leans ~28° toward
    /// the light, so it sweeps along the sheet as it bends.
    private func sheenColor(u: Double, pose p: FoldPose) -> CGColor {
        let deg = lean(at: u, pose: p) * 180 / .pi
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
        return "view=\(bounds.size) tilt=\(pose.tilt) bend=\(pose.bend) mblur=\(pose.motionBlur) frost=\(pose.frost) shade=\(pose.shade) filters=\(filtersInstalled) buffer=\(bw)x\(bh)"
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
