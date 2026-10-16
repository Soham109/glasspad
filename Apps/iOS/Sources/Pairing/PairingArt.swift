import GlasspadKit
import SwiftUI

// Pictures for the pairing screens: the Mac and the iPhone drawn as they really look, and the
// pairing code's dots (the same pattern the Mac shows, from GlasspadKit's `PairingPattern`).

/// The real hardware's colours. They are the devices' own finish, not the app's surface, so
/// they are the same in every theme (the screens inside them use the palette).
enum Hardware {
    /// The black glass around a display.
    static let bezel = Color(red: 0.05, green: 0.05, blue: 0.06)
    /// A display that is off, or a camera's dark view.
    static let glass = Color(red: 0.03, green: 0.03, blue: 0.04)
    /// The machined edge of the case, light (silver) or dark (space black).
    static func metal(dark: Bool) -> [Color] {
        dark ? [Color(red: 0.36, green: 0.37, blue: 0.39), Color(red: 0.2, green: 0.2, blue: 0.22)]
             : [Color(red: 0.89, green: 0.89, blue: 0.9), Color(red: 0.69, green: 0.7, blue: 0.72)]
    }
}

// MARK: - Pattern

/// The pairing code's dots at one moment, drawn in `ink`, turning `success` as they gather.
struct PatternCanvas: View {
    let pattern: PairingPattern
    let time: Double
    var motion: Double = 1
    var gather: Double = 0
    let ink: Color
    var success: Color

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let m = size.width / CGFloat(pattern.size)
            let finder = PairingPattern.finderAlpha(gather: gather)
            if finder > 0 {
                for corner in pattern.finders {
                    for path in PairingPattern.finderPaths(origin: CGPoint(x: corner.x * m, y: corner.y * m), module: m) {
                        context.fill(Path(path), with: .color(ink.opacity(finder)), style: FillStyle(eoFill: true))
                    }
                }
            }
            for dot in pattern.frame(time: time, motion: motion, gather: gather) where dot.alpha > 0.01 {
                let r = dot.radius * m
                let shape = Path(ellipseIn: CGRect(x: dot.center.x * m - r, y: dot.center.y * m - r, width: r * 2, height: r * 2))
                if dot.success < 1 { context.fill(shape, with: .color(ink.opacity(Double(dot.alpha * (1 - dot.success))))) }
                if dot.success > 0 { context.fill(shape, with: .color(success.opacity(Double(dot.alpha * dot.success)))) }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Builds a pattern once per code (it reads pixels back from Core Image).
@MainActor
enum PatternCache {
    private static var last: (String, PairingPattern?)?

    static func pattern(for message: String) -> PairingPattern? {
        if let last, last.0 == message { return last.1 }
        let p = PairingPattern(message: message)
        last = (message, p)
        return p
    }

    /// A stand-in code for pictures (the simulator's camera, illustrations). It reads as a
    /// Glasspad code with a made-up Mac, never a real key.
    static let sample = PairingPayload(macID: UUID(uuidString: "6F1C2A4E-3B5D-4C7E-9F10-2A3B4C5D6E7F")!,
                                       macName: "MacBook Pro", pairKey: Data(repeating: 0x5A, count: 32)).url.absoluteString
}

// MARK: - MacBook

/// A MacBook Pro seen from the front: the black display bezel with its notch, a thin aluminium
/// edge, and the base with its opening lip. `screen` draws what is on the display.
struct MacBookArt<Screen: View>: View {
    @Environment(\.palette) private var palette
    var width: CGFloat = 300
    @ViewBuilder var screen: Screen

    var body: some View {
        let w = width
        let lidH = w * 0.64
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: w * 0.04, bottomLeadingRadius: w * 0.008,
                                       bottomTrailingRadius: w * 0.008, topTrailingRadius: w * 0.04, style: .continuous)
                    .fill(Hardware.bezel)
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: w * 0.04, bottomLeadingRadius: w * 0.008,
                                               bottomTrailingRadius: w * 0.008, topTrailingRadius: w * 0.04, style: .continuous)
                            .strokeBorder(LinearGradient(colors: Hardware.metal(dark: palette.isDark), startPoint: .top, endPoint: .bottom),
                                          lineWidth: max(1, w * 0.006))
                    }
                screen
                    .frame(width: w * 0.94, height: lidH * 0.9)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: w * 0.022, topTrailingRadius: w * 0.022, style: .continuous))
                    .padding(.top, w * 0.026)
                // The camera housing.
                UnevenRoundedRectangle(bottomLeadingRadius: w * 0.008, bottomTrailingRadius: w * 0.008)
                    .fill(Hardware.bezel)
                    .frame(width: w * 0.1, height: w * 0.022)
                    .padding(.top, w * 0.026)
            }
            .frame(width: w, height: lidH)
            // The base: a thin slab wider than the lid, with the lip you open it by.
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: w * 0.004, bottomLeadingRadius: w * 0.03,
                                       bottomTrailingRadius: w * 0.03, topTrailingRadius: w * 0.004, style: .continuous)
                    .fill(LinearGradient(colors: Hardware.metal(dark: palette.isDark), startPoint: .top, endPoint: .bottom))
                UnevenRoundedRectangle(bottomLeadingRadius: w * 0.012, bottomTrailingRadius: w * 0.012)
                    .fill(.black.opacity(0.18))
                    .frame(width: w * 0.16, height: w * 0.01)
            }
            .frame(width: w * 1.12, height: w * 0.032)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(palette.isDark ? 0.4 : 0.12), radius: w * 0.04, y: w * 0.02)
        .accessibilityHidden(true)
    }
}

