import SwiftUI
import GlasspadKit

/// Now playing on the Mac: artwork, title, a live progress bar you can scrub, transport,
/// shuffle, repeat, the Mac's sound output, volume and brightness. Taps show at once and the
/// Mac's next state confirms them (`MediaPlayback`).
struct MediaMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.inLayoutPane) private var inPane
    @Environment(\.modeTopClearance) private var topClearance
    var session = MacSession.shared
    var store = MediaStore.shared
    private var accent: Color { AppMode.media.accent(palette) }

    @State private var volume: Double = 0.5
    @State private var brightness: Double = 0.5
    @State private var editingVolume = false
    @State private var editingBrightness = false
    @State private var heldUntil = Date.distantPast
    @State private var throttle = SliderThrottle()

    private var state: MediaState { store.state ?? MediaState() }
    private var playback: MediaPlayback { store.playback }

    var body: some View {
        ZStack {
            if !session.isConnected && store.state == nil {
                ModeOfflineMessage(mode: .media)
            } else {
                content
            }
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-GPMediaDemo") {
                store.applyDemo(i + 1 < args.count ? args[i + 1] : nil)
            }
            #endif
            session.send(.mediaRequest)
            syncSliders()
        }
        .onChange(of: store.state) { syncSliders() }
    }

    // MARK: Layout

    @ViewBuilder private var content: some View {
        if inPane {
            // A layout pane: as much of the player as its height allows, most used first.
            GeometryReader { geo in
                let h = geo.size.height
                if verticalSize == .compact && h >= 300 {
                    full
                } else if verticalSize != .compact && h >= 640 {
                    full
                } else if geo.size.width >= Self.narrowest {
                    paneLayout(height: h)
                        .frame(width: geo.size.width, height: h)
                } else {
                    // Narrower than the transport: drawn at its narrowest and scaled to fit.
                    let k = geo.size.width / Self.narrowest
                    paneLayout(height: h / k)
                        .frame(width: Self.narrowest, height: h / k)
                        .scaleEffect(k, anchor: .topLeading)
                }
            }
        } else {
            full
        }
    }

    /// Below this width the player no longer fits a pane.
    private static let narrowest: CGFloat = 300

    /// The player in a short pane: small artwork when there is room, the track, its progress,
    /// the transport, then volume.
    private func paneLayout(height h: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: topClearance ?? 52)
            if h >= 470 {
                artwork
                    .frame(height: min(180, h * 0.3))
                    .padding(.bottom, 16)
            }
            header
            if h >= 280 { progress.padding(.top, 10) }
            transport.padding(.top, 2)
            if h >= 360 { volumeSlider.padding(.top, 6) }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var full: some View {
        if verticalSize == .compact {
            // Sideways: artwork on the left, everything you touch on the right.
            HStack(spacing: 32) {
                artwork
                    .frame(maxHeight: .infinity)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    header
                    progress.padding(.top, 10)
                    transport.padding(.top, 2)
                    options.padding(.top, 2)
                    volumeSlider.padding(.top, 6)
                    automationNote.padding(.top, 8)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: 440)
            }
            .padding(.top, topClearance ?? 48)
            .padding(.bottom, 16)
            .padding(.horizontal, 28)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: topClearance ?? 76)
                artwork
                    .padding(.horizontal, 30)
                header
                    .padding(.horizontal, 30)
                    .padding(.top, 28)
                progress
                    .padding(.horizontal, 30)
                    .padding(.top, 18)
                transport
                    .padding(.top, 8)
                Spacer(minLength: 8)
                options
                    .padding(.horizontal, 22)
                automationNote
                    .padding(.horizontal, 30)
                    .padding(.bottom, 4)
                sliders
                    .padding(.horizontal, 30)
                    .padding(.top, 8)
                    .padding(.bottom, 26)
            }
        }
    }

    // MARK: Artwork

    private var artwork: some View {
        RenderTime { context in
            let playing = playback.isPlaying(at: context.date)
            // A square sized by its container; the cover fills it edge to edge.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background(palette.raisedColor)
                .overlay {
                    if let image = store.artwork, playback.hasTrack {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .transition(.opacity)
                            .id(store.artworkID)
                    } else {
                        Image(systemName: playback.hasTrack ? "music.note" : "music.note.list")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(palette.inkSoftColor.opacity(0.7))
                    }
                }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.lineColor, lineWidth: 1))
            .frame(maxWidth: 360)
            .scaleEffect(playing || reduceMotion || !playback.hasTrack ? 1 : 0.88)
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: playing)
            .animation(.easeInOut(duration: 0.3), value: store.artworkID)
        }
        .accessibilityHidden(true)
    }

    // MARK: Titles

    @ViewBuilder private var header: some View {
        if playback.hasTrack {
            VStack(spacing: 5) {
                source
                MarqueeText(text: state.title ?? "", font: .title3.weight(.semibold), color: palette.inkColor)
                MarqueeText(text: subtitle, font: .body, color: palette.inkSoftColor)
            }
            .accessibilityElement(children: .combine)
        } else {
            emptyHeader
        }
    }

    /// The app playing, with its icon: "Spotify", "Safari".
    @ViewBuilder private var source: some View {
        if let name = state.sourceName {
            HStack(spacing: 6) {
                if let icon = store.sourceIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 18, height: 18)
                }
                Text(name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.inkSoftColor)
            }
            .padding(.bottom, 2)
            .accessibilityLabel("Playing in \(name)")
        }
    }

    private var subtitle: String {
        [state.artist, state.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var emptyHeader: some View {
        VStack(spacing: 6) {
            if let notice = state.notice {
                NoticeCard(notice: notice, accent: accent)
            } else {
                Text("Nothing Playing")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.inkColor)
                Text("Play something on your Mac in Spotify, Music, Podcasts or a browser.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Progress and transport

    @ViewBuilder private var progress: some View {
        if playback.hasTrack, let duration = state.duration, duration > 0 {
            // Ticks only while the song plays; paused, the bar and clock hold still.
            let tick = playback.isPlaying(at: Date()) ? PowerMonitor.shared.policy.progressInterval : 3600
            TimelineView(.periodic(from: .now, by: tick)) { context in
                ScrubBar(duration: duration, position: playback.position(at: context.date) ?? 0,
                         enabled: state.canSeek ?? false) { store.seek(to: $0) }
            }
        } else {
            Color.clear.frame(height: playback.hasTrack ? 50 : 8)
        }
    }

    private var transport: some View {
        RenderTime { context in
            let playing = playback.isPlaying(at: context.date)
            HStack(spacing: 0) {
                transportButton("backward.fill", "Previous track", size: 32) { store.previous() }
                Spacer()
                Button {
                    Haptics.shared.play(.click)
                    store.togglePlay()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 50))
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .frame(width: 88, height: 88)
                        .contentShape(Circle())
                }
                .accessibilityLabel(playing ? "Pause" : "Play")
                Spacer()
                transportButton("forward.fill", "Next track", size: 32) { store.next() }
            }
            .frame(maxWidth: 320)
            .buttonStyle(TileStyle())
            .foregroundStyle(palette.inkColor)
        }
    }

    private func transportButton(_ symbol: String, _ label: String, size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 68, height: 68)
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
    }

    /// Shuffle, sound output, repeat. Shuffle and repeat show only when the player reports them.
    private var options: some View {
        RenderTime { context in
            let now = context.date
            HStack {
                if let shuffle = playback.shuffle(at: now), playback.hasTrack {
                    MediaToggle(symbol: "shuffle", label: "Shuffle", on: shuffle, accent: accent) { store.toggleShuffle() }
                } else {
                    Color.clear.frame(width: 48, height: 48)
                }
                Spacer()
                OutputPicker(outputs: playback.outputs(at: now), accent: accent) { store.selectOutput($0) }
                Spacer()
                if let mode = playback.repeatMode(at: now), playback.hasTrack {
                    MediaToggle(symbol: mode == .one ? "repeat.1" : "repeat",
                                label: mode == .one ? "Repeat one" : "Repeat", on: mode != .off, accent: accent) {
                        store.cycleRepeat()
                    }
                } else {
                    Color.clear.frame(width: 48, height: 48)
                }
            }
            .frame(maxWidth: 360)
        }
    }

    // MARK: Automation

    /// The Mac reports Spotify or Music control refused. Only song details depend on it, so this
    /// stays a small note (the full card shows instead when nothing is playing).
    @ViewBuilder private var automationNote: some View {
        if session.macStatus?.automationMedia == .denied, state.notice?.kind != MediaNotice.automationDenied {
            Label {
                Text("Song details from Spotify or Music need permission on your Mac: System Settings > Privacy & Security > Automation > Glasspad.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "hand.raised")
            }
            .font(.caption)
            .foregroundStyle(palette.inkSoftColor)
            .frame(maxWidth: 360, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Sliders

    private var sliders: some View {
        VStack(spacing: 16) {
            volumeSlider
            LevelSlider(value: $brightness, low: "sun.min.fill", high: "sun.max.fill",
                        label: "Brightness", enabled: state.brightness != nil) { editing in
                editingBrightness = editing
                if !editing { heldUntil = Date().addingTimeInterval(0.8) }
            } onChange: { value in
                guard abs(value - (state.brightness ?? -1)) > 0.001 else { return }
                throttle.send("brightness", value) { session.send(.mediaSetBrightness($0)) }
            }
        }
    }

    private var volumeSlider: some View {
        LevelSlider(value: $volume, low: "speaker.fill", high: "speaker.wave.3.fill",
                    label: "Volume", enabled: state.volume != nil) { editing in
            editingVolume = editing
            // The Mac's reply to the last drag step can trail the finger; hold the slider still.
            if !editing { heldUntil = Date().addingTimeInterval(0.8) }
        } onChange: { value in
            // Values the Mac just reported are not echoed back to it.
            guard abs(value - (state.volume ?? -1)) > 0.001 else { return }
            throttle.send("volume", value) { session.send(.mediaSetVolume($0)) }
        }
    }

    private func syncSliders() {
        guard Date() >= heldUntil else { return }
        if !editingVolume, let v = state.volume { volume = v }
        if !editingBrightness, let b = state.brightness { brightness = b }
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(max(0, t).rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Why song info is missing, and what to do about it on the Mac.
private struct NoticeCard: View {
    @Environment(\.palette) private var palette
    let notice: MediaNotice
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.kind == MediaNotice.automationDenied ? "hand.raised.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.kind == MediaNotice.automationDenied ? "Allow \(notice.app ?? "the player") on your Mac" : "No song details")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.inkColor)
                Text(notice.message)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.raisedColor))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.lineColor, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
