import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Testing
@testable import GlasspadKit

/// The Mac shows the pairing code as moving dots. These draw that pattern the way the Mac does
/// (light and dark, at many moments of its motion, small and large) and read it back with the
/// same Vision reader the iPhone uses, so a styling change that breaks scanning fails here.
@Suite("Pairing pattern")
struct PairingPatternTests {
    static let payload = PairingPayload(macID: UUID(uuidString: "6F1C2A4E-3B5D-4C7E-9F10-2A3B4C5D6E7F")!,
                                        macName: "Soham's MacBook Pro",
                                        pairKey: Data((0..<32).map { UInt8($0 * 7 & 0xFF) }))
    static let message = payload.url.absoluteString

    @Test func matrixIsARealCode() throws {
        let p = try #require(PairingPattern(message: Self.message))
        // Version 2 and up are 4k+17 modules wide.
        #expect((p.size - 17) % 4 == 0)
        #expect(p.size >= 25)
        // Finder squares: a dark ring around a light ring around a dark 3x3 center.
        for (r0, c0) in [(0, 0), (0, p.size - 7), (p.size - 7, 0)] {
            #expect(p.isDark(row: r0, column: c0))
            #expect(!p.isDark(row: r0 + 1, column: c0 + 1))
            #expect(p.isDark(row: r0 + 3, column: c0 + 3))
        }
        // Dots are every dark module outside the finders.
        let dark = p.modules.filter { $0 }.count
        #expect(p.dots.count == dark - 3 * (24 + 9))
    }

    @Test func plainRenderReadsBack() throws {
        let p = try #require(PairingPattern(message: Self.message))
        let image = try #require(Render.image(p, time: 0, motion: 0, dark: false, side: 400))
        #expect(PairingCodeReader.read(image)?.text == Self.message)
    }

    @Test(arguments: [false, true])
    func movingPatternReadsBackThroughoutItsMotion(dark: Bool) throws {
        let p = try #require(PairingPattern(message: Self.message))
        // Many moments across the drift and shimmer cycles, and two sizes the Mac uses.
        for side in [220, 300] {
            for step in 0..<12 {
                let t = Double(step) * 1.37
                let image = try #require(Render.image(p, time: t, motion: 1, dark: dark, side: side))
                let read = PairingCodeReader.read(image)
                #expect(read?.text == Self.message, "not read: dark \(dark), side \(side), t \(t)")
            }
        }
    }

    /// Roughly what a phone camera gets from a screen: softer, smaller, washed out and tilted.
    @Test(arguments: [false, true])
    func readsThroughACameraLikePicture(dark: Bool) throws {
        let p = try #require(PairingPattern(message: Self.message))
        let image = try #require(Render.image(p, time: 2.2, motion: 1, dark: dark, side: 300))
        var picture = CIImage(cgImage: image)
            .applyingGaussianBlur(sigma: 1.2)
            .transformed(by: CGAffineTransform(rotationAngle: 0.22).scaledBy(x: 0.6, y: 0.6))
        // Contrast down to about two thirds, as glare and a dim screen do.
        let flatten = CIFilter.colorControls()
        flatten.inputImage = picture
        flatten.contrast = 0.65
        picture = try #require(flatten.outputImage)
        #expect(PairingCodeReader.read(picture)?.text == Self.message)
    }

    @Test func readerFindsTheCodeWhereItIs() throws {
        let p = try #require(PairingPattern(message: Self.message))
        let image = try #require(Render.image(p, time: 0, motion: 1, dark: true, side: 260, canvas: 600, at: CGPoint(x: 60, y: 80)))
        let read = try #require(PairingCodeReader.read(image))
        // Vision's box has its origin bottom left; the code was drawn 80 pt from the top.
        let box = read.bounds
        #expect(abs(box.minX - 0.1) < 0.06)
        #expect(abs((1 - box.maxY) - 80.0 / 600) < 0.06)
        #expect(abs(box.width - 0.4) < 0.08)
    }

    @Test func motionStaysInsideTheCell() throws {
        let p = try #require(PairingPattern(message: Self.message))
        for t in stride(from: 0.0, to: 30, by: 0.7) {
            for (dot, drawn) in zip(p.dots, p.frame(time: t)) {
                #expect(abs(drawn.center.x - dot.home.x) <= PairingPattern.drift + 0.0001)
                #expect(abs(drawn.center.y - dot.home.y) <= PairingPattern.drift + 0.0001)
                #expect(drawn.alpha >= 0.79 && drawn.alpha <= 1.0001)
            }
        }
    }

    @Test func reduceMotionStandsStill() throws {
        let p = try #require(PairingPattern(message: Self.message))
        #expect(p.frame(time: 1, motion: 0) == p.frame(time: 9, motion: 0))
    }

    @Test func gatherEndsAsACheckmarkInARing() throws {
        let p = try #require(PairingPattern(message: Self.message))
        let end = p.frame(time: 3, motion: 1, gather: 1)
        let landed = zip(p.dots, end).filter { $0.0.target != nil }
        #expect(landed.count > 60)
        for (dot, drawn) in landed {
            #expect(hypot(drawn.center.x - dot.target!.x, drawn.center.y - dot.target!.y) < 0.1)
            #expect(drawn.success == 1)
        }
        for (dot, drawn) in zip(p.dots, end) where dot.target == nil { #expect(drawn.alpha == 0) }
        #expect(PairingPattern.finderAlpha(gather: 1) == 0)
    }

    @Test func eachFrameIsCheap() throws {
        let p = try #require(PairingPattern(message: Self.message))
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for i in 0..<120 { _ = p.frame(time: Double(i) / 60, motion: 1, gather: 0) }
        }
        // Two seconds of frames in well under a frame's budget each.
        #expect(elapsed < .milliseconds(120 * 2))
    }
}

enum Render {
    /// The pattern on its card: dark dots on white, or light dots on near black.
    static func image(_ p: PairingPattern, time: Double, motion: Double, dark: Bool, side: Int,
                      canvas: Int? = nil, at origin: CGPoint? = nil) -> CGImage? {
        let full = canvas ?? side + 40
        guard let ctx = CGContext(data: nil, width: full, height: full, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Top-left origin, as the views draw.
        ctx.translateBy(x: 0, y: CGFloat(full))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(dark ? CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1) : CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: full, height: full))
        let o = origin ?? CGPoint(x: 20, y: 20)
        let ink = dark ? CGColor(red: 0.92, green: 0.95, blue: 1, alpha: 1) : CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
        p.draw(in: ctx, rect: CGRect(x: o.x, y: o.y, width: CGFloat(side), height: CGFloat(side)),
               time: time, motion: motion, ink: ink)
        return ctx.makeImage()
    }
}
