import GlasspadKit
import SwiftUI

/// Hands its content the time of each render, for values that change only when state does
/// (a tap's confirm window ends with a redraw from `MediaStore`), so nothing ticks while the
/// screen sits still. Shaped like `TimelineView` so the two swap freely.
struct RenderTime<Content: View>: View {
    private let content: (RenderTimeContext) -> Content
    init(@ViewBuilder content: @escaping (RenderTimeContext) -> Content) { self.content = content }
    var body: some View { content(RenderTimeContext(date: Date())) }
}

struct RenderTimeContext { let date: Date }

/// One line of text that scrolls sideways when it does not fit (like Music's now playing),
/// pausing at the start of each pass. It scrolls by a few times (`PowerPolicy.marqueePasses`)
/// after the text changes or appears, then rests at its start, so a screen left open does not
/// redraw forever. Centred and still when it fits or with Reduce Motion.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var alignment: HorizontalAlignment = .center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var start = Date()
    @State private var resting = false
    private var power: PowerPolicy { PowerMonitor.shared.policy }

    private let gap: CGFloat = 44
    /// Width of the fade at each edge while the text scrolls.
    private let fade: CGFloat = 12
    private let speed: CGFloat = 32
    private let pause: TimeInterval = 2.4

    var body: some View {
        // Sets the line height; the visible text is drawn in the overlay.
        Text(text).font(font).lineLimit(1).opacity(0)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    let fits = textWidth <= geo.size.width + 0.5
                    if fits || reduceMotion || resting || power.decorativeFrameInterval == nil {
                        label
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: geo.size.width, alignment: alignment == .leading ? .leading : .center)
                    } else {
                        TimelineView(.animation(minimumInterval: power.decorativeFrameInterval)) { context in
                            let x = offset(at: context.date)
                            HStack(spacing: gap) {
                                label.fixedSize()
                                label.fixedSize()
                            }
                            .offset(x: x)
                            .frame(width: geo.size.width, alignment: .leading)
                            // Both edges fade, as in Music, so no letter is ever cut in half. The
                            // leading fade grows in as the text moves, so the first letter sits
                            // sharp while it waits.
                            .mask { edgeFade(width: geo.size.width, leading: min(fade, -x)) }
                        }
                    }
                }
            }
            .background {
                label.fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .task(id: TaskKey(text: text, width: textWidth, passes: power.marqueePasses)) {
                // Scroll by a few times, then rest at the start until the text changes.
                start = Date()
                resting = false
                let cycle = pause + TimeInterval((textWidth + gap) / speed)
                try? await Task.sleep(for: .seconds(cycle * Double(power.marqueePasses) + pause / 2))
                if !Task.isCancelled { resting = true }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color)
    }

    /// Clear to opaque over `leading` points, opaque, then opaque to clear over the last `fade`.
    private func edgeFade(width: CGFloat, leading: CGFloat) -> some View {
        let w = max(width, 1)
        let lead = max(0, leading) / w, trail = fade / w
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: lead),
            .init(color: .black, location: 1 - trail),
            .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }

    private struct TaskKey: Equatable {
        let text: String
        let width: CGFloat
        let passes: Int
    }

    private func offset(at date: Date) -> CGFloat {
        let distance = textWidth + gap
        let travel = TimeInterval(distance / speed)
        let t = date.timeIntervalSince(start).truncatingRemainder(dividingBy: pause + travel)
        return t < pause ? 0 : -CGFloat(t - pause) * speed
    }
}

/// Thin progress line you can drag to seek, with elapsed and remaining time. It thickens while
/// dragged, like the system players.
struct ScrubBar: View {
    @Environment(\.palette) private var palette
    let duration: TimeInterval
    let position: TimeInterval
    let enabled: Bool
    var onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?

