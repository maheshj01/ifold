import Foundation
import IOKit
import IOKit.hid

/// Reads the MacBook's hinge angle from the built-in lid-angle HID sensor.
///
/// The sensor is exposed as a plain HID device (Apple VID 0x05AC, PID 0x8104,
/// Sensor usage page / Orientation usage). Feature report #1 carries the angle
/// in whole degrees as a little-endian UInt16 at bytes 1–2. No private API,
/// no entitlements — only requirement is a non-sandboxed process.
final class LidAngleSensor {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private let none = IOOptionBits(kIOHIDOptionsTypeNone)
    private let queue = DispatchQueue(label: "ifold.lid-sensor", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    /// Called on the main thread every sample (~60 Hz) with the angle in degrees.
    var onAngle: ((Double) -> Void)?

    var isAvailable: Bool { device != nil }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, none)
        device = findDevice()
    }

    deinit {
        stop()
        if let device { IOHIDDeviceClose(device, none) }
        IOHIDManagerClose(manager, none)
    }

    private func findDevice() -> IOHIDDevice? {
        guard IOHIDManagerOpen(manager, none) == kIOReturnSuccess else { return nil }
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            "UsagePage": 0x0020, // HID Sensor page
            "Usage": 0x008A,     // Orientation
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }

        // Several interfaces match; only one answers the feature report.
        for candidate in devices {
            guard IOHIDDeviceOpen(candidate, none) == kIOReturnSuccess else { continue }
            if Self.readRaw(from: candidate) != nil { return candidate }
            IOHIDDeviceClose(candidate, none)
        }
        return nil
    }

    private static func readRaw(from device: IOHIDDevice) -> Double? {
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        let raw = UInt16(report[2]) << 8 | UInt16(report[1])
        return Double(raw)
    }

    /// One synchronous read. Returns nil if the sensor is unavailable.
    func read() -> Double? {
        guard let device else { return nil }
        return Self.readRaw(from: device)
    }

    private(set) var rate: Double = 0

    func start(hz: Double = 60) {
        guard device != nil, timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.setEventHandler { [weak self] in
            guard let self, let angle = self.read() else { return }
            DispatchQueue.main.async { self.onAngle?(angle) }
        }
        timer = t
        setRate(hz: hz)
        t.resume()
    }

    /// Poll slower while the lid is parked; a HID feature-report read is a
    /// kernel round-trip each time, so this is most of the idle cost.
    func setRate(hz: Double) {
        guard let timer, hz != rate else { return }
        rate = hz
        timer.schedule(deadline: .now(), repeating: 1.0 / hz, leeway: .milliseconds(hz > 40 ? 2 : 8))
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
