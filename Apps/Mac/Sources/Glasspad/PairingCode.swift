import AppKit
import GlasspadKit
import SwiftUI

/// The pairing code as the Mac shows it: a real QR code drawn as soft round dots that drift
/// and shimmer on a calm card, in the spirit of the Apple Watch pairing cloud. The iPhone reads
/// it with Vision (PairingPatternTests and PairingCodeRenderTests prove it still reads).
///
/// When pairing finishes the dots gather into a checkmark in a ring. When the code runs out
/// they stop and fade. Reduce Motion stills the dots and turns the gathering into a fade.
struct PairingCodeView: View {
    enum Phase: Equatable {
        /// Waiting for a scan: alive.
        case live
        /// Paired: gathering into the checkmark since this moment.
        case gathered(since: Date)
        /// Expired or failed: still and faded.
        case resting
    }

    let message: String
    var size: CGFloat = 220
    var phase: Phase = .live
    /// The snapshot harness draws a fixed moment of the motion; the app leaves it nil.
    var fixedTime: Double?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pattern = PatternCache.pattern(for: message)
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { context in
            let t = fixedTime ?? context.date.timeIntervalSinceReferenceDate
            if let pattern {
                PatternLayers(pattern: pattern, time: t, motion: motion, gather: gather(at: context.date),
                              ink: ink, glow: glow, side: size)
            }
        }
        .frame(width: size, height: size)
        .padding(size * 0.075)
        .background { card }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private var paused: Bool {
        switch phase {
        case .live: reduceMotion || fixedTime != nil
        case .gathered(let since): fixedTime != nil || Date().timeIntervalSince(since) > PairingPattern.gatherDuration + 3
        case .resting: true
        }
    }

    private var motion: Double {
        if reduceMotion { return 0 }
        return phase == .resting ? 0 : 1
    }

    private func gather(at now: Date) -> Double {
        guard case .gathered(let since) = phase else { return 0 }
        if fixedTime != nil { return 1 }
        let p = now.timeIntervalSince(since) / PairingPattern.gatherDuration
        return min(1, max(0, p))
    }

    /// Graphite dots on white, or Watch-like light dots on near black.
    private var ink: Color {
        let base = scheme == .dark ? Color(red: 0.9, green: 0.94, blue: 1) : Color(red: 0.11, green: 0.11, blue: 0.13)
        return phase == .resting ? base.opacity(0.28) : base
    }

    private var glow: Double {
        if phase == .resting { return 0 }
        return scheme == .dark ? 0.75 : 0.18
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.11, style: .continuous)
        return shape
            .fill(scheme == .dark ? Color(white: 0.06) : .white)
            .overlay {
                shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 10, y: 3)
    }

    private var accessibilityLabel: String {
        switch phase {
        case .live: "Pairing code. Hold your iPhone over it with Glasspad open, or use Show Code as Text."
        case .gathered: "Paired"
        case .resting: "Pairing code, no longer valid"
        }
    }
}

/// One frame of the pattern: a blurred copy underneath for the glow, the sharp dots on top.
private struct PatternLayers: View {
    let pattern: PairingPattern
    let time: Double
    let motion: Double
    let gather: Double
    let ink: Color
    let glow: Double
    let side: CGFloat

    var body: some View {
        let dots = pattern.frame(time: time, motion: motion, gather: gather)
        let finder = PairingPattern.finderAlpha(gather: gather)
        ZStack {
            if glow > 0 {
                DotCanvas(pattern: pattern, dots: dots, finderAlpha: finder, ink: ink, haloScale: 1.5)
                    .blur(radius: side / CGFloat(pattern.size) * 1.1)
                    .opacity(glow)
            }
            DotCanvas(pattern: pattern, dots: dots, finderAlpha: finder, ink: ink, haloScale: 1)
        }
    }
}

private struct DotCanvas: View {
    let pattern: PairingPattern
    let dots: [PairingPattern.DrawnDot]
    let finderAlpha: CGFloat
    let ink: Color
    let haloScale: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let m = size.width / CGFloat(pattern.size)
            if finderAlpha > 0 {
                for corner in pattern.finders {
                    let origin = CGPoint(x: corner.x * m, y: corner.y * m)
                    for path in PairingPattern.finderPaths(origin: origin, module: m) {
                        context.fill(Path(path), with: .color(ink.opacity(finderAlpha)), style: FillStyle(eoFill: true))
                    }
                }
            }
            let success = Color.green
            for dot in dots where dot.alpha > 0.01 {
                let r = dot.radius * m * haloScale
                let rect = CGRect(x: dot.center.x * m - r, y: dot.center.y * m - r, width: r * 2, height: r * 2)
                let shape = Path(ellipseIn: rect)
                if dot.success < 1 {
                    context.fill(shape, with: .color(ink.opacity(Double(dot.alpha * (1 - dot.success)))))
                }
                if dot.success > 0 {
                    context.fill(shape, with: .color(success.opacity(Double(dot.alpha * dot.success))))
                }
            }
        }
    }
}

/// Building the matrix reads pixels back from Core Image, so do it once per code.
@MainActor
enum PatternCache {
    private static var last: (String, PairingPattern?)?

    static func pattern(for message: String) -> PairingPattern? {
        if let last, last.0 == message { return last.1 }
        let p = PairingPattern(message: message)
        last = (message, p)
        return p
    }
}

// MARK: - Text fallback

/// The same code as a link, for no camera, VoiceOver, or a phone that cannot read it.
struct PairingLinkView: View {
    @EnvironmentObject private var model: AppModel
    let url: URL
    let width: CGFloat
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            Text(url.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.background.secondary, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Pairing link")
            Text(PairingCopy.linkHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    model.actions.copyPairingLink(url)
                    copied = true
                } label: {
                    Label(copied ? PairingCopy.copied : PairingCopy.copyLink, systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityHint("Copies the pairing link. Paste it in Glasspad on your iPhone.")
                ShareLink(item: url) {
                    Label(PairingCopy.share, systemImage: "square.and.arrow.up")
                }
                .accessibilityHint("Sends the pairing link to your iPhone with AirDrop or Messages.")
            }
            .controlSize(.small)
        }
        .frame(width: width)
        .onChange(of: url) { _, _ in copied = false }
    }
}
