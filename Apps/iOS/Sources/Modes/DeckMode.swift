import SwiftUI
import GlasspadKit

/// A grid of the buttons set up in the Mac app. Tap runs one on the Mac and shows the outcome.
struct DeckMode: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    private let accent = AppMode.deck.accent(.paper)

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            if let buttons = session.deckButtons {
                if buttons.isEmpty {
                    QuietMessage(symbol: "square.grid.2x2", title: "No buttons yet",
                                 detail: "Add buttons in the Glasspad menu on your Mac. They show up here.")
                } else {
                    grid(buttons)
                }
            } else if session.isConnected {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ModeOfflineMessage(mode: .deck)
            }
        }
        .overlay(alignment: .bottom) { failureBanner }
        .onAppear { session.send(.deckRequest) }
    }

    private func grid(_ buttons: [DeckButton]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(buttons) { button in
                    DeckTile(button: button, accent: accent,
                             pending: session.deckPending.contains(button.id),
                             outcome: session.deckOutcomes[button.id]) {
                        Haptics.shared.play(.click)
                        session.runDeck(button.id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 32)
        }
        .refreshable { session.send(.deckRequest) }
    }

    @ViewBuilder private var failureBanner: some View {
        if let failure = session.deckFailure {
            Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(palette.inkColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassCapsule()
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(failure.id)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

private struct DeckTile: View {
    @Environment(\.palette) private var palette
    let button: DeckButton
    let accent: Color
    let pending: Bool
    let outcome: DeckOutcome?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Image(systemName: UIImage(systemName: button.symbol) == nil ? "square.dashed" : button.symbol)
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                        .opacity(pending ? 0 : 1)
                        .symbolEffect(.bounce, value: outcome?.id)
                    if pending { ProgressView() }
                }
                .frame(height: 30)
                Text(button.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(palette.inkColor)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 104)
        }
        .glassButton()
        .buttonBorderShape(.roundedRectangle(radius: 22))
        .overlay(alignment: .topTrailing) {
            if let outcome, outcome.ok {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(Color.green)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: outcome?.id)
        .accessibilityLabel(button.title)
        .accessibilityHint(button.action.spokenHint)
    }
}

/// The last result of running a Deck button.
struct DeckOutcome: Equatable {
    let id = UUID()
    let ok: Bool
    let message: String?
}

struct DeckFailure: Equatable {
    let id = UUID()
    let message: String
}

extension DeckAction {
    var spokenHint: String {
        switch self {
        case .openApp: "Opens an app on your Mac"
        case .openURL: "Opens a link on your Mac"
        case .runShortcut(let name): "Runs the shortcut \(name) on your Mac"
        case .keystroke: "Presses a key combination on your Mac"
        case .shellScript: "Runs a script on your Mac"
        }
    }
}
