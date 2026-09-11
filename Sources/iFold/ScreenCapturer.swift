import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

enum CaptureError: LocalizedError {
    case displayNotFound
    var errorDescription: String? { "Built-in display not found for capture." }
}

/// Streams the live desktop of one display via ScreenCaptureKit, excluding
/// this app's own windows so the overlay never captures itself.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "ifold-mac.capture", qos: .userInteractive)
    private var loggedFirstFrame = false

    /// Delivered on the main thread. Retain the buffer for as long as you display it.
    var onFrame: ((CVPixelBuffer) -> Void)?
    /// Delivered on the main thread when the stream dies (display sleep, permission change…).
    var onStopped: ((Error) -> Void)?

    var isRunning: Bool { stream != nil }

    func start(displayID: CGDirectDisplayID, fps: Int32 = 60) async throws {
        guard stream == nil else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ourselves = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ourselves, exceptingWindows: [])

        // CGDisplayPixelsWide reports points on scaled Retina modes; use the
        // screen's backing scale so the capture is truly full-resolution.
        let scale = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }?.backingScaleFactor ?? 2
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: fps)
        config.queueDepth = 5
        config.showsCursor = false

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await s.startCapture()
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        stream = nil
        Task { try? await s.stopCapture() }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw), status == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        if !loggedFirstFrame {
            loggedFirstFrame = true
            let info = attachments.first ?? [:]
            log.notice("first frame: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) contentRect=\(String(describing: info[.contentRect]), privacy: .public) contentScale=\(String(describing: info[.contentScale]), privacy: .public) scaleFactor=\(String(describing: info[.scaleFactor]), privacy: .public)")
        }
        DispatchQueue.main.async { [weak self] in self?.onFrame?(pixelBuffer) }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stream = nil
            self.onStopped?(error)
        }
    }
}
