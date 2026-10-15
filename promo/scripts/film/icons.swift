import AppKit
let out = CommandLine.arguments[1]
let ids = ["com.apple.finder","com.apple.Safari","com.apple.mail","com.apple.MobileSMS","com.apple.iCal","com.apple.Notes","com.apple.reminders","com.apple.Music","com.apple.Photos","com.microsoft.Word","com.microsoft.Excel","com.microsoft.Outlook","com.microsoft.Powerpoint","com.apple.dt.Xcode","com.apple.Terminal","com.apple.AppStore","com.apple.systempreferences","com.figma.Desktop","com.apple.Preview","com.apple.TextEdit","com.apple.Maps","com.spotify.client","com.apple.FaceTime","com.apple.freeform","com.apple.keynote","com.tinyspeck.slackmacgap","com.google.Chrome","com.apple.Passwords"]
var list: [[String: String]] = []
for id in ids {
  guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { print("missing", id); continue }
  let icon = NSWorkspace.shared.icon(forFile: url.path)
  let size = 256
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size)); NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(id).png"))
  let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
  list.append(["id": id, "name": name])
}
try! JSONSerialization.data(withJSONObject: list, options: .prettyPrinted).write(to: URL(fileURLWithPath: "\(out)/list.json"))
print(list.count, "icons")
