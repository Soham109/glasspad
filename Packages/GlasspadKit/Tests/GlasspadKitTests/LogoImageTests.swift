import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GlasspadKit

@Suite struct LogoImageTests {
    /// A grey image, like the Wikipedia logo UIKit refused to decode.
    private func grey(_ side: Int = 32) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0.3, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }

    private func encode(_ image: CGImage, as type: UTType) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return data as Data
    }

    @Test func greyAndIconLogosAreStoredAsPlainSRGB() throws {
        let greyPNG = encode(grey(), as: .png)
        let greyDecoded = try #require(LogoImage.decode(greyPNG))
        #expect(!LogoImage.isPlain(greyDecoded))
        let rgb = try #require(LogoImage.plainBitmap(grey()))
        let icon = encode(rgb, as: .ico)
        for data in [greyPNG, icon] {
            let decoded = try #require(LogoImage.decode(data))
            let plain = try #require(LogoImage.plainBitmap(decoded))
            #expect(LogoImage.isPlain(plain))
            let stored = try #require(LogoImage.png(plain))
            let back = try #require(LogoImage.decode(stored))
            #expect(LogoImage.isPlain(back) && back.width == 32)
        }
    }

    @Test func whatIsNotAnImageIsNotKept() {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>"#.utf8)
        let page = Data("<!doctype html><title>Not found</title>".utf8)
        let cut = encode(grey(), as: .png).prefix(30)
        for data in [svg, page, Data(cut), Data()] { #expect(LogoImage.decode(data) == nil) }
    }
}
