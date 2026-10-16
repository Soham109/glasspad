import AppKit
import GlasspadKit
import GlasspadMacCore
import SwiftUI

// MARK: - Permission rows

/// The two permissions, in the order they are asked: Accessibility (required), then Spotify
/// and Music (optional). Used by the welcome window and the popover checklist.
enum PermissionKind: Hashable {
    case accessibility, media
}

struct PermissionRow: View {
    @EnvironmentObject private var model: AppModel
    let kind: PermissionKind
    var iconSize: CGFloat = 26

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingsIcon(symbol: kind == .accessibility ? "hand.raised.fill" : "music.note",
                         color: kind == .accessibility ? .blue : .pink, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                    RequirementBadge(required: kind == .accessibility)
                }
                .fixedSize()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        kind == .accessibility ? PermissionCopy.accessibilityTitle : PermissionCopy.mediaTitle
    }

    private var detail: String {
        kind == .accessibility
            ? PermissionCopy.accessibilityDetail
            : PermissionCopy.mediaDetail(model.automation, denied: model.automationDenied)
    }

    private var note: String? {
        guard kind == .media else { return nil }
        if model.automation == .notDetermined && !model.accessibilityTrusted { return PermissionCopy.askAfterAccessibility }
        return model.automationHint
    }

    @ViewBuilder
    private var trailing: some View {
        switch kind {
        case .accessibility:
            if model.accessibilityTrusted {
                GrantedBadge()
            } else {
                Button("Allow…") { model.actions.requestAccessibility() }
                    .controlSize(.small)
                    .accessibilityLabel("Allow Accessibility")
                    .accessibilityHint(PermissionCopy.accessibilityHint)
            }
        case .media:
            switch model.automation {
            case .granted:
                GrantedBadge()
            case .denied:
                Button("Open Settings…") { model.actions.openAutomationSettings() }
                    .controlSize(.small)
                    .accessibilityLabel("Allow Spotify and Music")
                    .accessibilityHint(PermissionCopy.mediaHint)
            case .notDetermined:
                Button("Ask…") { model.actions.requestAutomation() }
                    .controlSize(.small)
                    // Asked in order: Accessibility first.
                    .disabled(!model.accessibilityTrusted)
                    .accessibilityLabel("Ask for Spotify and Music control")
            case .notNeeded:
                Text("Not needed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "Required" or "Optional" as a small capsule next to a permission's name.
struct RequirementBadge: View {
    let required: Bool

    var body: some View {
        // Primary or secondary text on a light tint, so it stays readable (orange text is not).
        Text(required ? PermissionCopy.required : PermissionCopy.optional)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(required ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(required ? AnyShapeStyle(Color.orange.opacity(0.25)) : AnyShapeStyle(.quaternary)))
    }
}

/// "Allowed" with a green check.
struct GrantedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Allowed")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pairing panel

/// Pairing in every state: the code (with Copy Link and Share for no camera or VoiceOver),
/// then "Paired" with the phone's name, "Code Expired" with a new code, or what went wrong.
struct PairingPanel: View {
    @EnvironmentObject private var model: AppModel
    var qrSize: CGFloat = 216
    var showsHeading = false
    /// Called a moment after "Paired" shows, to close or reset whatever holds the panel.
    var onFinished: @MainActor () -> Void = {}
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            switch model.pairing {
            case .idle:
                EmptyView()
            case .waiting(let url, _):
                if showsHeading { heading }
                QRCodeView(url: url, size: qrSize)
                Text(PairingCopy.instruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        Text(PairingCopy.waiting)
                            .font(.callout.weight(.medium))
                    }
                    Text(PairingCopy.lifetime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: 8) {
                    Button {
                        model.actions.copyPairingLink(url)
                        copied = true
                    } label: {
                        Label(copied ? PairingCopy.copied : PairingCopy.copyLink,
                              systemImage: copied ? "checkmark" : "link")
                    }
                    .accessibilityHint("Copies the pairing link. Paste it in Glasspad on your iPhone.")
                    ShareLink(item: url) {
                        Label(PairingCopy.share, systemImage: "square.and.arrow.up")
                    }
                    .accessibilityHint("Send the pairing link to your iPhone with AirDrop or Messages.")
                }
                .controlSize(.small)
                Text(PairingCopy.linkHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            case .paired:
                ResultIcon(symbol: "checkmark", color: .green)
                heading
                detailText
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        if case .paired = model.pairing { onFinished() }
                    }
            case .expired:
                ResultIcon(symbol: "clock.badge.exclamationmark", color: .orange)
                heading
                detailText
                Button(PairingCopy.newCode) { model.actions.beginPairing() }
                    .keyboardShortcut(.defaultAction)
            case .failed:
                ResultIcon(symbol: "exclamationmark.triangle", color: .orange)
                heading
                detailText
                Button(PairingCopy.tryAgain) { model.actions.beginPairing() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: model.pairing.url) { _, _ in copied = false }
        .frame(maxWidth: .infinity)
    }

    private var heading: some View {
        Text(PairingCopy.heading(model.pairing))
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private var detailText: some View {
        Text(PairingCopy.detail(model.pairing))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ResultIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.15))
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}

// MARK: - Welcome window

/// Opens on launch while no iPhone is paired, so a first launch never sits silently in the
/// menu bar: the code straight away, three short steps, and the permissions in order.
struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    var icon: NSImage?
    var onClose: @MainActor () -> Void = {}

    static let size = CGSize(width: 640, height: 470)

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(nsImage: icon ?? AppInfoText.icon)
                            .resizable()
                            .frame(width: 52, height: 52)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Welcome to Glasspad")
                                .font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text("Your iPhone as a trackpad and remote for this Mac.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    WelcomeStep(number: 1, title: nil) {
                        PermissionRow(kind: .accessibility, iconSize: 24)
                    }
                    WelcomeStep(number: 2, title: "Pair your iPhone") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open Glasspad on your iPhone, tap Pair a Mac, and scan the code. Keep both on the same Wi-Fi.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Link("Get Glasspad for iPhone", destination: URL(string: "https://github.com/Soham109/glasspad#install")!)
                                .font(.callout)
                        }
                    }
                    WelcomeStep(number: 3, title: nil) {
                        PermissionRow(kind: .media, iconSize: 24)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if model.pairing.isActive {
                        PairingPanel(qrSize: 190, showsHeading: false) { onClose() }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Button(PairingCopy.menuItem) { model.actions.beginPairing() }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 240)
                .padding(14)
                .background(.background.secondary, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .padding(22)

            Divider()
            HStack(spacing: 8) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Glasspad lives in the menu bar. Click its icon any time to pair or change settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isPaired ? "Done" : "Close") { onClose() }
                    .keyboardShortcut(isPaired ? .defaultAction : .cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .frame(width: Self.size.width)
        .onAppear { model.actions.refresh() }
    }

    private var isPaired: Bool {
        if case .paired = model.pairing { return true }
        return false
    }
}

private struct WelcomeStep<Content: View>: View {
    let number: Int
    /// nil when the content names itself (a permission row).
    let title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .accessibilityLabel("Step \(number), \(title)")
                }
                content()
            }
        }
    }
}

/// The AppKit window around `WelcomeView`, so the menu bar app can open it at launch.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var model: AppModel?

    func show(_ model: AppModel) {
        self.model = model
        if window == nil {
            let view = WelcomeView { [weak self] in self?.close() }.environmentObject(model)
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = "Welcome to Glasspad"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        if !model.pairing.isActive { model.actions.beginPairing() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        // A code nobody will see is disarmed; a result is dismissed.
        if let model, model.pairing.isActive { model.actions.cancelPairing() }
        window = nil
    }
}
