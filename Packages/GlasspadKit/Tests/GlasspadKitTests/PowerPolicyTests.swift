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