/// What a display shows behind everything: the theme's surface, softly lit. Starts from the
/// plain surface colour, so the translucent glass themes do not show the black bezel through.
struct ScreenWallpaper: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.solidColor
            LinearGradient(colors: [palette.raisedColor, palette.raisedPressedColor], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - iPhone

/// An iPhone seen from the front: the frame, the black border, the Dynamic Island, and the
/// Glasspad surface with two finger dots drifting on it.
struct IPhoneArt: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var height: CGFloat = 250
    var power = PowerMonitor.shared

    var body: some View {
        let h = height, w = height * 0.49
        // Gentle drift at a decorative frame rate; still with Reduce Motion or a warm phone.
        let interval = power.policy.decorativeFrameInterval.map { max($0, 1.0 / 30) }
        ZStack {
            RoundedRectangle(cornerRadius: w * 0.2, style: .continuous)
                .fill(LinearGradient(colors: Hardware.metal(dark: palette.isDark), startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: w * 0.185, style: .continuous)
                .fill(Hardware.bezel)
                .padding(w * 0.018)
            TimelineView(.animation(minimumInterval: interval, paused: reduceMotion || interval == nil)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    SurfaceBackground()
                    SoftDot(color: palette.dot, size: w * 0.3)
                        .offset(x: -w * 0.15 + w * 0.05 * sin(t * 0.9), y: -h * 0.04 + h * 0.1 * sin(t * 0.7))
                    SoftDot(color: palette.dot, size: w * 0.3)
                        .offset(x: w * 0.17 + w * 0.05 * sin(t * 0.9), y: h * 0.02 + h * 0.1 * sin(t * 0.7))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: w * 0.15, style: .continuous))
            .padding(w * 0.045)
            Capsule()
                .fill(Hardware.bezel)
                .frame(width: w * 0.3, height: w * 0.085)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, w * 0.085)
        }
        .frame(width: w, height: h)
        .compositingGroup()
        .shadow(color: .black.opacity(palette.isDark ? 0.4 : 0.12), radius: 14, y: 6)
        .accessibilityHidden(true)
    }
}

/// The finger dot used everywhere: solid centre, soft edge.
struct SoftDot: View {
    let color: UIColor
    var size: CGFloat = 44
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(uiColor: color), Color(uiColor: color).opacity(0.85), Color(uiColor: color).opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

// MARK: - Mac with Glasspad's menu open

/// The Mac with Glasspad's menu bar window open and Pair Your iPhone under the pointer: where
/// the person should look on their Mac.
struct MacMenuArt: View {
    @Environment(\.palette) private var palette
    var width: CGFloat = 300

    var body: some View {
        MacBookArt(width: width) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topTrailing) {
                    ScreenWallpaper()
                    // Menu bar, with Glasspad's icon highlighted.
                    HStack(spacing: w * 0.035) {
                        Image(systemName: "apple.logo")
                        Spacer()
                        Image(systemName: "hand.point.up.left.fill")
                            .padding(.horizontal, w * 0.012)
                            .padding(.vertical, w * 0.006)
                            .background(palette.inkColor.opacity(0.14), in: RoundedRectangle(cornerRadius: w * 0.01, style: .continuous))
                        Image(systemName: "wifi")
                        Image(systemName: "battery.75percent")
                    }
                    .font(.system(size: w * 0.036, weight: .medium))
                    .foregroundStyle(palette.inkColor)
                    .padding(.horizontal, w * 0.04)
                    .frame(height: w * 0.06)
                    .background(palette.raisedColor.opacity(0.7))
                    // Glasspad's window under its icon.
                    VStack(alignment: .leading, spacing: w * 0.012) {
                        menuRow(symbol: "iphone.slash", title: "No iPhone Paired", w: w, highlighted: false, bold: true)
                        Rectangle().fill(palette.lineColor).frame(height: 1)
                        menuRow(symbol: "qrcode", title: "Pair Your iPhone…", w: w, highlighted: true, bold: false)
                        menuRow(symbol: "dock.rectangle", title: "Hide Mac Dock", w: w, highlighted: false, bold: false)
                    }
                    .padding(w * 0.018)
                    .frame(width: w * 0.46)
                    .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: w * 0.025, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.025, style: .continuous).strokeBorder(palette.lineColor))
                    .shadow(color: .black.opacity(0.18), radius: w * 0.02, y: w * 0.01)
                    .padding(.top, w * 0.07)
                    .padding(.trailing, w * 0.08)
                }
            }
        }
    }

    private func menuRow(symbol: String, title: String, w: CGFloat, highlighted: Bool, bold: Bool) -> some View {
        HStack(spacing: w * 0.018) {
            Image(systemName: symbol)
                .font(.system(size: w * 0.022, weight: .medium))
                .frame(width: w * 0.045, height: w * 0.045)
                .background(Circle().fill(palette.inkColor.opacity(0.1)))
            Text(title)
                .font(.system(size: w * 0.03, weight: bold ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.inkColor)
        .padding(.horizontal, w * 0.012)
        .padding(.vertical, w * 0.006)
        .background(RoundedRectangle(cornerRadius: w * 0.012, style: .continuous)
            .fill(highlighted ? palette.inkColor.opacity(0.1) : .clear))
    }
}
