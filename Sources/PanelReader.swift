import AppKit
import Vision

/// Reading the Properties panel's Text section as a map of named controls, so every part of it can
/// be found by name: what the routine changes today (Font Size) and what later functions will
/// (font, weight, case, alignment, tracking, leading). Reading only: nothing here clicks.
///
/// Text gives the anchors ("Text", the font and style names, "Font Size"); the icon rows carry no
/// readable text, so their buttons are found from pixels, in Premiere's fixed order.
extension Desktop {
    struct PanelControl: Equatable {
        var name: String
        /// Where to click, normalized to the window.
        var point: CGPoint
        /// The control's extent.
        var rect: CGRect
        /// For toggles: switched on (drawn on a lighter box).
        var on: Bool? = nil
        /// For fields: the value shown, as read.
        var value: String? = nil
    }

    struct TextSection: Equatable {
        var font: PanelControl?
        var fontStyle: PanelControl?
        /// Faux Bold, Faux Italic, All Caps, Small Caps, Superscript, Subscript, Underline.
        var typeButtons: [PanelControl] = []
        var fontSize: PanelControl?
        var sizeSlider: PanelControl?
        /// Align left, centre, right, justify; top, middle, bottom; left to right, right to left.
        var paragraphButtons: [PanelControl] = []
        var tracking: PanelControl?
        var leading: PanelControl?

        var all: [PanelControl] {
            [font, fontStyle].compactMap { $0 } + typeButtons + [fontSize, sizeSlider].compactMap { $0 }
                + paragraphButtons + [tracking, leading].compactMap { $0 }
        }
    }

    static let typeButtonNames = ["Faux Bold", "Faux Italic", "All Caps", "Small Caps", "Superscript", "Subscript", "Underline"]
    static let paragraphButtonNames = ["Align left", "Align centre", "Align right", "Justify",
                                       "Align top", "Align middle", "Align bottom", "Left to right", "Right to left"]

    /// The Text section of the Properties panel, or nil when its "Font Size" row is not on screen.
    static func textSection(in hits: [TextHit], image: CGImage) -> TextSection? {
        func words(_ hit: TextHit) -> String {
            normalized(hit.text).filter { $0 != "v" && $0 != ">" }.joined(separator: " ")
        }
        guard let label = hits.first(where: { words($0) == "font size" }) else { return nil }
        let line = label.rect.height
        // The section header: "Text" above Font Size, at the panel's left.
        let header = hits.filter { words($0) == "text" && $0.rect.maxY < label.rect.minY && abs($0.rect.minX - label.rect.minX) < 0.04 }
            .max { $0.rect.minY < $1.rect.minY }
        var section = TextSection()
        let value = numberField(labelled: "Font Size", in: hits, image: image)
        // The panel's right edge: the size value sits at it; failing that, the widest text in the section.
        let inSection = hits.filter { $0.rect.minY > (header?.rect.maxY ?? label.rect.minY - line * 8) && $0.rect.maxY < label.rect.minY + line * 10 }
        let right = value.map { $0.rect.maxX + 0.004 } ?? (inSection.map(\.rect.maxX).max() ?? 1)
        let left = label.rect.minX - line

        // Font and weight: the first two lines of text between the header and Font Size, each the
        // leftmost text on its row.
        let between = hits.filter { $0.rect.minY > (header?.rect.maxY ?? label.rect.minY - line * 8) && $0.rect.maxY < label.rect.minY
            && $0.rect.minX >= left - 0.005 && $0.rect.minX < label.rect.minX + 0.05 }
            .sorted { $0.rect.minY < $1.rect.minY }
        var rows: [TextHit] = []
        for hit in between where !rows.contains(where: { abs($0.rect.midY - hit.rect.midY) < line * 0.8 }) { rows.append(hit) }
        if rows.count >= 1 {
            section.font = PanelControl(name: "Font", point: CGPoint(x: rows[0].rect.midX, y: rows[0].rect.midY), rect: rows[0].rect, value: rows[0].text)
        }
        if rows.count >= 2 {
            let style = rows[1]
            section.fontStyle = PanelControl(name: "Font style", point: CGPoint(x: style.rect.midX, y: style.rect.midY), rect: style.rect, value: style.text)
            // The seven type buttons share its row, right of the dropdown: the last seven icons there.
            let icons = rowIcons(in: image, y: style.rect.midY, height: line * 2.2, from: style.rect.maxX + line, to: right, line: line)
            if icons.count >= typeButtonNames.count {
                section.typeButtons = zip(typeButtonNames, icons.suffix(typeButtonNames.count)).map { name, icon in
                    PanelControl(name: name, point: CGPoint(x: icon.rect.midX, y: icon.rect.midY), rect: icon.rect)
                }
            }
        }
        if let value {
            section.fontSize = PanelControl(name: "Font Size", point: CGPoint(x: value.rect.midX, y: value.rect.midY), rect: value.rect, value: String(value.value))
        }

        // Below the label: the slider, then the paragraph buttons, then tracking and leading.
        let bands = inkBands(in: image, top: label.rect.maxY + line * 0.3, bottom: min(1, label.rect.maxY + line * 9), from: left, to: right)
        var rest = bands
        if let slider = rest.first, slider.wide {
            // The slider: a line across the panel with a ring on it; the ring is the brightest spot.
            if let knob = brightestSpot(in: image, band: slider.rect) {
                section.sizeSlider = PanelControl(name: "Font Size slider", point: knob, rect: slider.rect,
                                                  value: String(format: "%.0f%%", (knob.x - slider.rect.minX) / max(0.001, slider.rect.width) * 100))
            }
            rest.removeFirst()
        }
        if let paragraph = rest.first {
            let icons = rowIcons(in: image, y: paragraph.rect.midY, height: paragraph.rect.height + line * 0.6, from: left, to: right, line: line)
            if icons.count == paragraphButtonNames.count {
                section.paragraphButtons = zip(paragraphButtonNames, icons).map { name, icon in
                    PanelControl(name: name, point: CGPoint(x: icon.rect.midX, y: icon.rect.midY), rect: icon.rect, on: icon.boxed)
                }
            }
            // Tracking and leading: the row after, each an icon and a blue number. The digits are too
            // small and isolated for OCR on the whole window, so each blue number is found by colour
            // and read magnified, the way Font Size's value is.
            if rest.count >= 2 {
                let numbers = blueClusters(in: image, band: rest[1].rect)
                let read = numbers.compactMap { rect -> PanelControl? in
                    guard let value = readNumber(in: image, rect: rect) else { return nil }
                    return PanelControl(name: "", point: CGPoint(x: rect.midX, y: rect.midY), rect: rect, value: value)
                }
                if read.count >= 1 { section.tracking = read[0]; section.tracking?.name = "Tracking" }
                if read.count >= 2 { section.leading = read[1]; section.leading?.name = "Leading" }
            }
        }
        return section
    }

