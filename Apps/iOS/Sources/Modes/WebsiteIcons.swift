import ImageIO
import SwiftUI
import UIKit
import GlasspadKit

/// Logos and names for Website buttons, fetched by the phone from the site itself (never from
/// a favicon service, so no one else learns which sites are pinned). Each site is asked once:
/// the logo is kept in the Caches folder by host, and a site with no usable logo is not asked
/// again for a week.
@MainActor
@Observable
final class WebsiteIcons {
    static let shared = WebsiteIcons()

    /// host key -> logo. Observed, so tiles update when a logo arrives.
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var loading: [String: Task<UIImage?, Never>] = [:]
    @ObservationIgnored private var titles: [String: String] = [:]
    @ObservationIgnored private let folder: URL?
    @ObservationIgnored private let session: URLSession

    /// Logos are stored at most this many pixels on a side: sharp at 3x for any tile size.
    static let storedPixels: CGFloat = 256
    private static let retryAfter: TimeInterval = 7 * 24 * 3600
    private static let pageLimit = 400_000

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        folder = base?.appendingPathComponent("SiteIcons", isDirectory: true)
        if let folder { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        // Sites serve their phone icons to a phone browser.
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept-Language": Locale.preferredLanguages.prefix(2).joined(separator: ","),
        ]
        session = URLSession(configuration: config)
    }

    /// The logo already on hand for a Website button's link (memory or disk), without asking
    /// the network. `load` fetches it.
    func image(for link: String) -> UIImage? {
        guard let url = SiteInfo.webURL(link), let key = SiteInfo.key(for: url) else { return nil }
        if let image = images[key] { return image }
        return nil
    }

    /// Gets the logo for a link: from disk, or from the site. Safe to call often; each site is
    /// fetched once at a time.
    @discardableResult
    func load(_ link: String) async -> UIImage? {
        guard let url = SiteInfo.webURL(link), let key = SiteInfo.key(for: url) else { return nil }
        if let image = images[key] { return image }
        if let disk = fromDisk(key) {
            images[key] = disk
            return disk
        }
        if let task = loading[key] { return await task.value }
        guard !recentlyMissing(key) else { return nil }
        let task = Task { await self.fetch(url, key: key) }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image { images[key] = image } else { markMissing(key) }
        return image
    }

    /// A name for the site: the page's own when it can be read, else one from the address.
    func title(for link: String) async -> String? {
        guard let url = SiteInfo.webURL(link), let key = SiteInfo.key(for: url) else { return nil }
        if let t = titles[key] { return t }
        if let html = await page(https(url))?.html, let t = SiteInfo.title(html: html, host: key) {
            titles[key] = t
            return t
        }
        return SiteInfo.name(fromHost: key)
    }

    // MARK: Fetching

    private func fetch(_ url: URL, key: String) async -> UIImage? {
        let target = https(url)
        let loaded = await page(target)
        if let html = loaded?.html, let t = SiteInfo.title(html: html, host: key) { titles[key] = t }
        let candidates = SiteInfo.iconCandidates(html: loaded?.html ?? "", page: loaded?.finalURL ?? target)
        // The best few, fetched together; the largest real image wins.
        let session = self.session
        let images = await withTaskGroup(of: CGImage?.self) { group in
            for c in candidates.prefix(5) { group.addTask { await Self.download(c.url, session: session) } }
            var all: [CGImage] = []
            for await image in group { if let image { all.append(image) } }
            return all
        }
        guard let best = images.max(by: { min($0.width, $0.height) < min($1.width, $1.height) }),
              min(best.width, best.height) >= 16 else { return nil }
        let image = UIImage(cgImage: best)
        let stored = Self.downscaled(image)
        if let png = stored.pngData(), let file = file(key) { try? png.write(to: file, options: .atomic) }
        return stored
    }

    /// Plain http links are asked over https (the phone allows only secure loads).
    private func https(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http", var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.scheme = "https"
        return c.url ?? url
    }

    private func page(_ url: URL) async -> (html: String, finalURL: URL)? {
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return nil }
        let head = data.prefix(Self.pageLimit)
        let html = String(data: head, encoding: .utf8) ?? String(decoding: head, as: UTF8.self)
        return (html, http.url ?? url)
    }

    /// Downloads an image and decodes its largest frame (an `.ico` holds several sizes).
    private nonisolated static func download(_ url: URL, session: URLSession) async -> CGImage? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 3_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var best: CGImage?
        for i in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            if best == nil || image.width > best!.width { best = image }
        }
        return best
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > storedPixels else { return image }
        let scale = storedPixels / side
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    // MARK: Disk

    private func file(_ key: String) -> URL? {
        folder?.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".png")
    }

    private func missingFile(_ key: String) -> URL? {
        folder?.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".missing")
    }

    private func fromDisk(_ key: String) -> UIImage? {
        guard let url = file(key), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)?.preparingForDisplay()
    }

    private func recentlyMissing(_ key: String) -> Bool {
        guard let url = missingFile(key),
              let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(date) < Self.retryAfter
    }

    private func markMissing(_ key: String) {
        guard let url = missingFile(key) else { return }
        try? Data().write(to: url, options: .atomic)
    }
}

/// A website's logo in a rounded square, or its first letter on a soft tile until the logo
/// arrives (and for sites that have none).
struct WebsiteLogo: View {
    @Environment(\.palette) private var palette
    let link: String
    let tint: Color
    let size: CGFloat
    var icons = WebsiteIcons.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        Group {
            if let image = icons.image(for: link) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    // Small or transparent logos sit on white, like a Home Screen web clip.
                    .background(Color.white)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(palette.lineColor, lineWidth: 0.5))
                    .saturation(palette.monochrome ? 0 : 1)
                    .transition(.opacity)
            } else {
                shape.fill(palette.tint(tint).opacity(palette.isDark ? 0.28 : 0.16))
                    .overlay {
                        Text(monogram)
                            .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.tint(tint))
                    }
                    .frame(width: size, height: size)
            }
        }
        .animation(.easeOut(duration: 0.2), value: icons.image(for: link) != nil)
        .task(id: link) { await icons.load(link) }
        .accessibilityHidden(true)
    }

    private var monogram: String {
        guard let url = SiteInfo.webURL(link), let key = SiteInfo.key(for: url) else { return "?" }
        return String(SiteInfo.name(fromHost: key).prefix(1)).uppercased()
    }
}

extension DeckAction {
    /// The link of a Website button (http or https), nil for every other action.
    var websiteLink: String? {
        guard case .openURL(let s) = self, SiteInfo.webURL(s) != nil,
              !s.hasPrefix(SettingsPanes.prefix) else { return nil }
        return s
    }
}
