import SwiftUI
import UniformTypeIdentifiers
import GlasspadKit

/// Send the phone clipboard to the Mac, or bring the Mac clipboard to the phone.
/// Sending uses the system Paste button, so iOS never shows a "paste from" prompt.
struct ClipboardMode: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    /// Shown as a page inside Actions (no room needed for the mode pill).
    var embedded = false
    private let accent = AppMode.clipboard.accent(.paper)

    @State private var sentNote: String?
    @State private var sending = false
    /// Checking for content does not read it, so iOS shows no paste prompt.
    @State private var pasteboardHasContent = UIPasteboard.general.hasStrings || UIPasteboard.general.hasImages || UIPasteboard.general.hasURLs

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sendCard
                pullCard
            }
            .padding(.horizontal, 16)
            .padding(.top, embedded ? 14 : 76)
            .padding(.bottom, 32)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in refreshPasteboard() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refreshPasteboard() }
        .overlay {
            if !session.isConnected { ModeOfflineMessage(mode: .clipboard).background(palette.backgroundColor) }
        }
    }

    // MARK: To Mac

    private var sendCard: some View {
        Card {
            CardHeader(symbol: "iphone.and.arrow.forward", title: "To your Mac",
                       detail: "Text or an image copied on this iPhone.")
            HStack {
                PasteButton(supportedContentTypes: [.image, .plainText, .url]) { providers in
                    Task { @MainActor in await send(providers) }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(accent)
                .disabled(sending)
                Spacer()
                if sending { ProgressView() }
            }
            if !pasteboardHasContent && sentNote == nil {
                Text("Copy something on this iPhone first, then tap Paste.")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
            }
            if let sentNote {
                Label(sentNote, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(accent)
                    .transition(.opacity)
            }
        }
    }

    private func refreshPasteboard() {
        let pb = UIPasteboard.general
        pasteboardHasContent = pb.hasStrings || pb.hasImages || pb.hasURLs
    }

    private func send(_ providers: [NSItemProvider]) async {
        sending = true
        defer { sending = false }
        guard let content = await ClipboardReader.content(from: providers) else {
            sentNote = nil
            Haptics.shared.play(.error)
            return
        }
        session.send(.clipboardPush(content))
        Haptics.shared.play(.snap)
        withAnimation {
            switch content {
            case .text(let t): sentNote = "Sent \(t.count) characters"
            case .imagePNG: sentNote = "Sent an image"
            }
        }
    }

    // MARK: From Mac

    private var pullCard: some View {
        Card {
            CardHeader(symbol: "laptopcomputer.and.arrow.down", title: "From your Mac",
                       detail: "Copies what is on the Mac clipboard to this iPhone.")
            Button {
                Haptics.shared.tap()
                session.pullClipboard()
            } label: {
                Label("Get Mac clipboard", systemImage: "arrow.down.doc")
                    .padding(.horizontal, 4)
            }
            .glassButton(prominent: true, accent: accent)
            .disabled(session.clipboardPullPending)

            if session.clipboardPullPending {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else if let pulled = session.clipboardPulled {
                PulledPreview(pulled: pulled, accent: accent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.snappy, value: session.clipboardPulled)
    }
}

private struct PulledPreview: View {
    @Environment(\.palette) private var palette
    let pulled: PulledClipboard
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch pulled.content {
            case .none:
                Text("The Mac clipboard has no text or image.")
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
            case .text(let text):
                Text(text)
                    .font(.body)
                    .foregroundStyle(palette.inkColor)
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(palette.backgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                copiedLine
            case .imagePNG(let data):
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Image from your Mac")
                    HStack {
                        copiedLine
                        Spacer()
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Image from Mac", image: Image(uiImage: image)))
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }

    private var copiedLine: some View {
        Label("Copied to iPhone", systemImage: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(accent)
    }
}

/// What the Mac sent back, with a timestamp so the same text twice still animates.
struct PulledClipboard: Equatable {
    let id = UUID()
    let content: ClipboardContent?
}

/// Reads pasted items into a `ClipboardContent`. Large photos are scaled down so a 48 MP
/// image does not become a 100 MB message.
@MainActor
enum ClipboardReader {
    static let maxImageSide: CGFloat = 3000

    static func content(from providers: [NSItemProvider]) async -> ClipboardContent? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = await loadData(provider, type: .image),
               let png = pngData(from: data) {
                return .imagePNG(png)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let data = await loadData(provider, type: .url),
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                return .text(url.absoluteString)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let data = await loadData(provider, type: .plainText),
               let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return .text(text)
            }
        }
        return nil
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    static func pngData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = max(image.size.width, image.size.height)
        guard side > maxImageSide else { return image.pngData() }
        let scale = maxImageSide / side
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(palette.lineColor))
    }
}

struct CardHeader: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(palette.inkColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(palette.inkColor)
                Text(detail).font(.subheadline).foregroundStyle(palette.inkSoftColor)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
