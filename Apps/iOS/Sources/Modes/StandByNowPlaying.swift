import GlasspadKit
import SwiftUI
import UIKit

/// The Now Playing StandBy screen: the cover large, the title and artist, and back, play or
/// pause and next. Everything comes from `MediaStore`, the same as Media; this only draws it
/// the StandBy way. Side by side in a wide pane, one above the other in a tall one.
struct NowPlayingMode: View {
    var session = MacSession.shared
    var store = MediaStore.shared

    private var playback: MediaPlayback { store.playback }
    private var state: MediaState { store.state ?? MediaState() }

    var body: some View {
        StandByScreen { _, style in
            GeometryReader { geo in
                if !session.isConnected && store.state == nil {
                    // The same message as every mode without its Mac, in StandBy's greys.
                    ModeOfflineMessage(mode: .nowPlaying)
                        .environment(\.palette, .graphite)
                        .padding(.horizontal, 20)
                } else {
                    content(style, geo.size)
                }
            }
        }
        .contextMenu { StandByMenu() }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-GPMediaDemo") {
                store.applyDemo(i + 1 < args.count ? args[i + 1] : nil)
            }
            #endif
            session.send(.mediaRequest)
        }
    }

    @ViewBuilder private func content(_ style: StandByStyle, _ size: CGSize) -> some View {
        let pad = CGSize(width: max(18, size.width * 0.07), height: max(18, size.height * 0.08))
        let room = CGSize(width: size.width - pad.width * 2, height: size.height - pad.height * 2)
        let wide = room.width > room.height * 1.2
        if wide {
            // Cover on the left, words and buttons on the right, centred on each other.
            let side = min(room.height, room.width * 0.46)
            let column = room.width - side - side * 0.12
            HStack(spacing: side * 0.12) {
                cover(style, side: side)
                details(style, width: column, scale: min(side, column * 1.1), alignment: .leading)
                    .frame(width: column, alignment: .leading)
            }
            .frame(width: size.width, height: size.height)
        } else {
            // Cover above, then the words and buttons. The cover takes what they leave.
            let scale = min(room.width, room.height * 0.62)
            let textBlock = scale * 0.5
            let side = max(40, min(room.width * 0.86, room.height - textBlock))
            VStack(spacing: side * 0.09) {
                cover(style, side: side)
                details(style, width: room.width, scale: scale, alignment: .center)
                    .frame(width: room.width)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: Cover

    private func cover(_ style: StandByStyle, side: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.07, style: .continuous)
        return ZStack {
            shape.fill(style.fill)
            if let image = store.artwork, playback.hasTrack {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    // A cover is the brightest thing on screen; StandBy keeps it a touch dim.
                    .opacity(0.9)
                    .transition(.opacity)
                    .id(store.artworkID)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.3, weight: .light))
                    .foregroundStyle(style.faint)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .animation(.easeInOut(duration: 0.4), value: store.artworkID)
        .accessibilityHidden(true)
    }

    // MARK: Words and buttons

    /// `scale` sets the type and button sizes: the room the pane has for them.
    @ViewBuilder
    private func details(_ style: StandByStyle, width: CGFloat, scale: CGFloat, alignment: HorizontalAlignment) -> some View {
        let titleSize = min(30, max(15, scale * 0.085))
        let textAlignment: TextAlignment = alignment == .leading ? .leading : .center
        VStack(alignment: alignment, spacing: titleSize * 0.9) {
            VStack(alignment: alignment, spacing: titleSize * 0.18) {
                Text(playback.hasTrack ? (state.title ?? "") : "Nothing Playing")
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(style.primary)
                Text(playback.hasTrack ? subtitle : "Play something on your Mac.")
                    .font(.system(size: titleSize * 0.8, weight: .regular))
                    .foregroundStyle(style.secondary)
            }
            .lineLimit(1)
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: width, alignment: alignment == .leading ? .leading : .center)
            .accessibilityElement(children: .combine)
            if playback.hasTrack {
                transport(style, size: titleSize, alignment: alignment)
            }
        }
    }

    private var subtitle: String {
        let artist = state.artist?.isEmpty == false ? state.artist : nil
        return artist ?? state.album ?? state.sourceName ?? ""
    }

    /// Back, play or pause, next. A tap shows at once and the Mac's next state confirms it;
    /// `MediaStore` redraws when an unconfirmed tap runs out, so no timer is needed here.
    private func transport(_ style: StandByStyle, size: CGFloat, alignment: HorizontalAlignment) -> some View {
        let playing = playback.isPlaying(at: Date())
        let skip = size * 1.15
        return HStack(spacing: size * 1.1) {
            button("backward.fill", "Previous track", size: skip, style) { store.previous() }
            button(playing ? "pause.fill" : "play.fill", playing ? "Pause" : "Play", size: size * 1.55, style) {
                store.togglePlay()
            }
            button("forward.fill", "Next track", size: skip, style) { store.next() }
        }
        // The back button's touch area reaches past its symbol; line the symbol up with the
        // title instead.
        .padding(.leading, alignment == .leading ? -Self.slack("backward.fill", size: skip) : 0)
    }

    /// The empty room either side of a symbol inside its button.
    private static func slack(_ symbol: String, size: CGFloat) -> CGFloat {
        let config = UIImage.SymbolConfiguration(pointSize: size)
        let width = UIImage(systemName: symbol, withConfiguration: config)?.size.width ?? size
        return (buttonSide(size) - width) / 2
    }

    private static func buttonSide(_ size: CGFloat) -> CGFloat { max(44, size * 1.6) }

    private func button(_ symbol: String, _ label: String, size: CGFloat, _ style: StandByStyle,
                        _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(style.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.buttonSide(size), height: Self.buttonSide(size))
                .contentShape(Rectangle())
        }
        .buttonStyle(TileStyle())
        .accessibilityLabel(label)
    }
}
