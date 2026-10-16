import SwiftUI

/// Three calm screens: what Glasspad is, get the Mac ready, scan the code.
struct OnboardingView: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    var onFinish: () -> Void

    @State private var page = 0
    @State private var paired: PairedMac?

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                prepare.tag(1)
                scan.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            Group {
                if verticalSize == .compact { compactFooter } else { footer }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(SurfaceBackground())
    }

    // MARK: Pages

    private var welcome: some View {
        OnboardingPage(title: "Your iPhone,\nas a trackpad",
                       detail: "Move, click, scroll and swipe on your Mac, with a tap you can feel. Everything stays on your Wi-Fi.") {
            FingerDotsArt()
        }
    }

    private var prepare: some View {
        OnboardingPage(title: "Open Glasspad\non your Mac",
                       detail: "Click the Glasspad icon in the menu bar and choose Pair Your iPhone. Keep both on the same Wi-Fi.") {
            MenuBarArt()
        }
    }

    private func scanHeading(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 10) {
            Text(paired == nil ? "Scan the code" : "You're all set")
                .font(.largeTitle.bold())
                .foregroundStyle(palette.inkColor)
            Text(paired == nil ? "Point the camera at the code on your Mac." : "Glasspad will connect whenever this Mac is nearby.")
                .font(.body)
                .foregroundStyle(palette.inkSoftColor)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
        }
    }

    @ViewBuilder private var scan: some View {
        if verticalSize == .compact {
            HStack(spacing: 40) {
                scanHeading(alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let paired {
                        PairedBadge(name: paired.name)
                    } else if page == 2 {
                        PairingScanner { mac in withAnimation(.snappy) { paired = mac } }
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
        } else {
            scanPortrait
        }
    }

    private var scanPortrait: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 12)
            scanHeading(alignment: .center)
            if let paired {
                PairedBadge(name: paired.name)
                    .frame(maxHeight: .infinity)
            } else if page == 2 {
                // Only start the camera when this page is actually on screen.
                PairingScanner { mac in withAnimation(.snappy) { paired = mac } }
            } else {
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 18) {
            pageDots

            // One control in the same place on every page: the next step, or on the scan
            // page (until a Mac is paired) a quiet way to skip.
            if page == 2 && paired == nil {
                Button("Pair Later") { onFinish() }
                    .font(.headline)
                    .foregroundStyle(palette.inkSoftColor)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
            } else {
                Button {
                    if page < 2 { page += 1 } else { onFinish() }
                } label: {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .glassButton(prominent: true)
                .controlSize(.large)
            }
        }
    }

    /// Sideways: one row, so the page above keeps the height.
    private var compactFooter: some View {
        HStack(spacing: 18) {
            pageDots
            Spacer()
            if page == 2 && paired == nil {
                Button("Pair Later") { onFinish() }
                    .font(.headline)
                    .foregroundStyle(palette.inkSoftColor)
                    .frame(minHeight: 44)
            } else {
                Button {
                    if page < 2 { page += 1 } else { onFinish() }
                } label: {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(width: 220)
                        .padding(.vertical, 4)
                }
                .glassButton(prominent: true)
                .controlSize(.large)
            }
        }
        .frame(height: 52)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i == page ? palette.inkColor : palette.inkColor.opacity(0.18))
                    .frame(width: i == page ? 20 : 7, height: 7)
            }
        }
        .animation(.snappy, value: page)
        .accessibilityHidden(true)
    }

    private var buttonTitle: String {
        switch page {
        case 0: "Get Started"
        case 1: "I See the Code"
        default: "Start"
        }
    }
}

private struct OnboardingPage<Art: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var dynamicType
    let title: String
    let detail: String
    @ViewBuilder var art: Art

    var body: some View {
        if verticalSize == .compact {
            // Sideways: picture on the left, words on the right.
            HStack(spacing: 48) {
                art.frame(width: 300, height: 260)
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(palette.inkColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(palette.inkSoftColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 48)
            .padding(.top, 12)
        } else {
            portrait
        }
    }

    private var portrait: some View {
        // Scrolls only when very large text no longer fits; the words always show in full.
        ScrollView {
            VStack(spacing: 34) {
                if !dynamicType.isAccessibilitySize {
                    art.frame(height: 260)
                }
                VStack(spacing: 14) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.inkColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.inkSoftColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 320)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
    }
}

/// A phone-shaped card with two soft finger dots drifting, like the real surface.
private struct FingerDotsArt: View {
    @Environment(\.palette) private var palette
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(palette.raisedColor)
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(palette.lineColor))
                    .frame(width: 150, height: 250)
                SoftDot(color: palette.dot)
                    .offset(x: -22 + 8 * sin(t * 0.9), y: -10 + 26 * sin(t * 0.7))
                SoftDot(color: palette.dot)
                    .offset(x: 26 + 8 * sin(t * 0.9), y: 4 + 26 * sin(t * 0.7))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A sketch of the Mac menu bar with the Glasspad item highlighted.
private struct MenuBarArt: View {
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "apple.logo")
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "hand.point.up.left.fill")
                    .padding(6)
                    .background(palette.inkColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Image(systemName: "battery.75percent")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(palette.inkColor)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(palette.raisedColor)

            HStack {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 92, weight: .ultraLight))
                        .foregroundStyle(palette.inkColor)
                    Text("Pair Your iPhone")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.inkSoftColor)
                }
                .padding(22)
                .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.lineColor))
                .padding(.trailing, 28)
                .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 300, height: 240)
        .background(palette.backgroundColor.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.lineColor))
        .accessibilityHidden(true)
    }
}

/// The finger dot used everywhere: 44 pt, solid centre, soft edge.
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
