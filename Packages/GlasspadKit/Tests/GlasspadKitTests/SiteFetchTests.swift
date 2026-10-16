import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GlasspadKit

@Suite struct SiteFetchTests {
    private let site = URL(string: "https://example.com")!

    /// A page can name any address as its icon. Devices on the Wi-Fi, plain http and addresses
    /// written as numbers are never asked, so a site cannot point the phone at the router.
    @Test func iconsAndRedirectsNeverReachTheLocalNetwork() {
        for bad in ["http://example.com/favicon.ico", "https://192.168.1.1/reboot", "https://127.1/", "https://[::1]/x.png",
                    "https://10.0.0.1:8443/a.png", "https://router.local/logo.png", "https://nas/x.png", "https://localhost/x.png",
                    "https://0x7f.0x0.0x0.0x1/", "https://printer.home.arpa/i.png", "ftp://example.com/x.png"] {
            #expect(!SiteFetch.mayFetch(URL(string: bad)!, site: site), "\(bad)")
        }
        for good in ["https://example.com/favicon.ico", "https://cdn.example.net/apple-touch-icon.png", "https://EXAMPLE.com/a.png"] {
            #expect(SiteFetch.mayFetch(URL(string: good)!, site: site), "\(good)")
        }
        // A link the user typed to a device of their own is asked, and only that device.
        let nas = URL(string: "https://192.168.1.20")!
        #expect(SiteFetch.mayFetch(URL(string: "https://192.168.1.20/favicon.ico")!, site: nas))
        #expect(!SiteFetch.mayFetch(URL(string: "https://192.168.1.1/favicon.ico")!, site: nas))
    }

    @Test func refusedAddressesAreNeverRequested() async {
        let request = URLRequest(url: URL(string: "http://192.168.1.1/")!)
        #expect(await SiteFetch.data(for: request, site: site, limit: 10, session: .shared) == nil)
    }

    /// A huge or endlessly decompressing answer stops at the limit instead of filling memory.
    @Test func readingStopsAtTheLimit() async throws {
        func stream(_ n: Int) -> AsyncStream<UInt8> {
            AsyncStream { c in
                for _ in 0..<n { c.yield(7) }
                c.finish()
            }
        }
        #expect(try await SiteFetch.collect(stream(100), limit: 100, cut: false)?.count == 100)
        #expect(try await SiteFetch.collect(stream(101), limit: 100, cut: false) == nil)
        #expect(try await SiteFetch.collect(stream(5000), limit: 100, cut: true)?.count == 100)
        // Endless: still ends.
        #expect(try await SiteFetch.collect(Endless(), limit: 1000, cut: false) == nil)
    }

    /// A logo file of a few bytes that says it is 50000 pixels square is never decoded.
    @Test func logoDecompressionBombsAreNotDecoded() throws {
        let bomb = blankPNG(width: 5000, height: 5000)
        let source = try #require(CGImageSourceCreateWithData(bomb as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 5000 && bomb.count < 30_000)
        #expect(LogoImage.thumbnail(bomb, maxPixelSize: 256) == nil)
        let ctx = try #require(CGContext(data: nil, width: 600, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
        let image = try #require(ctx.makeImage())
        let png = try #require(LogoImage.png(image))
        let small = try #require(LogoImage.thumbnail(png, maxPixelSize: 256))
        #expect(small.width == 256 && small.height == 256)
    }
}

/// Bytes that never end, like a decompression bomb.
private struct Endless: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = UInt8
    mutating func next() async -> UInt8? { 1 }
    func makeAsyncIterator() -> Endless { self }
}

/// A black grey-scale PNG this size. Black rows pack a thousand to one, so the file is tiny
/// next to what it takes once decoded: the shape of a decompression bomb.
func blankPNG(width: UInt32, height: UInt32) -> Data {
    func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 { c = c & 1 != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
        }
        return ~c
    }
    func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + body
        return be(UInt32(body.count)) + typed + be(crc32(typed))
    }
    // Each row: filter byte 0, then the pixels. zlib framing around Foundation's raw deflate.
    let raw = Data(count: Int(height) * (Int(width) + 1))
    let deflated = (try? (raw as NSData).compressed(using: .zlib) as Data) ?? Data()
    // Adler-32 of all zero bytes: 1, and the length.
    let idat = [0x78, 0x9C] + Array(deflated) + be(UInt32(raw.count % 65521) << 16 | 1)
    let header = be(width) + be(height) + [8, 0, 0, 0, 0]
    return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", header) + chunk("IDAT", idat) + chunk("IEND", []))
}
