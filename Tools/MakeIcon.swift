// Draws Edit Assist's app icon and writes Resources/AppIcon.icns. Run: swift Tools/MakeIcon.swift
// The mark is the sidebar logo (a cursor with motion lines) over a caption line with one phrase
// highlighted in the app's mint accent: what the tool does, at a glance.
import AppKit

func render(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let s = CGFloat(size) / 1024
    let mint = NSColor(red: 0.43, green: 0.88, blue: 0.73, alpha: 1)

    // macOS icon grid: an 824-point rounded square centred in 1024, with a soft drop shadow.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 28 * s; shadow.shadowOffset = NSSize(width: 0, height: -12 * s); shadow.set()
    NSColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.13, green: 0.17, blue: 0.20, alpha: 1), NSColor(red: 0.045, green: 0.06, blue: 0.075, alpha: 1)])!
        .draw(in: shape, angle: -90)
    // A faint mint glow from the top left, and a fine rim.
    NSGraphicsContext.saveGraphicsState(); shape.addClip()
    NSGradient(colors: [mint.withAlphaComponent(0.22), mint.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 260 * s, y: 860 * s), radius: 0, toCenter: NSPoint(x: 260 * s, y: 860 * s), radius: 620 * s, options: [])
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.10).setStroke(); shape.lineWidth = 4 * s; shape.stroke()

    // A caption line: grey words, one phrase highlighted.
    func bar(_ x: CGFloat, _ width: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x * s, y: 560 * s, width: width * s, height: 72 * s), xRadius: 36 * s, yRadius: 36 * s).fill()
    }
    bar(200, 150, NSColor.white.withAlphaComponent(0.22))
    bar(372, 300, mint)
    bar(694, 130, NSColor.white.withAlphaComponent(0.22))
    // The highlighted phrase sits under a marker underline, slightly brighter.
    mint.withAlphaComponent(0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: 372 * s, y: 506 * s, width: 300 * s, height: 22 * s), xRadius: 11 * s, yRadius: 11 * s).fill()

    // The cursor with motion lines, the sidebar logo, pointing at the phrase.
    let config = NSImage.SymbolConfiguration(pointSize: 260 * s, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        // The arrow's tip is the glyph's top-left corner: put it on the highlighted phrase.
        let box = NSRect(x: 560 * s, y: 600 * s - symbol.size.height, width: symbol.size.width, height: symbol.size.height)
        NSGraphicsContext.saveGraphicsState()
        let lift = NSShadow(); lift.shadowColor = NSColor.black.withAlphaComponent(0.5)
        lift.shadowBlurRadius = 18 * s; lift.shadowOffset = NSSize(width: 0, height: -8 * s); lift.set()
        symbol.draw(in: box)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let set = root.appendingPathComponent(".build/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(points * scale).representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
    }
}
try render(1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(".build/AppIcon-preview.png"))
print(set.path)
