import AppKit
import SwiftUI

/// A floating heads-up display shown while a routine runs, because Adobe is focused then and the
/// main window is hidden behind it. The panel never takes focus and never receives mouse events, so
/// clicks pass straight through to the editor; Desktop.checkHit is told to ignore it.
@MainActor
final class RunOverlay {
    private var panel: NSPanel?
    private var inspectionPanel: NSPanel?
    private let inspection = InspectionModel()
    var inspectionWindowID: CGWindowID { CGWindowID(inspectionPanel?.windowNumber ?? 0) }
    var inspectionVisible: Bool { inspectionPanel?.isVisible == true }
    private let model = OverlayModel()

    var windowID: CGWindowID { CGWindowID(panel?.windowNumber ?? 0) }

    func show(on frame: CGRect) {
        if panel == nil {
            let hosting = NSHostingView(rootView: OverlayView(model: model))
            let created = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            created.contentView = hosting
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.level = .screenSaver                 // above a full-screen editor
            created.ignoresMouseEvents = true            // never intercept a click meant for Adobe
            created.hidesOnDeactivate = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            created.isReleasedWhenClosed = false
            created.animationBehavior = .none          // appear at once, without the zoom-in
            panel = created
        }
        guard let panel else { return }
        let size = NSSize(width: 460, height: 96)
        panel.setContentSize(size)
        // Cocoa screen coordinates have their origin at the bottom left; window frames do not.
        let screenHeight = NSScreen.screens.first?.frame.height ?? frame.maxY
        let x = frame.midX - size.width / 2
        let y = screenHeight - frame.minY - size.height - 18
        panel.setFrameOrigin(NSPoint(x: x, y: max(12, y)))
        panel.orderFrontRegardless()
    }

    func update(step: Int, limit: Int, headline: String, detail: String, confidence: Double?, paused: Bool) {
        model.step = step
        model.limit = limit
        model.headline = headline
        model.detail = detail
        model.confidence = confidence
        model.paused = paused
    }

    /// Shows the style you picked beside the progress, or clears it with nil.
    func setReference(_ image: CGImage?, label: String) {
        model.reference = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        model.referenceLabel = label
    }

    func configureInspection(boxes: Bool, text: Bool, details: Bool) {
        inspection.showBoxes = boxes; inspection.showText = text; inspection.showDetails = details
    }

    func inspect(_ shot: Observation) {
        inspection.boxes = Self.ocrBoxes(shot.text, image: shot.image)
        // The legend shows when the text was read; the grid boxes are redrawn from every look's pixels.
        inspection.stamp = shot.textTimestamp.formatted(date: .omitted, time: .standard)
        if inspectionPanel == nil {
            let created = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.contentView = NSHostingView(rootView: InspectionView(model: inspection))
            created.isOpaque = false; created.backgroundColor = .clear; created.hasShadow = false
            created.level = .screenSaver; created.ignoresMouseEvents = true; created.hidesOnDeactivate = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            created.isReleasedWhenClosed = false
            created.animationBehavior = .none          // appear at once, without the zoom-in
            inspectionPanel = created
        }
        let frame = shot.window.frame
        let screenHeight = NSScreen.screens.first?.frame.height ?? frame.maxY
        // Live looks arrive up to 30 times a second; only move or raise the panel when that changes something.
        let placed = CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
        if inspectionPanel?.frame != placed { inspectionPanel?.setFrame(placed, display: true) }
        if inspectionPanel?.isVisible != true { inspectionPanel?.orderFrontRegardless() }
        if panel?.isVisible == true { panel?.orderFrontRegardless() }
    }

    private static var sectionCache: (hits: [TextHit], size: (Int, Int), section: Desktop.TextSection?)?

