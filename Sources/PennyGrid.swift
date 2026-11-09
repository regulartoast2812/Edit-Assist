import SwiftUI

/// A table drawn as one canvas, its header still buttons that sort (2026-11-09: drawn as a view per cell, each with
/// selectable text and a tooltip, the hour table was 392 views and each creatives table 562, and scrolling to them
/// crawled; drawn like this each is one). Pointing at a row lights it and shows its tip, which says what a tooltip did.
struct PennyGrid: View {
    enum Align: Equatable { case leading, trailing, center }

    struct Column: Equatable {
        var name: String
        /// nil: the column takes what the others leave.
        var width: CGFloat?
        var align = Align.trailing
        var sorts = true
        var inset: CGFloat = 0
    }

    /// An hour's ROAS as a filled slider: the fill from 0 to its average in its colour, a lighter band from its bad
    /// stretch to its good, a white tick at breakeven, capped at `top`.
    struct Slider: Equatable { var roas: Double?; var floor: Double?; var ceiling: Double?; var breakeven: Double; var top: Double; var color: Color }

    struct Cell: Equatable {
        var text = ""
        var color: Color? = nil
        var size: CGFloat = 11
        var weight = Font.Weight.regular
        /// A smaller line under the text, as a creative's publisher.
        var sub: String? = nil
        var slider: Slider? = nil
    }

    struct Row: Identifiable {
        var id: String
        var cells: [Cell]
        /// The row's wash and the stripe at its left, in its verdict's colour; nil for plain.
        var shade: Color? = nil
        var tip: String
        var tipLines: [PennyTipLine] = []
        var tipNote: String? = nil
    }

    let columns: [Column]
    let rows: [Row]
    @Binding var sort: String
    var rowHeight: CGFloat = 24
    var gap: CGFloat = 2
    /// Rows on rounded washes (the hours) or plain with a line between (creatives, campaigns).
    var washed = true

    static let spacing: CGFloat = 6
    static let lead: CGFloat = 7
    static let trail: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            GridHover(rows: rows, rowHeight: rowHeight, gap: gap) {
                GridCanvas(columns: columns, cells: rows.map(\.cells), shades: rows.map(\.shade), rowHeight: rowHeight, gap: gap, washed: washed)
                    .equatable()
            }
            .frame(height: CGFloat(rows.count) * (rowHeight + gap))
            .padding(.top, 3)
        }
    }

    var header: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                let alignment: Alignment = column.align == .leading ? .leading : column.align == .center ? .center : .trailing
                let label = Text(L(column.name) + (sort == column.name ? " ↓" : "")).lineLimit(1)
                    .padding(.leading, column.inset)
                    .frame(minWidth: column.width, maxWidth: column.width ?? .infinity, alignment: alignment)
                if column.sorts { Button { sort = column.name } label: { label }.buttonStyle(.plain) } else { label }
            }
        }
        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        .padding(.leading, Self.lead).padding(.trailing, Self.trail).padding(.vertical, 4)
    }

    /// Where each column starts and how wide it is, the one without a width taking what's left.
    static func frames(_ columns: [Column], width: CGFloat) -> [(x: CGFloat, width: CGFloat)] {
        let fixed = columns.compactMap(\.width).reduce(0, +)
        let rest = max(0, width - lead - trail - fixed - spacing * CGFloat(max(columns.count - 1, 0)))
        var x = lead
        return columns.map { column in
            let width = column.width ?? rest
            defer { x += width + spacing }
            return (x, width)
        }
    }
}

/// The rows themselves: drawn again only when they change, never on hover.
private struct GridCanvas: View, Equatable {
    let columns: [PennyGrid.Column]
    let cells: [[PennyGrid.Cell]]
    let shades: [Color?]
    let rowHeight: CGFloat
    let gap: CGFloat
    let washed: Bool

