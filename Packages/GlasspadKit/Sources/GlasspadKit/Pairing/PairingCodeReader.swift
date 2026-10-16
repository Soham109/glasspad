import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// Reads a QR code out of a picture with Vision: the phone's camera frames, and the tests'
/// renders of the Mac's pattern. The Mac shows light dots on a dark card in Dark Mode, so a
/// picture with no code in it is tried again with its brightness inverted.
public enum PairingCodeReader {
    public struct Reading: Sendable, Equatable {
        public let text: String
        /// Where the code is, in Vision's normalised space (0...1, origin bottom left) of the
        /// picture as it was handed in.
        public let bounds: CGRect
    }

    /// The first QR code in `image`, read as it is or inverted.
    public static func read(_ image: CIImage, orientation: CGImagePropertyOrientation = .up,
                            tryInverted: Bool = true) -> Reading? {
        if let found = detect(image, orientation: orientation) { return found }
        guard tryInverted else { return nil }
        let invert = CIFilter.colorInvert()
        invert.inputImage = image
        guard let inverted = invert.outputImage else { return nil }
        return detect(inverted, orientation: orientation)
    }

    public static func read(_ image: CGImage) -> Reading? {
        read(CIImage(cgImage: image))
    }

    private static func detect(_ image: CIImage, orientation: CGImagePropertyOrientation) -> Reading? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(ciImage: image, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let hit = request.results?.first(where: { $0.payloadStringValue?.isEmpty == false }),
              let text = hit.payloadStringValue else { return nil }
        return Reading(text: text, bounds: hit.boundingBox)
    }
}
