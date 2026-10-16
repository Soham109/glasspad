import GlasspadKit
import SwiftUI

/// Settings rows for the trackpad's feel, for a `Form`. `.motion` is pointer speed (on top of
/// the Mac's tracking speed, with a live preview pad), acceleration, scroll speed and momentum;
/// `.haptics` is the trackpad's haptic strength per kind. Everything is stored on the phone and
/// synced to the Mac (`TrackpadTuningStore`).
struct TrackpadTuningSection: View {
    enum Part { case motion, haptics }

    @Environment(\.palette) private var palette
    @Bindable var store = TrackpadTuningStore.shared
    var session = MacSession.shared
    let part: Part

    var body: some View {
        switch part {
        case .motion: motion
        case .haptics: haptics
        }
    }

    @ViewBuilder private var motion: some View {
        Section {
            multiplierRow("Pointer Speed", value: $store.tuning.pointerSpeed, range: TrackpadTuning.pointerSpeedRange)
            PointerPreview(settings: store.merged(session.trackpadSettings))
                .frame(height: 150)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            Picker("Acceleration", selection: $store.tuning.acceleration) {
                Text("Mac Curve").tag(PointerAcceleration.mac)
                Text("Linear").tag(PointerAcceleration.linear)
                Text("Off").tag(PointerAcceleration.off)
            }
        } header: {
            Text("Pointer")
        } footer: {
            Text("Match Mac moves the pointer the way your Mac's own trackpad would. Drag in the box to try it.")
        }
        .listRowBackground(palette.raisedColor)

        Section {
            multiplierRow("Scroll Speed", value: $store.tuning.scrollSpeed, range: TrackpadTuning.scrollSpeedRange)
            momentumRow
        } header: {
            Text("Scrolling")
        } footer: {
            Text("Scrolling direction and whether momentum is on follow your Mac's trackpad settings.")
        }
        .listRowBackground(palette.raisedColor)
    }

    private var haptics: some View {
        Section {
            strengthRow("Click", value: $store.tuning.clickHaptic, cue: .click)
            strengthRow("Force Click", value: $store.tuning.forceClickHaptic, cue: .forceClickDeep)
            strengthRow("Drag Lock", value: $store.tuning.dragLockHaptic, cue: .dragLock)
        } header: {
            Text("On the Trackpad")
        } footer: {
            Text("Like a Mac trackpad, only clicks, force clicks and drag lock buzz. Swipes and scrolling stay silent.")
        }
        .listRowBackground(palette.raisedColor)
    }

    // MARK: Rows

    /// A multiplier slider on a log scale, so 0.5x and 2x sit equally far from Match Mac.
    private func multiplierRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let log = Binding<Double>(
            get: { Foundation.log2(min(max(value.wrappedValue, range.lowerBound), range.upperBound)) },
            set: { v in
                let snapped = abs(v) < 0.08 ? 0 : v      // a small dead zone around Match Mac
                value.wrappedValue = pow(2, snapped)
            })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if abs(value.wrappedValue - 1) < 0.001 {
                    Text("Match Mac").foregroundStyle(palette.inkSoftColor)
                } else {
                    Button("Match Mac") { value.wrappedValue = 1 }
                        .buttonStyle(.borderless)
                    Text(String(format: "%.2fx", value.wrappedValue))
                        .monospacedDigit()
                        .foregroundStyle(palette.inkSoftColor)
                }
            }
            Slider(value: log, in: Foundation.log2(range.lowerBound)...Foundation.log2(range.upperBound))
                .accessibilityValue(String(format: "%.2f times", value.wrappedValue))
        }
        .padding(.vertical, 4)
    }

    private var momentumRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Momentum")
                Spacer()
                let m = store.tuning.momentumStrength
                Text(m < 0.01 ? "Off" : abs(m - 1) < 0.001 ? "Match Mac" : String(format: "%.2fx", m))
                    .monospacedDigit()
                    .foregroundStyle(palette.inkSoftColor)
            }
            Slider(value: Binding(get: { store.tuning.momentumStrength },
                                  set: { store.tuning.momentumStrength = abs($0 - 1) < 0.05 ? 1 : $0 }),
                   in: TrackpadTuning.momentumRange)
        }
        .padding(.vertical, 4)
    }

    private func strengthRow(_ title: String, value: Binding<Double>, cue: HapticCue) -> some View {
        HStack(spacing: 12) {
            // A fixed label column so the three sliders line up.
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 104, alignment: .leading)
            Slider(value: value, in: 0...1) { editing in
                if !editing { Haptics.shared.play(cue) }
            }
            .accessibilityLabel("\(title) strength")
            Text(value.wrappedValue < 0.01 ? "Off" : value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(palette.inkSoftColor)
        }
    }
}

/// A small box standing in for the Mac's screen: drag a finger in it and the dot moves the way
/// the Mac's pointer would, with the same gain the recognizer uses (`GestureRecognizer.pointerGain`).
private struct PointerPreview: View {
    @Environment(\.palette) private var palette
    let settings: TrackpadSettings
    /// Width of the Mac screen the box stands for, in Mac points (a 14-inch MacBook Pro).
    private let macWidth: Double = 1512
    @State private var dot = CGPoint(x: 0.5, y: 0.5)     // 0...1 of the box
    @State private var last: (p: CGPoint, t: TimeInterval)?
    @State private var speed: Double = 0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(palette.backgroundColor)
                RoundedRectangle(cornerRadius: 12).strokeBorder(palette.inkSoftColor.opacity(0.3))
                Image(systemName: "cursorarrow")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.inkColor)
                    .position(x: dot.x * size.width, y: dot.y * size.height)
                Text("Drag here")
                    .font(.caption)
                    .foregroundStyle(palette.inkSoftColor)
                    .padding(8)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let now = ProcessInfo.processInfo.systemUptime
                        defer { last = (g.location, now) }
                        guard let l = last else { return }
                        let dx = g.location.x - l.p.x, dy = g.location.y - l.p.y
                        let dt = max(now - l.t, 1.0 / 120)
                        let v = (dx * dx + dy * dy).squareRoot() / dt
                        speed = 0.5 * speed + 0.5 * v
                        let gain = GestureRecognizer.pointerGain(speed: speed, settings: settings)
                        // Mac points -> fraction of the Mac screen -> fraction of the box.
                        let scale = gain / macWidth
                        let aspect = Double(size.width / max(size.height, 1))
                        dot.x = min(max(dot.x + dx * scale, 0), 1)
                        dot.y = min(max(dot.y + dy * scale * aspect, 0), 1)
                    }
                    .onEnded { _ in last = nil; speed = 0 }
            )
            .accessibilityLabel("Pointer speed preview")
        }
    }
}
