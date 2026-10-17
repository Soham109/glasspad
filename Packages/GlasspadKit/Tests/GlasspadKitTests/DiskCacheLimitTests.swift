import Foundation
import Testing
@testable import GlasspadKit

@Suite struct DiskCacheLimitTests {
    private func file(_ id: String, age: TimeInterval, bytes: Int) -> DiskCacheLimit.File<String> {
        .init(id: id, modified: Date(timeIntervalSince1970: 1_000_000 - age), bytes: bytes)
    }

    @Test func underTheLimitNothingGoes() {
        let limit = DiskCacheLimit(maxFiles: 3, maxBytes: 100)
        #expect(limit.overflow([file("a", age: 1, bytes: 10), file("b", age: 2, bytes: 10)]).isEmpty)
        #expect(limit.overflow([DiskCacheLimit.File<String>]()).isEmpty)
    }

    @Test func tooManyFilesDropsTheOldest() {
        let limit = DiskCacheLimit(maxFiles: 2, maxBytes: 1000)
        let files = [file("new", age: 1, bytes: 1), file("old", age: 30, bytes: 1), file("mid", age: 10, bytes: 1),
                     file("oldest", age: 50, bytes: 1)]
        #expect(limit.overflow(files) == ["oldest", "old"])
    }

    @Test func tooManyBytesDropsTheOldest() {
        let limit = DiskCacheLimit(maxFiles: 10, maxBytes: 100)
        let files = [file("a", age: 1, bytes: 60), file("b", age: 2, bytes: 30), file("c", age: 3, bytes: 30)]
        #expect(limit.overflow(files) == ["c"])
    }

    @Test func aSmallOlderFileStillFitsAfterABigOneIsDropped() {
        let limit = DiskCacheLimit(maxFiles: 10, maxBytes: 100)
        let files = [file("a", age: 1, bytes: 80), file("big", age: 2, bytes: 50), file("small", age: 3, bytes: 10)]
        #expect(limit.overflow(files) == ["big"])
    }

    @Test func theNewestFileStaysEvenWhenTooBig() {
        let limit = DiskCacheLimit(maxFiles: 10, maxBytes: 100)
        let files = [file("huge", age: 1, bytes: 500), file("b", age: 2, bytes: 10)]
        #expect(limit.overflow(files) == ["b"])
    }
}
