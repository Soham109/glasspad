import Testing
@testable import GlasspadKit

@Suite struct RecentKeysTests {
    @Test func keepsUpToTheLimit() {
        var recent = RecentKeys<String>(limit: 2)
        #expect(recent.use("a").isEmpty)
        #expect(recent.use("b").isEmpty)
        #expect(recent.use("c") == ["a"])
        #expect(recent.keys == ["b", "c"])
    }

    @Test func usingAKeyAgainKeepsIt() {
        var recent = RecentKeys<String>(limit: 2)
        recent.use("a")
        recent.use("b")
        recent.use("a")
        #expect(recent.use("c") == ["b"])
        #expect(recent.keys == ["a", "c"])
    }

    @Test func theNewestKeyIsNeverDropped() {
        var recent = RecentKeys<Int>(limit: 0)
        #expect(recent.limit == 1)
        #expect(recent.use(1).isEmpty)
        #expect(recent.use(2) == [1])
        #expect(recent.use(2).isEmpty)
        #expect(recent.keys == [2])
    }

    @Test func removeAllStartsOver() {
        var recent = RecentKeys<Int>(limit: 1)
        recent.use(1)
        recent.removeAll()
        #expect(recent.use(2).isEmpty)
        #expect(recent.keys == [2])
    }
}
