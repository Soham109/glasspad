import ImageIO
import SwiftUI
import UIKit
import GlasspadKit

/// Logos and names for Website buttons, fetched by the phone from the site itself (never from
/// a favicon service, so no one else learns which sites are pinned). Each site is asked once:
/// the logo is kept in the Caches folder by host, and a site with no usable logo is not asked
/// again for a week.
///
/// Every logo is redrawn as a plain sRGB bitmap and checked before it is kept, and read back
/// with ImageIO. UIKit's own decoder refused some of them ("Error -17102 decompressing image"):
/// grey PNGs and the PNGs `UIImage.pngData()` writes for a scaled-down `.ico` frame.
@MainActor
@Observable
final class WebsiteIcons {
    static let shared = WebsiteIcons()

    /// host key -> logo. Observed, so tiles update when a logo arrives.
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var loading: [String: Task<UIImage?, Never>] = [:]
    @ObservationIgnored private var titles: [String: String] = [:]
    /// Sites that did not answer at all (offline, a typo, a timeout): asked again after a
    /// minute, never marked as having no logo.
    @ObservationIgnored private var unreachable: [String: Date] = [:]
    @ObservationIgnored private let folder: URL?
    @ObservationIgnored private let session: URLSession

    /// Logos are stored at most this many pixels on a side: sharp at 3x for any tile size.
    nonisolated static let storedPixels: CGFloat = 256
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
        // Logos come back from disk on demand, so memory can go first when it is short.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WebsiteIcons.shared.images.removeAll() }
        }
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
        guard !recentlyMissing(key), (unreachable[key].map { Date() > $0 } ?? true) else { return nil }
        // A moment's wait, so an address being typed is not fetched at every letter (the
        // caller's task is cancelled when the link changes).
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return nil }
        if let image = images[key] { return image }
        if let task = loading[key] { return await task.value }
        let task = Task { await self.fetch(url, key: key) }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image { images[key] = image }
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
        let results = await withTaskGroup(of: (answered: Bool, image: CGImage?).self) { group in
            for c in candidates.filter({ SiteFetch.mayFetch($0.url, site: target) }).prefix(5) {
                group.addTask { await Self.download(c.url, site: target, session: session) }
            }
            var all: [(answered: Bool, image: CGImage?)] = []
            for await result in group { all.append(result) }
            return all
        }
        let images = results.compactMap(\.image)
        guard let best = images.max(by: { min($0.width, $0.height) < min($1.width, $1.height) }),
              min(best.width, best.height) >= 16 else {
            // Only a site that answered is known to have no logo; one that could not be
            // reached is asked again later.
            if loaded != nil || results.contains(where: \.answered) {
                markMissing(key)
            } else {
                unreachable[key] = Date().addingTimeInterval(60)
            }
            return nil
        }
        // A logo that does not survive being stored is not kept, and asked for again later.
        guard let clean = LogoImage.plainBitmap(best), let png = LogoImage.png(clean), LogoImage.decode(png) != nil else {
            unreachable[key] = Date().addingTimeInterval(60)
            return nil
        }
        if let file = file(key) { try? png.write(to: file, options: .atomic) }
        return UIImage(cgImage: clean)
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
        guard let (head, http) = await SiteFetch.data(for: request, site: url, limit: Self.pageLimit, cut: true, session: session),
              (200..<400).contains(http.statusCode) else { return nil }
        let html = String(data: head, encoding: .utf8) ?? String(decoding: head, as: UTF8.self)
        return (html, http.url ?? url)
    }

    /// Downloads an image (at most 3 MB) and decodes its largest frame, scaled down to
    /// `storedPixels` while decoding (`LogoImage.thumbnail`). `answered` says whether the site
    /// replied at all.
    private nonisolated static func download(_ url: URL, site: URL, session: URLSession) async -> (answered: Bool, image: CGImage?) {
        guard let (data, http) = await SiteFetch.data(for: URLRequest(url: url), site: site, limit: 3_000_000, session: session)
        else { return (false, nil) }
        guard http.statusCode == 200 else { return (true, nil) }
        return (true, LogoImage.thumbnail(data, maxPixelSize: Int(storedPixels)))
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
        // Kept by an older build as it came, or damaged: dropped, so it is fetched again.
        guard let image = LogoImage.decode(data), LogoImage.isPlain(image) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return UIImage(cgImage: image)
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