    /// Horizontal bands below a point that carry ink, top to bottom. `wide` marks a band whose ink
    /// spans most of the width: a slider or divider rather than a row of controls.
    private static func inkBands(in image: CGImage, top: CGFloat, bottom: CGFloat, from left: CGFloat, to right: CGFloat) -> [(rect: CGRect, wide: Bool)] {
        let rect = CGRect(x: left * CGFloat(image.width), y: top * CGFloat(image.height),
                          width: (right - left) * CGFloat(image.width), height: (bottom - top) * CGFloat(image.height))
        guard rect.width > 8, rect.height > 8 else { return [] }
        let columns = max(8, Int(rect.width)), rows = max(8, Int(rect.height))
        let rgba = patch(of: image, rect: rect, width: columns, height: rows)
        func luma(_ x: Int, _ y: Int) -> Int { let i = (y * columns + x) * 4; return (Int(rgba[i]) * 30 + Int(rgba[i + 1]) * 59 + Int(rgba[i + 2]) * 11) / 100 }
        let background = (0 ..< columns).map { luma($0, 0) }.sorted()[columns / 2]
        let share = (0 ..< rows).map { y in Double((0 ..< columns).filter { abs(luma($0, y) - background) > 24 }.count) / Double(columns) }
        var bands: [(rect: CGRect, wide: Bool)] = []
        var y = 0
        while y < rows {
            guard share[y] > 0.004 else { y += 1; continue }
            var end = y
            while end + 1 < rows, share[end + 1] > 0.004 { end += 1 }
            let wide = share[y ... end].max() ?? 0 > 0.6
            let band = CGRect(x: left, y: top + CGFloat(y) / CGFloat(rows) * (bottom - top),
                              width: right - left, height: CGFloat(end - y + 1) / CGFloat(rows) * (bottom - top))
            if end - y >= 1 { bands.append((band, wide)) }
            y = end + 1
        }
        return bands
    }

