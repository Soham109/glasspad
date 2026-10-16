import SwiftUI
import GlasspadKit

/// A couch remote, like the Siri Remote: one big touch surface (tap to play or pause, swipe
/// sideways to skip, up and down for volume) and a few large buttons under it. The controls
/// follow the Mac's frontmost player (`RemoteKeymap`). Always dark and dim, so it does not
/// light up the room; the screen locks as usual so a long film does not drain the battery.
struct RemoteMode: View {
    var settings = PhoneSettings.shared
    /// Set when opened from the mode menu's tools: a close button leads the top row.
    var onClose: (() -> Void)?

    var body: some View {
        // Mono stays black and white here too. Read from the setting, as the full screen
        // tool is not handed the app's palette.
        RemoteScreen(onClose: onClose)
            .environment(\.palette, settings.theme == .mono ? ThemeChoice.mono.preview(dark: true) : .graphite)
            .environment(\.colorScheme, .dark)
    }
}

/// Remote as a tool: full screen over the current mode, telling the Mac while it shows.
struct RemoteCover: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RemoteMode { dismiss() }
            .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .onAppear { MacSession.shared.send(.modeSelected(.remote)) }
        .onDisappear { MacSession.shared.modesDidChange(to: AppRouter.shared.screenModes) }
    }
}

