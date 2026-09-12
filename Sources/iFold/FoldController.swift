import AppKit
import Combine
import CoreGraphics
import os

let log = Logger(subsystem: "com.wml.ifold-mac", category: "fold")

/// Orchestrates sensor → capture → overlay.
///
/// State machine:
///   idle      lid open, overlay hidden, capture stopped (pre-warms when the lid nears the threshold)
///   engaged   lid below `clearAngle`, overlay tracks the hinge every frame
///   releasing lid came back up: spring to flat, then hide and stop capturing
@MainActor
final class FoldController: ObservableObject {
    static let shared = FoldController()

    let settings = Settings()
    private let sensor = LidAngleSensor()
    private let capturer = ScreenCapturer()
    private var window: FoldWindow?
    private var view: FoldView?

    @Published private(set) var lidAngle: Double = 0
    @Published private(set) var sensorAvailable = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var isEngaged = false
    @Published private(set) var isPaused = false
    @Published private(set) var captureError: String?

    private enum Phase { case idle, engaged, releasing }
    private var phase: Phase = .idle

    /// Second-order follower: the picture carries a little inertia behind the
    /// hinge and settles with a whisper of overshoot instead of lerping.
    private struct Spring {
        var x = 0.0, v = 0.0
        var response = 0.32      // seconds to reach the target, roughly
        var damping = 0.82       // < 1 → slight overshoot
        mutating func step(to target: Double, dt: Double) {
            let w = 2 * Double.pi / response
            let a = w * w * (target - x) - 2 * damping * w * v
            v += a * dt
            x += v * dt
        }
        var isSettled: Bool { abs(x) < 0.1 && abs(v) < 1.5 }
    }
    private var tilt = Spring()
    private var blurRadius = 0.0
    private var lidVelocity = 0.0 // deg/s, smoothed; negative = closing
    private var lastSampleTime = CACurrentMediaTime()
    private var debugBlurOverride: Double?
    private var ticker: Timer?
    private var displayLink: CADisplayLink?
    private var lastTick = CACurrentMediaTime()
    private var captureStartTask: Task<Void, Never>?
    private var idleSince: Date?
    /// Set while the machine is asleep / the screen is locked: no overlay, no capture.
    private var suspendedUntil = Date.distantPast
    #if IFOLD_DEBUG
    private var debugSnapshot: DebugSnapshot?
    private var demoDriver: DemoDriver?
    #endif

    private let maxTilt: Double = 80
    /// Hysteresis around `clearAngle`. The sensor reports whole degrees and a
    /// lid parked near the threshold flexes a degree or two under typing, so:
    /// engage only once the lid is `engageBand` below clear (and has stayed
    /// there `engageDwell`, unless it's clearly moving down), release a degree
    /// under clear, and map the lean so the sheet is flat at the release point.
    private let engageBand: Double = 4
    private let engageDwell: TimeInterval = 0.12
    private var belowSince: TimeInterval?
    private let rampDegrees: Double = 45 // frost reaches its maximum this many degrees below clearAngle
    private let prewarmMargin: Double = 15
    private let maxMotionBlur: Double = 28

    private init() {}

