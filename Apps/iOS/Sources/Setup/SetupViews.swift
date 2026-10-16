import GlasspadKit
import SwiftUI

// MARK: - Mac permission banner

/// Calm, persistent notice while the Mac reports Accessibility off. It never takes touches
/// (the trackpad keeps them) and goes away by itself when the Mac's answer changes.
struct MacPermissionBanner: View {
    @Environment(\.palette) private var palette
    /// The mode menu's smaller version.
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(compact ? .body : .title3)
                .foregroundStyle(palette.caution)
                .frame(width: compact ? 22 : 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your Mac needs one permission")
                    .font((compact ? Font.footnote : .subheadline).weight(.semibold))
                    .foregroundStyle(palette.inkColor)
                Text(MacPermissionBanner.steps)
                    .font(compact ? .caption : .footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(compact ? 12 : 16)
        .background(RoundedRectangle(cornerRadius: compact ? 16 : 20, style: .continuous).fill(palette.raisedColor))
        .overlay(RoundedRectangle(cornerRadius: compact ? 16 : 20, style: .continuous).strokeBorder(palette.lineColor, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    static let steps = "On your Mac, open System Settings > Privacy & Security > Accessibility and turn on Glasspad. Until then the pointer cannot move."
}

/// Over the trackpad: the permission banner, and the setup test's coach card. Placed at the
/// edge away from the mode pill.
struct TrackpadNotices: View {
    var session = MacSession.shared
    var guide = SetupGuide.shared
    var settings = PhoneSettings.shared

    var body: some View {
        let bottom = settings.pillPosition == .top
        VStack(spacing: 10) {
            if !bottom { Spacer().frame(height: 64) }
            if !bottom { cards }
            Spacer(minLength: 0)
            if bottom { cards }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: 460)
        // Floats over the trackpad like the pill: grows with text size, but never covers the pad.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .animation(.easeInOut(duration: 0.3), value: session.macNeedsAccessibility)
        .animation(.easeInOut(duration: 0.3), value: guide.testActive)
        .animation(.easeInOut(duration: 0.3), value: guide.testPassed)
    }

    @ViewBuilder private var cards: some View {
        if session.macNeedsAccessibility {
            MacPermissionBanner()
                .allowsHitTesting(false)
                .transition(.opacity)
        } else if guide.testActive && session.isConnected {
            SetupTestCoach()
                .transition(.opacity)
        }
    }
}

/// "Move one finger": fills as touches go out, then says they arrived.
struct SetupTestCoach: View {
    @Environment(\.palette) private var palette
    var guide = SetupGuide.shared

    var body: some View {
        let progress = min(1, guide.testTravel / SetupGuide.travelNeeded)
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(palette.lineColor, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: guide.testPassed ? 1 : progress)
                    .stroke(guide.testPassed ? palette.good : palette.inkColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if guide.testPassed {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(palette.good)
                }
            }
            .frame(width: 30, height: 30)
            .animation(.easeOut(duration: 0.15), value: progress)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(guide.testPassed ? "Your Mac is getting your touches" : "Move one finger on the trackpad")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.inkColor)
                Text(guide.testPassed ? "The pointer on your Mac moved with you." : "Your Mac's pointer should follow it.")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            if !guide.testPassed {
                Button {
                    guide.cancelTest()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.inkSoftColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Stop the test")
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.raisedColor))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.lineColor, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(guide.testPassed ? "Your Mac is getting your touches" : "Setup test. Move one finger on the trackpad.")
        .accessibilityValue(guide.testPassed ? "" : "\(Int(progress * 100)) percent")
    }
}

// MARK: - Checklist

/// One line of the checklist.
enum StepStatus: Equatable {
    /// Not reached yet (an earlier step is not done).
    case pending
    /// Next up, and possible now.
    case ready
    case checking
    case done
    /// Something to do, shown in the caution colour.
    case needsAction
    /// Cannot tell; guidance shown.
    case unknown
}

struct SetupStepRow<Accessory: View>: View {
    @Environment(\.palette) private var palette
    let number: Int
    let title: String
    let detail: String
    let status: StepStatus
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(status == .pending ? palette.inkSoftColor : palette.inkColor)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title), \(statusWord). \(detail)")
    }

    private var statusWord: String {
        switch status {
        case .pending: "not started"
        case .ready: "ready"
        case .checking: "checking"
        case .done: "done"
        case .needsAction: "needs attention"
        case .unknown: "not sure"
        }
    }

    @ViewBuilder private var icon: some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(palette.good)
        case .checking:
            ProgressView().controlSize(.regular)
        case .needsAction:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(palette.caution)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .font(.title2)
                .foregroundStyle(palette.inkSoftColor)
        case .pending, .ready:
            Text("\(number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status == .ready ? palette.inkColor : palette.inkSoftColor)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(status == .ready ? palette.inkColor : palette.lineColor, lineWidth: 1.5))
        }
    }
}