private struct RemoteScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var session = MacSession.shared
    var store = MediaStore.shared
    let onClose: (() -> Void)?
    private var accent: Color { AppMode.remote.accent(palette) }

    @State private var searching = false
    @State private var query = ""
    /// The volume this remote last set, held for a moment so quick swipes build on each other
    /// before the Mac's next state catches up.
    @State private var localVolume: Double?
    @State private var localVolumeUntil = Date.distantPast
    @State private var systemRun: UUID?
    @State private var notice: String?

    private var state: MediaState? { store.state }

    /// The controls for the Mac's frontmost player, or the one playing.
    private var keymap: RemoteKeymap {
        RemoteKeymap(frontmost: session.frontmostBundleID, playing: state?.sourceBundleID,
                     nowPlaying: [state?.title, state?.artist, state?.album])
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // At the top of the screen (not in a lower split pane), leave room for the mode pill
            // or the close button.
            let atTop = onClose == nil && geo.frame(in: .global).minY < 120
            let top: CGFloat = atTop ? (size.width > size.height ? 44 : 60) : 12
            Group {
                if size.width > size.height * 1.15 {
                    wide(size, top: top)
                } else {
                    tall(size, top: top)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .overlay {
            if searching { searchPanel }
        }
        .overlay {
            if !session.isConnected {
                ModeOfflineMessage(mode: .remote).background(palette.backgroundColor)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: searching)
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-GPMediaDemo") {
                store.applyDemo(i + 1 < args.count ? args[i + 1] : nil)
            }
            if args.contains("-GPRemoteSearch") { openSearch() }
            #endif
            session.send(.mediaRequest)
        }
        .onChange(of: systemRun.flatMap { session.deckOutcomes[$0] }) { _, outcome in
            guard let outcome, !outcome.ok else { return }
            show(notice: outcome.message ?? "Your Mac did not do that.")
        }
    }

    // MARK: Layouts

    private func tall(_ size: CGSize, top: CGFloat) -> some View {
        VStack(spacing: 12) {
            if size.height > 470 || onClose != nil { header }
            if let notice { noticeLine(notice) }
            RemoteSurface(keymap: keymap, accent: accent, onTap: { run(.playPause) },
                          onSkip: skip, onVolume: changeVolume, volume: currentVolume)
            transport
                .frame(height: size.height > 560 ? 84 : 68)
            if size.height > 380 {
                options
                    .frame(height: 64)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, top)
        .padding(.bottom, 16)
    }

    /// Sideways: the surface takes the wide side, the buttons sit in a column beside it.
    private func wide(_ size: CGSize, top: CGFloat) -> some View {
        HStack(spacing: 16) {
            RemoteSurface(keymap: keymap, accent: accent, onTap: { run(.playPause) },
                          onSkip: skip, onVolume: changeVolume, volume: currentVolume)
            VStack(spacing: 12) {
                if size.height > 250 || onClose != nil { header }
                if let notice { noticeLine(notice) }
                Spacer(minLength: 0)
                transport
                    .frame(height: size.height > 330 ? 76 : 60)
                options
                    .frame(height: 60)
            }
            .frame(width: min(330, size.width * 0.42))
        }
        .padding(.horizontal, 16)
        .padding(.top, top)
        .padding(.bottom, 16)
    }

    // MARK: Now playing

    private var header: some View {
        HStack(spacing: 12) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.inkSoftColor)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(palette.raisedColor))
                        .overlay(Circle().strokeBorder(palette.lineColor, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(TileStyle())
                .accessibilityLabel("Close Remote")
            }
            artwork
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: title, font: .headline, color: palette.inkColor, alignment: .leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            moreMenu
        }
        .frame(height: 52)
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(palette.raisedColor)
            .frame(width: 48, height: 48)
            .overlay {
                if let image = store.artwork, store.playback.hasTrack {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        // A little dimmer than the cover itself, to stay calm in the dark.
                        .opacity(0.85)
                } else {
                    Image(systemName: keymap.skipsTracks ? "music.note" : "tv")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(palette.inkSoftColor)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.lineColor, lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var title: String {
        store.playback.hasTrack ? (state?.title ?? "") : "Nothing Playing"
    }

    /// Where it plays and whose controls are in use: "Netflix in Safari", "Apple TV", "Spotify".
    private var subtitle: String {
        let app = state?.sourceName
        switch (keymap.player, keymap.name, app) {
        case (.browser(let site), let name?, let app?) where site != .other: return "\(name) in \(app)"
        case (.music, _, let app?), (.appleMusic, _, let app?): return [state?.artist, app].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case (_, _, let app?) where store.playback.hasTrack: return app
        case (_, let name?, _): return name
        default: return "Play a film or a song on your Mac."
        }
    }

    /// Sleep Display and Do Not Disturb: small things for the couch, out of the way.
    private var moreMenu: some View {
        Menu {
            ForEach([DeckSystemAction.sleepDisplay, .doNotDisturb], id: \.self) { action in
                Button {
                    runSystem(action)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.inkSoftColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(palette.raisedColor))
                .overlay(Circle().strokeBorder(palette.lineColor, lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
    }

    private func noticeLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(palette.inkSoftColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }

    // MARK: Buttons

    private var transport: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let playing = store.playback.isPlaying(at: context.date)
            HStack(spacing: 10) {
                if keymap.has(.back, canSeek: canSeek) {
                    bigButton(keymap.skipsTracks ? "backward.fill" : "gobackward.10",
                              keymap.skipsTracks ? "Previous" : "Back 10 seconds", size: 26) { run(.back) }
                }
                Button {
                    Haptics.shared.play(.click)
                    run(.playPause)
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(palette.inkColor)
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(KeyCapStyle(cornerRadius: 24))
                .accessibilityLabel(playing ? "Pause" : "Play")
                if keymap.has(.forward, canSeek: canSeek) {
                    bigButton(keymap.skipsTracks ? "forward.fill" : "goforward.10",
                              keymap.skipsTracks ? "Next" : "Forward 10 seconds", size: 26) { run(.forward) }
                }
            }
        }
    }

    private func bigButton(_ symbol: String, _ label: String, size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(palette.inkSoftColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyCapStyle(cornerRadius: 24))
        .frame(width: 92)
        .accessibilityLabel(label)
    }

    /// Only what the player in front has: Search, Subtitles, Full Screen, Mute, and Skip Intro
    /// or Next video where the site has a key for them.
    private var options: some View {
        HStack(spacing: 8) {
            option("magnifyingglass", "Search") { openSearch() }
            if keymap.has(.skipIntro) { option("forward.end", "Skip Intro") { run(.skipIntro) } }
            if keymap.has(.subtitles) { option("captions.bubble", "Subtitles") { run(.subtitles) } }
            if keymap.has(.fullScreen) {
                option("arrow.up.left.and.arrow.down.right", "Full Screen") { run(.fullScreen) }
            }
            if keymap.has(.next), !keymap.skipsTracks { option("forward.end.alt", "Next") { run(.next) } }
            option("speaker.slash", "Mute") { session.send(.mediaCommand(.mute)) }
        }
    }

    private func option(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 22)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(palette.inkSoftColor)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyCapStyle(cornerRadius: 18))
        .accessibilityLabel(title)
    }

    // MARK: Search

    private var searchPanel: some View {
        VStack(spacing: 0) {
            // Tapping outside the field closes it.
            palette.backgroundColor.opacity(0.75)
                .contentShape(Rectangle())
                .onTapGesture { closeSearch() }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(palette.inkSoftColor)
                        RemoteSearchField(text: $query, placeholder: "Search on your Mac", palette: palette,
                                          onSubmit: sendSearch)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Capsule().fill(palette.raisedColor))
                    .overlay(Capsule().strokeBorder(palette.lineColor, lineWidth: 1))
                    Button {
                        closeSearch()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(palette.inkSoftColor)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(palette.raisedColor))
                            .overlay(Circle().strokeBorder(palette.lineColor, lineWidth: 1))
                    }
                    .buttonStyle(TileStyle())
                    .accessibilityLabel("Close search")
                }
                Text(keymap.searchPrefix.isEmpty ? "Types where the cursor is on your Mac, then presses Return."
                                                 : "Goes into \(keymap.name ?? "the site")'s search box, then presses Return.")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(palette.backgroundColor)
        }
        .transition(.opacity)
    }

    private func openSearch() {
        query = ""
        searching = true
    }

    private func closeSearch() {
        searching = false
    }

    private func sendSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return closeSearch() }
        for key in keymap.searchPrefix { session.send(.keysKeystroke(key)) }
        session.send(.keysText(text))
        session.send(.keysKeystroke(Keystroke(key: .special(.returnKey))))
        Haptics.shared.play(.snap)
        closeSearch()
    }

    // MARK: Sending

    private func run(_ action: RemoteAction) {
        guard let output = keymap.output(action) else { return }
        switch output {
        case .media(.playPause): store.togglePlay()
        case .media(.nextTrack): store.next()
        case .media(.previousTrack): store.previous()
        default:
            let messages = RemoteKeymap.message(for: output, position: store.playback.position(at: Date()),
                                                canSeek: canSeek, duration: state?.duration)
            for message in messages {
                if case .mediaControl(.seek(let target)) = message { store.seek(to: target) } else { session.send(message) }
            }
        }
    }

    /// Seeking through now playing is only right when the controls are the playing app's.
    private var canSeek: Bool {
        guard state?.canSeek == true else { return false }
        return RemoteKeymap.player(bundleID: state?.sourceBundleID,
                                   nowPlaying: [state?.title, state?.artist, state?.album]) == keymap.player
    }

    private func skip(_ steps: Int) {
        let action: RemoteAction = steps > 0 ? .forward : .back
        for _ in 0..<abs(steps) { run(action) }
    }

    private var currentVolume: Double? {
        if let localVolume, Date() < localVolumeUntil { return localVolume }
        return state?.volume ?? localVolume
    }

    private func changeVolume(_ steps: Int) {
        guard let from = currentVolume else {
            // The Mac did not say its volume: press its volume keys instead.
            for _ in 0..<abs(steps) {
                session.send(.remoteSystem(id: UUID(), action: steps > 0 ? .volumeUp : .volumeDown))
            }
            return
        }
        let target = RemoteKeymap.volume(from: from, steps: steps)
        localVolume = target
        localVolumeUntil = Date().addingTimeInterval(1.5)
        session.send(.mediaSetVolume(target))
    }

    private func runSystem(_ action: DeckSystemAction) {
        Haptics.shared.tap()
        let id = UUID()
        systemRun = id
        session.send(.remoteSystem(id: id, action: action))
    }

    private func show(notice text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if notice == text { withAnimation { notice = nil } }
        }
    }
}

