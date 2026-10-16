import Foundation
import Testing
@testable import GlasspadKit

@Suite struct SiteInfoTests {
    let page = URL(string: "https://www.example.com/news/today.html")!

    @Test func iconsAreResolvedRankedAndFiltered() {
        let html = """
        <html><head>
        <link rel="icon" href="/favicon-16.png" sizes="16x16">
        <link rel='apple-touch-icon' href='touch.png'>
        <link rel="icon" type="image/svg+xml" href="/logo.svg">
        <link rel="mask-icon" href="/mask.png">
        <link href="https://cdn.example.com/big.png" rel="icon" sizes="192x192 512x512">
        <link rel="stylesheet" href="/site.css">
        </head></html>
        """
        let urls = SiteInfo.iconCandidates(html: html, page: page).map(\.url.absoluteString)
        #expect(urls == [
            "https://cdn.example.com/big.png",
            "https://www.example.com/news/touch.png",
            "https://www.example.com/apple-touch-icon.png",
            "https://www.example.com/favicon.ico",
            "https://www.example.com/favicon-16.png",
        ])
    }

    @Test func baseHrefAndEntitiesAreHonoured() {
        let html = #"<base href="https://static.example.com/a/"><link rel="shortcut icon" href="i.png?v=1&amp;x=2">"#
        let first = SiteInfo.iconCandidates(html: html, page: page).first { $0.url.host == "static.example.com" }
        #expect(first?.url.absoluteString == "https://static.example.com/a/i.png?v=1&x=2")
    }

    @Test func pagesWithoutIconsStillTryTheWellKnownPaths() {
        let urls = SiteInfo.iconCandidates(html: "<html></html>", page: URL(string: "http://site.org:8080/x")!).map(\.url.absoluteString)
        #expect(urls == ["http://site.org:8080/apple-touch-icon.png", "http://site.org:8080/favicon.ico"])
    }

    @Test func titlePrefersTheSiteName() {
        #expect(SiteInfo.title(html: #"<meta property="og:site_name" content="The Verge"><title>Some story - The Verge</title>"#) == "The Verge")
        #expect(SiteInfo.title(html: "<title>Let&#39;s build from here · GitHub</title>", host: "github.com") == "GitHub")
        #expect(SiteInfo.title(html: "<title>\n  Hacker News\n</title>") == "Hacker News")
        #expect(SiteInfo.title(html: "<title>Inbox | Mail</title>", host: "fastmail.com") == "Mail")
        #expect(SiteInfo.title(html: "<p>no title</p>") == nil)
    }

    @Test func namesAndKeysFromTheAddress() {
        #expect(SiteInfo.name(fromHost: "www.nytimes.com") == "Nytimes")
        #expect(SiteInfo.name(fromHost: "news.bbc.co.uk") == "Bbc")
        #expect(SiteInfo.name(fromHost: "m.youtube.com") == "Youtube")
        #expect(SiteInfo.name(fromHost: "localhost") == "Localhost")
        #expect(SiteInfo.key(for: URL(string: "https://WWW.Apple.com/mac")!) == "apple.com")
    }

    @Test func typedAddressesBecomeLinks() {
        #expect(SiteInfo.webURL("apple.com")?.absoluteString == "https://apple.com")
        #expect(SiteInfo.webURL(" https://x.org/a ")?.absoluteString == "https://x.org/a")
        #expect(SiteInfo.webURL("https://") == nil)
        #expect(SiteInfo.webURL("hello world") == nil)
        #expect(SiteInfo.webURL("x-apple.systempreferences:com.apple.wifi") == nil)
        #expect(SiteInfo.webURL("ftp://x.org") == nil)
        // Other kinds of links stay what they are.
        #expect(SiteInfo.webURL("mailto:me@example.com") == nil)
        #expect(SiteInfo.webURL("slack://open?team=a.b") == nil)
        #expect(SiteInfo.webURL("example.com:8080/x")?.absoluteString == "https://example.com:8080/x")
        #expect(SiteInfo.webURL("en.wikipedia.org/wiki/Help:Contents") != nil)
        #expect(SiteInfo.webURL("localhost:3000")?.absoluteString == "https://localhost:3000")
    }

    @Test func sizesAttribute() {
        #expect(SiteInfo.largestSize("16x16 32x32") == 32)
        #expect(SiteInfo.largestSize("any") == 512)
        #expect(SiteInfo.largestSize("bogus") == 0)
    }
}
