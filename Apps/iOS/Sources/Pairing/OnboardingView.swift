import SwiftUI

/// First launch, the way Apple sets up a new device: what Glasspad is, get the Mac ready, then
/// the pairing flow (permissions explained, the viewfinder, and the Mac it connected to).
struct OnboardingView: View {
    var onFinish: () -> Void

    enum Page: Hashable { case hello, mac, pair }

    @State private var page: Page
    @State private var forward = true

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        #if DEBUG
        _page = State(initialValue: PairingDemo.onboardingPage ?? .hello)
        #else
        _page = State(initialValue: .hello)
        #endif
    }

    var body: some View {
        ZStack {
            switch page {
            case .hello:
                // A non-breaking hyphen keeps Wi-Fi on one line where the sentence wraps.
                SetupPage(title: "Your Mac, at\nYour Fingertips",
                          detail: "Your Mac, at your fingertips. Your iPhone and Mac talk only over your Wi\u{2011}Fi.",
                          primary: "Continue", primaryAction: { go(.mac) }) {
                    IPhoneArt(height: 250)
                }
                .transition(.push(from: forward ? .trailing : .leading))
            case .mac:
                SetupPage(title: "Open Glasspad\non Your Mac",
                          detail: "In the menu bar, click Glasspad and choose Pair Your iPhone. Keep both on the same Wi\u{2011}Fi.",
                          primary: "Pair a Mac", secondary: "Set Up Later",
                          primaryAction: { go(.pair) }, secondaryAction: onFinish) {
                    MacMenuArt(width: 300)
                }
                .transition(.push(from: forward ? .trailing : .leading))
            case .pair:
                pairFlow
                    .transition(.push(from: forward ? .trailing : .leading))
            }
        }
        .animation(.smooth(duration: 0.5), value: page)
        .background(SurfaceBackground())
    }

    @ViewBuilder private var pairFlow: some View {
        #if DEBUG
        PairFlow(cancelTitle: "Back", start: PairingDemo.pairStep, mac: PairingDemo.mac,
                 onCancel: { go(.mac) }, onFinish: onFinish)
        #else
        PairFlow(cancelTitle: "Back", onCancel: { go(.mac) }, onFinish: onFinish)
        #endif
    }

    private func go(_ target: Page) {
        let order: [Page] = [.hello, .mac, .pair]
        forward = (order.firstIndex(of: target) ?? 0) > (order.firstIndex(of: page) ?? 0)
        page = target
    }
}

#if DEBUG
/// Debug builds only: launch arguments that open each pairing screen for screenshots and
/// videos in the simulator (which has no camera; the viewfinder shows a stand-in Mac).
///   -GPOnboarding -GPPairStep <hello|mac|network|camera|scan|connected>
///   -GPPairAuto        the stand-in code is "seen" two seconds in, so the lock-on plays
///   -GPPairDenied      the viewfinder with camera access turned off
///   -GPPairPaste       the paste sheet open
/// -GPPairSheet (RootView) opens Pair a Mac; -GPPairStep applies there too.
enum PairingDemo {
    static var args: [String] { ProcessInfo.processInfo.arguments }

    static var step: String? {
        guard let i = args.firstIndex(of: "-GPPairStep"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var onboardingPage: OnboardingView.Page? {
        switch step {
        case "hello": .hello
        case "mac": .mac
        case nil: nil
        default: .pair
        }
    }

    static var pairStep: PairFlow.Step? { step.flatMap(PairFlow.Step.init(rawValue:)) }

    static var autoScan: Bool { args.contains("-GPPairAuto") }

    /// -GPPairDenied: the viewfinder as it is when camera access was turned off.
    static var cameraDenied: Bool { args.contains("-GPPairDenied") }

    /// -GPPairPaste: the paste sheet open over the flow.
    static var pasteOpen: Bool { args.contains("-GPPairPaste") }

    /// The Mac on the Connected screen, without pairing anything.
    static var mac: PairedMac? {
        guard pairStep == .connected else { return nil }
        return PairedMac(macID: UUID(uuidString: "6F1C2A4E-3B5D-4C7E-9F10-2A3B4C5D6E7F")!, name: "Soham's MacBook Pro",
                         pairKey: Data(repeating: 0x5A, count: 32), pairedAt: Date())
    }
}
#endif