    static func ocrBoxes(_ hits: [TextHit], image: CGImage? = nil) -> [InspectionBox] {
        let eligible = Desktop.captionBlocks(in: hits).flatMap { $0 }
        // With the style browser open, show its grid as the pass counts it: one box per rounded tile,
        // each row in its own colour. OCR's "Ag" boxes merge neighbouring tiles, so they are left out.
        var styleBoxes: [InspectionBox] = []
        var styleLeft: CGFloat?
        if let image, let left = Desktop.stylePanelLeft(in: hits) {
            let grid = Desktop.styleGrid(in: hits, image: image, left: left)
            let cells = grid.cells
            // Rows are numbered from the top of the browser, not of the view, and keep their number and
            // colour as the list scrolls. "R?" means it scrolled further than could be followed; any
            // look at the top of the list re-anchors the count.
            let offset = Desktop.styleRows.observe(cells, image: image, atTop: grid.atTop)
            if !cells.isEmpty {
                styleLeft = left
                for (row, cellsInRow) in cells.enumerated() {
                    let absolute = offset.map { $0 + row }
                    let name = absolute.map { "R\($0 + 1)" } ?? "R?"
                    // The row's number, just left of its first tile.
                    if let first = cellsInRow.first {
                        let width = first.width * 0.2
                        styleBoxes.append(InspectionBox(rect: CGRect(x: max(0, first.minX - width - first.width * 0.04), y: first.midY - first.height * 0.18,
                                                                     width: width, height: first.height * 0.36),
                                                        label: absolute.map { "\($0 + 1)" } ?? "?", kind: .styleRow(absolute ?? 99), marker: true))
                    }
                    for (column, cell) in cellsInRow.enumerated() {
                        styleBoxes.append(InspectionBox(rect: cell, label: "\(name) C\(column + 1)", kind: .styleRow(absolute ?? 99),
                                                        text: "\(name) C\(column + 1)",
                                                        detail: String(format: "Style tile %@ C%d · x %.3f y %.3f", name, column + 1, cell.minX, cell.minY)))
                    }
                }
            }
        } else if let image {
            _ = Desktop.styleRows.observe([], image: image, panelOpen: false)
        }
        // The Properties panel's Text section as named controls. Read once per text reading, not per
        // frame: its small numbers are read magnified, which costs a few OCR passes.
        var controlBoxes: [InspectionBox] = []
        if let image {
            let section: Desktop.TextSection?
            if let cached = sectionCache, cached.hits == hits, cached.size == (image.width, image.height) { section = cached.section }
            else { section = Desktop.textSection(in: hits, image: image); sectionCache = (hits, (image.width, image.height), section) }
            for control in section?.all ?? [] {
                let name = control.name + (control.value.map { ": \($0)" } ?? "") + (control.on == true ? " · on" : "")
                controlBoxes.append(InspectionBox(rect: control.rect.insetBy(dx: -0.002, dy: -0.002), label: name, kind: .control(on: control.on),
                                                  text: name, detail: String(format: "%@ · click at x %.3f y %.3f", name, control.point.x, control.point.y)))
            }
        }
        let controlled = controlBoxes.map(\.rect)
        let shown = (styleLeft.map { left in hits.filter { !Desktop.isStyleTileHit($0, left: left) } } ?? hits)
            .filter { hit in !controlled.contains { $0.intersects(hit.rect) } }
        return styleBoxes + controlBoxes + shown.map { hit in
            let candidate = eligible.contains(hit)
            return InspectionBox(rect: hit.rect,
                                 label: "\(candidate ? "Caption candidate" : "Excluded by size filter"): \(hit.text)",
                                 kind: candidate ? .candidate : .excluded,
                                 text: hit.text,
                                 detail: String(format: "%@ · x %.3f y %.3f w %.3f h %.3f", candidate ? "Caption candidate" : "Excluded by size filter", hit.rect.minX, hit.rect.minY, hit.rect.width, hit.rect.height))
        }
    }

    func inspectDecision(rect: CGRect, label: String, kind: InspectionBox.Kind) {
        guard inspectionPanel?.isVisible == true else { return }
        inspection.boxes.append(InspectionBox(rect: rect, label: label, kind: kind))
    }

    func hideInspection() { inspectionPanel?.orderOut(nil); inspection.boxes = [] }
    func hide() { panel?.orderOut(nil); hideInspection() }

}

