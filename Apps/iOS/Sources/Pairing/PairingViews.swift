import SwiftUI
import GlasspadKit
import AVFoundation

/// Turns a scanned or pasted string into a pairing, or a plain reason it failed.
enum PairingParser {
    static func parse(_ text: String) -> PairingPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "glasspad" else { return nil }
        return PairingPayload(url: url)
    }
}

/// The scan step: camera when there is one and access is allowed, a paste box otherwise.
/// Used by onboarding and by "Pair a Mac" in Settings.
struct PairingScanner: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    var onPaired: (PairedMac) -> Void

    @State private var cameraStatus = CameraAccess.status
    @State private var errorText: String?
    @State private var showPaste = !CameraAccess.hasCamera
    @State private var pasteText = ""
    @State private var scannerKey = 0

    var body: some View {
        VStack(spacing: verticalSize == .compact ? 10 : 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.raisedColor)
                cameraArea
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(palette.lineColor, lineWidth: 1)
            }
            .aspectRatio(1, contentMode: .fit)
            // Sideways the square gives up height so the paste box still fits below it.
            .frame(maxWidth: 320, maxHeight: verticalSize == .compact ? 210 : .infinity)

            Text(errorText ?? " ")
                .font(.footnote)
                .foregroundStyle(Color(hex: 0xD9443A))
                .multilineTextAlignment(.center)
                .frame(minHeight: 18)
                .accessibilityHidden(errorText == nil)

            if CameraAccess.hasCamera {
                Button(showPaste ? "Hide link box" : "Paste the link instead") {
                    withAnimation(.snappy) { showPaste.toggle() }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.inkSoftColor)
            }

            if showPaste {
                HStack(spacing: 10) {
                    TextField("glasspad://pair?...", text: $pasteText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(palette.raisedColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onSubmit { handle(pasteText) }
                    Button("Pair") { handle(pasteText) }
                        .glassButton(prominent: true)
                        .disabled(pasteText.isEmpty)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .task {
            if cameraStatus == .notDetermined, CameraAccess.hasCamera {
                _ = await CameraAccess.request()
                cameraStatus = CameraAccess.status
            }
        }
    }

    @ViewBuilder private var cameraArea: some View {
        if !CameraAccess.hasCamera {
            QuietMessage(symbol: "camera", title: "No camera here",
                         detail: "Paste a glasspad:// pairing link below.")
        } else {
            switch cameraStatus {
            case .authorized:
                QRScannerView { handle($0) }
                    .id(scannerKey)
                    .overlay { ScanFrame() }
            case .notDetermined:
                ProgressView()
            default:
                VStack(spacing: 14) {
                    QuietMessage(symbol: "camera", title: "Camera is off for Glasspad",
                                 detail: "Allow it in Settings, or scan the code with the Camera app. It opens Glasspad and pairs.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let payload = PairingParser.parse(text) else {
            errorText = "That is not a Glasspad pairing code."
            Haptics.shared.play(.error)
            // Let the camera report the next code, even if it is the same one again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { scannerKey += 1 }
            return
        }
        errorText = nil
        Haptics.shared.play(.snap)
        let mac = PairingStore.shared.add(payload)
        MacSession.shared.didPair(mac)
        onPaired(mac)
    }
}

/// Four soft corner brackets over the camera, showing where to aim.
private struct ScanFrame: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.62
            let arm: CGFloat = 26
            Path { p in
                let r = CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2, width: side, height: side)
                for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                         (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
                    p.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
                    p.addLine(to: corner)
                    p.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
                }
            }
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

/// "Pair a Mac" sheet from Settings.
struct PairSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSize
    @State private var paired: PairedMac?

    var body: some View {
        Group {
            if verticalSize == .compact {
                // Sideways: words on the left, the camera or the result on the right.
                HStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 18) {
                        heading(alignment: .leading)
                        if paired != nil { doneButton }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if let paired {
                            PairedBadge(name: paired.name)
                        } else {
                            PairingScanner { mac in withAnimation(.snappy) { paired = mac } }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 22) {
                    heading(alignment: .center)
                        .padding(.horizontal, 24)
                        .padding(.top, 32)
                    if let paired {
                        PairedBadge(name: paired.name)
                            .frame(maxHeight: .infinity)
                        doneButton
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    } else {
                        PairingScanner { mac in withAnimation(.snappy) { paired = mac } }
                            .padding(.horizontal, 24)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.backgroundColor.ignoresSafeArea())
    }

    private func heading(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(paired == nil ? "Pair a Mac" : "Paired")
                .font(.title2.bold())
                .foregroundStyle(palette.inkColor)
            Text(paired.map { "Glasspad now controls \($0.name)." }
                 ?? "On your Mac, open the Glasspad menu and choose Pair. Then point the camera at the code.")
                .font(.subheadline)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .foregroundStyle(palette.inkSoftColor)
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .glassButton(prominent: true)
        .controlSize(.large)
    }
}

/// A calm confirmation with the Mac's name.
struct PairedBadge: View {
    @Environment(\.palette) private var palette
    let name: String
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(hex: 0x2E9E5B).opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2E9E5B))
            }
            Label(name, systemImage: "laptopcomputer")
                .font(.headline)
                .foregroundStyle(palette.inkColor)
        }
    }
}
