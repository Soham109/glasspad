// Exports the SF Symbols the drawn Mac screens use, as white template PNGs (Apple's symbols,
// not committed; used only to draw macOS true to life). Run on a Mac:
//   swift scripts/v4/symbols.swift public/v4/symbols
import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let names = ["wifi", "battery.100percent", "switch.2", "magnifyingglass", "moon.fill", "apple.logo", "bell.fill",
             "play.fill", "pause.fill", "gobackward.10", "goforward.10", "scissors", "chevron.left", "chevron.right",
             "square.and.arrow.up", "sidebar.left", "plus", "envelope", "trash", "archivebox", "arrowshape.turn.up.left",
             "square.and.pencil", "lock.fill", "display.2", "doc.text", "photo", "rectangle.split.2x1.fill",
             "moon.circle.fill", "speaker.wave.2.fill", "arrow.clockwise", "square.on.square", "flag.fill",
             "paperclip", "line.3.horizontal.decrease", "film", "waveform", "music.note", "laptopcomputer",
             "iphone", "lock.shield.fill", "person.crop.circle.fill", "xmark", "captions.bubble", "magnifyingglass.circle"]
for n in names {
  guard let base = NSImage(systemSymbolName: n, accessibilityDescription: nil) else { print("missing", n); continue }
  let cfg = NSImage.SymbolConfiguration(pointSize: 96, weight: .regular)
  let img = base.withSymbolConfiguration(cfg)!
  let s = img.size
  let scale: CGFloat = 2
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s.width * scale), pixelsHigh: Int(s.height * scale),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = s
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  img.draw(in: NSRect(origin: .zero, size: s))
  NSColor.white.set(); NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
  NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(n).png"))
}
print(names.count, "symbols")