    func start() {
        sensorAvailable = sensor.isAvailable
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        if let angle = sensor.read() { lidAngle = angle }
        log.notice("start: sensor=\(self.sensorAvailable) screenRecording=\(self.screenRecordingGranted) angle=\(self.lidAngle) clear=\(self.settings.clearAngle)")

        #if IFOLD_DEBUG
        debugSnapshot = DebugSnapshot(window: { [weak self] in self?.window },
                                      displayID: { Self.builtInScreen().flatMap(Self.displayID) })
        demoDriver = DemoDriver(settings: settings, window: { [weak self] in self?.window })
        #endif
        observeSystemEvents()

        // Create the overlay window now (it stays ordered out until needed) so
        // this app owns a window before any capture stream starts: the stream
        // excludes our application, and that list is built from apps that have
        // windows. Without this the exclusion is empty and only the window's
        // sharingType keeps the capture from seeing the overlay.
        if window == nil, let screen = Self.builtInScreen() { makeWindow(on: screen) }

        sensor.onAngle = { [weak self] angle in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let dt = now - self.lastSampleTime
            if dt > 0.005 {
                let v = (angle - self.lidAngle) / dt
                self.lidVelocity += (v - self.lidVelocity) * 0.3
                self.lastSampleTime = now
            }
            self.lidAngle = angle
        }
        sensor.start()

        capturer.onFrame = { [weak self] buffer in
            guard let self, self.phase != .idle || self.wantsPrewarm else { return }
            self.view?.display(buffer)
            if self.phase == .engaged, let window = self.window, !window.isVisible {
                window.orderFrontRegardless()
                self.isEngaged = true
            }
        }
        capturer.onStopped = { [weak self] error in
            guard let self else { return }
            log.error("capture stopped: \(error.localizedDescription, privacy: .public)")
            self.captureError = error.localizedDescription
            if self.phase != .idle { self.hideOverlay() }
        }

        // Drive the pose from the built-in display's refresh (120 Hz on ProMotion).
        let screen = Self.builtInScreen() ?? NSScreen.main
        if let link = screen?.displayLink(target: self, selector: #selector(displayLinkFired)) {
            link.add(to: .main, forMode: .common)
            displayLink = link
            setLinkRate(engaged: false)
        } else {
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(ticker!, forMode: .common)
        }
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        tick()
    }

    /// Idle: a lazy 20 Hz is plenty to notice the lid starting to move.
    /// Engaged: the full panel rate so the spring and smear are silky.
    private var linkEngaged = false
    private func setLinkRate(engaged: Bool) {
        guard let displayLink, linkEngaged != engaged || tickCount <= 1 else { return }
        linkEngaged = engaged
        displayLink.preferredFrameRateRange = engaged
            ? CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            : CAFrameRateRange(minimum: 10, maximum: 30, preferred: 20)
        sensor.setRate(hz: engaged ? 60 : 30)
    }

    // MARK: System events — never keep a picture of the desktop around while
    // the machine sleeps or the screen is locked, and rebuild on display changes.

