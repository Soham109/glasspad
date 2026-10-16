@preconcurrency import AVFoundation
import GlasspadKit
import SwiftUI
import UIKit

/// Live camera preview that reads QR codes with Vision (`PairingCodeReader`), so the Mac's
/// moving dot pattern reads in light and dark, and reports where in the preview the code is,
/// so the frame can lock onto it.
struct QRScannerView: UIViewRepresentable {
    /// The code's text and its rectangle in this view's coordinates.
    var onCode: (String, CGRect) -> Void
    /// Change it to let the same code be reported again (after one that was not a pairing code).
    var attempt = 0

    func makeUIView(context: Context) -> ScannerPreview {
        let view = ScannerPreview()
        view.onCode = onCode
        view.start()
        return view
    }

    func updateUIView(_ uiView: ScannerPreview, context: Context) {
        uiView.onCode = onCode
        if uiView.attempt != attempt {
            uiView.attempt = attempt
            uiView.reset()
        }
    }

    static func dismantleUIView(_ uiView: ScannerPreview, coordinator: ()) {
        uiView.stop()
    }

    final class ScannerPreview: UIView {
        var onCode: ((String, CGRect) -> Void)?
        var attempt = 0
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "glasspad.scanner")
        private let reader = FrameReader()
        private var lastCode: String?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.session = session
            reader.onReading = { [weak self] reading in
                MainActor.assumeIsolated { self?.deliver(reading) }
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Keep the camera picture upright when the interface turns.
            guard let connection = previewLayer.connection,
                  let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation else { return }
            let angle: CGFloat = switch orientation {
            case .landscapeRight: 0
            case .landscapeLeft: 180
            case .portraitUpsideDown: 270
            default: 90
            }
            if connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
        }

        func start() {
            let session = self.session
            let reader = self.reader
            sessionQueue.async {
                session.beginConfiguration()
                session.sessionPreset = .hd1920x1080
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    session.commitConfiguration()
                    return
                }
                session.addInput(input)
                // A screen held close: focus near, and keep refocusing as the phone moves.
                if (try? device.lockForConfiguration()) != nil {
                    if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
                    if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                    device.unlockForConfiguration()
                }
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    return
                }
                session.addOutput(output)
                // Frames stay in the sensor's own orientation: the space the preview layer
                // converts code positions from.
                output.setSampleBufferDelegate(reader, queue: reader.queue)
                session.commitConfiguration()
                session.startRunning()
            }
        }

        func stop() {
            let session = self.session
            sessionQueue.async { session.stopRunning() }
        }

        func reset() { lastCode = nil }

        private func deliver(_ reading: PairingCodeReader.Reading) {
            guard reading.text != lastCode else { return }
            lastCode = reading.text
            // Vision's box has its origin bottom left; the capture space has it top left.
            let b = reading.bounds
            let metadataRect = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
            onCode?(reading.text, rect)
        }
    }
}

/// Reads camera frames on its own queue, about 15 a second, and reports each code it finds.
private final class FrameReader: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "glasspad.scanner.frames", qos: .userInitiated)
    /// Called on the main queue.
    var onReading: (@MainActor @Sendable (PairingCodeReader.Reading) -> Void)?
    private var lastRead: UInt64 = 0
    private var frame = 0

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastRead > 66_000_000, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRead = now
        frame += 1
        // Vision usually reads light dots on a dark card as they are; every other frame also
        // tries the picture inverted, in case it does not.
        guard let reading = PairingCodeReader.read(CIImage(cvPixelBuffer: buffer), tryInverted: frame % 2 == 0) else { return }
        let deliver = onReading
        DispatchQueue.main.async { MainActor.assumeIsolated { deliver?(reading) } }
    }
}

enum CameraAccess {
    static var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static var hasCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
