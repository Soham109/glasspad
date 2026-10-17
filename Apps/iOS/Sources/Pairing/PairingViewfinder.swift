import GlasspadKit
import SwiftUI

/// The scan step, as Apple Watch pairing does it: the camera fills the screen, a rounded frame
/// floats over it, and the words say what to do. When the Mac's pattern is seen the frame
/// springs onto it, the phone taps once, and the code's own dots appear over the camera and
/// flow into a checkmark. Then `onPaired` hands over the saved Mac.
struct PairingViewfinder: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var cancelTitle = "Cancel"
    var onCancel: () -> Void
    var onPaste: () -> Void
    var onPaired: (PairedMac) -> Void

    @State private var cameraStatus = CameraAccess.status
    @State private var lock: Lock?
    @State private var attempt = 0
    @State private var notGlasspad = false
    @State private var shake = 0.0

    /// The code the camera locked onto: its text, where it was, and when.
    struct Lock: Equatable {
        let payload: PairingPayload
        let rect: CGRect
        let at: Date
    }

    /// From lock to handing over: the frame settles, the dots appear, then gather.
    static let settle: Double = 0.35
    static var handOver: Double { settle + PairingPattern.gatherDuration + 0.45 }

    var body: some View {
        // The safe area is read outside; the picture itself fills the whole screen.
        GeometryReader { outer in
            let safe = outer.safeAreaInsets
            GeometryReader { geo in
                let size = geo.size
                let idle = Self.idleFrame(in: size, safe: safe)
                let target = lock.map { Self.square($0.rect, in: size) } ?? idle
                ZStack {
                    camera(idle: idle)
                    if !cameraDenied {
                        Scrim(cutout: target, cornerRadius: target.width * 0.16)
                            .animation(.spring(duration: 0.5, bounce: 0.28), value: lock)
                            .allowsHitTesting(false)
                        ViewfinderFrame(cornerRadius: target.width * 0.16, locked: lock != nil)
                            .frame(width: target.width, height: target.height)
                            .position(x: target.midX, y: target.midY)
                            .modifier(Shake(amount: shake))
                            .animation(.spring(duration: 0.5, bounce: 0.28), value: lock)
                            .allowsHitTesting(false)
                    }
                    if let lock {
                        LockedDots(lock: lock, rect: target, success: palette.good)
                            .allowsHitTesting(false)
                    }
                    chrome(size: size, frame: idle, safe: safe)
                }
                .frame(width: size.width, height: size.height)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .task {
            if cameraStatus == .notDetermined, CameraAccess.hasCamera {
                _ = await CameraAccess.request()
                cameraStatus = CameraAccess.status
            }
        }
        .task(id: lock) {
            guard let lock else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.9 : Self.handOver))
            guard !Task.isCancelled else { return }
            let mac = PairingStore.shared.add(lock.payload)
            MacSession.shared.didPair(mac)
            onPaired(mac)
        }
        #if DEBUG
        .task {
            // -GPPairAuto: the simulator "sees" its stand-in code after a moment, for videos.
            guard PairingDemo.autoScan else { return }
            try? await Task.sleep(for: .seconds(2.2))
            simulateScan()
        }
        #endif
    }

    // MARK: Camera

    @ViewBuilder private func camera(idle: CGRect) -> some View {
        #if targetEnvironment(simulator)
        if cameraDenied {
            Hardware.glass
        } else {
            SimulatedCamera(codeRect: Self.simulatedCode(idle), hidden: lock != nil)
            #if DEBUG
                .onTapGesture { simulateScan() }
            #endif
        }
        #else
        if !CameraAccess.hasCamera {
            Hardware.glass
        } else if cameraStatus == .authorized {
            QRScannerView(onCode: handle, attempt: attempt)
        } else {
            Hardware.glass
        }
        #endif
    }

    #if DEBUG
    private func simulateScan() {
        guard lock == nil else { return }
        let size = UIScreen.main.bounds.size
        let idle = Self.idleFrame(in: size, safe: .init())
        handle(PatternCache.sample, rect: Self.simulatedCode(idle))
    }
    #endif

    private func handle(_ text: String, rect: CGRect) {
        guard lock == nil else { return }
        guard let payload = PairingParser.parse(text) else {
            Haptics.shared.play(.error)
            withAnimation(.default) { shake += 1 }
            withAnimation(.smooth) { notGlasspad = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.smooth) { notGlasspad = false }
                attempt += 1
            }
            return
        }
        notGlasspad = false
        Haptics.shared.play(.snap)
        UIAccessibility.post(notification: .announcement, argument: "Pairing with \(payload.macName)")
        lock = Lock(payload: payload, rect: rect, at: Date())
    }

    // MARK: Words and buttons

    @ViewBuilder private func chrome(size: CGSize, frame: CGRect, safe: EdgeInsets) -> some View {
        let landscape = size.width > size.height
        let denied = cameraDenied
        ZStack {
            // Words: above the frame upright, beside it sideways.
            Group {
                if denied {
                    deniedMessage
                } else {
                    VStack(alignment: landscape ? .leading : .center, spacing: 8) {
                        if let lock {
                            Text("Pairing with \(lock.payload.macName)")
                                .font(.title2.weight(.semibold))
                                .transition(.opacity)
                        } else {
                            Text("Hold your iPhone over the Mac's screen")
                                .font(.title2.weight(.semibold))
                            Text(notGlasspad ? "That code is not from Glasspad." : "Line up the code in the frame.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                    }
                    .transition(.opacity)
                    .multilineTextAlignment(landscape ? .leading : .center)
                    .animation(.smooth(duration: 0.3), value: lock)
                    .animation(.smooth(duration: 0.3), value: notGlasspad)
                }
            }
            .foregroundStyle(.primary)
            .shadow(color: .black.opacity(0.35), radius: 8)
            .frame(maxWidth: landscape ? max(200, frame.minX - safe.leading - 56) : 340,
                   alignment: landscape ? .leading : .center)
            .position(x: landscape ? safe.leading + 28 + max(200, frame.minX - safe.leading - 56) / 2 : size.width / 2,
                      y: landscape || denied ? size.height / 2 : max(safe.top + 70, frame.minY / 2 + safe.top / 2))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack {
                HStack {
                    Button(cancelTitle, action: onCancel)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .glassCapsule(interactive: true)
                    Spacer()
                }
                Spacer()
                if lock == nil {
                    HStack {
                        Button("Paste the Link Instead", action: onPaste)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .glassCapsule(interactive: true)
                        // Sideways it sits under the words, clear of the frame.
                        if landscape { Spacer() }
                    }
                    .padding(.leading, landscape ? 12 : 0)
                    .transition(.opacity)
                }
            }
            .padding(.top, max(safe.top, 12) + 4)
            .padding(.bottom, max(safe.bottom, 16) + 8)
            .padding(.horizontal, max(safe.leading, safe.trailing, 0) + 16)
            .animation(.smooth, value: lock)
        }
    }

    private var cameraDenied: Bool {
        #if DEBUG
        if PairingDemo.cameraDenied { return true }
        #endif
        #if targetEnvironment(simulator)
        return false
        #else
        return !CameraAccess.hasCamera || cameraStatus == .denied || cameraStatus == .restricted
        #endif
    }

    /// A phone always has a camera; only the simulator (and a debug run) gets here without one.
    private var hasCamera: Bool {
        #if DEBUG
        if PairingDemo.cameraDenied { return true }
        #endif
        return CameraAccess.hasCamera
    }

    private var deniedMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.secondary)
            Text(hasCamera ? "Allow Camera Access" : "No Camera")
                .font(.title2.weight(.semibold))
            Text(hasCamera
                 ? "Glasspad uses the camera only to read the pairing code on your Mac. Turn on Camera for Glasspad in Settings."
                 : "Paste the pairing link from your Mac instead.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if hasCamera {
                Button("Open Settings") { openAppSettings() }
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 48)
                    .glassCapsule(interactive: true)
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: Geometry

    /// The frame while looking: a large rounded square a little above the middle (upright), or
    /// right of the words (sideways).
    static func idleFrame(in size: CGSize, safe: EdgeInsets) -> CGRect {
        if size.width > size.height {
            let side = min(size.height * 0.62, 300)
            return CGRect(x: size.width * 0.64 - side / 2, y: (size.height - side) / 2, width: side, height: side)
        }
        let side = min(size.width * 0.74, 330)
        return CGRect(x: (size.width - side) / 2, y: size.height * 0.46 - side / 2, width: side, height: side)
    }

    /// A code's box made square around its center, with a little room, kept on screen.
    static func square(_ r: CGRect, in size: CGSize) -> CGRect {
        let side = min(max(r.width, r.height) * 1.12, min(size.width, size.height) * 0.9)
        var out = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
        out.origin.x = min(max(8, out.minX), size.width - side - 8)
        out.origin.y = min(max(8, out.minY), size.height - side - 8)
        return out
    }

    /// Where the simulator's stand-in Mac shows its code: a little off the frame, so locking
    /// on is seen to move.
    static func simulatedCode(_ idle: CGRect) -> CGRect {
        let side = idle.width * 0.7
        return CGRect(x: idle.midX - side / 2 + idle.width * 0.06, y: idle.midY - side / 2 + idle.width * 0.07,
                      width: side, height: side)
    }
}

/// The code's dots over the camera, appearing where the code was seen and flowing into a check.
private struct LockedDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lock: PairingViewfinder.Lock
    let rect: CGRect
    let success: Color
    /// The check mark has formed: the last frame stays and nothing redraws.
    @State private var formed = false

    /// Seconds from the lock until the dots are a still check mark.
    private var formsAfter: Double {
        reduceMotion ? 0.3 : PairingViewfinder.settle + PairingPattern.gatherDuration
    }

    var body: some View {
        if let pattern = PatternCache.pattern(for: lock.payload.url.absoluteString) {
            TimelineView(.animation(minimumInterval: nil, paused: formed)) { context in
                // Once formed, drawn as at the moment it formed, whatever date a still timeline hands over.
                let date = formed ? max(context.date, lock.at.addingTimeInterval(formsAfter)) : context.date
                let t = date.timeIntervalSince(lock.at)
                let appear = min(1, t / PairingViewfinder.settle)
                let gather = reduceMotion ? 1 : (t - PairingViewfinder.settle) / PairingPattern.gatherDuration
                PatternCanvas(pattern: pattern, time: date.timeIntervalSinceReferenceDate,
                              motion: reduceMotion ? 0 : 1, gather: max(0, gather), ink: .white, success: success)
                    .padding(rect.width * 0.08)
                    .frame(width: rect.width, height: rect.height)
                    .opacity(reduceMotion ? min(1, t / 0.3) : appear)
                    .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * appear)
                    .shadow(color: success.opacity(0.6 * max(0, min(1, gather))), radius: 12)
                    .position(x: rect.midX, y: rect.midY)
            }
            .task(id: lock) {
                formed = false
                let left = formsAfter - Date().timeIntervalSince(lock.at)
                if left > 0 { try? await Task.sleep(for: .seconds(left)) }
                if !Task.isCancelled { formed = true }
            }
        }
    }
}

