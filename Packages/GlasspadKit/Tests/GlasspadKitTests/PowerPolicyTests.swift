import Foundation
import Testing
@testable import GlasspadKit

@Suite struct PowerPolicyTests {
    let awake = KeepAwakeInputs(sceneActive: true, enabled: true, screenNeedsIt: true,
                                coveredBySheet: false, connected: true, idle: 0)

    @Test func coolPhoneRunsEverything() {
        let p = PowerPolicy()
        #expect(!p.isWarm)
        #expect(p.allowsHaptics && p.allowsHeartbeats)
        #expect(p.decorativeFrameRate == 60)
        #expect(p.decorativeFrameInterval == 1.0 / 60)
        #expect(p.marqueePasses == 3)
        #expect(p.progressInterval == 0.25)
        #expect(p.heartbeatIdleTimeout == GlasspadService.heartbeatIdleTimeout)
        #expect(p.keepAwakeLimit == 600)
    }

    @Test func lowPowerTrimsExtras() {
        let p = PowerPolicy(lowPower: true)
        #expect(p.allowsHaptics && p.allowsHeartbeats)
        #expect(p.decorativeFrameRate == 30)
        #expect(p.marqueePasses == 1)
        #expect(p.progressInterval == 1)
        #expect(p.heartbeatIdleTimeout == PowerPolicy.lowPowerHeartbeatIdle)
        #expect(p.keepAwakeLimit == 180)
    }

    @Test func fairHeatOnlySlowsMotion() {
        let p = PowerPolicy(heat: .fair)
        #expect(!p.isWarm)
        #expect(p.decorativeFrameRate == 30)
        #expect(p.marqueePasses == 3)
        #expect(p.keepAwakeLimit == 600)
    }

    @Test func warmPhoneHoldsStill() {
        for heat in [PowerPolicy.Heat.serious, .critical] {
            let p = PowerPolicy(heat: heat)
            #expect(p.isWarm)
            #expect(!p.allowsHaptics && !p.allowsHeartbeats)
            #expect(p.decorativeFrameRate == 0)
            #expect(p.decorativeFrameInterval == nil)
            #expect(p.marqueePasses == 0)
            #expect(p.progressInterval == 1)
        }
        #expect(PowerPolicy(heat: .serious).keepAwakeLimit == 180)
        #expect(PowerPolicy(heat: .critical).keepAwakeLimit == 60)
    }

    @Test func heatOrders() {
        #expect(PowerPolicy.Heat.nominal < .fair)
        #expect(PowerPolicy.Heat.fair < .serious)
        #expect(PowerPolicy.Heat.serious < .critical)
    }

    @Test func keepAwakeNeedsEveryCondition() {
        let p = PowerPolicy()
        #expect(p.keepsScreenAwake(awake))
        var s = awake; s.sceneActive = false
        #expect(!p.keepsScreenAwake(s))
        s = awake; s.enabled = false
        #expect(!p.keepsScreenAwake(s))
        s = awake; s.screenNeedsIt = false
        #expect(!p.keepsScreenAwake(s))
        s = awake; s.coveredBySheet = true
        #expect(!p.keepsScreenAwake(s))
        s = awake; s.connected = false
        #expect(!p.keepsScreenAwake(s))
    }

    @Test func keepAwakeLetsGoAfterLongIdle() {
        var s = awake
        s.idle = 599
        #expect(PowerPolicy().keepsScreenAwake(s))
        s.idle = 600
        #expect(!PowerPolicy().keepsScreenAwake(s))
        s.idle = 200
        #expect(PowerPolicy().keepsScreenAwake(s))
        #expect(!PowerPolicy(lowPower: true).keepsScreenAwake(s))
        s.idle = 61
        #expect(!PowerPolicy(heat: .critical).keepsScreenAwake(s))
    }
}

