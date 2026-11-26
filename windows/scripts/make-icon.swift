// Farrosh Windows ikonkasi: ko'k yumaloq kvadrat va oq "Popuk" F logosi (1024×1024 PNG).
// Ishlatish: swift scripts/make-icon.swift icon-source.png  →  npx tauri icon icon-source.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-source.png"
let px = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Windows ikonkalari kichik o'lchamda ham ko'rinishi uchun tana deyarli butun maydonni egallaydi.
let shape = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210)
NSGradient(
    starting: NSColor(srgbRed: 0x3B/255.0, green: 0x82/255.0, blue: 0xF6/255.0, alpha: 1),
    ending: NSColor(srgbRed: 0x1E/255.0, green: 0x3A/255.0, blue: 0x8A/255.0, alpha: 1))!.draw(in: shape, angle: -45)

let t = NSAffineTransform()
t.translateX(by: 512, yBy: 512)
t.scaleX(by: 1.9, yBy: -1.9)
t.translateX(by: -114, yBy: -153)
t.concat()
NSColor.white.set()
func slab(_ pts: [(CGFloat, CGFloat)]) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: pts[0].0, y: pts[0].1))
    for q in pts.dropFirst() { path.line(to: NSPoint(x: q.0, y: q.1)) }
    path.close()
    path.lineWidth = 12
    path.lineJoinStyle = .round
    path.fill()
    path.stroke()
}
slab([(0, 100), (224, 6), (228, 108), (0, 146)])
slab([(0, 170), (174, 154), (174, 228), (0, 230)])
for (i, h) in [58, 50, 42, 34].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: -6 + CGFloat(i) * 32, y: 248, width: 22, height: CGFloat(h)), xRadius: 11, yRadius: 11).fill()
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
