import AppKit
import CoreMedia
import ScreenCaptureKit

/// A continuous capture of one window. ScreenCaptureKit only delivers a frame when the window's
/// pixels change, so an idle editor costs nothing and a scroll shows up within a frame or two,
/// instead of paying ~110 ms to locate the window and take a fresh screenshot on every look.
final class LiveFeed: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "EditAssist.live", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: CGImage?
    private var scheduled = false
    /// Called on the main thread with the newest frame. Frames that arrive while one is being handled
    /// replace each other, so a busy main thread never falls behind the screen.
    var onFrame: ((CGImage) -> Void)?
    var onStop: (() -> Void)?

    @MainActor func start(_ choice: WindowChoice) async throws -> CGRect {
        await stop()
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == choice.id && $0.owningApplication?.processID == choice.pid }) else {
            throw AssistError.message("That window has closed. Click the window you want to work in, then try again.")
        }
        // Same pixel size as Desktop.capture, so OCR, the grid and the row tracker see identical images.
        let config = SCStreamConfiguration()
        let scale = min(1.5, 2400 / window.frame.width)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.includeChildWindows = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 4
        let created = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: self)
        try created.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        // Registered before starting: the first frame can arrive before startCapture returns, and an
        // idle window sends no second one.
        stream = created
        do { try await created.startCapture() } catch { if stream === created { stream = nil }; throw error }
        return window.frame
    }

    @MainActor func stop() async {
        guard let current = stream else { return }
        stream = nil
        try? await current.stopCapture()
    }

    var running: Bool { stream != nil }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sample),
              let image = Self.image(from: buffer) else { return }
        lock.lock()
        pending = image
        let schedule = !scheduled
        scheduled = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let frame = self.pending
            self.pending = nil; self.scheduled = false
            self.lock.unlock()
            if let frame { self.onFrame?(frame) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.onStop?()
        }
    }

    /// Copies the frame out of ScreenCaptureKit's buffer pool, so holding a reading or the tracker's
    /// previous look never starves the stream of buffers.
    static func image(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard let provider = CGDataProvider(data: Data(bytes: base, count: stride * height) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Where the window is now, in the same top-left screen points as SCWindow.frame. Cheap enough
    /// to ask on every frame, which keeps the overlay on the window while it is dragged.
    static func bounds(of id: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let dictionary = info.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }
}