@Suite struct IdleDeadlineTests {
    @Test func looksAgainWhenTheScreenWouldDim() {
        // Touched 10 s ago, dims after 60 s: look in 50 s, not every 2 s.
        #expect(IdleDeadline.next(idle: 10, dimDelay: 60, dimmed: false, holdingAwake: true,
                                  keepAwakeLimit: 600, blocked: false) == 50)
        // Dimmed already: the next thing is Keep Screen On letting go.
        #expect(IdleDeadline.next(idle: 70, dimDelay: 60, dimmed: true, holdingAwake: true,
                                  keepAwakeLimit: 600, blocked: false) == 530)
        // A limit shorter than the dim delay (Low Power Mode, 3 min, Dim After 5 min).
        #expect(IdleDeadline.next(idle: 0, dimDelay: 300, dimmed: false, holdingAwake: true,
                                  keepAwakeLimit: 180, blocked: false) == 180)
    }

    @Test func nothingLeftToWaitFor() {
        // Dimmed and no longer held awake: the next touch starts it again, no timer meanwhile.
        #expect(IdleDeadline.next(idle: 700, dimDelay: 60, dimmed: true, holdingAwake: false,
                                  keepAwakeLimit: 600, blocked: false) == nil)
        // Dim After set to Never and not held awake.
        #expect(IdleDeadline.next(idle: 5, dimDelay: 0, dimmed: false, holdingAwake: false,
                                  keepAwakeLimit: 600, blocked: false) == nil)
    }

    @Test func aPassedDeadlineDoesNotSpin() {
        // A check that comes late (the timer's tolerance) looks again soon, never at once.
        #expect(IdleDeadline.next(idle: 61, dimDelay: 60, dimmed: false, holdingAwake: false,
                                  keepAwakeLimit: 600, blocked: false) == IdleDeadline.minimumWait)
    }

    @Test func aSheetOnTopIsLookedAtNowAndThen() {
        #expect(IdleDeadline.next(idle: 1_000, dimDelay: 60, dimmed: false, holdingAwake: true,
                                  keepAwakeLimit: 600, blocked: true) == IdleDeadline.blockedPoll)
    }
}

@Suite struct TalkKeepAwakeTests {
    let talk = KeepAwakeInputs(sceneActive: true, enabled: true, screenNeedsIt: true,
                               coveredBySheet: false, connected: true, idle: 3_600, presenting: true)

    @Test func aTalkKeepsTheScreenOnPastTheLimit() {
        #expect(PowerPolicy().keepsScreenAwake(talk))
        #expect(PowerPolicy(lowPower: true).keepsScreenAwake(talk))
        #expect(PowerPolicy(heat: .serious).keepsScreenAwake(talk))
    }

    @Test func criticalHeatStillLetsGo() {
        #expect(!PowerPolicy(heat: .critical).keepsScreenAwake(talk))
        var s = talk; s.idle = 59
        #expect(PowerPolicy(heat: .critical).keepsScreenAwake(s))
        #expect(!PowerPolicy(heat: .critical).ignoresIdleLimit(presenting: true))
    }

    @Test func notPresentingIsUnchanged() {
        var s = talk; s.presenting = false
        #expect(!PowerPolicy().keepsScreenAwake(s))
        s.idle = 599
        #expect(PowerPolicy().keepsScreenAwake(s))
        #expect(!PowerPolicy().ignoresIdleLimit(presenting: false))
        // The default, for callers that do not know about talks.
        #expect(!KeepAwakeInputs(sceneActive: true, enabled: true, screenNeedsIt: true,
                                 coveredBySheet: false, connected: true, idle: 0).presenting)
    }

    @Test func aTalkStillNeedsEverythingElse() {
        let p = PowerPolicy()
        var s = talk; s.connected = false
        #expect(!p.keepsScreenAwake(s))
        s = talk; s.coveredBySheet = true
        #expect(!p.keepsScreenAwake(s))
        s = talk; s.sceneActive = false
        #expect(!p.keepsScreenAwake(s))
        s = talk; s.enabled = false
        #expect(!p.keepsScreenAwake(s))
        s = talk; s.screenNeedsIt = false
        #expect(!p.keepsScreenAwake(s))
    }
}
