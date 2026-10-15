import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import GlasspadKit
import GlasspadMacCore
import ServiceManagement
import SwiftUI

// MARK: - Menu bar label

struct MenuBarLabel: View {
    let state: LinkState
    @ObservedObject var macros: MacroCoordinator

    var body: some View {
        // While recording a macro the menu bar says so too.
        if macros.isRecording {
            Image(systemName: "record.circle.fill")
                .accessibilityLabel("Glasspad, recording a macro")
        // The template icon from Resources when bundled; an SF Symbol under `swift run`.
        } else if let image = Self.icon {
            Image(nsImage: image)
                .accessibilityLabel("Glasspad, \(state.title)")
        } else {
            Image(systemName: state.isConnected ? "hand.point.up.left.fill" : "hand.point.up.left")
                .accessibilityLabel("Glasspad, \(state.title)")
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

// MARK: - Link state text

extension LinkState {
    var isConnected: Bool { if case .connected = self { true } else { false } }

    var title: String {
        switch self {
        case .idle: "Off"
        case .searching: "Waiting for iPhone"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .failed: "Not available"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "pause.circle"
        case .searching: "antenna.radiowaves.left.and.right"
        case .connecting: "ellipsis.circle"
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .failed: .orange
        default: .secondary
        }
    }
}

extension SynthMode {
    var label: String {
        switch self {
        case .native: "Native"
        case .fallback: "Shortcut"
        case .unavailable: "Unavailable"
        }
    }

    var help: String {
        switch self {
        case .native: "Sent as a real trackpad gesture, follows your fingers."
        case .fallback: "Sent as the equivalent keyboard shortcut."
        case .unavailable: "Not supported on this Mac."
        }
    }
}

func formatRTT(_ ms: Double?) -> String? {
    guard let ms else { return nil }
    return ms < 10 ? String(format: "%.1f ms", ms) : String(format: "%.0f ms", ms)
}

// MARK: - QR code

enum QRCode {
    /// Black on white at an integer scale, so it stays crisp and scannable in dark mode too.
    static func image(for string: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, floor(size / output.extent.width))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - Launch at login

@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval

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

// MARK: - Glass where available

extension View {
    /// Liquid Glass on macOS 26, the regular material before that.
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
