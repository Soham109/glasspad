import SwiftUI

@main
struct GlasspadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        DebugLaunch.apply()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { AppRouter.shared.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            let active = phase == .active
            ScreenAwake.sceneActive = active
            ScreenAwake.update()
            MacSession.shared.setForeground(phase != .background)
            LiveActivityController.shared.sceneChanged(active: active)
        }
    }
}

struct RootView: View {
    @Environment(\.colorScheme) private var systemScheme
    var settings = PhoneSettings.shared
    var router = AppRouter.shared
    var session = MacSession.shared

    var body: some View {
        let palette = settings.theme.resolved(systemScheme).customized(settings)
        @Bindable var router = router
        ZStack {
            palette.backgroundColor.ignoresSafeArea()
            if settings.hasOnboarded {
                main(palette)
            } else {
                OnboardingView {
                    settings.hasOnboarded = true
                    router.show(.trackpad)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: settings.hasOnboarded)
        .environment(\.palette, palette)
        .preferredColorScheme(settings.theme == .system ? nil : palette.colorScheme)
        .tint(palette.inkColor)
        .statusBarHidden(true)
        .sheet(isPresented: $router.showSettings, onDismiss: ScreenAwake.update) {
            SettingsView()
                .environment(\.palette, palette)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $router.showPairing, onDismiss: ScreenAwake.update) {
            PairSheet()
                .environment(\.palette, palette)
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func main(_ palette: Palette) -> some View {
        let focus = router.dims
        ZStack {
            modeContent
                .id(router.mode)
                .transition(.opacity)
            if router.mode == .trackpad {
                TrackpadStatus()
            }
            if router.mode == .present && router.isDimmed {
                // Present dims too; the first touch only wakes it.
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { router.noteActivity() }
                    .transition(.opacity)
                    .accessibilityLabel("Screen dimmed. Double tap to wake.")
            }
            ModeSwitcher()
            if session.isWarm {
                WarmNotice()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: router.mode)
        .animation(.easeInOut(duration: router.isDimmed ? 1.2 : 0.25), value: router.isDimmed)
        .persistentSystemOverlays(focus ? .hidden : .automatic)
        .defersSystemGestures(on: router.mode == .trackpad ? .all : [])
        .simultaneousGesture(TapGesture().onEnded { router.noteActivity() }, including: router.mode == .present ? .all : .subviews)
    }

    @ViewBuilder private var modeContent: some View {
        switch router.mode {
        case .trackpad: TrackpadScreen()
        case .dock: DockMode()
        case .keys: KeysMode()
        case .media: MediaMode()
        case .actions: ActionsMode()
        case .deck: DeckMode()
        case .macros: MacrosMode()
        case .clipboard: ClipboardMode()
        case .present: PresentMode()
        }
    }
}

/// Quiet status over the trackpad, only when it is not connected. Never takes touches,
/// except the "Pair a Mac" button when nothing is paired.
private struct TrackpadStatus: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    var router = AppRouter.shared

    var body: some View {
        if PairingStore.shared.selected == nil {
            VStack(spacing: 18) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(palette.inkSoftColor)
                Text("No Mac paired")
                    .font(.headline)
                    .foregroundStyle(palette.inkColor)
                Button("Pair a Mac") { router.showPairing = true }
                    .glassButton(prominent: true)
                    .controlSize(.large)
            }
        } else if !session.isConnected {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(session.state.statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.inkSoftColor)
                    if let name = session.macName {
                        Text(name)
                            .font(.footnote)
                            .foregroundStyle(palette.inkSoftColor.opacity(0.8))
                    }
                }
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                // The only touchable part; the surface keeps every other touch.
                LinkActions()
            }
            .padding(.horizontal, 40)
            .transition(.opacity)
        }
    }
}

/// Shown while the phone is warm. Haptics and keep-awake traffic are paused meanwhile.
private struct WarmNotice: View {
    @Environment(\.palette) private var palette
    var body: some View {
        VStack {
            Spacer()
            Label("Your iPhone is warm. Haptics are paused until it cools down.", systemImage: "thermometer.medium")
                .font(.footnote)
                .foregroundStyle(palette.inkColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCapsule()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

#if DEBUG
/// Debug builds only: launch arguments that drive the app for simulator screenshots and
/// end-to-end runs against a test Mac, where there is no camera and no finger.
///   -GPPair <glasspad://pair?... URL>   pair as if the code was scanned
///   -GPMode <trackpad|dock|...>         open that mode
///   -GPOnboarding                       show onboarding again
///   -GPSettings / -GPMenu / -GPPairSheet open Settings, the mode menu or the pair sheet
///   -GPOrientation <automatic|portrait|landscape>  set the orientation choice (it is saved)
///   -GPDemo <icon folder>               fill the screens with sample Mac data (no Mac needed)
///   -GPActionsPage <mac|mine|clipboard|present>  open that Actions page; -GPEdit starts editing
enum DebugLaunch {
    @MainActor static func apply() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let o = value("-GPOrientation"), let choice = OrientationChoice(rawValue: o) {
            PhoneSettings.shared.orientation = choice
        }
        if let t = value("-GPTheme"), let theme = ThemeChoice(rawValue: t) { PhoneSettings.shared.theme = theme }
        if args.contains("-GPOnboarding") { PhoneSettings.shared.hasOnboarded = false }
        if let pair = value("-GPPair"), let url = URL(string: pair) { AppRouter.shared.open(url) }
        if let mode = value("-GPMode"), let target = AppMode(rawValue: mode) {
            PhoneSettings.shared.hasOnboarded = true
            AppRouter.shared.show(target)
        }
        if args.contains("-GPSettings") { AppRouter.shared.showSettings = true }
        if args.contains("-GPPairSheet") { AppRouter.shared.showPairing = true }
        if args.contains("-GPMenu") { showMenuAtLaunch = true }
        if let folder = value("-GPDemo") { MacSession.shared.applyDemo(DemoData(iconFolder: folder)) }
        if let page = value("-GPActionsPage") { demoActionsPage = page }
        if args.contains("-GPEdit") { demoEditing = true }
    }
    @MainActor static var showMenuAtLaunch = false
    /// `mac`, `mine`, `clipboard` or `present`: the Actions page to open.
    @MainActor static var demoActionsPage: String?
    @MainActor static var demoEditing = false
}
#endif