    /// Icons along a row, left to right: clusters of ink of about a line's size. `boxed` marks one
    /// drawn on a lighter box, Premiere's look for a toggle that is on.
    private static func rowIcons(in image: CGImage, y: CGFloat, height: CGFloat, from left: CGFloat, to right: CGFloat, line: CGFloat) -> [(rect: CGRect, boxed: Bool)] {
        let pixels = CGRect(x: left * CGFloat(image.width), y: (y - height / 2) * CGFloat(image.height),
                            width: (right - left) * CGFloat(image.width), height: height * CGFloat(image.height))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard pixels.width > 8, pixels.height > 4 else { return [] }
        let columns = Int(pixels.width), rows = Int(pixels.height)
        let rgba = patch(of: image, rect: pixels, width: columns, height: rows)
        func luma(_ x: Int, _ y: Int) -> Int { let i = (y * columns + x) * 4; return (Int(rgba[i]) * 30 + Int(rgba[i + 1]) * 59 + Int(rgba[i + 2]) * 11) / 100 }
        var levels = [Int](); for x in stride(from: 0, to: columns, by: 2) { levels.append(luma(x, 0)); levels.append(luma(x, rows - 1)) }
        let background = levels.sorted()[levels.count / 2]
        let inked = (0 ..< columns).map { x in (0 ..< rows).contains { abs(luma(x, $0) - background) > 24 } }
        let gapLimit = max(2, Int(line * CGFloat(image.height) * 0.25))
        var clusters: [(Int, Int)] = []
        var x = 0
        while x < columns {
            guard inked[x] else { x += 1; continue }
            var end = x, gap = 0, scan = x + 1
            while scan < columns {
                if inked[scan] { end = scan; gap = 0 } else { gap += 1; if gap > gapLimit { break } }
                scan += 1
            }
            clusters.append((x, end)); x = end + 1
        }
        let linePixels = line * CGFloat(image.height)
        return clusters.compactMap { cluster -> (rect: CGRect, boxed: Bool)? in
            let width = CGFloat(cluster.1 - cluster.0 + 1)
            guard width >= linePixels * 0.4, width <= linePixels * 3.2 else { return nil }
            // Rows the cluster paints, for its extent, and how much of it is a flat lighter fill.
            var top = rows, bottom = -1, filled = 0, total = 0
            for yy in 0 ..< rows {
                for xx in cluster.0 ... cluster.1 {
                    let value = luma(xx, yy)
                    if abs(value - background) > 24 { top = min(top, yy); bottom = max(bottom, yy) }
                    if value > background + 18 && value < background + 90 { filled += 1 }
                    total += 1
                }
            }
            guard bottom >= top else { return nil }
            let rect = CGRect(x: (pixels.minX + CGFloat(cluster.0)) / CGFloat(image.width), y: (pixels.minY + CGFloat(top)) / CGFloat(image.height),
                              width: width / CGFloat(image.width), height: CGFloat(bottom - top + 1) / CGFloat(image.height))
            return (rect, Double(filled) / Double(max(1, total)) > 0.3)
        }
    }

    /// Runs of Premiere's blue (editable values) along a band, left to right, as rectangles.
    private static func blueClusters(in image: CGImage, band: CGRect) -> [CGRect] {
        let pixels = CGRect(x: band.minX * CGFloat(image.width), y: band.minY * CGFloat(image.height),
                            width: band.width * CGFloat(image.width), height: band.height * CGFloat(image.height))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard pixels.width > 8, pixels.height > 2 else { return [] }
        let columns = Int(pixels.width), rows = Int(pixels.height)
        let rgba = patch(of: image, rect: pixels, width: columns, height: rows)
        func blue(_ x: Int, _ y: Int) -> Bool {
            let i = (y * columns + x) * 4
            return Int(rgba[i + 2]) > 120 && Int(rgba[i + 2]) - Int(rgba[i]) > 50
        }
        var found: [CGRect] = []
        var x = 0
        while x < columns {
            guard (0 ..< rows).contains(where: { blue(x, $0) }) else { x += 1; continue }
            var end = x, gap = 0, scan = x + 1
            while scan < columns {
                if (0 ..< rows).contains(where: { blue(scan, $0) }) { end = scan; gap = 0 } else { gap += 1; if gap > rows / 2 { break } }
                scan += 1
            }
            let ys = (0 ..< rows).filter { y in (x ... end).contains { blue($0, y) } }
            if let top = ys.first, let bottom = ys.last, bottom - top >= 3 {
                found.append(CGRect(x: (pixels.minX + CGFloat(x)) / CGFloat(image.width), y: (pixels.minY + CGFloat(top)) / CGFloat(image.height),
                                    width: CGFloat(end - x + 1) / CGFloat(image.width), height: CGFloat(bottom - top + 1) / CGFloat(image.height)))
            }
            x = end + 1
        }
        return found
    }

