import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var controller: FoldController
    @ObservedObject var settings: Settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if !controller.screenRecordingGranted { permissionCard }
            if !controller.sensorAvailable { sensorCard }
            angleSection
            Divider()
            styleSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("iFold Mac").font(.headline)
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(controller.lidAngle))°")
                .font(.system(.title, design: .rounded).monospacedDigit())
                .foregroundStyle(controller.sensorAvailable ? .primary : .tertiary)
        }
    }

    private var statusLine: String {
        if controller.isPaused { return "Paused until the lid opens" }
        if controller.isEngaged { return "Bending" }
        if let err = controller.captureError { return err }
        return "Watching the hinge"
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Screen Recording needed", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Text("iFold Mac captures your desktop to bend it. Grant access in System Settings, then relaunch.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Grant Access") { controller.requestScreenRecording() }
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                Button("Relaunch") { controller.relaunch() }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var sensorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No lid angle sensor", systemImage: "sensor.tag.radiowaves.forward")
                .font(.subheadline.weight(.semibold))
            Text("This Mac doesn't expose a hinge sensor. Switch to manual angle to try the effect.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var angleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $settings.followLid) {
                Text("Follow lid").tag(true)
                Text("Manual").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !settings.followLid {
                slider("Angle", value: $settings.manualAngle, in: 0...130, unit: "°")
            }
            slider("Clears at", value: $settings.clearAngle, in: 60...125, unit: "°")
            Text("Below this hinge angle the desktop starts to bend.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Style").font(.subheadline.weight(.semibold))
                Spacer()
                ForEach(Settings.Style.allCases) { style in
                    Button(style.title) { settings.apply(style) }
                        .controlSize(.small)
                }
            }
            slider("Perspective", value: $settings.perspective, in: 0.3...2.0, format: "%.1f×")
            slider("Bend", value: $settings.bend, in: 0...1, format: "%.0f%%", scale: 100)
            slider("Motion blur", value: $settings.motion, in: 0...2, format: "%.1f×")
            slider("Frost", value: $settings.frost, in: 0...30, unit: " px")
            slider("Shade", value: $settings.shade, in: 0...1, format: "%.0f%%", scale: 100)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Click sound when the desktop clears", isOn: $settings.sound)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
            HStack {
                if controller.isPaused {
                    Button("Resume") { controller.resume() }
                } else if controller.isEngaged {
                    Button("Pause") { controller.pause() }
                }
                Link("♥ Sponsor", destination: URL(string: "https://github.com/sponsors/maheshj01")!)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit iFold Mac") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                        unit: String = "", format: String? = nil, scale: Double = 1) -> some View {
        HStack {
            Text(title).frame(width: 78, alignment: .leading)
            Slider(value: value, in: range)
            Text(format.map { String(format: $0, value.wrappedValue * scale) } ?? "\(Int(value.wrappedValue))\(unit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .font(.subheadline)
    }
}
