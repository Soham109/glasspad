import SwiftUI
import UniformTypeIdentifiers
import GlasspadKit

/// Send the phone clipboard to the Mac, or bring the Mac clipboard to the phone.
/// Sending uses the system Paste button, so iOS never shows a "paste from" prompt.
struct ClipboardMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.modeTopClearance) private var topClearance
    var session = MacSession.shared
    /// Shown as a page inside Actions (no room needed for the mode pill).
    var embedded = false
    private var accent: Color { AppMode.clipboard.accent(palette) }

    /// Reading the pasted items (the Mac's answer is `session.clipboardPush`).
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
            .padding(.top, embedded ? 14 : topClearance ?? 76)
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
                .disabled(sending || isWaiting)
                Spacer()
                if sending || isWaiting { ProgressView() }
            }
            if !pasteboardHasContent && session.clipboardPush == nil {
                Text("Copy something on this iPhone first, then tap Paste.")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
            }
            switch session.clipboardPush {
            case .waiting?:
                Text("Sending to your Mac…")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
            case .accepted(let note)?:
                Label(note, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(accent)
                    .transition(.opacity)
            case .refused(let reason)?:
                ClipboardProblem(title: "Not sent", message: reason)
                    .transition(.opacity)
            case nil:
                EmptyView()
            }
        }
        .animation(.snappy, value: session.clipboardPush)
    }

    private var isWaiting: Bool {
        if case .waiting = session.clipboardPush { true } else { false }
    }

    private func refreshPasteboard() {
        let pb = UIPasteboard.general
        pasteboardHasContent = pb.hasStrings || pb.hasImages || pb.hasURLs
    }

    private func send(_ providers: [NSItemProvider]) async {
        sending = true
        defer { sending = false }
        guard let content = await ClipboardReader.content(from: providers) else {
            session.clipboardPushFailed("Glasspad could not read what was copied, or the image is too large to send. Copy text or a smaller image, then tap Paste again.")
            return
        }
        // "Sent" appears only once the Mac says it took it.
        session.pushClipboard(content)
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
                Label("Get Mac Clipboard", systemImage: "arrow.down.doc")
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
    static let previewCharacters = 4000

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch pulled.content {
            case .none:
                if let problem = pulled.problem {
                    ClipboardProblem(title: "Not copied", message: problem)
                } else {
                    Text("The Mac clipboard has no text or image.")
                        .font(.subheadline)
                        .foregroundStyle(palette.inkSoftColor)
                }
            case .text(let text):
                // A few thousand characters are plenty to recognise it; laying out megabytes of
                // text in one Text view freezes the screen. The whole text is on the clipboard.
                Text(text.count > Self.previewCharacters ? String(text.prefix(Self.previewCharacters)) + "…" : text)
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

/// What the Mac sent back, with an id so the same text twice still animates.
struct PulledClipboard: Equatable {
    let id = UUID()
    let content: ClipboardContent?
    /// Why nothing came, in the Mac's words (or "did not answer"); nil for an empty clipboard.
    var problem: String? = nil
}

/// A send to the Mac clipboard, from tapping Paste to the Mac's answer.
enum ClipboardPushStatus: Equatable {
    /// Sent; the Mac has not answered yet. `whenDone` is shown once it says it took it.
    case waiting(whenDone: String)
    case accepted(String)
    /// The Mac's reason, or the phone's when it never got there.
    case refused(String)

    static let noConfirmation = "Your Mac did not confirm it got this. Check the Mac clipboard. If Glasspad on your Mac is an older version, update it so this iPhone can tell."
    static let noAnswer = "Your Mac did not answer. Try again."
}

/// A refusal or failure, in words, with a warning sign.
private struct ClipboardProblem: View {
    @Environment(\.palette) private var palette
    let title: String
    let message: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(palette.inkColor)
                Text(message).font(.footnote).foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
    }
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

    /// PNG no larger than `maxImageSide` and `ClipboardContent.maxImageBytes` (a photo PNG at
    /// 3000 points is often 12 to 15 MB, over the one-message limit once base64 encoded).
    static func pngData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = max(image.size.width, image.size.height)
        if side <= maxImageSide, let png = image.pngData(), png.count <= ClipboardContent.maxImageBytes { return png }
        var scale = min(1, maxImageSide / side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        for _ in 0..<6 {
            let size = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
            let png = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            if png.count <= ClipboardContent.maxImageBytes { return png }
            scale *= 0.7
        }
        return nil
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
