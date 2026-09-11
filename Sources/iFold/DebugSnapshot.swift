#if IFOLD_DEBUG
import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import notify

/// DEVELOPMENT ONLY — compiled in by `./build.sh --debug-tools`, never in a normal build.
///
/// `notifyutil -p com.wml.ifold-mac.snapshot` makes the app grab a screenshot of
/// the built-in display *including* its own overlay and write it to the path in
/// the `snapshotPath` default (falls back to /tmp/ifold-mac-snap.png).
///
/// Why it's gated: Darwin notifications and `defaults write` need no privileges,
/// so in a shipping build this would let any local process use iFold Mac's Screen
/// Recording grant to capture the screen — a TCC bypass.
@MainActor
final class DebugSnapshot {
    private var token: Int32 = 0
    private let window: () -> NSWindow?
    private let displayID: () -> CGDirectDisplayID?

    init(window: @escaping () -> NSWindow?, displayID: @escaping () -> CGDirectDisplayID?) {
        self.window = window
        self.displayID = displayID
        notify_register_dispatch("com.wml.ifold-mac.snapshot", &token, DispatchQueue.main) { [weak self] _ in
            Task { @MainActor in await self?.capture() }
        }
        log.warning("DEBUG BUILD: snapshot hook armed — do not ship this binary")
    }

    private func capture() async {
        guard let id = displayID() else { return }
        let path = UserDefaults.standard.string(forKey: "snapshotPath") ?? "/tmp/ifold-mac-snap.png"
        let w = window()
        w?.sharingType = .readOnly // let the screenshot see the overlay
        defer { w?.sharingType = .none }
        try? await Task.sleep(for: .milliseconds(150))
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { return }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.width = Int(CGDisplayPixelsWide(id)) / 2
            cfg.height = Int(CGDisplayPixelsHigh(id)) / 2
            cfg.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            log.notice("snapshot written to \(path, privacy: .public)")
        } catch {
            log.error("snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif

#if IFOLD_DEBUG
/// DEVELOPMENT ONLY — scripted lid motion for recording demo footage.
///
/// `notifyutil -p com.wml.ifold-mac.demo` switches to Manual mode, plays a
/// hand-like close / pause / dip / flick-open path through `manualAngle`, and
/// keeps the overlay visible to screen recorders for the duration. Settings are
/// restored afterwards. Gated for the same reason as `DebugSnapshot`.
@MainActor
final class DemoDriver {
    private var token: Int32 = 0
    private let settings: Settings
    private let window: () -> NSWindow?
    private var timer: Timer?

    /// (duration, target angle, easing) segments; nil target = hold.
    private typealias Segment = (dur: Double, to: Double?, ease: (Double) -> Double)
    private static let easeInOut: (Double) -> Double = { t in t < 0.5 ? 4*t*t*t : 1 - pow(-2*t + 2, 3)/2 }
    private static let easeOut: (Double) -> Double = { t in 1 - pow(1 - t, 3) }
    private static let easeIn: (Double) -> Double = { t in t*t*t }

    init(settings: Settings, window: @escaping () -> NSWindow?) {
        self.settings = settings
        self.window = window
        notify_register_dispatch("com.wml.ifold-mac.demo", &token, DispatchQueue.main) { [weak self] _ in
            Task { @MainActor in self?.play() }
        }
    }

    private func play() {
        guard timer == nil else { return }
        let clear = settings.clearAngle
        let saved = (settings.followLid, settings.manualAngle, settings.sound)
        settings.followLid = false
        settings.sound = true
        settings.manualAngle = clear + 3           // idle, but close enough to pre-warm capture

        let script: [Segment] = [
            (1.2, nil,        Self.easeInOut),     // settle, capture warms
            (1.9, clear - 48, Self.easeInOut),     // hand closes the lid
            (1.3, nil,        Self.easeInOut),     // pause, picture settles crisp
            (0.7, clear - 62, Self.easeInOut),     // a little further
            (1.0, nil,        Self.easeInOut),     // hold
            (0.9, clear + 14, Self.easeIn),        // flick open → springs flat, click
            (1.6, nil,        Self.easeInOut),     // hold on the flat desktop
        ]
        let total = script.reduce(0) { $0 + $1.dur }
        log.warning("DEMO: playing \(total, privacy: .public)s scripted lid path")

        let start = CACurrentMediaTime()
        var segStart = 0.0
        var from = settings.manualAngle
        var index = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/120, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.window()?.sharingType = .readOnly
            let now = CACurrentMediaTime() - start
            while index < script.count, now >= segStart + script[index].dur {
                if let to = script[index].to { from = to }
                segStart += script[index].dur
                index += 1
            }
            guard index < script.count else {
                t.invalidate(); self.timer = nil
                self.window()?.sharingType = .none
                (self.settings.followLid, self.settings.manualAngle, self.settings.sound) = saved
                log.warning("DEMO: done, settings restored")
                return
            }
            let seg = script[index]
            if let to = seg.to {
                let p = seg.ease(min(1, (now - segStart) / seg.dur))
                self.settings.manualAngle = from + (to - from) * p
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
#endif
