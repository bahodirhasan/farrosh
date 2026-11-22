// Farrosh ikonkasini chizadi: macOS uslubidagi yumaloq kvadrat, ko'k gradient va oq Popuk F logosi.
// Ishlatish: swift make-icon.swift <chiqish.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let px = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple ikonka to'ri: 1024 ichida 824 lik tana.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Ko'k gradient: yuqori chapdan (#3B82F6) pastki o'ngga (#1E3A8A).
let gradient = NSGradient(
    starting: NSColor(srgbRed: 0x3B/255.0, green: 0x82/255.0, blue: 0xF6/255.0, alpha: 1),
    ending: NSColor(srgbRed: 0x1E/255.0, green: 0x3A/255.0, blue: 0x8A/255.0, alpha: 1))!
gradient.draw(in: shape, angle: -45)

// "Popuk" F logosi: ikki plita + to'rtta shvabra popugi (Logo/2-popuk-kok-ikon.svg bilan bir xil).
// SVG koordinatalari (y pastga) markazga, 1.6 marta kattalashtirib, y ni ag'darib chiziladi.
let t = NSAffineTransform()
t.translateX(by: 512, yBy: 512)
t.scaleX(by: 1.6, yBy: -1.6)
t.translateX(by: -114, yBy: -153)
NSGraphicsContext.saveGraphicsState()
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

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