/// First run after pairing: Local Network, the Mac found and connected, Accessibility on the
/// Mac, then a real test on the trackpad. Never opens by itself once finished; Settings has it.
struct SetupChecklistView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var session = MacSession.shared
    var guide = SetupGuide.shared
    var probe = LocalNetworkProbe.shared
    var settings = PhoneSettings.shared
    /// Pushed inside Settings rather than presented on its own.
    var inSettings = false

    /// How long to look before saying what to check.
    static let searchGrace: TimeInterval = 5

    var body: some View {
        Group {
            if inSettings {
                content
            } else {
                NavigationStack {
                    content
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                if !allDone { Button("Not Now") { dismiss() } }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                if allDone {
                                    if #available(iOS 26.0, *) {
                                        Button("Done", systemImage: "checkmark", role: .confirm) { finish() }
                                    } else {
                                        Button("Done") { finish() }.fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            probe.start()
            PhoneNetwork.shared.start()
            session.setDiagnosticsVisible(true)
        }
        .onDisappear {
            probe.stop()
            PhoneNetwork.shared.stop()
            session.setDiagnosticsVisible(false)
        }
        .onChange(of: allDone) { _, done in
            if done {
                settings.setupComplete = true
                Haptics.shared.play(.snap)
            }
        }
    }

    private var content: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    VStack(alignment: .leading, spacing: 18) {
                        localNetworkStep(now)
                        Divider()
                        connectedStep(now)
                        Divider()
                        accessibilityStep(now)
                        Divider()
                        testStep
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.raisedColor))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.lineColor, lineWidth: 1))
                    footerButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .background(SurfaceBackground())
        .navigationTitle("Set Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(allDone ? "You're all set" : "Four quick checks")
                .font(.title2.bold())
                .foregroundStyle(palette.inkColor)
            Text(allDone ? "Glasspad can move and click on \(macName)." : "So the first touch on the trackpad works on \(macName).")
                .font(.subheadline)
                .foregroundStyle(palette.inkSoftColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Steps

    private var macName: String { session.macName ?? "your Mac" }

    @ViewBuilder private func localNetworkStep(_ now: Date) -> some View {
        let access = probe.effectiveAccess
        let late = probe.nothingFound(after: Self.searchGrace, now: now)
        switch access {
        case .allowed:
            SetupStepRow(number: 1, title: "Local Network Allowed", detail: "This iPhone can see devices on your Wi-Fi.", status: .done) { EmptyView() }
        case .denied:
            SetupStepRow(number: 1, title: "Allow Local Network",
                         detail: "iOS is blocking Glasspad from your Wi-Fi. In Settings, open Glasspad and turn on Local Network.",
                         status: .needsAction) { settingsButton }
        case .unknown where late:
            SetupStepRow(number: 1, title: "Local Network",
                         detail: "No Mac found yet. If you tapped Don't Allow earlier, turn on Local Network for Glasspad in Settings.",
                         status: .unknown) { settingsButton }
        case .unknown:
            SetupStepRow(number: 1, title: "Local Network", detail: "Checking that this iPhone can see your Wi-Fi.", status: .checking) { EmptyView() }
        }
    }

    @ViewBuilder private func connectedStep(_ now: Date) -> some View {
        let late = probe.stillNotConnected(after: Self.searchGrace, now: now)
        if session.isConnected {
            SetupStepRow(number: 2, title: "Connected to \(macName)", detail: "Found on this Wi-Fi and paired.", status: .done) { EmptyView() }
        } else if session.isReplaced {
            SetupStepRow(number: 2, title: "Another iPhone has \(macName)", detail: "A Mac follows one iPhone at a time.", status: .needsAction) {
                LinkActions()
            }
        } else if case .failed(let reason) = session.state {
            SetupStepRow(number: 2, title: "Could Not Connect", detail: ConnectionWords.failure(reason), status: .needsAction) { helpLink }
        } else if session.linkIssue == .networkBlocksDevices {
            SetupStepRow(number: 2, title: "This Wi-Fi Blocks Glasspad", detail: ConnectionWords.blockedNetwork, status: .needsAction) { helpLink }
        } else if late || probe.effectiveAccess == .denied {
            SetupStepRow(number: 2, title: "Looking for \(macName)",
                         detail: probe.seesSelectedMac ? "\(macName) is on this Wi-Fi but did not answer yet." : "Keep both on the same Wi-Fi, with Glasspad open in the Mac's menu bar.",
                         status: .needsAction) { helpLink }
        } else {
            SetupStepRow(number: 2, title: "Find \(macName)", detail: "Looking on this Wi-Fi.", status: .checking) { EmptyView() }
        }
    }

    @ViewBuilder private func accessibilityStep(_ now: Date) -> some View {
        let title = "Accessibility on the Mac"
        if !session.isConnected {
            SetupStepRow(number: 3, title: title, detail: "Lets Glasspad move the pointer and click.", status: .pending) { EmptyView() }
        } else if let status = session.macStatus {
            if status.accessibilityTrusted {
                SetupStepRow(number: 3, title: "Accessibility On", detail: "\(macName) lets Glasspad move the pointer and click.", status: .done) { EmptyView() }
            } else {
                SetupStepRow(number: 3, title: "Turn on Accessibility", detail: MacPermissionBanner.steps, status: .needsAction) { EmptyView() }
            }
        } else if let since = session.connectedAt, now.timeIntervalSince(since) < 3 {
            SetupStepRow(number: 3, title: title, detail: "Asking \(macName).", status: .checking) { EmptyView() }
        } else {
            SetupStepRow(number: 3, title: title,
                         detail: "If the pointer does not move in the next step, turn on Glasspad in Privacy & Security > Accessibility on the Mac.",
                         status: .unknown) { EmptyView() }
        }
    }

    @ViewBuilder private var testStep: some View {
        if guide.testPassed {
            SetupStepRow(number: 4, title: "Trackpad Works", detail: "Your touches reached \(macName).", status: .done) { EmptyView() }
        } else if session.isConnected && guide.accessibilityOK {
            SetupStepRow(number: 4, title: "Try the Trackpad", detail: "Move one finger on the trackpad. The pointer on your Mac should follow.", status: .ready) { EmptyView() }
        } else {
            SetupStepRow(number: 4, title: "Try the Trackpad", detail: "After the steps above.", status: .pending) { EmptyView() }
        }
    }

    // MARK: Buttons

    private var allDone: Bool { settings.setupComplete || (guide.testPassed && guide.accessibilityOK) }

    @ViewBuilder private var footerButton: some View {
        if allDone {
            if inSettings {
                EmptyView()
            } else {
                Button { finish() } label: {
                    Text("Start Using Glasspad").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .glassButton(prominent: true)
                .controlSize(.large)
            }
        } else if session.isConnected && guide.accessibilityOK {
            Button { guide.startTest() } label: {
                Text("Try It").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .glassButton(prominent: true)
            .controlSize(.large)
            .accessibilityHint("Opens the trackpad. Move one finger on it.")
        }
    }

    private var settingsButton: some View {
        Button("Open Settings") { openAppSettings() }
            .glassButton()
            .controlSize(.small)
    }

    private var helpLink: some View {
        NavigationLink {
            ConnectionHelpView()
        } label: {
            Text("Connection Help")
                .font(.subheadline.weight(.medium))
        }
        .glassButton()
        .controlSize(.small)
    }

    private func finish() {
        settings.setupComplete = true
        guide.cancelTest()
        if inSettings { return }
        dismiss()
        AppRouter.shared.show(.trackpad)
    }
}
