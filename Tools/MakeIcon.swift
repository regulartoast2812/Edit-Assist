// Draws Edit Assist's app icon and writes Resources/AppIcon.icns. Run: swift Tools/MakeIcon.swift
// The mark is Kino, the AI video helper (an orange blob in a red beret with a clapperboard), in pixel art on the dark
// tile with an orange glow (2026-11-03, chosen from the seven helpers). His rows and colours are PixelKino.rest's.
import AppKit

func render(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let s = CGFloat(size) / 1024
    let glow = NSColor(red: 250 / 255, green: 160 / 255, blue: 70 / 255, alpha: 1)

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
    // A faint orange glow from the top left, and a fine rim.
    NSGraphicsContext.saveGraphicsState(); shape.addClip()
    NSGradient(colors: [glow.withAlphaComponent(0.26), glow.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 260 * s, y: 860 * s), radius: 0, toCenter: NSPoint(x: 260 * s, y: 860 * s), radius: 620 * s, options: [])
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.10).setStroke(); shape.lineWidth = 4 * s; shape.stroke()

    // Kino, square pixels centred on the tile, lifted by a soft shadow.
    let rows = ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO.....",
                ".OOOOOOOOOO.....", ".OOKOOOOKOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
                ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"]
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
    let colors: [Character: NSColor] = ["O": rgb(250, 160, 70), "D": rgb(205, 131, 57), "R": rgb(215, 55, 60), "r": rgb(160, 35, 45),
                                        "K": rgb(25, 25, 28), "B": rgb(95, 95, 108), "W": rgb(240, 240, 240)]
    // The last row is empty: centre on the rows that are drawn.
    let pixel = (824 * 0.72 / 16).rounded(.down) * s, drawn = CGFloat(rows.count - 1)
    let left = 512 * s - 8 * pixel, top = 512 * s + drawn / 2 * pixel
    NSGraphicsContext.saveGraphicsState()
    let lift = NSShadow(); lift.shadowColor = NSColor.black.withAlphaComponent(0.45)
    lift.shadowBlurRadius = 22 * s; lift.shadowOffset = NSSize(width: 0, height: -10 * s); lift.set()
    NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
    for (y, row) in rows.enumerated() {
        for (x, mark) in row.enumerated() {
            guard let color = colors[mark] else { continue }
            color.setFill()
            // Each square a hair wider, so no seam shows between neighbours at small sizes.
            NSRect(x: left + CGFloat(x) * pixel, y: top - CGFloat(y + 1) * pixel, width: pixel + 0.5, height: pixel + 0.5).fill()
        }
    }
    NSGraphicsContext.current?.cgContext.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
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
