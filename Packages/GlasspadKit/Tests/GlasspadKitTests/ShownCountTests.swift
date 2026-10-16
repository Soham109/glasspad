import Testing
@testable import GlasspadKit

@Suite struct ShownCountTests {
    /// Two trackpad panes, the new one appearing before the old one goes: still shown.
    @Test func staysShownUntilTheLastOneGoes() {
        var c = ShownCount()
        c.set(true)
        c.set(true)
        c.set(false)
        #expect(c.isShown)
        c.set(false)
        #expect(!c.isShown)
    }

    @Test func anExtraDisappearDoesNotHideTheNextOne() {
        var c = ShownCount()
        c.set(false)
        c.set(true)
        #expect(c.isShown && c.count == 1)
    }
}