/// Dims and frosts the camera everywhere but the frame.
private struct Scrim: View {
    var cutout: CGRect
    var cornerRadius: CGFloat

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.25))
            .mask {
                CutoutShape(cutout: cutout, cornerRadius: cornerRadius)
                    .fill(style: FillStyle(eoFill: true))
            }
    }
}

private struct CutoutShape: Shape {
    var cutout: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(cutout.minX, cutout.minY), .init(cutout.width, cornerRadius)) }
        set {
            cutout = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.first)
            cornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRoundedRect(in: cutout, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        return p
    }
}

/// Four rounded corners of a square, like the camera's own code brackets. Breathes gently
/// while looking; turns solid and a little bolder once locked.
private struct ViewfinderFrame: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cornerRadius: CGFloat
    let locked: Bool
    var power = PowerMonitor.shared
    @State private var breathe = false

    var body: some View {
        CornerBrackets(cornerRadius: cornerRadius)
            .stroke(.white.opacity(locked ? 1 : 0.92),
                    style: StrokeStyle(lineWidth: locked ? 5 : 4, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.25), radius: 6)
            .scaleEffect(breathe && !locked ? 1.025 : 1)
            .onAppear {
                // A slow breath, only when motion is welcome and the phone is cool.
                guard !reduceMotion, power.policy.decorativeFrameInterval != nil else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
            }
            .onChange(of: locked) { _, now in if now { withAnimation(.spring(duration: 0.4)) { breathe = false } } }
    }
}