private final class OverlayModel: ObservableObject {
    @Published var step = 0
    @Published var limit = 0
    @Published var headline = "Starting…"
    @Published var detail = ""
    @Published var confidence: Double?
    @Published var paused = false
    @Published var reference: NSImage?
    @Published var referenceLabel = ""
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    private let accent = Color(red: 0.43, green: 0.88, blue: 0.73)

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill((model.paused ? Color.orange : accent).opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: model.paused ? "pause.fill" : "cursorarrow.motionlines")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(model.paused ? .orange : accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(model.headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    if model.limit > 1, model.step > 0 {
                        Text("step \(model.step) of \(model.limit)").font(.system(size: 10))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.white.opacity(0.12), in: Capsule()).foregroundStyle(.white.opacity(0.85))
                    }
                    if let confidence = model.confidence {
                        Text("\(Int(confidence * 100))%").font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(confidence < 0.9 ? .orange : accent)
                    }
                }
                if !model.detail.isEmpty {
                    Text(model.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                }
                Text("Move the mouse to pause · Escape stops")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            if let reference = model.reference {
                // The style you picked, so you can see what every remaining phrase receives.
                VStack(spacing: 3) {
                    Image(nsImage: reference).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(0.8), lineWidth: 1.5))
                    Text(model.referenceLabel).font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(width: 460, height: 96, alignment: .leading)
        .background(Color(red: 0.07, green: 0.09, blue: 0.11).opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.14)))
    }
}

struct InspectionBox: Identifiable {
    enum Kind: Equatable { case candidate, excluded, selected, style, styleRow(Int), control(on: Bool?) }
    let id = UUID()
    let rect: CGRect
    let label: String
    let kind: Kind
    var text: String = ""
    var detail: String = ""
    /// Drawn as a filled badge with its label centred, regardless of the text settings.
    var marker = false
    init(rect: CGRect, label: String, kind: Kind, text: String = "", detail: String = "", marker: Bool = false) {
        self.rect = rect; self.label = label; self.kind = kind; self.text = text; self.detail = detail; self.marker = marker
    }
    func displayedLabel(text showText: Bool, details showDetails: Bool) -> String {
        var parts: [String] = []
        if showText && !text.isEmpty { parts.append(text) }
        if showDetails { parts.append(detail.isEmpty ? label : detail) }
        return parts.joined(separator: " · ")
    }
    var color: Color {
        switch kind {
        case .candidate: return .yellow
        case .excluded: return .gray
        case .selected: return .green
        case .style: return .cyan
        case let .control(on): return on == true ? .green : .teal
        case let .styleRow(row):
            guard row != 99 else { return .gray }
            let palette: [Color] = [.orange, .pink, .purple, .mint, .indigo, .brown]
            return palette[row % palette.count]
        }
    }
}

private final class InspectionModel: ObservableObject {
    @Published var boxes: [InspectionBox] = []
    @Published var stamp = ""
    @Published var showBoxes = true
    @Published var showText = true
    @Published var showDetails = true
}

private struct InspectionView: View {
    @ObservedObject var model: InspectionModel
    var body: some View {
        Canvas { context, size in
            for box in model.boxes {
                let rect = CGRect(x: box.rect.minX * size.width, y: box.rect.minY * size.height,
                                  width: box.rect.width * size.width, height: box.rect.height * size.height)
                if box.marker {
                    guard model.showBoxes else { continue }
                    let badge = Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.3)
                    context.fill(badge, with: .color(box.color.opacity(0.92)))
                    let number = context.resolve(Text(box.label).font(.system(size: max(10, min(rect.height * 0.62, 22)), weight: .bold, design: .rounded)).foregroundColor(.black))
                    context.draw(number, at: CGPoint(x: rect.midX, y: rect.midY))
                    continue
                }
                if model.showBoxes {
                    context.stroke(Path(rect), with: .color(box.color.opacity(0.9)), lineWidth: { if case .excluded = box.kind { return 1 } else { return 2 } }())
                }
                let label = box.displayedLabel(text: model.showText, details: model.showDetails)
                guard !label.isEmpty else { continue }
                let text = Text(String(label.prefix(160))).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(box.color)
                let resolved = context.resolve(text)
                let measured = resolved.measure(in: CGSize(width: min(390, size.width), height: model.showDetails ? 32 : 16))
                let labelRect = CGRect(x: min(max(0, rect.minX), max(0, size.width - measured.width - 6)),
                                       y: max(0, rect.minY - measured.height - 1), width: measured.width + 6, height: measured.height)
                context.fill(Path(labelRect), with: .color(.black.opacity(0.85)))
                context.draw(resolved, in: labelRect.insetBy(dx: 3, dy: 0))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if model.showDetails { Text("OCR snapshot \(model.stamp) · Yellow: caption candidate · Gray: filtered out · Green: phrase match · Cyan: your style · Teal: panel controls (green when on) · other colours: style browser rows")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white).padding(7).background(.black.opacity(0.85)).padding(8) }
        }
        .allowsHitTesting(false)
    }
}
