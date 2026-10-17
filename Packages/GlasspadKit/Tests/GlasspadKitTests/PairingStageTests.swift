import Foundation
import Testing
@testable import GlasspadKit

/// The screen after the scan: no "Paired" before Allow, the refusal shown, then connected.
@Suite struct PairingStageTests {
    @Test func neverPairedBeforeTheMacLetsThePhoneIn() {
        #expect(PairingStage(state: .searching, issue: nil, hasConnected: false) == .reaching)
        #expect(PairingStage(state: .connecting, issue: nil, hasConnected: false) == .reaching)
        #expect(PairingStage(state: .connecting, issue: .awaitingApproval, hasConnected: false) == .awaitingApproval)
        #expect(PairingStage(state: .connected(rttMs: nil), issue: nil, hasConnected: true) == .connected)
        #expect(PairingStage(state: .searching, issue: nil, hasConnected: true) == .reconnecting)
    }

    @Test func aRefusalIsShownEvenWhileTheIssueLingers() {
        let refused = PairingStage(state: .failed(GlasspadService.notAllowedFailure), issue: .awaitingApproval,
                                   hasConnected: false)
        #expect(refused == .failed(GlasspadService.notAllowedFailure))
    }
}
