import GlasspadKit
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
        // Paper and Graphite force the window light or dark; System leaves it to the phone.
        // Set on the window, not with preferredColorScheme, so that system text, controls,
        // sheets already on screen, menus, alerts and the keyboard all follow a change at once.
        .background(WindowAppearance(style: settings.theme.interfaceStyle))
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
        .sheet(isPresented: $router.showSetup, onDismiss: ScreenAwake.update) {
            SetupChecklistView()
                .environment(\.palette, palette)
                .presentationDragIndicator(.visible)
        }
        .task(id: canAutoShowSetup) {
            guard canAutoShowSetup else { return }
            // Let the pairing sheet or onboarding finish leaving first.
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled, canAutoShowSetup else { return }
            SetupGuide.shared.pendingAutoShow = false
            router.showSetup = true
        }
        .sheet(isPresented: $router.showClipboard, onDismiss: ScreenAwake.update) {
            ClipboardSheet()
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $router.showLayouts, onDismiss: ScreenAwake.update) {
            LayoutGallery()
                .environment(\.palette, palette)
        }
        .sheet(item: $router.layoutDraft, onDismiss: ScreenAwake.update) { draft in
            LayoutEditor(draft: draft)
                .environment(\.palette, palette)
        }
        .fullScreenCover(isPresented: $router.showPresenter) {
            PresenterCover()
                .environment(\.palette, palette)
        }
        .fullScreenCover(isPresented: $router.showRemote) { RemoteCover() }
        .alert(router.pairingRequest.map { "Pair with \($0.macName)?" } ?? "Pair with this Mac?",
               isPresented: Binding(get: { router.pairingRequest != nil }, set: { if !$0 { router.pairingRequest = nil } }),
               presenting: router.pairingRequest) { payload in
            Button("Pair") { router.pair(payload) }
            Button("Cancel", role: .cancel) { router.pairingRequest = nil }
        } message: { _ in
            Text("Only pair with a code your own Mac is showing. This iPhone will then control that Mac, and what you type goes to it.")
        }
    }

    @ViewBuilder
    private func main(_ palette: Palette) -> some View {
        let focus = router.dims
        let layout = router.layout
        ZStack {
            if let layout {
                GeometryReader { geo in
                    LayoutScreen(layout: layout, safeArea: geo.safeAreaInsets)
                }
                .ignoresSafeArea(.keyboard)
                .id(layout.id)
                .transition(.opacity)
            } else {
                ModeScreen(mode: router.mode)
                    .id(router.mode)
                    .transition(.opacity)
            }
            if layout == nil && router.mode == .trackpad && !filmActive {
                TrackpadStatus()
                TrackpadNotices()
            }
            if layout == nil && router.mode == .present && router.isDimmed {
                // Present dims too; the first touch only wakes it.
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { router.noteActivity() }
                    .transition(.opacity)
                    .accessibilityLabel("Screen dimmed. Double tap to wake.")
            }
            #if DEBUG
            ModeSwitcher().id(FilmDirector.shared.switcherID)
            #else
            ModeSwitcher()
            #endif
            if session.isWarm {
                WarmNotice()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: router.mode)
        .animation(.easeInOut(duration: 0.25), value: router.layoutID)
        .animation(.easeInOut(duration: router.isDimmed ? 1.2 : 0.25), value: router.isDimmed)
        .persistentSystemOverlays(focus ? .hidden : .automatic)
        .defersSystemGestures(on: router.screenModes.contains(.trackpad) ? .all : [])
        .simultaneousGesture(TapGesture().onEnded { router.noteActivity() }, including: router.mode == .present ? .all : .subviews)
    }

    /// The first-run checklist waits for a new pairing and for nothing else to be on screen.
    private var canAutoShowSetup: Bool {
        SetupGuide.shared.pendingAutoShow && settings.hasOnboarded && !settings.setupComplete
            && !router.showPairing && !router.showSettings && !router.showSetup
            && !router.showClipboard && !router.showPresenter && !router.showRemote && router.pairingRequest == nil
    }

    /// Debug film scenes (DemoScript.swift) hide the trackpad's connection status.
    private var filmActive: Bool {
        #if DEBUG
        FilmDirector.shared.active
        #else
        false
        #endif
    }
}

/// One mode's screen, full size or inside a layout pane.
struct ModeScreen: View {
    let mode: AppMode

    var body: some View {
        switch mode {
        case .trackpad: TrackpadScreen()
        case .dock: DockMode()
        case .keys: KeysMode()
        case .media: MediaMode()
        case .actions: ActionsMode()
        case .deck: DeckMode()
        case .macros: MacrosMode()
        case .clipboard: ClipboardMode()
        case .present: PresentMode()
        case .remote: RemoteMode()
        case .clock: ClockMode()
        case .nowPlaying: NowPlayingMode()
        case .calendar: CalendarMode()
        }
    }
}

