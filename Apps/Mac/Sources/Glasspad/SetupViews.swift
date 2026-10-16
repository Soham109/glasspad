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

/// Pairing in every state, around the living code: the code with one line of instruction (and
/// the same code as text for no camera or VoiceOver), then the dots gathering into a check with
/// the phone's name, or "Code Expired" and what went wrong with a way to start again.
struct PairingPanel: View {
    @EnvironmentObject private var model: AppModel
    var qrSize: CGFloat = 216
    var showsHeading = false
    /// Called once "Paired" has been on screen long enough to read, to close or reset whatever
    /// holds the panel.
    var onFinished: @MainActor () -> Void = {}
    /// The snapshot harness draws one fixed moment; the app leaves it nil.
    var fixedTime: Double?

    @State private var showsText = false
    /// The code last shown, so the dots can still gather after the phase drops the link.
    @State private var lastMessage: String?
    @State private var pairedAt: Date?
    @State private var showsResult = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long "Paired" stays before `onFinished`, counted from the first dot moving.
    static let finishDelay: Double = PairingPattern.gatherDuration + 2.2

    var body: some View {
        VStack(spacing: 14) {
            if showsHeading, model.pairing.url != nil {
                Text(PairingCopy.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            codeArea
            caption
        }
        .frame(maxWidth: .infinity)
        .onAppear { remember(model.pairing) }
        .onChange(of: model.pairing) { _, phase in remember(phase) }
    }

    private var cardSide: CGFloat { qrSize * 1.15 }

    @ViewBuilder private var codeArea: some View {
        switch model.pairing {
        case .idle:
            EmptyView()
        case .waiting(let url, _):
            ZStack {
                if showsText {
                    PairingLinkView(url: url, width: cardSide)
                        .transition(.opacity)
                } else {
                    PairingCodeView(message: url.absoluteString, size: qrSize, fixedTime: fixedTime)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .frame(height: cardSide)
        case .paired:
            PairingCodeView(message: lastMessage ?? Self.placeholder, size: qrSize,
                            phase: .gathered(since: pairedAt ?? .distantPast), fixedTime: fixedTime)
        case .expired, .failed:
            PairingCodeView(message: lastMessage ?? Self.placeholder, size: qrSize, phase: .resting, fixedTime: fixedTime)
        }
    }

    @ViewBuilder private var caption: some View {
        switch model.pairing {
        case .idle:
            EmptyView()
        case .waiting:
            Text(PairingCopy.instruction)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(showsText ? PairingCopy.showCode : PairingCopy.showText) {
                withAnimation(.smooth(duration: 0.3)) { showsText.toggle() }
            }
            .buttonStyle(.link)
            .font(.callout)
        case .paired(let name):
            VStack(spacing: 4) {
                Text(PairingCopy.heading(.paired(phoneName: name)))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(PairingCopy.detail(.paired(phoneName: name)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .opacity(showsResult ? 1 : 0)
            .offset(y: showsResult ? 0 : 6)
            .accessibilityElement(children: .combine)
            .task(id: pairedAt) {
                // The words arrive as the check forms, then whoever holds the panel closes it.
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.1 : PairingPattern.gatherDuration * 0.7))
                withAnimation(.smooth(duration: 0.45)) { showsResult = true }
                guard fixedTime == nil else { return }
                try? await Task.sleep(for: .seconds(Self.finishDelay - PairingPattern.gatherDuration * 0.7))
                if case .paired = model.pairing { onFinished() }
            }
        case .expired, .failed:
            VStack(spacing: 4) {
                Text(PairingCopy.heading(model.pairing))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(PairingCopy.detail(model.pairing))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            Button(model.pairing == .expired ? PairingCopy.newCode : PairingCopy.tryAgain) { model.actions.beginPairing() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func remember(_ phase: PairingPhase) {
        switch phase {
        case .waiting(let url, _):
            lastMessage = url.absoluteString
            pairedAt = nil
            showsResult = false
        case .paired:
            if pairedAt == nil { pairedAt = Date() }
            if fixedTime != nil { showsResult = true }
        case .idle:
            showsText = false
        default:
            break
        }
    }

    /// Drawn when the panel opens straight onto a result (no code was seen here).
    static let placeholder = "glasspad://pair"
}

// MARK: - Welcome window

/// The first launch, as a short assistant in the manner of the Mac's own setup screens: a
/// welcome, the permissions as a sequence that ticks itself off as each is granted, and the
/// living pairing code. Opens while no iPhone is paired, so a first launch never sits silently
/// in the menu bar.
struct WelcomeView: View {
    enum Page: Int, CaseIterable { case hello, permissions, pair }

    @EnvironmentObject private var model: AppModel
    var icon: NSImage?
    var onClose: @MainActor () -> Void = {}
    /// The snapshot harness draws one fixed moment of the code.
    var fixedTime: Double?

    @State private var page: Page
    @State private var forward = true

    static let size = CGSize(width: 620, height: 600)

    init(icon: NSImage? = nil, start: Page = .hello, fixedTime: Double? = nil, onClose: @escaping @MainActor () -> Void = {}) {
        self.icon = icon
        self.onClose = onClose
        self.fixedTime = fixedTime
        _page = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(page)
                    .transition(.push(from: forward ? .trailing : .leading))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear { model.actions.refresh() }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .hello: HelloPage(icon: icon ?? AppInfoText.icon)
        case .permissions: PermissionsPage { go(to: .pair) }
        case .pair: PairPage(fixedTime: fixedTime, onFinished: onClose)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if page == .pair {
                Link(WelcomeCopy.getIPhoneApp, destination: WelcomeCopy.iPhoneAppURL)
                    .font(.callout)
            } else if page != .hello {
                Button(WelcomeCopy.back) { go(to: Page(rawValue: page.rawValue - 1)!) }
            }
            Spacer()
            switch page {
            case .hello:
                Button(WelcomeCopy.continueTitle) { go(to: next(after: .hello)) }
                    .keyboardShortcut(.defaultAction)
            case .permissions:
                if model.accessibilityTrusted {
                    Button(WelcomeCopy.continueTitle) { go(to: .pair) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(WelcomeCopy.skip) { go(to: .pair) }
                }
            case .pair:
                if case .paired = model.pairing {
                    Button(WelcomeCopy.done) { onClose() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(WelcomeCopy.later) { onClose() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }

    /// Permissions already granted are not asked again.
    private func next(after page: Page) -> Page {
        page == .hello && model.accessibilityTrusted ? .pair : .permissions
    }

    private func go(to target: Page) {
        forward = target.rawValue > page.rawValue
        withAnimation(.smooth(duration: 0.45)) { page = target }
    }
}

/// A page's picture, title and one sentence, centred as the Mac's setup screens set them.
private struct PageHeader<Art: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var art: Art

    var body: some View {
        VStack(spacing: 14) {
            art
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
        }
    }
}

private struct HelloPage: View {
    let icon: NSImage

    var body: some View {
        VStack {
            Spacer()
            PageHeader(title: WelcomeCopy.helloTitle, detail: WelcomeCopy.helloDetail) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 128, height: 128)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
    }
}

// MARK: Permissions

private struct PermissionsPage: View {
    @EnvironmentObject private var model: AppModel
    /// Called when the required permission arrives and nothing optional is left to ask.
    var onComplete: @MainActor () -> Void
    @State private var openedSettings = false

    var body: some View {
        VStack(spacing: 26) {
            PageHeader(title: WelcomeCopy.permissionsTitle, detail: WelcomeCopy.permissionsDetail) {
                SettingsIcon(symbol: "hand.raised.fill", color: .blue, size: 72)
                    .padding(.bottom, 6)
            }
            VStack(spacing: 0) {
                PermissionStep(number: 1, kind: .accessibility, isCurrent: !model.accessibilityTrusted,
                               openedSettings: $openedSettings)
                Divider().padding(.leading, 58)
                PermissionStep(number: 2, kind: .media, isCurrent: model.accessibilityTrusted && model.automation == .notDetermined,
                               openedSettings: .constant(false))
            }
            .background(.background.secondary, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .frame(maxWidth: 500)
            .animation(.spring(duration: 0.45, bounce: 0.25), value: model.accessibilityTrusted)
            .animation(.spring(duration: 0.45, bounce: 0.25), value: model.automation)

            Text(model.accessibilityTrusted ? " " : WelcomeCopy.permissionsFooter)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .accessibilityHidden(model.accessibilityTrusted)
        }
        .padding(.horizontal, 40)
        .padding(.top, 44)
        .frame(maxHeight: .infinity, alignment: .top)
        // Live checks: macOS does not say when a permission changes, so look every second while
        // this page is up. The step ticks itself off the moment it is granted.
        .task {
            while !Task.isCancelled {
                model.actions.recheckPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: model.accessibilityTrusted) { was, now in
            guard !was, now else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            // Spotify and Music is optional and macOS asks for it on first use anyway, so once
            // Accessibility is on there is nothing that has to happen here.
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                if model.automation != .notDetermined { onComplete() }
            }
        }
    }
}

/// One permission in the sequence: its number (or a check once granted), what it allows, and
/// one button that opens the exact pane of System Settings, or asks macOS.
private struct PermissionStep: View {
    @EnvironmentObject private var model: AppModel
    let number: Int
    let kind: PermissionKind
    let isCurrent: Bool
    @Binding var openedSettings: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            marker
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(kind == .accessibility ? PermissionCopy.accessibilityTitle : PermissionCopy.mediaTitle)
                        .font(.body.weight(.semibold))
                    RequirementBadge(required: kind == .accessibility)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .opacity(isCurrent || isDone || kind == .accessibility ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number)")
    }

    private var isDone: Bool {
        kind == .accessibility ? model.accessibilityTrusted : model.automation == .granted
    }

    private var detail: String {
        kind == .accessibility
            ? PermissionCopy.accessibilityDetail
            : (model.automationHint ?? PermissionCopy.mediaDetail(model.automation, denied: model.automationDenied))
    }

    @ViewBuilder private var marker: some View {
        if isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .accessibilityLabel("Allowed")
        } else if kind == .accessibility && openedSettings {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Waiting for you to turn it on")
        } else {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(isCurrent ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch kind {
        case .accessibility:
            if model.accessibilityTrusted {
                Text("Allowed").foregroundStyle(.secondary)
            } else {
                Button(WelcomeCopy.openSettings) {
                    openedSettings = true
                    model.actions.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(PermissionCopy.accessibilityHint)
            }
        case .media:
            switch model.automation {
            case .granted:
                Text("Allowed").foregroundStyle(.secondary)
            case .denied:
                Button(WelcomeCopy.openSettings) { model.actions.openAutomationSettings() }
                    .accessibilityHint(PermissionCopy.mediaHint)
            case .notDetermined:
                Button("Allow…") { model.actions.requestAutomation() }
                    .disabled(!model.accessibilityTrusted)
                    .accessibilityLabel("Allow Spotify and Music")
            case .notNeeded:
                Text("Not needed").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Pair

private struct PairPage: View {
    @EnvironmentObject private var model: AppModel
    var fixedTime: Double?
    var onFinished: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(PairingCopy.title)
                    .font(.system(size: 26, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
            }
            PairingPanel(qrSize: 260, onFinished: onFinished, fixedTime: fixedTime)
                .frame(maxWidth: 420)
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            // A fresh code each time the page is reached, unless one is already up.
            if model.pairing.url == nil, !isPaired { model.actions.beginPairing() }
        }
    }

    private var isPaired: Bool {
        if case .paired = model.pairing { return true }
        return false
    }
}

/// The AppKit window around `WelcomeView`, so the menu bar app can open it at launch. A full
/// size content view with a clear title bar, as the Mac's own setup windows are.
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
            w.title = WelcomeCopy.helloTitle
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
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
