import AppKit
import Combine
import GlasspadMacCore
import SwiftUI

/// A small floating indicator at the top of the screen while a macro is being recorded, so the
/// user always knows their keyboard and mouse are being captured, whichever app is in front.
/// It never takes focus; its Stop click is trimmed from the recording.
@MainActor
final class RecordingIndicator {
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?

    func observe(_ macros: MacroCoordinator) {
        cancellable = macros.$isRecording
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self, weak macros] recording in
                guard let self, let macros else { return }
                if recording { self.show(macros) } else { self.hide() }
            }
    }

    private func show(_ macros: MacroCoordinator) {
        if panel == nil {
            let host = NSHostingView(rootView: RecordingIndicatorView(macros: macros))
            host.setFrameSize(host.fittingSize)
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.contentView = host
            p.isFloatingPanel = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.setAccessibilityLabel("Recording a macro")
            panel = p
        }
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 10))
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }
}

/// The pill itself: a pulsing dot, what is happening, how to stop.
struct RecordingIndicatorView: View {
    @ObservedObject var macros: MacroCoordinator

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recording Macro")
                    .font(.headline)
                StopShortcutHint(after: "or click Stop")
            }
            Button("Stop") { macros.stopRecording(fromMacMenu: true) }
                .controlSize(.regular)
                .accessibilityLabel("Stop recording")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .glassBackground(cornerRadius: 18)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording a macro")
    }
}
