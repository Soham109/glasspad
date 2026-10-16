import GlasspadKit
import SwiftUI
import UIKit

/// The Clock StandBy screen: one of three faces, as large as the pane allows. A tap moves to
/// the next face; touch and hold for night mode and the screen choices.
struct ClockMode: View {
    @Bindable var settings = StandBySettings.shared
    var monitor = StandByMonitor.shared
    @State private var uses24Hour = ClockText.uses24Hour()

    var body: some View {
        // Read outside the timeline (see StandByScreen).
        let face = settings.face
        let charge = charge
        let ticks = monitor.power.ticksSeconds
        StandByScreen { minute, style in
            GeometryReader { geo in
                ZStack {
                    switch face {
                    case .digital:
                        DigitalFace(date: minute, uses24Hour: uses24Hour, style: style, size: geo.size, charge: charge)
                    case .analog:
                        AnalogFace(minute: minute, ticks: ticks, style: style, size: geo.size, charge: charge)
                    case .minimal:
                        MinimalFace(date: minute, uses24Hour: uses24Hour, style: style, size: geo.size, charge: charge)
                    }
                }
                .id(face)
                .transition(.opacity)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(minute.formatted(date: .complete, time: .shortened))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.shared.tap()
            withAnimation(.easeInOut(duration: 0.35)) { settings.face = settings.face.next }
        }
        .contextMenu { StandByMenu(showsFaces: true) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Changes the clock face")
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            uses24Hour = ClockText.uses24Hour()
        }
    }

    /// The battery while it charges, as StandBy shows it.
    private var charge: Double? {
        monitor.charging ? (monitor.batteryLevel ?? 1) : nil
    }
}

// MARK: - Shared pieces

/// Room kept clear around a face, so it never touches the pane's rounded corners.
private func facePadding(_ size: CGSize) -> CGSize {
    CGSize(width: max(16, size.width * 0.07), height: max(16, size.height * 0.08))
}

/// The date under or over a face, with the charge level while charging.
private struct DateLine: View {
    let date: Date
    let fontSize: CGFloat
    /// Room across, to choose between "Friday, October 16" and "Fri, Oct 16".
    let width: CGFloat
    let style: StandByStyle
    let charge: Double?
    var color: Color? = nil