    var body: some View {
        Canvas { context, size in
            let frames = PennyGrid.frames(columns, width: size.width)
            for (index, row) in cells.enumerated() {
                let top = CGFloat(index) * (rowHeight + gap), mid = top + rowHeight / 2
                if washed {
                    let shade = shades[index]
                    context.fill(Path(roundedRect: CGRect(x: 0, y: top, width: size.width, height: rowHeight), cornerRadius: 4),
                                 with: .color(shade?.opacity(0.1) ?? .white.opacity(0.02)))
                    if let shade {
                        context.fill(Path(roundedRect: CGRect(x: 0, y: top, width: 3, height: rowHeight), cornerRadius: 1.5), with: .color(shade.opacity(0.9)))
                    }
                } else if index < cells.count - 1 {
                    context.fill(Path(CGRect(x: 0, y: top + rowHeight + gap / 2 - 0.25, width: size.width, height: 0.5)), with: .color(.white.opacity(0.1)))
                }
                for (column, frame) in zip(columns.indices, frames) where column < row.count {
                    let cell = row[column], spec = columns[column]
                    if let slider = cell.slider {
                        Self.draw(slider, in: CGRect(x: frame.x, y: mid - 7, width: frame.width, height: 14), context)
                        continue
                    }
                    let room = frame.width - spec.inset
                    let text = PennyStyle.fit(context, cell.text, cell.size, cell.color ?? .primary, cell.weight, width: room)
                    let y = cell.sub == nil ? mid : mid - 6
                    switch spec.align {
                    case .leading: context.draw(text, at: CGPoint(x: frame.x + spec.inset, y: y), anchor: .leading)
                    case .trailing: context.draw(text, at: CGPoint(x: frame.x + frame.width, y: y), anchor: .trailing)
                    case .center: context.draw(text, at: CGPoint(x: frame.x + frame.width / 2, y: y), anchor: .center)
                    }
                    if let sub = cell.sub, !sub.isEmpty {
                        context.draw(PennyStyle.fit(context, sub, 9, .secondary, .regular, width: room), at: CGPoint(x: frame.x + spec.inset, y: mid + 7), anchor: .leading)
                    }
                }
            }
        }
    }

    static func draw(_ slider: PennyGrid.Slider, in rect: CGRect, _ context: GraphicsContext) {
        let x = { (roas: Double) in rect.minX + rect.width * min(max(roas, 0), slider.top) / slider.top }
        let mid = rect.midY
        context.fill(Path(roundedRect: CGRect(x: rect.minX, y: mid - 3, width: rect.width, height: 6), cornerRadius: 3), with: .color(.white.opacity(0.08)))
        if let floor = slider.floor, let ceiling = slider.ceiling, ceiling > floor {
            let start = max(rect.minX, x(floor) - 4), end = min(rect.maxX, x(ceiling) + 4)
            context.fill(Path(roundedRect: CGRect(x: min(start, rect.maxX - 8), y: mid - 5, width: max(8, end - start), height: 10), cornerRadius: 5),
                         with: .color(slider.color.opacity(0.28)))
        }
        if let roas = slider.roas {
            context.fill(Path(roundedRect: CGRect(x: rect.minX, y: mid - 3, width: max(6, x(roas) - rect.minX), height: 6), cornerRadius: 3), with: .color(slider.color))
        }
        context.fill(Path(CGRect(x: x(slider.breakeven) - 0.75, y: mid - 6, width: 1.5, height: 12)), with: .color(.white.opacity(0.7)))
        if let roas = slider.roas {
            let dot = CGRect(x: min(max(x(roas) - 5, rect.minX), rect.maxX - 10), y: mid - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)), with: .color(PennyStyle.surface))
            context.fill(Path(ellipseIn: dot), with: .color(slider.color))
        }
    }
}

/// The row under the pointer, lit, with its tip beside the pointer: above the row in the table's lower half, so it
/// stays inside the panel.
private struct GridHover<Content: View>: View {
    let rows: [PennyGrid.Row]
    let rowHeight: CGFloat
    let gap: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var row: Int?
    @State private var x: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let pitch = rowHeight + gap
            content()
                .overlay(alignment: .topLeading) {
                    if let row, rows.indices.contains(row) {
                        RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.06))
                            .frame(width: geometry.size.width, height: rowHeight).offset(y: CGFloat(row) * pitch).allowsHitTesting(false)
                    }
                }
                .overlay(alignment: row.map { $0 >= rows.count / 2 } == true ? .bottomLeading : .topLeading) {
                    if let row, rows.indices.contains(row) {
                        let item = rows[row], below = row < rows.count / 2
                        ChartTip(title: item.tip, lines: item.tipLines, note: item.tipNote)
                            .offset(x: min(x + 14, max(0, geometry.size.width - ChartTip.width)),
                                    y: below ? CGFloat(row + 1) * pitch + 2 : CGFloat(row) * pitch - geometry.size.height - 4)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard case let .active(point) = phase else { row = nil; return }
                    let at = Int(point.y / pitch)
                    let inside = rows.indices.contains(at) && point.y - CGFloat(at) * pitch <= rowHeight ? at : nil
                    if inside != row { row = inside; x = point.x }
                }
        }
        .zIndex(row == nil ? 0 : 1)
    }
}