/// The big touch surface. Tap plays or pauses; sideways swipes skip (one step per swipe, more
/// as the finger keeps going); up and down change the volume in the Mac's own steps.
private struct RemoteSurface: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let keymap: RemoteKeymap
    let accent: Color
    var onTap: () -> Void
    var onSkip: (Int) -> Void
    var onVolume: (Int) -> Void
    var volume: Double?

    @State private var swipe = RemoteSwipe()
    @State private var touch: CGPoint?
    @State private var flash: Flash?
    @State private var showVolume = false
    @State private var used = false
    @State private var hideTask: Task<Void, Never>?

    private struct Flash: Equatable {
        let id = UUID()
        let symbol: String
    }

    private let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

    var body: some View {
        ZStack {
            shape.fill(palette.raisedColor)
            shape.strokeBorder(palette.lineColor, lineWidth: 1)
            if let touch {
                // A soft glow under the finger, like light through the Siri Remote's glass.
                Circle()
                    .fill(palette.inkColor.opacity(0.06))
                    .frame(width: 96, height: 96)
                    .position(touch)
                    .allowsHitTesting(false)
            }
            if let flash {
                Image(systemName: flash.symbol)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(palette.inkColor.opacity(0.8))
                    .id(flash.id)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
            } else if !used {
                hint.transition(.opacity)
            }
            if showVolume, let volume { volumeLevel(volume) }
        }
        .clipShape(shape)
        .contentShape(shape)
        .gesture(drag)
        .accessibilityElement()
        .accessibilityLabel("Touch surface")
        .accessibilityHint("Double tap to play or pause. Swipe up or down to change the volume.")
        .accessibilityValue(volume.map { "Volume \(Int(($0 * 100).rounded())) percent" } ?? "")
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAction { onTap() }
        .accessibilityAction(.magicTap) { onTap() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onVolume(1)
            case .decrement: onVolume(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: keymap.skipsTracks ? "Previous" : "Back") { onSkip(-1) }
        .accessibilityAction(named: keymap.skipsTracks ? "Next" : "Forward") { onSkip(1) }
    }

    private var hint: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(accent.opacity(0.8))
            Text("Tap to play or pause")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.inkSoftColor)
            Text(keymap.skipsTracks ? "Swipe sideways to change the song,\nup or down for volume"
                                    : "Swipe sideways to skip,\nup or down for volume")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.inkSoftColor.opacity(0.7))
        }
        .padding(24)
        .allowsHitTesting(false)
    }

    private func volumeLevel(_ value: Double) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Capsule().fill(palette.inkColor.opacity(0.12))
                        Capsule().fill(palette.inkColor.opacity(0.7))
                            .frame(height: max(6, geo.size.height * value))
                    }
                }
                .frame(width: 6)
                Image(systemName: "speaker.fill")
                    .font(.caption)
            }
            .foregroundStyle(palette.inkSoftColor)
            .padding(.vertical, 28)
            .padding(.trailing, 18)
        }
        .animation(.snappy(duration: 0.2), value: value)
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if touch == nil {
                    withAnimation(.easeOut(duration: 0.15)) { used = true }
                }
                touch = value.location
                if let event = swipe.moved(dx: value.translation.width, dy: value.translation.height) { handle(event) }
            }
            .onEnded { value in
                touch = nil
                if let event = swipe.ended(dx: value.translation.width, dy: value.translation.height) { handle(event) }
            }
    }

    private func handle(_ event: RemoteSwipe.Event) {
        switch event {
        case .tap:
            Haptics.shared.play(.click)
            onTap()
            show("playpause.fill")
        case .step(.horizontal, let n):
            Haptics.shared.play(.detent)
            onSkip(n)
            if keymap.skipsTracks {
                show(n > 0 ? "forward.fill" : "backward.fill")
            } else {
                show(n > 0 ? "goforward.10" : "gobackward.10")
            }
        case .step(.vertical, let n):
            Haptics.shared.play(.detent)
            onVolume(n)
            show(n > 0 ? "speaker.plus.fill" : "speaker.minus.fill", volume: true)
        }
    }

    private func show(_ symbol: String, volume: Bool = false) {
        withAnimation(.snappy(duration: 0.18)) {
            flash = Flash(symbol: symbol)
            if volume { showVolume = true }
        }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(volume ? 1.2 : 0.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                flash = nil
                showVolume = false
            }
        }
    }
}

/// The search box. UIKit, so the keyboard is dark like the rest of the Remote whatever the
/// app's theme, and it comes up as soon as the box shows.
private struct RemoteSearchField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let palette: Palette
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardAppearance = .dark
        field.overrideUserInterfaceStyle = .dark
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = palette.ink
        field.tintColor = palette.ink
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: palette.inkSoft])
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
    }

    static func dismantleUIView(_ field: UITextField, coordinator: Coordinator) {
        field.resignFirstResponder()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RemoteSearchField
        init(parent: RemoteSearchField) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.text = field.text ?? ""
            parent.onSubmit()
            return false
        }
    }
}
