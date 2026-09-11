#if IFOLD_DEBUG
import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import notify

/// DEVELOPMENT ONLY — compiled in by `./build.sh --debug-tools`, never in a normal build.
///
/// `notifyutil -p com.mahesh.ifold.snapshot` makes the app grab a screenshot of
/// the built-in display *including* its own overlay and write it to the path in
/// the `snapshotPath` default (falls back to /tmp/ifold-snap.png).
///
/// Why it's gated: Darwin notifications and `defaults write` need no privileges,
/// so in a shipping build this would let any local process use iFold's Screen
/// Recording grant to capture the screen — a TCC bypass.
@MainActor
final class DebugSnapshot {
    private var token: Int32 = 0
    private let window: () -> NSWindow?
    private let displayID: () -> CGDirectDisplayID?

    init(window: @escaping () -> NSWindow?, displayID: @escaping () -> CGDirectDisplayID?) {
        self.window = window
        self.displayID = displayID
        notify_register_dispatch("com.mahesh.ifold.snapshot", &token, DispatchQueue.main) { [weak self] _ in
            Task { @MainActor in await self?.capture() }
        }
        log.warning("DEBUG BUILD: snapshot hook armed — do not ship this binary")
    }

    private func capture() async {
        guard let id = displayID() else { return }
        let path = UserDefaults.standard.string(forKey: "snapshotPath") ?? "/tmp/ifold-snap.png"
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