/// Quiet status over the trackpad, only when it is not connected. Never takes touches,
/// except the "Pair a Mac" button when nothing is paired.
struct TrackpadStatus: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    var router = AppRouter.shared

    var body: some View {
        if PairingStore.shared.selected == nil {
            // Same look as every other mode without a Mac.
            VStack(spacing: 16) {
                QuietMessage(symbol: "laptopcomputer", title: "No Mac paired",
                             detail: "Pair a Mac to use the trackpad.")
                    .frame(maxHeight: 180)
                    .allowsHitTesting(false)
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
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(palette.inkSoftColor.opacity(0.8))
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

extension TrackpadStatus {
    /// What to check, in the same words the other modes use.
    fileprivate var detail: String {
        let name = session.macName ?? "your Mac"
        if session.isReplaced { return "\(name) follows one iPhone at a time." }
        switch session.linkIssue {
        case .localNetworkDenied?: return "Turn on Local Network for Glasspad in Settings."
        case .networkBlocksDevices?: return "\(name) was found, but this Wi-Fi keeps devices apart. Guest Wi-Fi and VPNs often do."
        case nil: break
        }
        if case .connecting = session.state { return name }
        return "Keep both on the same Wi-Fi with Glasspad open on \(name)."
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
///   -GPTheme / -GPThemeLater <paper|graphite|system>  set the theme at launch, or two seconds later
///   -GPDemo <icon folder>               fill the screens with sample Mac data (no Mac needed)
///   -GPActionsPage <library|front|folder|clipboard|present|remote>  open that Actions sheet or tool; -GPEdit starts editing
///   -GPFilm <trackpad|menu|actions|media>  play a scripted scene for the demo film (DemoScript.swift)
///   -GPSetup / -GPSetupTest / -GPSetupReset  open the setup checklist, start its trackpad test, or mark it unfinished
///   -GPSettingsPage <connection|setup>  open Settings on that page
///   -GPKeysFn / -GPKeysLock             Keyboard with the function row, or with Command locked and Shift latched
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
        // Switches the theme two seconds after launch, the way a person does from Settings.
        if let t = value("-GPThemeLater"), let theme = ThemeChoice(rawValue: t) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                PhoneSettings.shared.theme = theme
            }
        }
        if args.contains("-GPOnboarding") { PhoneSettings.shared.hasOnboarded = false }
        if let pair = value("-GPPair"), let payload = PairingParser.parse(pair) { AppRouter.shared.pair(payload) }
        if let mode = value("-GPMode"), let target = AppMode(rawValue: mode) {
            PhoneSettings.shared.hasOnboarded = true
            AppRouter.shared.show(target)
        }
        if args.contains("-GPSettings") { AppRouter.shared.showSettings = true }
        if args.contains("-GPPairSheet") { AppRouter.shared.showPairing = true }
        if args.contains("-GPMenu") { showMenuAtLaunch = true }
        if let folder = value("-GPDemo") { MacSession.shared.applyDemo(DemoData(iconFolder: folder)) }
        if let page = value("-GPActionsPage") {
            demoActionsPage = page
            if page == "clipboard" { AppRouter.shared.openTool(.clipboard) }
            if page == "present" { AppRouter.shared.openTool(.present) }
            if page == "remote" { AppRouter.shared.openTool(.remote) }
        }
        if args.contains("-GPEdit") { demoEditing = true }
        if args.contains("-GPSetup") { AppRouter.shared.showSetup = true }
        if args.contains("-GPSetupTest") { SetupGuide.shared.startTest() }
        if let travel = value("-GPSetupTravel").flatMap(Double.init) {
            SetupGuide.shared.debugSet(active: true, travel: travel, passed: travel >= SetupGuide.travelNeeded)
        }
        if args.contains("-GPSetupReset") { PhoneSettings.shared.setupComplete = false }
        if args.contains("-GPKeysFn") { PhoneSettings.shared.keysShowsFunctionRow = true }
        if args.contains("-GPKeysLock") { demoKeysLock = true }
        if let page = value("-GPSettingsPage") {
            settingsPage = page
            AppRouter.shared.showSettings = true
        }
        // Layouts: -GPLayout <template id> opens a layout made from that template (saved once),
        // -GPLayoutSplit <0...1> sets its line, -GPLayouts opens the gallery, -GPLayoutEdit
        // <template id> opens the editor on a new layout from that template.
        if let id = value("-GPLayout"), let template = LayoutTemplate.builtIn.first(where: { $0.id == id }) {
            PhoneSettings.shared.hasOnboarded = true
            let store = LayoutStore.shared
            var layout = store.layouts.first { $0.name == template.name } ?? template.makeLayout()
            if let share = value("-GPLayoutSplit").flatMap(Double.init) { layout.split = share }
            if let share = value("-GPLayoutInner").flatMap(Double.init) { layout.innerSplit = share }
            if let d = value("-GPLayoutDirection").flatMap(SplitDirection.init(rawValue:)) { layout.direction = d }
            store.save(layout)
            AppRouter.shared.show(layout: layout)
        }
        // -GPLayoutPanes trackpad,media,actions: a throwaway layout with exactly those panes.
        if let list = value("-GPLayoutPanes") {
            PhoneSettings.shared.hasOnboarded = true
            var layout = ScreenLayout(name: "Test", panes: list.split(separator: ",").map(String.init))
            if let old = LayoutStore.shared.layouts.first(where: { $0.name == "Test" }) { layout.id = old.id }
            if let d = value("-GPLayoutDirection").flatMap(SplitDirection.init(rawValue:)) { layout.direction = d }
            LayoutStore.shared.save(layout)
            AppRouter.shared.show(layout: layout)
        }
        if args.contains("-GPLayouts") { AppRouter.shared.showLayouts = true }
        if let id = value("-GPLayoutEdit"), let template = LayoutTemplate.builtIn.first(where: { $0.id == id }) {
            AppRouter.shared.layoutDraft = AppRouter.shared.newLayout(from: template)
        }
        if let scene = value("-GPFilm") { FilmDirector.shared.start(scene: scene, iconFolder: value("-GPDemo")) }
    }
    @MainActor static var showMenuAtLaunch = false
    /// `library`, `front` or `folder`: the Actions sheet (or Pinned folder) to open.
    @MainActor static var demoActionsPage: String?
    @MainActor static var demoEditing = false
    /// `connection` or `setup`: the Settings page to open with -GPSettingsPage.
    @MainActor static var settingsPage: String?
    /// Keyboard opens with Command locked and Shift latched.
    @MainActor static var demoKeysLock = false
}
#endif
