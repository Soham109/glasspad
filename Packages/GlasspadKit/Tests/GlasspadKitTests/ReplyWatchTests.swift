import Testing
@testable import GlasspadKit

@Suite struct ReplyWatchTests {
    @Test func anUnansweredRequestFailsOnceAtItsDeadline() {
        var w = ReplyWatch()
        let g = w.start()
        #expect(w.isWaiting)
        let first = w.timedOut(g), second = w.timedOut(g)
        #expect(first && !second)
        #expect(!w.isWaiting)
    }

    @Test func anAnswerOrANewerRequestCancelsTheDeadline() {
        var w = ReplyWatch()
        let answered = w.start()
        w.settle()
        let afterAnswer = w.timedOut(answered)
        let older = w.start()
        let newer = w.start()
        let oldExpired = w.timedOut(older), newExpired = w.timedOut(newer)
        #expect(!afterAnswer && !oldExpired && newExpired)
    }
}
