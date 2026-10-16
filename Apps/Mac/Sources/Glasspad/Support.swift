import AppKit
import GlasspadKit
import GlasspadMacCore
import ServiceManagement
import SwiftUI

// MARK: - Menu bar label

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var macros: MacroCoordinator

    init(model: AppModel) {
        self.model = model
        self.macros = model.macros
    }

    var body: some View {
        // While recording a macro the menu bar says so too.
        if macros.isRecording {
            Image(systemName: "record.circle.fill")
                .accessibilityLabel("Glasspad, recording a macro")
        // The template icon from Resources when bundled; an SF Symbol under `swift run`.
        } else if let image = Self.icon {
            Image(nsImage: image)
                .opacity(model.isPaused ? 0.45 : 1)
                .accessibilityLabel("Glasspad, \(model.statusTitle)")
        } else {
            Image(systemName: model.isConnected ? "hand.point.up.left.fill" : "hand.point.up.left")
                .opacity(model.isPaused ? 0.45 : 1)
                .accessibilityLabel("Glasspad, \(model.statusTitle)")
        }
    }

    static let icon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        if let url2x = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
           let rep = NSImageRep(contentsOf: url2x) {
            rep.size = image.size
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }()
}

// MARK: - Status text

extension LinkState {
    var isConnected: Bool { if case .connected = self { true } else { false } }
}

extension AppModel {
    /// One or two words for the state, used as the headline when no phone is connected and
    /// in VoiceOver labels.
    var statusTitle: String {
        if isPaused { return "Paused" }
        switch link {
        case .idle: return "Starting"
        case .searching: return phones.isEmpty ? "No iPhone Paired" : "Waiting for iPhone"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .failed: return "Not Available"
        }
    }

    /// The line under the headline: what is going on and what to do next.
    var statusDetail: String {
        if isPaused { return "Your iPhone cannot connect until you resume." }
        if case .failed(let reason) = link { return reason }
        if let error = lastError { return error }
        switch link {
        case .idle: return "Getting ready to listen for your iPhone."
        case .searching:
            switch pairing {
            case .waiting: return "Scan the code below with your iPhone."
            case .expired: return "The pairing code expired."
            default: break
            }
            return phones.isEmpty
                ? "Pair your iPhone to use it as a trackpad."
                : "Open Glasspad on your iPhone to connect."
        case .connecting: return "Securing the connection."
        case .connected:
            guard let s = signal else { return "Connected" }
            if let advice = s.advice { return "\(s.title) signal. \(advice)" }
            return "\(s.title) signal"
        case .failed: return ""
        }
    }

    var statusTint: Color {
        if isPaused { return .secondary }
        switch link {
        case .connected: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }
}

extension SynthMode {
    /// Advanced > Diagnostics: how each gesture reaches the Mac.
    var label: String {
        switch self {
        case .native: "Trackpad gesture"
        case .fallback: "Keyboard shortcut"
        case .unavailable: "Not available"
        }
    }

    var help: String {
        switch self {
        case .native: "Sent as a real trackpad gesture, so it follows your fingers."
        case .fallback: "Sent as the matching keyboard shortcut, so it plays all at once."
        case .unavailable: "This Mac does not support it."
        }
    }
}

func formatMilliseconds(_ ms: Double?) -> String {
    guard let ms else { return "Not measured yet" }
    return ms < 10 ? String(format: "%.1f ms", ms) : String(format: "%.0f ms", ms)
}

// MARK: - Launch at login

@MainActor
final class LaunchAtLogin {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Fails when not running from an app bundle (swift run); the toggle snaps back.
        }
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }
}

// MARK: - System Settings links

enum SystemSettings {
    static func openAccessibility() {
        NSWorkspace.shared.open(GlasspadController.accessibilitySettingsURL)
    }

    static func openTrackpad() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
    }

    static func openLoginItems() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }
}

// MARK: - App info

@MainActor
enum AppInfoText {
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    static var icon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp?.applicationIconImage ?? NSWorkspace.shared.icon(for: .application)
    }
}

// MARK: - Shared pieces

extension EnvironmentValues {
    /// Set by the snapshot harness: offscreen drawing cannot capture glass or blur, so it
    /// draws the solid surface glass sits on instead.
    @Entry var solidSurfaces = false
}

extension View {
    /// Liquid Glass on macOS 26, the regular material before that.
    func glassBackground(cornerRadius: CGFloat) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

private struct GlassBackground: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.solidSurfaces) private var solid

    func body(content: Content) -> some View {
        if solid {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.separator, lineWidth: 1)
                }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

/// Four rising bars, filled to the signal's level, as the menu bar draws Wi-Fi strength.
struct SignalBars: View {
    let quality: SignalQuality

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < filled ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 3.5, height: 5 + CGFloat(i) * 3.5)
            }
        }
        .frame(height: 16, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Signal \(quality.title)")
    }

    private var filled: Int {
        switch quality {
        case .excellent: 4
        case .good: 3
        case .fair: 2
        case .weak: 1
        case .measuring: 0
        }
    }

    private var tint: Color {
        switch quality {
        case .fair: .yellow
        case .weak: .orange
        default: .primary.opacity(0.75)
        }
    }
}

/// An SF Symbol on a small filled rounded square, as System Settings draws its row icons.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A full width row in the popover that highlights under the pointer, like a menu item.
struct PopoverRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(.rect(cornerRadius: 7))
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.primary.opacity(configuration.isPressed ? 0.14 : (hovering && isEnabled ? 0.08 : 0)))
                }
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
        }
    }
}

/// "Press ⌃⌥⌘. …" with the stop-recording shortcut drawn as key caps, so its period reads as
/// a key and not as the end of a sentence.
struct StopShortcutHint: View {
    /// Text after the keys, such as "or click Stop".
    let after: String
    var font: Font = .caption

    static let keys = ["⌃", "⌥", "⌘", "."]

    var body: some View {
        HStack(spacing: 4) {
            Text("Press")
            HStack(spacing: 2) {
                ForEach(Self.keys, id: \.self) { key in
                    Text(key)
                        .fontWeight(.medium)
                        .frame(minWidth: 11)
                        .padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary))
                }
            }
            Text(after)
        }
        .font(font)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Press Control Option Command Period \(after)")
    }
}
