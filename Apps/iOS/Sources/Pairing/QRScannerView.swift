@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Live camera preview that reports the first QR code it reads.
/// Uses `AVCaptureMetadataOutput`, so decoding happens in the system, not in our code.
struct QRScannerView: UIViewRepresentable {
    var onCode: (String) -> Void

    func makeUIView(context: Context) -> ScannerPreview {
        let view = ScannerPreview()
        view.onCode = onCode
        view.start()
        return view
    }

    func updateUIView(_ uiView: ScannerPreview, context: Context) {
        uiView.onCode = onCode
    }

    static func dismantleUIView(_ uiView: ScannerPreview, coordinator: ()) {
        uiView.stop()
    }

    final class ScannerPreview: UIView, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "glasspad.scanner")
        private var lastCode: String?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.session = session
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func start() {
            let session = self.session
            sessionQueue.async { [weak self] in
                guard let self else { return }
                session.beginConfiguration()
                session.sessionPreset = .high
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    session.commitConfiguration()
                    return
                }
                session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    return
                }
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()
                session.startRunning()
            }
        }

        func stop() {
            let session = self.session
            sessionQueue.async { session.stopRunning() }
        }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                        didOutput metadataObjects: [AVMetadataObject],
                                        from connection: AVCaptureConnection) {
            let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            guard let code = codes.first else { return }
            MainActor.assumeIsolated {
                guard code != lastCode else { return }
                lastCode = code
                onCode?(code)
            }
        }
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
