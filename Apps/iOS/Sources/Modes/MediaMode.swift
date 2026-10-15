import SwiftUI
import GlasspadKit

/// Now playing on the Mac, with transport, volume and brightness.
struct MediaMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var session = MacSession.shared
    private let accent = AppMode.media.accent(.paper)

    @State private var volume: Double = 0.5
    @State private var brightness: Double = 0.5
    @State private var editingVolume = false
    @State private var editingBrightness = false
    @State private var throttle = SliderThrottle()

    private var state: MediaState { session.media ?? MediaState() }

    var body: some View {
        ZStack {
            if !session.isConnected && session.media == nil {
                ModeOfflineMessage(mode: .media)
            } else {
                content
            }
        }
        .onAppear {
            session.send(.mediaRequest)
            syncSliders()
        }
        .onChange(of: session.media) { syncSliders() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 72)
            artwork
                .padding(.horizontal, 36)
            VStack(spacing: 4) {
                Text(state.title ?? "Nothing playing")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.inkColor)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(palette.inkSoftColor)
            }
            .lineLimit(1)
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .accessibilityElement(children: .combine)

            progress
                .padding(.horizontal, 32)
                .padding(.top, 18)

            transport
                .padding(.top, 18)

            Spacer(minLength: 16)

            VStack(spacing: 18) {
                LevelSlider(value: $volume, low: "speaker.fill", high: "speaker.wave.3.fill",
                            label: "Volume", enabled: state.volume != nil, accent: accent) { editing in
                    editingVolume = editing
                } onChange: { value in
                    // Values the Mac just reported are not echoed back to it.
                    guard abs(value - (state.volume ?? -1)) > 0.001 else { return }
                    throttle.send("volume", value) { session.send(.mediaSetVolume($0)) }
                }
                LevelSlider(value: $brightness, low: "sun.min.fill", high: "sun.max.fill",
                            label: "Brightness", enabled: state.brightness != nil, accent: accent) { editing in
                    editingBrightness = editing
                } onChange: { value in
                    guard abs(value - (state.brightness ?? -1)) > 0.001 else { return }
                    throttle.send("brightness", value) { session.send(.mediaSetBrightness($0)) }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }

    private var subtitle: String {
        [state.artist, state.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            .ifEmpty(state.title == nil ? "Play something on your Mac" : " ")
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.raisedColor)
            if let data = state.artworkPNG, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(palette.inkSoftColor)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(palette.isDark ? 0.45 : 0.16), radius: 24, y: 12)
        .scaleEffect(state.isPlaying || reduceMotion ? 1 : 0.86)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: state.isPlaying)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var progress: some View {
        if let duration = state.duration, duration > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = currentElapsed(at: context.date, duration: duration)
                VStack(spacing: 6) {
                    ProgressView(value: elapsed, total: duration)
                        .tint(palette.inkColor.opacity(0.7))
                    HStack {
                        Text(Self.clock(elapsed))
                        Spacer()
                        Text("-" + Self.clock(duration - elapsed))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.inkSoftColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Self.clock(elapsed)) of \(Self.clock(duration))")
            }
        } else {
            Color.clear.frame(height: 24)
        }
    }

    private var transport: some View {
        HStack(spacing: 44) {
            transportButton("backward.fill", "Previous track", .previousTrack, size: 30)
            Button {
                Haptics.shared.play(.click)
                session.send(.mediaCommand(.playPause))
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 76, height: 76)
                    .contentShape(Circle())
            }
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            transportButton("forward.fill", "Next track", .nextTrack, size: 30)
        }
        .buttonStyle(TileStyle())
        .foregroundStyle(palette.inkColor)
    }

    private func transportButton(_ symbol: String, _ label: String, _ command: MediaCommand, size: CGFloat) -> some View {
        Button {
            Haptics.shared.tap()
            session.send(.mediaCommand(command))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
    }

    private func currentElapsed(at date: Date, duration: TimeInterval) -> TimeInterval {
        guard let base = state.elapsed else { return 0 }
        let since = state.isPlaying ? date.timeIntervalSince(session.mediaReceivedAt ?? date) : 0
        return min(duration, max(0, base + since))
    }

    private func syncSliders() {
        if !editingVolume, let v = state.volume { volume = v }
        if !editingBrightness, let b = state.brightness { brightness = b }
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// System-looking slider flanked by two symbols.
private struct LevelSlider: View {
    @Environment(\.palette) private var palette
    @Binding var value: Double
    let low: String
    let high: String
    let label: String
    let enabled: Bool
    let accent: Color
    var onEditing: (Bool) -> Void
    var onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: low).font(.footnote).frame(width: 20)
            Slider(value: $value, in: 0...1, onEditingChanged: onEditing)
                .tint(palette.inkColor.opacity(0.75))
                .onChange(of: value) { _, new in onChange(new) }
                .accessibilityLabel(label)
            Image(systemName: high).font(.footnote).frame(width: 20)
        }
        .foregroundStyle(palette.inkSoftColor)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityHint(enabled ? "" : "Your Mac does not report this")
    }
}

/// Sends slider values at most every 50 ms, plus the final value, so dragging does not
/// flood the connection.
@MainActor
final class SliderThrottle {
    private var lastSent: [String: Date] = [:]
    private var pending: [String: Task<Void, Never>] = [:]

    func send(_ key: String, _ value: Double, _ action: @escaping @MainActor (Double) -> Void) {
        pending[key]?.cancel()
        let now = Date()
        if now.timeIntervalSince(lastSent[key] ?? .distantPast) >= 0.05 {
            lastSent[key] = now
            action(value)
        } else {
            pending[key] = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                self.lastSent[key] = Date()
                action(value)
            }
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
