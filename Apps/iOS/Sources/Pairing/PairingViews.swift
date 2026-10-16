import SwiftUI
import GlasspadKit
import AVFoundation

/// Turns a scanned or pasted string into a pairing, or a plain reason it failed.
enum PairingParser {
    static func parse(_ text: String) -> PairingPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "glasspad" else { return nil }
        return PairingPayload(url: url)
    }
}

// MARK: - Setup page

/// One screen of setup in Apple's manner: a picture, a title, one sentence, one prominent
/// button and an optional text button beneath it. Sideways the picture sits beside the words.
struct SetupPage<Art: View, Extra: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var dynamicType
    let title: String
    let detail: String
    let primary: String
    var secondary: String?
    var primaryAction: () -> Void
    var secondaryAction: () -> Void = {}
    @ViewBuilder var art: Art
    @ViewBuilder var extra: Extra

    var body: some View {
        if verticalSize == .compact {
            HStack(spacing: 44) {
                if !dynamicType.isAccessibilitySize {
                    art.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        words(alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    buttons
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: 380)
            }
            .padding(.horizontal, 44)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 30) {
                        if !dynamicType.isAccessibilitySize {
                            art.frame(height: 250)
                        }
                        words(alignment: .center)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.center)
                buttons
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)
            }
        }
    }

    private func words(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 14) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(palette.inkColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.body)
                .foregroundStyle(palette.inkSoftColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340, alignment: alignment == .center ? .center : .leading)
            extra
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            Button(action: primaryAction) {
                Text(primary)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .glassButton(prominent: true)
            .controlSize(.large)
            // Same height with or without the text button, so the main one never moves.
            Button(secondary ?? " ", action: secondaryAction)
                .font(.body.weight(.medium))
                .foregroundStyle(palette.inkColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .opacity(secondary == nil ? 0 : 1)
                .disabled(secondary == nil)
                .accessibilityHidden(secondary == nil)
        }
        .frame(maxWidth: 360)
    }
}

extension SetupPage where Extra == EmptyView {
    init(title: String, detail: String, primary: String, secondary: String? = nil,
         primaryAction: @escaping () -> Void, secondaryAction: @escaping () -> Void = {}, @ViewBuilder art: () -> Art) {
        self.init(title: title, detail: detail, primary: primary, secondary: secondary, primaryAction: primaryAction,
                  secondaryAction: secondaryAction, art: art, extra: { EmptyView() })
    }
}

/// A large SF Symbol in a soft tile, the picture on the permission screens.
struct SymbolArt: View {
    @Environment(\.palette) private var palette
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 64, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(palette.inkColor)
            .frame(width: 132, height: 132)
            .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(palette.lineColor))
            .accessibilityHidden(true)
    }
}

// MARK: - Pair flow

/// Everything after the Mac shows its code: the two permissions explained before iOS asks,
/// the viewfinder, then the Mac it connected to. Used by onboarding and by Pair a Mac.
struct PairFlow: View {
    enum Step: String, Hashable { case network, camera, scan, connected }

    @Environment(\.palette) private var palette
    var cancelTitle = "Cancel"
    var onCancel: () -> Void
    var onFinish: () -> Void

    @State private var step: Step
    @State private var mac: PairedMac?
    @State private var showPaste = false
    @State private var probing = false
    @AppStorage("pairing.localNetworkExplained") private var networkExplained = false

    init(cancelTitle: String = "Cancel", start: Step? = nil, mac: PairedMac? = nil,
         onCancel: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.cancelTitle = cancelTitle
        self.onCancel = onCancel
        self.onFinish = onFinish
        _step = State(initialValue: start ?? Self.firstStep)
        _mac = State(initialValue: mac)
    }

    /// Only what still needs explaining: iOS asks for each permission once.
    private static var firstStep: Step {
        if !UserDefaults.standard.bool(forKey: "pairing.localNetworkExplained") { return .network }
        if CameraAccess.hasCamera, CameraAccess.status == .notDetermined { return .camera }
        return .scan
    }

