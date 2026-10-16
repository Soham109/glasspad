import Foundation

/// How the phone fetches a website's page and logos: over https only, never more than a set
/// number of bytes (counted after decompression, so a compressed bomb stops early), and never
/// from a device on the local network unless the link the user typed is that device. A page
/// can name any address as its icon, or redirect anywhere, so without this a site could make
/// the phone send requests to the router or other devices on the Wi-Fi, which iOS lets through
/// for addresses like 192.168.1.1 even over plain http.
public enum SiteFetch {
    /// True when the phone may ask `url` for something on behalf of the link to `site`.
    public static func mayFetch(_ url: URL, site: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == site.host?.lowercased() { return true }
        return !isLocal(host)
    }

    /// An address on the local network, or one written as numbers (public sites always have a
    /// name): `localhost`, `printer.local`, `nas`, `192.168.1.1`, `127.1`, `[::1]`.
    static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if h.contains(":") || !h.contains(".") { return true }
        if h == "localhost" || [".localhost", ".local", ".home.arpa", ".internal", ".lan"].contains(where: h.hasSuffix) { return true }
        // A name's last part always has a letter; an address written as numbers does not.
        let last = h.split(separator: ".").last ?? ""
        return last.allSatisfy(\.isNumber) || last.hasPrefix("0x")
    }

    /// The response body, at most `limit` bytes. Past it: nil, or with `cut` the first `limit`
    /// bytes (a page is read only as far as its head). nil too when the request or a redirect
    /// goes where `mayFetch` says no.
    public static func data(for request: URLRequest, site: URL, limit: Int, cut: Bool = false,
                            session: URLSession) async -> (data: Data, response: HTTPURLResponse)? {
        guard let url = request.url, mayFetch(url, site: site) else { return nil }
        guard let (bytes, response) = try? await session.bytes(for: request, delegate: RedirectCheck(site: site)),
              let http = response as? HTTPURLResponse else { return nil }
        defer { bytes.task.cancel() }
        if !cut, http.expectedContentLength > Int64(limit) { return nil }
        guard let data = try? await collect(bytes, limit: limit, cut: cut) else { return nil }
        return (data, http)
    }

    /// Reads bytes until the end or the limit. Internal for tests.
    static func collect<S: AsyncSequence>(_ bytes: S, limit: Int, cut: Bool) async throws -> Data? where S.Element == UInt8 {
        var data = Data()
        for try await b in bytes {
            guard data.count < limit else { return cut ? data : nil }
            data.append(b)
        }
        return data
    }

    /// Follows a redirect only to a place `mayFetch` allows; otherwise the redirect itself is
    /// the answer, which no caller takes as a page or an image.
    private final class RedirectCheck: NSObject, URLSessionTaskDelegate, Sendable {
        let site: URL
        init(site: URL) { self.site = site }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard let url = request.url, SiteFetch.mayFetch(url, site: site) else { return nil }
            return request
        }
    }
}
