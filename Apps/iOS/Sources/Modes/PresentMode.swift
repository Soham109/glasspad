import SwiftUI
import GlasspadKit

/// A presenter remote: a big Next button, Previous, a timer, and a laser pad. Touch the pad
/// and a red dot appears on the Mac where your finger is; lift and it hides.
struct PresentMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSize
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    private let accent = AppMode.present.accent(.paper)

    @State private var timer = PresentTimer()

    var body: some View {
        Group {
            if verticalSize == .compact { landscape } else { portrait }
        }
        .overlay {
            if !session.isConnected { ModeOfflineMessage(mode: .present).background(palette.backgroundColor) }
        }
        .onDisappear { session.laserOff() }
    }

    private var portrait: some View {
        VStack(spacing: 14) {
            timerBar
                .padding(.top, 64)
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
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(MediaMode.clock(timer.elapsed(at: context.date)))
                    .font(.system(.largeTitle, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(timer.isRunning ? palette.inkColor : palette.inkSoftColor)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
                    .animation(.snappy, value: Int(timer.elapsed(at: context.date)))
                    .accessibilityLabel("Elapsed time \(MediaMode.clock(timer.elapsed(at: context.date)))")
            }
            Spacer()
            Button {
                Haptics.shared.tap()
                timer.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
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
                    .frame(width: 28, height: 28)
            }
            .glassButton(prominent: true, accent: accent)
            .buttonBorderShape(.circle)
            .accessibilityLabel(timer.isRunning ? "Pause timer" : "Start timer")
        }
    }

    private var previousButton: some View {
        Button {
            Haptics.shared.tap()
            session.send(.presentPrevious)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 30, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .glassButton()
        .buttonBorderShape(.roundedRectangle(radius: 30))
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
        .glassButton(prominent: true, accent: accent)
        .buttonBorderShape(.roundedRectangle(radius: 30))
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
                        .fill(Color.red)
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

/// Elapsed time that survives pausing.
struct PresentTimer {
    private(set) var isRunning = false
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0

    var hasTime: Bool { isRunning || accumulated > 0 }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    mutating func toggle() {
        if isRunning {
            accumulated = elapsed(at: .now)
            startedAt = nil
        } else {
            startedAt = .now
        }
        isRunning.toggle()
    }

    mutating func reset() {
        accumulated = 0
        startedAt = isRunning ? .now : nil
    }
}