    var body: some View {
        let font = StandByType.swiftUI(fontSize, weight: .semibold, rounded: true)
        let long = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let short = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let roomy = width > fontSize * 17
        HStack(spacing: fontSize * 0.7) {
            Text(roomy ? long : short)
                .foregroundStyle(color ?? style.secondary)
            if let charge {
                HStack(spacing: fontSize * 0.2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: fontSize * 0.82, weight: .semibold))
                        .foregroundStyle(style.charge)
                    Text(charge.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(style.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Charging, \(charge.formatted(.percent.precision(.fractionLength(0))))")
            }
        }
        .font(font)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Digital

/// Big rounded numerals. Side by side ("9:41") or, in a tall pane, hours over minutes, which
/// ever is larger.
private struct DigitalFace: View {
    let date: Date
    let uses24Hour: Bool
    let style: StandByStyle
    let size: CGSize
    let charge: Double?

    private static let wide = StandByType.metrics("88:88", weight: .semibold, rounded: true)
    private static let pair = StandByType.metrics("88", weight: .semibold, rounded: true)
    /// Space between the rows of a stacked clock, per point of font size.
    private static let rowGap: CGFloat = 0.12

    var body: some View {
        let pad = facePadding(size)
        let room = CGSize(width: size.width - pad.width * 2, height: size.height - pad.height * 2)
        // The date takes a line of its own; give it a size that follows the pane.
        let dateSize = min(24, max(13, min(room.width, room.height) * 0.07))
        let dateBlock = dateSize * 2.1
        let across = min(room.width / Self.wide.width, (room.height - dateBlock) / Self.wide.capHeight)
        let stackedSize = min(room.width / Self.pair.width,
                              (room.height - dateBlock) / (Self.pair.capHeight * 2 + Self.rowGap))
        let stacked = stackedSize > across * 1.15
        let fontSize = max(10, stacked ? stackedSize : across)
        let parts = ClockText.parts(date, uses24Hour: uses24Hour)
        let font = StandByType.swiftUI(fontSize, weight: .semibold, rounded: true)
        // A line of text is taller than its numerals; these pull the date and the second row
        // in so the visible gaps are the ones intended.
        let lineSlack = (Self.wide.lineHeight - Self.wide.capHeight) * fontSize / 2
        VStack(spacing: dateSize * 0.9 - lineSlack) {
            DateLine(date: date, fontSize: dateSize, width: room.width, style: style, charge: charge)
            Group {
                if stacked {
                    VStack(spacing: Self.rowGap * fontSize - lineSlack * 2) {
                        Text(parts.hour)
                        Text(parts.minute)
                    }
                } else {
                    Text("\(parts.hour):\(parts.minute)")
                }
            }
            .font(font)
            .kerning(-fontSize * 0.01)
            .foregroundStyle(style.primary)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.5), value: parts.minute)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Minimal

/// Thin numerals with the date under them: the quietest face, and the dimmest at night.
private struct MinimalFace: View {
    let date: Date
    let uses24Hour: Bool
    let style: StandByStyle
    let size: CGSize
    let charge: Double?

    private static let metrics = StandByType.metrics("88:88", weight: .thin, rounded: false)

    var body: some View {
        let pad = facePadding(size)
        let room = CGSize(width: size.width - pad.width * 2, height: size.height - pad.height * 2)
        let fontSize = max(10, min(room.width * 0.78 / Self.metrics.width, room.height * 0.42 / Self.metrics.capHeight))
        let dateSize = min(22, max(13, fontSize * 0.15))
        let parts = ClockText.parts(date, uses24Hour: uses24Hour)
        let lineSlack = (Self.metrics.lineHeight - Self.metrics.capHeight) * fontSize / 2
        VStack(spacing: dateSize * 1.1 - lineSlack) {
            Text("\(parts.hour):\(parts.minute)")
                .font(StandByType.swiftUI(fontSize, weight: .thin, rounded: false))
                .foregroundStyle(style.primary)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.5), value: parts.minute)
            DateLine(date: date, fontSize: dateSize, width: room.width, style: style, charge: charge)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Analog

/// A dial with the twelve hours, minute marks, two hands and an orange second hand that ticks
/// once a second (not when saving power or warm: then it hides and the hands move each minute).
private struct AnalogFace: View {
    let minute: Date
    let ticks: Bool
    let style: StandByStyle
    let size: CGSize
    let charge: Double?

    var body: some View {
        let pad = facePadding(size)
        let room = CGSize(width: size.width - pad.width * 2, height: size.height - pad.height * 2)
        let dateSize = min(22, max(13, min(room.width, room.height) * 0.06))
        let dateBlock = dateSize * 2.4
        let side = max(40, min(room.width, room.height - dateBlock))
        VStack(spacing: dateSize * 1.0) {
            Group {
                if ticks {
                    TimelineView(.periodic(from: Self.secondStart, by: 1)) { context in
                        Dial(date: standByTime(context.date), showsSeconds: true, style: style)
                    }
                } else {
                    Dial(date: minute, showsSeconds: false, style: style)
                }
            }
            .frame(width: side, height: side)
            DateLine(date: minute, fontSize: dateSize, width: room.width, style: style, charge: charge)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Ticks land on the whole second.
    private static var secondStart: Date {
        Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down))
    }
}

private struct Dial: View {
    let date: Date
    let showsSeconds: Bool
    let style: StandByStyle

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ degrees: Double, _ length: CGFloat) -> CGPoint {
                let a = degrees * .pi / 180
                return CGPoint(x: c.x + CGFloat(sin(a)) * length, y: c.y - CGFloat(cos(a)) * length)
            }
            func line(_ degrees: Double, from: CGFloat, to: CGFloat, width: CGFloat, _ color: Color) {
                var p = Path()
                p.move(to: point(degrees, from))
                p.addLine(to: point(degrees, to))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            func dot(_ radius: CGFloat, _ color: Color) {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(color))
            }

            // Minute marks, the hours a little longer and brighter.
            for i in 0..<60 {
                let hour = i % 5 == 0
                line(Double(i) * 6, from: r * (hour ? 0.9 : 0.93), to: r * 0.985,
                     width: r * (hour ? 0.014 : 0.008), hour ? style.secondary : style.faint)
            }
            // The hours.
            let numeral = StandByType.swiftUI(r * 0.17, weight: .semibold, rounded: true)
            for h in 1...12 {
                let text = ctx.resolve(Text("\(h)").font(numeral).foregroundStyle(style.primary))
                ctx.draw(text, at: point(Double(h) * 30, r * 0.71), anchor: .center)
            }

            let angles = ClockText.handAngles(date)
            // Hour and minute hands: a thin stem from the centre, then the broad blade.
            for (angle, length) in [(angles.hour, r * 0.5), (angles.minute, r * 0.84)] {
                line(angle, from: 0, to: r * 0.13, width: r * 0.026, style.primary)
                line(angle, from: r * 0.13, to: length, width: r * 0.064, style.primary)
            }
            dot(r * 0.045, style.primary)
            if showsSeconds {
                line(angles.second + 180, from: 0, to: r * 0.14, width: r * 0.014, style.hand)
                line(angles.second, from: 0, to: r * 0.93, width: r * 0.014, style.hand)
                dot(r * 0.03, style.hand)
            }
            dot(r * 0.012, StandByStyle.backgroundColor)
        }
    }
}
