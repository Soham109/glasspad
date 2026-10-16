import Foundation

/// What the phone reads from a website for a Website button: where its icons are and what it
/// calls itself. Pure parsing, so it is tested without the network. The phone only ever asks
/// the site itself (no favicon services), so nobody else learns which sites are pinned.
public enum SiteInfo {
    /// An icon the page declares, or one at a well known path.
    public struct IconCandidate: Equatable, Sendable {
        public var url: URL
        /// The declared size in pixels (the larger side), or a guess when it is not declared.
        public var size: Int
        public init(url: URL, size: Int) {
            self.url = url
            self.size = size
        }
    }

    /// The link a Website button opens, from what the user typed: `apple.com` becomes
    /// `https://apple.com`. Nil when it is not a web address.
    public static func webURL(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            guard !s.contains(":") || s.contains("."), s.contains(".") else { return nil }
            s = "https://" + s
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".") || host == "localhost" else { return nil }
        return url
    }

    /// The host an icon is stored under: lowercased, without `www.`.
    public static func key(for url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// A readable name from the address alone: `www.nytimes.com` is "Nytimes",
    /// `bbc.co.uk` is "Bbc". Used until (or instead of) the page's own name.
    public static func name(fromHost host: String) -> String {
        var labels = host.lowercased().split(separator: ".").map(String.init)
        if labels.first == "www" || labels.first == "m" { labels.removeFirst() }
        guard labels.count >= 2 else { return labels.first.map(capitalized) ?? host }
        let secondLevel = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or"]
        var i = labels.count - 2
        if i > 0, labels.last!.count == 2, secondLevel.contains(labels[i]) { i -= 1 }
        return capitalized(labels[i])
    }

    /// The site's name from its page: `og:site_name` or `application-name` when present,
    /// otherwise the part of the `<title>` that names the site ("Let's build · GitHub" is
    /// "GitHub"), otherwise the whole title.
    public static func title(html: String, host: String? = nil) -> String? {
        for key in ["og:site_name", "application-name", "apple-mobile-web-app-title"] {
            if let v = metaContent(html, key), !v.isEmpty, v.count <= 40 { return v }
        }
        guard let raw = firstMatch(html, #"<title[^>]*>([\s\S]*?)</title>"#).map(decodeEntities) else { return nil }
        let title = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let parts = title.components(separatedBy: CharacterSet(charactersIn: "|·•—–")).flatMap { $0.components(separatedBy: " - ") }
            .flatMap { $0.components(separatedBy: ": ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if parts.count > 1 {
            if let host {
                let label = name(fromHost: host).lowercased()
                if let match = parts.first(where: { $0.lowercased().replacingOccurrences(of: " ", with: "").contains(label) }) { return match }
            }
            return parts.min { $0.count < $1.count }
        }
        return title.count <= 40 ? title : String(title.prefix(40)).trimmingCharacters(in: .whitespaces)
    }

    /// Icons a page declares in `<link rel=...icon...>`, resolved against the page (or its
    /// `<base href>`), plus `/apple-touch-icon.png` and `/favicon.ico`, largest first.
    /// SVG and mask icons are left out (one colour outlines, and images the phone cannot draw).
    public static func iconCandidates(html: String, page: URL) -> [IconCandidate] {
        let base = firstMatch(html, #"<base\s[^>]*href\s*=\s*["']([^"']+)["']"#).flatMap { URL(string: $0, relativeTo: page) } ?? page
        var found: [IconCandidate] = []
        for tag in allMatches(html, #"<link\s[^>]*>"#) {
            guard let rel = attribute(tag, "rel")?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attribute(tag, "href").map(decodeEntities), !href.isEmpty,
                  let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            let type = attribute(tag, "type")?.lowercased() ?? ""
            if url.pathExtension.lowercased() == "svg" || type.contains("svg") { continue }
            let declared = attribute(tag, "sizes").map(largestSize) ?? 0
            let guess = rel.contains("apple-touch-icon") ? 180 : (url.pathExtension.lowercased() == "ico" ? 32 : 64)
            found.append(IconCandidate(url: url, size: declared > 0 ? declared : guess))
        }
        if let origin = origin(of: page) {
            for (path, size) in [("apple-touch-icon.png", 180), ("favicon.ico", 32)] {
                if let url = URL(string: path, relativeTo: origin)?.absoluteURL { found.append(IconCandidate(url: url, size: size)) }
            }
        }
        var seen = Set<URL>()
        let unique = found.filter { seen.insert($0.url).inserted }
        // Largest first; for equal sizes, declared order.
        return unique.enumerated().sorted { a, b in
            a.element.size != b.element.size ? a.element.size > b.element.size : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Helpers

    static func origin(of url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return URL(string: "\(scheme)://\(host)\(url.port.map { ":\($0)" } ?? "")/")
    }

    /// The largest side in a `sizes` attribute (`"16x16 32x32"`), 512 for `any`.
    static func largestSize(_ sizes: String) -> Int {
        sizes.lowercased().split(separator: " ").compactMap { item -> Int? in
            if item == "any" { return 512 }
            let parts = item.split(separator: "x").compactMap { Int($0) }
            return parts.count == 2 ? max(parts[0], parts[1]) : nil
        }.max() ?? 0
    }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private static func metaContent(_ html: String, _ key: String) -> String? {
        for tag in allMatches(html, #"<meta\s[^>]*>"#) {
            let name = (attribute(tag, "property") ?? attribute(tag, "name"))?.lowercased()
            if name == key, let content = attribute(tag, "content") {
                return decodeEntities(content).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    static func attribute(_ tag: String, _ name: String) -> String? {
        let pattern = #"(?:^|[\s"'])"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for i in 1...3 {
            if let r = Range(m.range(at: i), in: tag) { return String(tag[r]) }
        }
        return nil
    }

    private static func firstMatch(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    private static func allMatches(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        for (k, v) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"),
                       ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&middot;", "·"), ("&ndash;", "–"), ("&mdash;", "—")] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out
    }
}