    /// Reads a short number in a small area. Tiny isolated digits are lost at window scale, and a lone
    /// digit is often missed even magnified, so the area is enlarged, turned into dark digits on white
    /// with a margin, and read accurately first, then fast (which reads a lone 0 as the letter o).
    private static func readNumber(in image: CGImage, rect: CGRect) -> String? {
        let source = CGRect(x: rect.minX * CGFloat(image.width), y: rect.minY * CGFloat(image.height),
                            width: rect.width * CGFloat(image.width), height: rect.height * CGFloat(image.height))
            .insetBy(dx: -2, dy: -2).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard source.width > 1, source.height > 1, let crop = image.cropping(to: source) else { return nil }
        let lookalikes: [Character: Character] = ["o": "0", "O": "0", "l": "1", "I": "1", "|": "1"]
        for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
            var votes: [String: Int] = [:]
            for scale in [4, 8] {
                let inner = (width: Int(source.width) * scale, height: Int(source.height) * scale), margin = 40
                guard let enlarged = CGContext(data: nil, width: inner.width, height: inner.height, bitsPerComponent: 8, bytesPerRow: inner.width,
                                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
                      let page = CGContext(data: nil, width: inner.width + margin * 2, height: inner.height + margin * 2, bitsPerComponent: 8,
                                           bytesPerRow: inner.width + margin * 2, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
                else { continue }
                enlarged.interpolationQuality = .high
                enlarged.draw(crop, in: CGRect(x: 0, y: 0, width: inner.width, height: inner.height))
                if let data = enlarged.data?.bindMemory(to: UInt8.self, capacity: inner.width * inner.height) {
                    for i in 0 ..< inner.width * inner.height { data[i] = 255 - data[i] }
                }
                page.setFillColor(gray: 1, alpha: 1); page.fill(CGRect(x: 0, y: 0, width: page.width, height: page.height))
                guard let digits = enlarged.makeImage() else { continue }
                page.draw(digits, in: CGRect(x: margin, y: margin, width: inner.width, height: inner.height))
                guard let prepared = page.makeImage() else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = level; request.usesLanguageCorrection = false; request.minimumTextHeight = 0
                try? VNImageRequestHandler(cgImage: prepared, options: [:]).perform([request])
                for observation in request.results ?? [] {
                    guard let raw = observation.topCandidates(1).first?.string else { continue }
                    let text = String(raw.replacingOccurrences(of: " ", with: "").map { lookalikes[$0] ?? $0 })
                    guard !text.isEmpty, text.count <= 5, text.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }),
                          text.contains(where: \.isNumber) else { continue }
                    votes[text, default: 0] += 1
                }
            }
            if let winner = votes.max(by: { $0.value < $1.value })?.key { return winner }
        }
        return nil
    }

    /// The brightest small spot in a band: the slider's ring.
    private static func brightestSpot(in image: CGImage, band: CGRect) -> CGPoint? {
        let pixels = CGRect(x: band.minX * CGFloat(image.width), y: band.minY * CGFloat(image.height),
                            width: band.width * CGFloat(image.width), height: max(2, band.height * CGFloat(image.height)))
        let columns = max(4, Int(pixels.width)), rows = max(2, Int(pixels.height))
        let rgba = patch(of: image, rect: pixels, width: columns, height: rows)
        var best = (value: -1, x: 0, y: 0)
        for y in 0 ..< rows {
            for x in 0 ..< columns {
                let i = (y * columns + x) * 4
                let value = (Int(rgba[i]) * 30 + Int(rgba[i + 1]) * 59 + Int(rgba[i + 2]) * 11) / 100
                if value > best.value { best = (value, x, y) }
            }
        }
        guard best.value > 120 else { return nil }
        // The ring's centre: the middle of the bright pixels near the brightest one.
        var sumX = 0, sumY = 0, count = 0
        let reach = rows * 2
        for y in 0 ..< rows {
            for x in max(0, best.x - reach) ..< min(columns, best.x + reach) {
                let i = (y * columns + x) * 4
                let value = (Int(rgba[i]) * 30 + Int(rgba[i + 1]) * 59 + Int(rgba[i + 2]) * 11) / 100
                if value >= best.value * 85 / 100 { sumX += x; sumY += y; count += 1 }
            }
        }
        let centre = count > 0 ? (x: Double(sumX) / Double(count), y: Double(sumY) / Double(count)) : (x: Double(best.x), y: Double(best.y))
        return CGPoint(x: (pixels.minX + CGFloat(centre.x)) / CGFloat(image.width), y: (pixels.minY + CGFloat(centre.y)) / CGFloat(image.height))
    }
}
