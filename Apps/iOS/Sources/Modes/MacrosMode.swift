import SwiftUI
import GlasspadKit

/// Macros recorded or built on the Mac. The buttons follow the Mac's front app (per-app
/// profiles); "All" shows every macro. Run, watch progress, stop, or record a new one.
struct MacrosMode: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    private var accent: Color { AppMode.macros.accent(palette) }

    @State private var showAll = false

    @Environment(\.verticalSizeClass) private var verticalSize

    /// Three across in portrait; sideways, as many as fit so a profile usually sits in one row.
    private var columns: [GridItem] {
        verticalSize == .compact
            ? [GridItem(.adaptive(minimum: 150), spacing: 12)]
            : Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    }

    private var macros: [MacroSummary]? {
        showAll ? session.allMacros : session.macroProfile?.macros
    }

    var body: some View {
        ZStack {
            if !session.isConnected && session.macroProfile == nil {
                ModeOfflineMessage(mode: .macros)
            } else if session.macroProfile == nil {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onAppear { session.send(.macro(.listMacros)) }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if let macros, !macros.isEmpty {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(macros) { macro in
                            MacroTile(macro: macro, fallback: accent,
                                      pending: session.macroPendingID == macro.id,
                                      progress: session.macroRunning?.macroID == macro.id ? session.macroRunning : nil) {
                                Haptics.shared.play(.click)
                                session.runMacro(macro.id)
                            }
                        }
                    }
                } else {
                    QuietMessage(symbol: "wand.and.stars",
                                 title: showAll ? "No macros yet" : "Nothing for this app",
                                 detail: showAll ? "Tap Record and do something on your Mac, or build one in the Glasspad menu on the Mac."
                                                 : "Switch to All, or add macros to this app's profile on your Mac.")
                        .frame(minHeight: 260)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 24)
        }
        .refreshable { session.send(.macro(.listMacros)) }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Picker("Show", selection: $showAll) {
                Text(session.macroProfile.map { "For \($0.name)" } ?? "This app").tag(false)
                Text("All").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private var bottomBar: some View { MacroStatusBar(showsRecord: session.macroProfile != nil) }
}

/// Recording, running, last result, or the Record button. Used by Macros and Actions.
struct MacroStatusBar: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    var showsRecord = true
    private var accent: Color { AppMode.macros.accent(palette) }

    var body: some View { bottomBar }

    // MARK: Bottom bar: running, recording, result, or the Record button

    @ViewBuilder private var bottomBar: some View {
        Group {
            if session.isRecordingMacro {
                recordingBar
            } else if let running = session.macroRunning {
                runningBar(running)
            } else if let result = session.macroResult {
                resultBar(result)
            } else if session.isConnected && showsRecord {
                Button {
                    Haptics.shared.tap()
                    session.send(.macro(.recordStart(windowRelative: false, keepTiming: true)))
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .glassButton()
                .controlSize(.large)
                .tint(palette.bad)
                .accessibilityHint("Records your keyboard and mouse on the Mac until you stop")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .animation(.snappy, value: session.isRecordingMacro)
        .animation(.snappy, value: session.macroRunning)
        .animation(.snappy, value: session.macroResult)
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(palette.bad)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording on your Mac").font(.subheadline.weight(.semibold))
                Text("Do the steps on the Mac, then stop.").font(.caption).foregroundStyle(palette.inkSoftColor)
            }
            Spacer()
            Button("Stop") {
                Haptics.shared.play(.click)
                session.send(.macro(.recordStop))
            }
            .glassButton(prominent: true, accent: palette.bad)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func runningBar(_ progress: MacroProgress) -> some View {
        let name = (session.allMacros ?? session.macroProfile?.macros ?? []).first { $0.id == progress.macroID }?.name ?? "Macro"
        return HStack(spacing: 12) {
            Gauge(value: progress.fraction) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(accent)
                .scaleEffect(0.6)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(progress.currentSummary.isEmpty ? "Step \(progress.completedSteps) of \(progress.totalSteps)"
                                                     : progress.currentSummary)
                    .font(.caption).foregroundStyle(palette.inkSoftColor).lineLimit(1)
            }
            Spacer()
            Button("Stop") {
                Haptics.shared.play(.click)
                session.send(.macro(.cancelRun))
            }
            .glassButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }

    private func resultBar(_ result: MacroResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.symbol)
                .foregroundStyle(result.outcome == .completed ? palette.good : (result.outcome == .failed ? palette.bad : palette.inkSoftColor))
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.headline).font(.subheadline.weight(.semibold))
                if let detail = result.detail {
                    Text(detail).font(.caption).foregroundStyle(palette.inkSoftColor).lineLimit(3).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

struct MacroTile: View {
    @Environment(\.palette) private var palette
    let macro: MacroSummary
    let fallback: Color
    let pending: Bool
    let progress: MacroProgress?
    let action: () -> Void

    private var tint: Color {
        macro.rgb.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? fallback
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    if let progress {
                        Gauge(value: progress.fraction) { EmptyView() }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(tint)
                            .scaleEffect(0.55)
                    } else if pending {
                        ProgressView()
                    } else {
                        Image(systemName: UIImage(systemName: macro.symbol) == nil ? "wand.and.stars" : macro.symbol)
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(tint)
                    }
                }
                .frame(height: 30)
                Text(macro.name)
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
            if macro.usesScripts {
                Image(systemName: "terminal")
                    .font(.caption2)
                    .foregroundStyle(palette.inkSoftColor)
                    .padding(10)
                    .accessibilityLabel("Runs a script")
            }
        }
        .accessibilityLabel(macro.name)
        .accessibilityValue("\(macro.stepCount) steps")
        .accessibilityHint("Runs this macro on your Mac")
    }
}

/// The last macro outcome, shown briefly at the bottom.
struct MacroResult: Equatable {
    let id = UUID()
    let macroID: UUID?
    let title: String
    let outcome: RunOutcome
    let message: String?
    let output: String?

    var symbol: String {
        switch outcome {
        case .completed: "checkmark.circle.fill"
        case .cancelled, .interruptedByUser: "stop.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var headline: String {
        switch outcome {
        case .completed: title
        case .cancelled: "\(title) stopped"
        case .interruptedByUser: "\(title) stopped because you used the Mac"
        case .failed: "\(title) did not finish"
        }
    }

    var detail: String? { message ?? output }
}