private struct CornerBrackets: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width / 2)
        let arm = rect.width * 0.2
        var p = Path()
        // Top left, then clockwise.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r + arm))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r + arm, y: rect.minY))

        p.move(to: CGPoint(x: rect.maxX - r - arm, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r + arm))

        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r - arm))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r - arm, y: rect.maxY))

        p.move(to: CGPoint(x: rect.minX + r + arm, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - arm))
        return p
    }
}

/// A small side to side shake, for a code that is not Glasspad's.
private struct Shake: GeometryEffect {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 4), y: 0))
    }
}

#if targetEnvironment(simulator)
/// The simulator has no camera. In its place: a dim room and the Mac's screen glowing with
/// its living code, seen at a slight angle, the way the camera would show it.
private struct SimulatedCamera: View {
    let codeRect: CGRect
    let hidden: Bool

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(white: 0.2), Color(white: 0.06)], center: .init(x: 0.5, y: 0.45),
                           startRadius: 40, endRadius: 520)
            // The Mac's display around the code.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: codeRect.width * 2.1, height: codeRect.width * 1.5)
                .position(x: codeRect.midX, y: codeRect.midY)
                .blur(radius: 1.5)
            if let pattern = PatternCache.pattern(for: PatternCache.sample) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: hidden)) { context in
                    PatternCanvas(pattern: pattern, time: context.date.timeIntervalSinceReferenceDate,
                                  ink: Color(red: 0.9, green: 0.94, blue: 1), success: .clear)
                        .padding(codeRect.width * 0.075)
                        .background(RoundedRectangle(cornerRadius: codeRect.width * 0.11, style: .continuous).fill(Color(white: 0.05)))
                        .blur(radius: 0.6)
                }
                .frame(width: codeRect.width, height: codeRect.height)
                .position(x: codeRect.midX, y: codeRect.midY)
                .opacity(hidden ? 0 : 1)
                .animation(.easeOut(duration: 0.3), value: hidden)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
