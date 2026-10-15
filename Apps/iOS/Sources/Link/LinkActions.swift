import SwiftUI

/// What the user can do about a link that is not up: take the Mac back from another iPhone,
/// or wake a sleeping Mac. Shows nothing when neither applies.
struct LinkActions: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    var store = PairingStore.shared

    @State private var waking = false
    @State private var wakeNote: String?

    var body: some View {
        VStack(spacing: 10) {
            if session.isReplaced {
                Button("Use on This iPhone") {
                    Haptics.shared.tap()
                    session.useHere()
                }
                .glassButton(prominent: true)
                .controlSize(.large)
                .accessibilityHint("Takes the Mac back. The other iPhone disconnects.")
            } else if !session.isConnected, store.selected?.wakeTarget?.lastIPv4 != nil {
                Button {
                    Task { await wake() }
                } label: {
                    Label(waking ? "Waking" : "Wake Mac", systemImage: "power")
                }
                .glassButton()
                .controlSize(.large)
                .disabled(waking)
                .accessibilityHint("Sends a wake signal to your Mac on this network")
                if let wakeNote {
                    Text(wakeNote)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.inkSoftColor)
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy, value: session.isReplaced)
        .animation(.snappy, value: wakeNote)
    }

    private func wake() async {
        waking = true
        defer { waking = false }
        switch await session.wakeMac() {
        case .sent:
            Haptics.shared.play(.detent)
            wakeNote = "Sent. A sleeping Mac wakes only if Wake for network access is on."
        case .noAddress:
            wakeNote = "Connect once first, so Glasspad learns how to wake this Mac."
        case .failed:
            Haptics.shared.play(.error)
            wakeNote = "Could not send. Check that this iPhone is on the same Wi-Fi."
        }
        try? await Task.sleep(for: .seconds(5))
        wakeNote = nil
    }
}