    private func observeSystemEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        let suspend: (String) -> Void = { [weak self] why in
            Task { @MainActor in self?.suspend(reason: why) }
        }
        let resume: (String) -> Void = { [weak self] why in
            Task { @MainActor in self?.resumeAfterSuspend(reason: why) }
        }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in suspend("sleep") }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in suspend("display sleep") }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in suspend("fast user switch") }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in suspend("screen locked") }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in resume("wake") }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in resume("display wake") }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in resume("session active") }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in resume("screen unlocked") }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        }
    }

    private func suspend(reason: String) {
        log.notice("suspend: \(reason, privacy: .public)")
        suspendedUntil = .distantFuture
        hideOverlay()
        view?.clearFrame()
        capturer.stop()
    }

    private func resumeAfterSuspend(reason: String) {
        log.notice("resume: \(reason, privacy: .public)")
        // Brief grace so we don't engage on a stale angle while the lid is still swinging open.
        suspendedUntil = Date().addingTimeInterval(0.4)
    }

    private func screensChanged() {
        guard let window, let screen = Self.builtInScreen() else { return }
        if window.frame != screen.frame {
            log.notice("screens changed: rebuilding overlay window")
            hideOverlay()
            view?.clearFrame()
            capturer.stop()
            window.contentView = nil
            self.window = nil
            self.view = nil
        }
    }

    // MARK: Public controls

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        log.notice("requested screen recording: granted=\(self.screenRecordingGranted)")
    }

    /// Re-check permission (it can be granted while we're running; capture
    /// itself still needs a relaunch, but the UI should reflect it).
    func refreshPermission() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != screenRecordingGranted {
            log.notice("screen recording changed: \(granted)")
            screenRecordingGranted = granted
        }
    }

    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Hide the effect until the lid is opened past the threshold again.
    func pause() {
        guard phase == .engaged else { return }
        isPaused = true
        release()
    }

    func resume() {
        isPaused = false
    }

    // MARK: Core loop

    private var effectiveAngle: Double {
        settings.followLid ? lidAngle : settings.manualAngle
    }

    /// Start the (expensive) capture stream just before it's needed: when the
    /// lid is closing toward the threshold, or already sitting right at it.
    /// A lid parked at a normal working angle inside the margin must not keep
    /// the stream alive.
    private var wantsPrewarm: Bool {
        guard !isPaused else { return false }
        let gap = effectiveAngle - settings.clearAngle
        if !settings.followLid { return gap < prewarmMargin }
        return gap < 4 || (gap < prewarmMargin && lidVelocity < -8)
    }

    private func perspectiveDistance() -> CGFloat {
        (window?.frame.height ?? 900) * 1.9
    }

    private var tickCount = 0

    private func tick() {
        let angle = effectiveAngle
        let clear = settings.clearAngle
        let canEngage = settings.followLid ? sensorAvailable : true
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now

        // In Manual (preview) mode let clicks fall through so you can keep working.
        window?.ignoresMouseEvents = !settings.followLid

        tickCount += 1
        #if IFOLD_DEBUG
        if tickCount % 30 == 0 {
            debugBlurOverride = UserDefaults.standard.object(forKey: "debugMotionBlur") as? Double
        }
        #endif
        if Date() < suspendedUntil {
            if phase != .idle { hideOverlay() }
            return
        }
        if tickCount % 600 == 0 { // ~every 5 s
            refreshPermission()
            log.notice("tick: angle=\(angle) lidV=\(self.lidVelocity) clear=\(clear) phase=\(String(describing: self.phase), privacy: .public) tilt=\(self.tilt.x) v=\(self.tilt.v) capture=\(self.capturer.isRunning) paused=\(self.isPaused) visible=\(self.window?.isVisible ?? false) \(self.view?.stateDescription ?? "no view", privacy: .public)")
        }

        setLinkRate(engaged: phase != .idle || wantsPrewarm)

        switch phase {
        case .idle:
            if angle >= clear + 1 { isPaused = false }
            if wantsPrewarm && screenRecordingGranted {
                idleSince = nil
                ensureCapture()
            } else {
                stopCaptureIfCold()
            }
            if canEngage, !isPaused, screenRecordingGranted, shouldEngage(angle: angle, clear: clear, now: now) { engage() }

        case .engaged:
            if angle >= clear - 1 { release() }
            animate(angle: angle, clear: clear, dt: dt)

        case .releasing:
            // Lid dipped again before we settled: pick it straight back up, no pop.
            if !isPaused, angle <= clear - engageBand { phase = .engaged }
            animate(angle: angle, clear: clear, dt: dt)
            if tilt.isSettled && blurRadius < 0.3 { hideOverlay() }
        }
    }

    /// Below the band, and either moving down decisively or parked there for
    /// a moment. A wobble that crosses the line and comes back never counts.
    private func shouldEngage(angle: Double, clear: Double, now: TimeInterval) -> Bool {
        guard angle <= clear - engageBand else { belowSince = nil; return false }
        if !settings.followLid || lidVelocity < -15 { return true }
        if belowSince == nil { belowSince = now }
        return now - belowSince! >= engageDwell
    }

    /// One frame of the follower: spring toward the target lean, derive motion
    /// blur from how fast the picture is actually moving, hand the pose over.
    private func animate(angle: Double, clear: Double, dt: Double) {
        // Lean is measured from just under the release point, so the sheet is
        // already flat by the time the lid clears — no pop on the way out.
        let dropped = phase == .engaged ? max(0, (clear - 1) - angle) : 0
        let target = min(dropped * settings.perspective, maxTilt)
        tilt.step(to: target, dt: dt)

        // Smear scales with angular speed (deg/s). Fast attack so the first
        // moment of motion smears, slower release so it "resolves" as it settles.
        let wanted = min(maxMotionBlur, abs(tilt.v) * 0.12 * settings.motion)
        let k = wanted > blurRadius ? 1 - exp(-dt / 0.03) : 1 - exp(-dt / 0.14)
        blurRadius += (wanted - blurRadius) * k
        #if IFOLD_DEBUG
        if let forced = debugBlurOverride { blurRadius = forced }
        #endif

        let p = min(1, dropped / rampDegrees)
        let eased = p * p * (3 - 2 * p)

        var pose = FoldPose()
        pose.style = settings.style
        pose.tilt = max(0, tilt.x)
        pose.bend = settings.bend
        pose.shade = settings.shade
        pose.motionBlur = blurRadius
        pose.frost = settings.frost * eased
        view?.setPose(pose)
    }

    private func engage() {
        belowSince = nil
        guard let screen = Self.builtInScreen() else { log.error("engage: no built-in screen"); return }
        log.notice("engage at \(self.effectiveAngle)° (capture running=\(self.capturer.isRunning), hasFrame=\(self.view?.hasFrame ?? false))")
        if window == nil { makeWindow(on: screen) }
        tilt = Spring()
        blurRadius = 0
        phase = .engaged
        ensureCapture()
        // Window is ordered front by the first captured frame so we never flash black.
        if view?.hasFrame == true { window?.orderFrontRegardless(); isEngaged = true }
    }

    private func release() {
        guard phase == .engaged else { return }
        log.notice("release at \(self.effectiveAngle)°")
        phase = .releasing
        if settings.sound, window?.isVisible == true { Self.click.play() }
    }

    private func hideOverlay() {
        phase = .idle
        window?.orderOut(nil)
        tilt = Spring()
        blurRadius = 0
        view?.setPose(.flat)
        isEngaged = false
        idleSince = nil
    }

    // MARK: Capture lifecycle

    private func ensureCapture() {
        guard !capturer.isRunning, captureStartTask == nil,
              let screen = Self.builtInScreen(), let displayID = Self.displayID(of: screen) else { return }
        captureStartTask = Task { @MainActor in
            defer { captureStartTask = nil }
            do {
                try await capturer.start(displayID: displayID)
                captureError = nil
                log.notice("capture started on display \(displayID)")
            } catch {
                captureError = error.localizedDescription
                screenRecordingGranted = CGPreflightScreenCaptureAccess()
                log.error("capture start failed: \(error.localizedDescription, privacy: .public) (granted=\(self.screenRecordingGranted))")
            }
        }
    }

    /// Stop the stream a few seconds after the lid leaves the pre-warm zone.
    private func stopCaptureIfCold() {
        guard capturer.isRunning else { idleSince = nil; return }
        guard let since = idleSince else { idleSince = Date(); return }
        if Date().timeIntervalSince(since) > 3 {
            capturer.stop()
            view?.clearFrame()
            idleSince = nil
        }
    }

    // MARK: Window

    private func makeWindow(on screen: NSScreen) {
        let w = FoldWindow(screen: screen)
        w.ignoresMouseEvents = !settings.followLid
        let v = FoldView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.onClick = { [weak self] in self?.pause() }
        w.contentView = v
        v.frame = w.contentLayoutRect
        v.needsLayout = true
        v.layoutSubtreeIfNeeded()
        window = w
        view = v
        v.perspectiveDistance = perspectiveDistance()
        log.notice("window on \(screen.localizedName, privacy: .public) frame=\(String(describing: w.frame), privacy: .public) view=\(String(describing: v.bounds), privacy: .public) scale=\(w.backingScaleFactor)")
    }

    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = displayID(of: screen) else { return false }
            return CGDisplayIsBuiltin(id) != 0
        } ?? NSScreen.main
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static let click: NSSound = {
        let s = NSSound(named: "Pop") ?? NSSound()
        s.volume = 0.35
        return s
    }()
}
