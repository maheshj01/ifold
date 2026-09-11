import SwiftUI

@main
struct iFoldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            SettingsView(settings: FoldController.shared.settings)
                .environmentObject(FoldController.shared)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var welcome: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FoldController.shared.start()
        // The menu bar icon can hide behind the notch on a crowded bar, so
        // surface the controls in a window until permission is sorted.
        if !FoldController.shared.screenRecordingGranted { showWelcome() }
    }

    func showWelcome() {
        let content = SettingsView(settings: FoldController.shared.settings)
            .environmentObject(FoldController.shared)
        let w = NSWindow(contentViewController: NSHostingController(rootView: content))
        w.title = "iFold Mac"
        w.styleMask = [.titled, .closable]
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.center()
        welcome = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