    private var fraction: Double { dragFraction ?? (duration > 0 ? min(1, max(0, position / duration)) : 0) }
    private var shown: TimeInterval { fraction * duration }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let active = dragFraction != nil
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.inkColor.opacity(0.14))
                    Capsule().fill(palette.inkColor.opacity(active ? 0.95 : 0.72))
                        .frame(width: max(active ? 10 : 6, geo.size.width * fraction))
                }
                .frame(height: active ? 10 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(enabled ? drag(width: geo.size.width) : nil)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
            }
            .frame(height: 26)
            HStack {
                Text(MediaMode.clock(shown))
                Spacer()
                Text("-" + MediaMode.clock(max(0, duration - shown)))
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(palette.inkSoftColor)
        }
        .scaleEffect(x: dragFraction != nil ? 1.03 : 1, anchor: .center)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragFraction != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue("\(MediaMode.clock(shown)) of \(MediaMode.clock(duration))")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: onSeek(min(duration, position + 10))
            case .decrement: onSeek(max(0, position - 10))
            @unknown default: break
            }
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragFraction == nil { Haptics.shared.play(.click) }
                dragFraction = min(1, max(0, Double(value.location.x / max(1, width))))
            }
            .onEnded { _ in
                if let f = dragFraction { onSeek(f * duration) }
                Haptics.shared.tap()
                dragFraction = nil
            }
    }
}

/// System-looking slider flanked by two symbols.
struct LevelSlider: View {
    @Environment(\.palette) private var palette
    @Binding var value: Double
    let low: String
    let high: String
    let label: String
    let enabled: Bool
    var onEditing: (Bool) -> Void
    var onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: low).font(.footnote).frame(width: 20)
            Slider(value: $value, in: 0...1, onEditingChanged: onEditing)
                .tint(palette.inkColor.opacity(0.75))
                .onChange(of: value) { _, new in onChange(new) }
                .accessibilityLabel(label)
            Image(systemName: high).font(.footnote).frame(width: 20)
        }
        .foregroundStyle(palette.inkSoftColor)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityHint(enabled ? "" : "Your Mac does not report this")
    }
}

/// Lists the Mac's sound outputs; picking one switches the Mac's output (like AirPlay's menu).
struct OutputPicker: View {
    @Environment(\.palette) private var palette
    let outputs: [MediaOutput]
    let accent: Color
    var onSelect: (String) -> Void

    private var current: MediaOutput? { outputs.first(where: \.isCurrent) }

    var body: some View {
        Menu {
            Picker("Sound Output", selection: Binding(get: { current?.id ?? "" }, set: { id in
                Haptics.shared.tap()
                onSelect(id)
            })) {
                ForEach(outputs) { output in
                    Label(output.name, systemImage: Self.symbol(for: output)).tag(output.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(current.map { $0.kind == "builtIn" } ?? true ? palette.inkSoftColor : accent)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .disabled(outputs.isEmpty)
        // A greyed icon that does nothing reads as broken; keep its space, show nothing.
        .opacity(outputs.isEmpty ? 0 : 1)
        .accessibilityHidden(outputs.isEmpty)
        .accessibilityLabel("Sound output")
        .accessibilityValue(current?.name ?? "Unknown")
    }

    static func symbol(for output: MediaOutput) -> String {
        let name = output.name.lowercased()
        switch output.kind {
        case "builtIn": return "laptopcomputer"
        case "headphones": return "headphones"
        case "bluetooth":
            if name.contains("airpods max") { return "airpodsmax" }
            if name.contains("airpods pro") { return "airpodspro" }
            if name.contains("airpods") { return "airpods" }
            if name.contains("beats") { return "beats.headphones" }
            return name.contains("speaker") ? "hifispeaker.fill" : "headphones"
        case "airPlay": return name.contains("tv") ? "appletv" : "airplayaudio"
        case "hdmi", "displayPort", "thunderbolt": return "display"
        case "usb": return "hifispeaker"
        case "virtual": return "waveform"
        case "aggregate": return "square.stack.3d.up"
        default: return "speaker.wave.2"
        }
    }
}

/// A small round toggle (shuffle, repeat): accent when on.
struct MediaToggle: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let label: String
    let on: Bool
    let accent: Color
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(on ? accent : palette.inkSoftColor)
                .frame(width: 48, height: 48)
                .background(Circle().fill(on ? accent.opacity(0.14) : .clear).frame(width: 40, height: 40))
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(TileStyle())
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
    }
}

/// Sends slider values at most every 50 ms, plus the final value, so dragging does not
/// flood the connection.
@MainActor
final class SliderThrottle {
    private var lastSent: [String: Date] = [:]
    private var pending: [String: Task<Void, Never>] = [:]

    func send(_ key: String, _ value: Double, _ action: @escaping @MainActor (Double) -> Void) {
        pending[key]?.cancel()
        let now = Date()
        if now.timeIntervalSince(lastSent[key] ?? .distantPast) >= 0.05 {
            lastSent[key] = now
            action(value)
        } else {
            pending[key] = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                self.lastSent[key] = Date()
                action(value)
            }
        }
    }
}