    var body: some View {
        ZStack {
            switch step {
            case .network:
                SetupPage(title: "Find Your Mac on Wi-Fi",
                          detail: "Glasspad talks to your Mac over this network. iOS will ask to let it find devices nearby.",
                          primary: "Continue", primaryAction: allowNetwork) {
                    SymbolArt(symbol: "wifi")
                }
                .transition(.push(from: .trailing))
            case .camera:
                SetupPage(title: "Scan the Code on Your Mac",
                          detail: "Glasspad uses the camera only to read the pairing code. iOS will ask to allow it.",
                          primary: "Continue", secondary: "Paste the Link Instead",
                          primaryAction: allowCamera, secondaryAction: { showPaste = true }) {
                    SymbolArt(symbol: "camera.viewfinder")
                }
                .transition(.push(from: .trailing))
            case .scan:
                PairingViewfinder(cancelTitle: cancelTitle, onCancel: onCancel, onPaste: { showPaste = true }) { paired in
                    finishPairing(paired)
                }
                .transition(.opacity)
            case .connected:
                if let mac {
                    ConnectedView(mac: mac, onContinue: onFinish)
                        .transition(.blurReplace)
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: step)
        .sheet(isPresented: $showPaste) {
            PasteLinkSheet { paired in
                showPaste = false
                finishPairing(paired)
            }
            .environment(\.palette, palette)
        }
        .onDisappear { if probing { LocalNetworkProbe.shared.stop() } }
    }

    private func allowNetwork() {
        networkExplained = true
        // Browsing is what makes iOS ask. It keeps going until this flow leaves.
        if !probing {
            probing = true
            LocalNetworkProbe.shared.start()
        }
        step = CameraAccess.hasCamera && CameraAccess.status == .notDetermined ? .camera : .scan
    }

    private func allowCamera() {
        Task {
            _ = await CameraAccess.request()
            step = .scan
        }
    }

    private func finishPairing(_ paired: PairedMac) {
        mac = paired
        step = .connected
    }
}

// MARK: - Connected

/// After the scan: the Mac, its name, and Continue. Says Connected only once it is, and
/// what to fix when iOS is keeping Glasspad off the network.
struct ConnectedView: View {
    @Environment(\.palette) private var palette
    let mac: PairedMac
    var onContinue: () -> Void
    var session = MacSession.shared
    var probe = LocalNetworkProbe.shared

    var body: some View {
        SetupPage(title: title, detail: detail, primary: "Continue", primaryAction: onContinue) {
            MacBookArt(width: 280) {
                ZStack {
                    LinearGradient(colors: [palette.raisedColor, palette.raisedPressedColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let pattern = PatternCache.pattern(for: mac.payload.url.absoluteString) {
                        PatternCanvas(pattern: pattern, time: 0, motion: 0, gather: 1, ink: palette.inkColor, success: palette.good)
                            .frame(width: 104, height: 104)
                    }
                }
            }
        } extra: {
            status
        }
        .onAppear { probe.start() }
        .onDisappear { probe.stop() }
        .animation(.smooth, value: session.isConnected)
        .sensoryFeedback(.success, trigger: session.isConnected) { _, now in now }
    }

    private var title: String {
        session.isConnected ? "Connected to \(mac.name)" : "Paired with \(mac.name)"
    }

    private var detail: String {
        session.isConnected ? "Your iPhone is now a trackpad for this Mac." : "Glasspad will connect whenever this Mac is nearby."
    }

    @ViewBuilder private var status: some View {
        if session.isConnected {
            EmptyView()
        } else if probe.effectiveAccess == .denied {
            StatusRow(symbol: "exclamationmark.circle.fill", tint: palette.caution, title: "Local Network Is Off",
                      detail: "Turn it on for Glasspad in Settings so it can reach your Mac.") {
                Button("Open Settings") { openAppSettings() }
                    .glassButton()
                    .controlSize(.small)
            }
            .frame(maxWidth: 360)
            .padding(.top, 6)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting")
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Paste

/// For no camera, or a code that will not read: the link from the Mac's Show Code as Text.
struct PasteLinkSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var onPaired: (PairedMac) -> Void
    @State private var text = ""
    @State private var error = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("glasspad://pair?…", text: $text, axis: .vertical)
                        .focused($typing)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                        .onChange(of: text) { error = false }
                        .onSubmit(pair)
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { text = first }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                } footer: {
                    Text(error ? "That is not a Glasspad pairing link." : "On your Mac, choose Show Code as Text, then Copy Link, and paste it here.")
                        .foregroundStyle(error ? palette.bad : palette.inkSoftColor)
                }
                .listRowBackground(palette.raisedColor)
            }
            .scrollContentBackground(.hidden)
            .background(SurfaceBackground())
            .navigationTitle("Paste the Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pair", action: pair).fontWeight(.semibold).disabled(text.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pair() {
        guard let payload = PairingParser.parse(text) else {
            error = true
            Haptics.shared.play(.error)
            return
        }
        Haptics.shared.play(.snap)
        let mac = PairingStore.shared.add(payload)
        MacSession.shared.didPair(mac)
        onPaired(mac)
    }
}

// MARK: - Pair a Mac

/// "Pair a Mac" from Settings and the trackpad: the same flow as onboarding, in a sheet.
struct PairSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            #if DEBUG
            PairFlow(start: PairingDemo.pairStep, mac: PairingDemo.mac, onCancel: { dismiss() }, onFinish: { dismiss() })
            #else
            PairFlow(onCancel: { dismiss() }, onFinish: { dismiss() })
            #endif
        }
        .background(SurfaceBackground())
    }
}

/// A status line in the setup screens: a coloured symbol, what it is, one sentence, one fix.
struct StatusRow<Fix: View>: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder var fix: Fix

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.inkColor)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
                fix.padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .padding(14)
        .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.lineColor))
        .accessibilityElement(children: .combine)
    }
}
