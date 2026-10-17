import SwiftUI
import GlasspadKit

/// A presenter remote: a big Next button, Previous, a timer, and a laser pad. Touch the pad
/// and a red dot appears on the Mac where your finger is; lift and it hides.
struct PresentMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.modeTopClearance) private var topClearance
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    private var accent: Color { AppMode.present.accent(palette) }

    private var timer = PresentClock.shared

    var body: some View {
        Group {
            if verticalSize == .compact { landscape } else { portrait }
        }
        .overlay {
            if !session.isConnected { ModeOfflineMessage(mode: .present).background(SurfaceBackground()) }
        }
        .onDisappear { session.laserOff() }
    }

    private var portrait: some View {
        VStack(spacing: 14) {
            timerBar
                .padding(.top, topClearance ?? 64)
            laserPad
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 10, contentMode: .fit)

            HStack(spacing: 12) {
                if settings.leftHanded {
                    nextButton
                    previousButton.frame(width: 104)
                } else {
                    previousButton.frame(width: 104)
                    nextButton
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    /// Sideways: the laser pad takes the wide side, the buttons sit under the thumb.
    private var landscape: some View {
        HStack(spacing: 16) {
            let pad = laserPad
                .aspectRatio(16 / 10, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            let controls = VStack(spacing: 12) {
                timerBar
                nextButton
                previousButton.frame(height: 72)
            }
            .frame(width: 250)
            if settings.leftHanded {
                controls
                pad
            } else {
                pad
                controls
            }
        }
        .padding(.top, 40)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var laserPad: some View {
        LaserPad(accent: accent) { point in
            session.laser(at: point)
        } onEnd: {
            session.laserOff()
        }
    }

    private var timerBar: some View {
        HStack(spacing: 12) {
            // Ticks only while the timer runs.
            TimelineView(.periodic(from: .now, by: timer.isRunning ? 1 : 3600)) { context in
                clock(at: context.date)
            }
            .contentShape(Rectangle())
            .contextMenu { talkLengthMenu }
            Spacer()
            Button {
                Haptics.shared.tap()
                timer.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .glassButton()
            .buttonBorderShape(.circle)
            .disabled(!timer.hasTime)
            .accessibilityLabel("Reset timer")

            Button {
                Haptics.shared.tap()
                timer.toggle()
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 32)
            }
            // Plain, like Reset beside it, so it reads as the timer's control and not as starting the slides.
            .glassButton()
            .buttonBorderShape(.circle)
            .accessibilityLabel(timer.isRunning ? "Pause timer" : "Start timer")
        }
    }

    /// Counts up, or down from the talk length when one is set: orange in the last minute,
    /// then red with a plus once over.
    private func clock(at date: Date) -> some View {
        let remaining = timer.remaining(at: date)
        let text = remaining.map(TalkClock.text) ?? MediaMode.clock(timer.elapsed(at: date))
        let stage = remaining.map(TalkClock.stage) ?? .normal
        let color: Color = switch stage {
        case .normal: timer.isRunning ? palette.inkColor : palette.inkSoftColor
        case .warning: palette.caution
        case .over: palette.bad
        }
        return Text(text)
            .font(.system(.largeTitle, design: .rounded).weight(.medium).monospacedDigit())
            .foregroundStyle(color)
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: remaining.map { $0 > 0 } ?? false))
            .animation(.snappy, value: text)
            .accessibilityLabel(remaining.map(TalkClock.spoken) ?? "Elapsed time \(text)")
            .accessibilityHint("Touch and hold to set the talk length")
    }

    private var talkLengthMenu: some View {
        Section("Talk Length") {
            Picker("Talk Length", selection: Bindable(timer).lengthMinutes) {
                Text("Off").tag(0)
                ForEach(TalkClock.lengths, id: \.self) { minutes in
                    Text("\(minutes) Minutes").tag(minutes)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var previousButton: some View {
        Button {
            Haptics.shared.tap()
            session.send(.presentPrevious)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 30, weight: .semibold))
                Text("Back").font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyCapStyle(cornerRadius: 26))
        .accessibilityLabel("Previous slide")
    }

    private var nextButton: some View {
        Button {
            Haptics.shared.play(.click)
            session.send(.presentNext)
            if settings.presentStartsTimer && !timer.isRunning && !timer.hasTime { timer.toggle() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 44, weight: .semibold))
                Text("Next").font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyCapStyle(prominent: true, cornerRadius: 26))
        .accessibilityLabel("Next slide")
        .accessibilityHint("Starts the timer on the first press")
    }
}

/// A 16:10 pad mapped to the Mac's main display.
private struct LaserPad: View {
    @Environment(\.palette) private var palette
    let accent: Color
    var onMove: (CGPoint) -> Void
    var onEnd: () -> Void

    @State private var point: CGPoint?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(palette.raisedColor)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(palette.lineColor)
                if let point {
                    Circle()
                        .fill(palette.monochrome ? palette.inkColor : palette.bad)
                        .frame(width: 18, height: 18)
                        .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(accent)
                        Text("Touch and hold to point")
                            .font(.subheadline)
                            .foregroundStyle(palette.inkSoftColor)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = CGPoint(x: min(max(value.location.x / geo.size.width, 0), 1),
                                        y: min(max(value.location.y / geo.size.height, 0), 1))
                        if point == nil { Haptics.shared.tap() }
                        point = p
                        onMove(p)
                    }
                    .onEnded { _ in
                        point = nil
                        onEnd()
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Laser pointer pad")
        .accessibilityHint("Touch and move to show a red dot on your Mac screen")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
