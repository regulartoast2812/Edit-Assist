import SwiftUI
import Charts
import AppKit

/// A Grafana dashboard on Penny's page, drawn the way Grafana draws it: which dashboard and what time along the top, its
/// filters as Grafana's chips, then each row with its panels on the 24-column grid (stats, tables, bar gauges, pies,
/// charts, the clock, text); a closed row opens on a click and only then reads its panels (2026-11-05).
struct BoardView: View {
    @ObservedObject var board: PennyBoard
    @ObservedObject var desk: PennyDesk
    let user: Grafana.User

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            let filters = board.variables.filter { $0.hide < 2 }
            if !filters.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(filters) { variable in
                        FilterChip(variable: variable) { board.choose($0, for: variable.name) }
                    }
                }
            }
            if let trouble = board.trouble {
                Label(trouble, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
            }
            ForEach(board.dashboard.sections) { section in
                if !section.title.isEmpty { header(section) }
                if section.title.isEmpty || board.open.contains(section.id) {
                    GrafanaGrid {
                        ForEach(section.tiles) { tile in
                            PanelView(tile: tile, board: board)
                                .layoutValue(key: GridSpot.self, value: GridSpot.Spot(x: tile.x, y: tile.y, w: tile.w, h: tile.h))
                        }
                    }
                }
            }
        }
    }

    var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(desk.boards) { dashboard in
                    Button(dashboard.title) { desk.show(dashboard.uid) }
                }
            } label: {
                Label(board.dashboard.title, systemImage: "square.grid.2x2")
            }.fixedSize()
            Menu {
                ForEach(Grafana.spans, id: \.name) { preset in
                    Button(L(preset.name)) { board.choose(span: preset.span) }
                }
            } label: {
                Label(Grafana.name(of: board.span), systemImage: "clock")
            }.fixedSize()
            Button { board.load(settle: []) } label: { Image(systemName: "arrow.clockwise") }
                .help(L("Read the numbers again")).disabled(board.busy)
            if board.busy {
                ProgressView().controlSize(.small)
            } else if let updated = board.updated {
                Text(L("Read at %@", updated.formatted(date: .omitted, time: .shortened))).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { NSWorkspace.shared.open(board.link()) } label: { Label(L("Open in Grafana"), systemImage: "arrow.up.right.square") }
            Menu {
                Text(L("Signed in as %@", user.email.isEmpty ? user.login : user.email))
                Button(L("Read the dashboards again")) { desk.explore() }.disabled(desk.exploring)
                Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([PennyDesk.folder]) }
                Divider()
                Button(L("Sign out"), role: .destructive) { desk.signOut() }
            } label: {
                Image(systemName: "person.crop.circle")
            }.menuIndicator(.hidden).fixedSize().help(user.name.isEmpty ? user.login : user.name)
        }.controlSize(.small)
    }

    func header(_ section: Grafana.Section) -> some View {
        let open = board.open.contains(section.id)
        return Button { board.toggle(section.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).frame(width: 12)
                Text(Grafana.interpolate(section.title, with: board.variables, display: true)).font(.system(size: 14, weight: .semibold))
                if !open { Text(L("%@ panels", section.tiles.count)).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.top, 4)
    }
}

/// Grafana's grid: 24 columns, rows 30 points high with 8 between, each panel where the dashboard put it.
struct GrafanaGrid: Layout {
    static let cell: CGFloat = 30, gap: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let spots = subviews.map { $0[GridSpot.self] }
        let rows = CGFloat((spots.map { $0.y + $0.h }.max() ?? 0) - (spots.map(\.y).min() ?? 0))
        return CGSize(width: proposal.width ?? 900, height: max(0, rows * Self.cell + (rows - 1) * Self.gap))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let top = subviews.map { $0[GridSpot.self].y }.min() ?? 0
        let column = (bounds.width - 23 * Self.gap) / 24
        for view in subviews {
            let spot = view[GridSpot.self]
            view.place(at: CGPoint(x: bounds.minX + CGFloat(spot.x) * (column + Self.gap), y: bounds.minY + CGFloat(spot.y - top) * (Self.cell + Self.gap)),
                       proposal: ProposedViewSize(width: CGFloat(spot.w) * column + CGFloat(spot.w - 1) * Self.gap,
                                                  height: CGFloat(spot.h) * Self.cell + CGFloat(spot.h - 1) * Self.gap))
        }
    }
}

struct GridSpot: LayoutValueKey {
    struct Spot { var x, y, w, h: Int }
    static let defaultValue = Spot(x: 0, y: 0, w: 24, h: 8)
}

/// Grafana's named colours (its classic palette, the dark theme's shades), hex and rgb() colours. Text on a light page
/// takes the next darker shade, and white text the page's own colour, so the dark theme's choices stay readable.
struct GrafanaPaint {
    var red: Double, green: Double, blue: Double, alpha: Double = 1
    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
    var light: Bool { 0.299 * red + 0.587 * green + 0.114 * blue > 0.6 }
    func darker(_ amount: Double) -> Color { Color(red: red * amount, green: green * amount, blue: blue * amount, opacity: alpha) }

    static let shades: [String: [String]] = [
        "red": ["#FFA6B0", "#FF7383", "#F2495C", "#E02F44", "#C4162A"], "orange": ["#FFCB7D", "#FFB357", "#FF9830", "#FF780A", "#FA6400"],
        "yellow": ["#FFF899", "#FFEE52", "#FADE2A", "#F2CC0C", "#E0B400"], "green": ["#C8F2C2", "#96D98D", "#73BF69", "#56A64B", "#37872D"],
        "blue": ["#C0D8FF", "#8AB8FF", "#5794F2", "#3274D9", "#1F60C4"], "purple": ["#DEB6F2", "#CA95E5", "#B877D9", "#A352CC", "#8F3BB8"],
    ]
    static let palette = ["#73BF69", "#F2CC0C", "#8AB8FF", "#FF780A", "#F2495C", "#5794F2", "#B877D9", "#705DA0", "#37872D", "#FADE2A", "#447EBC", "#C15C17"]
        .compactMap { GrafanaPaint($0) }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }

    init?(_ name: String?, darker: Bool = false) {
        guard var name = name?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty, name != "text", name != "transparent" else { return nil }
        for (prefix, shift) in [("super-light-", 0), ("light-", 1), ("semi-dark-", 3), ("dark-", 4)] where name.hasPrefix(prefix) {
            if let shades = Self.shades[String(name.dropFirst(prefix.count))] { name = shades[min(4, shift + (darker ? 1 : 0))] }
        }
        if let shades = Self.shades[name] { name = shades[darker ? 3 : 2] }
        if name == "white" { name = "#ffffff" } else if name == "black" { name = "#000000" }
        if name.hasPrefix("#") {
            let hex = String(name.dropFirst())
            guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
            let shift = hex.count == 8 ? 8 : 0
            self.init(red: Double((value >> (16 + shift)) & 0xFF) / 255, green: Double((value >> (8 + shift)) & 0xFF) / 255,
                      blue: Double((value >> shift) & 0xFF) / 255, alpha: hex.count == 8 ? Double(value & 0xFF) / 255 : 1)
        } else if name.hasPrefix("rgb") {
            let parts = name.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count >= 3 else { return nil }
            self.init(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: parts.count > 3 ? parts[3] : 1)
        } else {
            return nil
        }
    }

    /// A colour for text on this page.
    static func text(_ name: String?, _ scheme: ColorScheme) -> Color? {
        guard let paint = GrafanaPaint(name, darker: scheme == .light) else { return nil }
        return scheme == .light && paint.light ? nil : paint.color
    }
}

/// One panel: its title (and description on hover), what it shows, and a menu to open it in Grafana or copy its table.
struct PanelView: View {
    let tile: Grafana.Tile
    @ObservedObject var board: PennyBoard
    @State private var hovering = false

    var body: some View {
        let outcome = board.outcomes[tile.id]
        let reading = board.reading.contains(tile.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(Grafana.interpolate(tile.title, with: board.variables, display: true)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if !tile.note.isEmpty { Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary).help(tile.note) }
                Spacer(minLength: 0)
                if case .failed(let reason)? = outcome { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.red).help(reason) }
                if reading { ProgressView().controlSize(.mini) }
                Menu {
                    Button(L("Open in Grafana")) { NSWorkspace.shared.open(board.link(panel: tile.id)) }
                    if case .frames(let frames)? = outcome, let frame = frames.first, frame.rows > 0 {
                        Button(L("Copy as a table")) { copy(frame) }
                    }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().opacity(hovering ? 1 : 0)
            }.frame(height: 16)
            content(outcome, reading: reading).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
        .opacity(reading && outcome != nil ? 0.55 : 1)
        .onHover { hovering = $0 }
    }

    @ViewBuilder func content(_ outcome: PennyBoard.Outcome?, reading: Bool) -> some View {
        switch tile.type {
        case "text": TextTile(tile: tile)
        case "grafana-clock-panel": ClockTile(tile: tile)
        default:
            switch outcome {
            case .frames(let frames)?: data(frames)
            case .failed(let reason)?:
                Text(reason).font(.system(size: 10)).foregroundStyle(.red).lineLimit(4).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut?: Text(L("Signed out of Grafana")).font(.system(size: 11)).foregroundStyle(.secondary)
            case nil: if reading { ProgressView().controlSize(.small) } else { Color.clear }
            }
        }
    }

    @ViewBuilder func data(_ frames: [Grafana.Frame]) -> some View {
        switch tile.type {
        case "stat", "gauge": StatTile(tile: tile, frames: frames)
        case "table": TableTile(tile: tile, frames: frames)
        case "bargauge": BarGaugeTile(tile: tile, frames: frames)
        case "piechart": PieTile(tile: tile, frames: frames)
        case "crossian-highchart-bar", "barchart": ColumnTile(tile: tile, frames: frames)
        case "timeseries", "graph", "trend": LineTile(tile: tile, frames: frames)
        default:
            VStack(spacing: 6) {
                Text(L("Penny doesn't draw this kind of panel yet")).font(.system(size: 11)).foregroundStyle(.secondary)
                Button(L("Open in Grafana")) { NSWorkspace.shared.open(board.link(panel: tile.id)) }.controlSize(.small)
            }
        }
    }

    /// The panel's table as tab-separated lines, to paste into a sheet: raw numbers, dates as dates.
    func copy(_ frame: Grafana.Frame) {
        let columns = frame.columns.filter { !Grafana.look(for: $0, in: tile.fieldConfig).hidden }
        func clean(_ text: String) -> String { text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
        var lines = [columns.map { clean(Grafana.look(for: $0, in: tile.fieldConfig).displayName ?? $0.name) }.joined(separator: "\t")]
        for row in 0 ..< frame.rows {
            lines.append(columns.map { column -> String in
                let cell = column.at(row)
                if column.isTime, let time = cell.number { return Grafana.time(time, unit: nil) }
                return clean(Grafana.text(of: cell) ?? "")
            }.joined(separator: "\t"))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

/// A stat: the panel's number, big, coloured by its thresholds; several side by side when it shows several.
struct StatTile: View {
    let tile: Grafana.Tile
    let frames: [Grafana.Frame]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let figures = Grafana.figures(of: tile, frames)
        let mode = tile.options["colorMode"] as? String ?? "value"
        if figures.isEmpty {
            Text(L("No data")).font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            GeometryReader { space in
                let layout = space.size.width >= space.size.height ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 4))
                layout {
                    ForEach(figures) { figure in value(figure, named: figures.count > 1, mode: mode) }
                }
            }
        }
    }

    func value(_ figure: Grafana.Figure, named: Bool, mode: String) -> some View {
        let shown = figure.shown
        let color = figure.look.color(for: figure.number)
        let paint = GrafanaPaint(color)
        let tint: Color = mode == "none" ? .primary
            : mode == "background" ? (paint?.light == true ? .black.opacity(0.85) : .white)
            : GrafanaPaint.text(color, scheme) ?? .primary
        return GeometryReader { space in
            let size = min(space.size.height * (named ? 0.5 : 0.7), 64)
            VStack(spacing: 0) {
                if named { Text(figure.name).font(.system(size: max(9, size * 0.3))).foregroundStyle(.secondary).lineLimit(1) }
                Text("\(Text(shown.prefix + shown.text).font(.system(size: size, weight: .medium)))\(Text(shown.suffix).font(.system(size: size * 0.6, weight: .medium)))")
                    .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.25)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if mode == "background", let paint { RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [paint.darker(0.8), paint.color], startPoint: .leading, endPoint: .trailing)) }
            }
        }
    }
}

/// A table: Grafana's columns after its transformations, written by unit, cells coloured as the panel says, a click
/// on a heading to sort by it. Columns without a set width share what is left.
struct TableTile: View {
    let tile: Grafana.Tile
    let frames: [Grafana.Frame]
    @State private var sortColumn: Int?
    @State private var descending = true
    @Environment(\.colorScheme) private var scheme
    static let rowHeight: CGFloat = 26

    var body: some View {
        let frame = frames.first ?? Grafana.Frame(columns: [])
        let columns = frame.columns.indices.map { (index: $0, look: Grafana.look(for: frame.columns[$0], in: tile.fieldConfig)) }.filter { !$0.look.hidden }
        if frame.rows == 0 {
            Text(L("No data")).font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            GeometryReader { space in
                let widths = Self.widths(frame, columns, available: space.size.width)
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(columns.enumerated()), id: \.offset) { at, item in
                                heading(frame.columns[item.index], item.look, index: item.index, width: widths[at])
                            }
                        }.background(Color.primary.opacity(0.05))
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(order(frame), id: \.self) { row in
                                    HStack(spacing: 0) {
                                        ForEach(Array(columns.enumerated()), id: \.offset) { at, item in
                                            cell(frame.columns[item.index], item.look, row: row, width: widths[at])
                                        }
                                    }
                                    .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
                                }
                            }
                        }
                        footer(frame, columns, widths)
                    }.frame(width: max(widths.reduce(0, +), space.size.width), height: space.size.height, alignment: .topLeading)
                }
            }
        }
    }

    func alignment(_ column: Grafana.Column, _ look: Grafana.Look) -> Alignment {
        switch look.align {
        case "left"?: return .leading
        case "right"?: return .trailing
        case "center"?: return .center
        default: return column.isNumber ? .trailing : .leading
        }
    }

    func heading(_ column: Grafana.Column, _ look: Grafana.Look, index: Int, width: CGFloat) -> some View {
        Button {
            if sortColumn == index { if descending { descending = false } else { sortColumn = nil } } else { sortColumn = index; descending = true }
        } label: {
            HStack(spacing: 3) {
                Text(look.displayName ?? column.name).lineLimit(1)
                if sortColumn == index { Image(systemName: descending ? "arrow.down" : "arrow.up").font(.system(size: 9)) }
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6).frame(width: width, height: Self.rowHeight, alignment: alignment(column, look))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder func cell(_ column: Grafana.Column, _ look: Grafana.Look, row: Int, width: CGFloat) -> some View {
        let value = column.at(row)
        let text = Text(Grafana.written(value, in: column, look: look)).font(.system(size: 12)).lineLimit(1)
        let color = look.color(for: value.number)
        switch look.cell ?? "auto" {
        case "color-background", "color-background-solid":
            let paint = GrafanaPaint(color)
            text.foregroundStyle(paint.map { $0.light ? Color.black.opacity(0.85) : .white } ?? .primary)
                .padding(.horizontal, 6).frame(width: width, height: Self.rowHeight, alignment: alignment(column, look))
                .background { if let paint { LinearGradient(colors: [paint.darker(0.82), paint.color], startPoint: .leading, endPoint: .trailing) } }
        case "color-text":
            text.foregroundStyle(GrafanaPaint.text(color, scheme) ?? .primary)
                .padding(.horizontal, 6).frame(width: width, height: Self.rowHeight, alignment: alignment(column, look))
        default:
            text.padding(.horizontal, 6).frame(width: width, height: Self.rowHeight, alignment: alignment(column, look))
        }
    }

    @ViewBuilder func footer(_ frame: Grafana.Frame, _ columns: [(index: Int, look: Grafana.Look)], _ widths: [CGFloat]) -> some View {
        let footer = tile.options["footer"] as? [String: Any] ?? [:]
        if footer["show"] as? Bool == true {
            let reducer = (footer["reducer"] as? [String])?.first ?? "sum"
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { at, item in
                    let column = frame.columns[item.index]
                    let total = column.isNumber ? Grafana.reduce(column.cells, reducer).map { Grafana.show($0, unit: item.look.unit, decimals: item.look.decimals).full } : at == 0 ? L("Total") : nil
                    Text(total ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 6).frame(width: widths[at], height: Self.rowHeight, alignment: alignment(column, item.look))
                }
            }.background(Color.primary.opacity(0.05))
        }
    }

    func order(_ frame: Grafana.Frame) -> [Int] {
        let rows = Array(0 ..< frame.rows)
        guard let sortColumn, frame.columns.indices.contains(sortColumn) else { return rows }
        let column = frame.columns[sortColumn]
        return rows.sorted { a, b in
            switch (column.at(a), column.at(b)) {
            case (.number(let x), .number(let y)): return descending ? x > y : x < y
            case (.text(let x), .text(let y)): return (x.localizedStandardCompare(y) == .orderedAscending) != descending
            case (.none, _): return false
            case (_, .none): return true
            default: return a < b
            }
        }
    }

    static func widths(_ frame: Grafana.Frame, _ columns: [(index: Int, look: Grafana.Look)], available: CGFloat) -> [CGFloat] {
        var widths = columns.map { item -> CGFloat in
            if let width = item.look.width { return CGFloat(width) }
            let column = frame.columns[item.index]
            let longest = (0 ..< min(frame.rows, 40)).map { Grafana.written(column.at($0), in: column, look: item.look).count }.max() ?? 0
            return min(320, max(56, CGFloat(max(longest, (item.look.displayName ?? column.name).count + 2)) * 7.4 + 14))
        }
        let flexible = columns.indices.filter { columns[$0].look.width == nil }
        let spare = available - widths.reduce(0, +)
        if spare > 0, !flexible.isEmpty { for at in flexible { widths[at] += spare / CGFloat(flexible.count) } }
        return widths
    }
}

/// A bar gauge: one bar per value, from the panel's minimum to its maximum, coloured by its thresholds.
struct BarGaugeTile: View {
    let tile: Grafana.Tile
    let frames: [Grafana.Frame]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let figures = Grafana.figures(of: tile, frames)
        let numbers = figures.compactMap(\.number).filter(\.isFinite)
        let low = figures.first?.look.min ?? min(0, numbers.min() ?? 0)
        let high = max(figures.first?.look.max ?? (numbers.max() ?? 1), low + 0.000001)
        if figures.isEmpty {
            Text(L("No data")).font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            GeometryReader { space in
                let height = max(16, min(30, (space.size.height - CGFloat(figures.count - 1) * 4) / CGFloat(figures.count)))
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(figures) { figure in
                            let paint = GrafanaPaint(figure.look.color(for: figure.number) ?? (figure.look.colorMode?.hasPrefix("palette") == true ? nil : "green"))
                                ?? GrafanaPaint.palette[figure.id % GrafanaPaint.palette.count]
                            HStack(spacing: 8) {
                                Text(figure.name).font(.system(size: 11)).lineLimit(1).frame(width: space.size.width * 0.3, alignment: .leading).help(figure.name)
                                GeometryReader { bar in
                                    let fraction = max(0, min(1, ((figure.number ?? low) - low) / (high - low)))
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.06))
                                        RoundedRectangle(cornerRadius: 2).fill(paint.color).frame(width: bar.size.width * fraction)
                                    }
                                }
                                Text(figure.shown.full).font(.system(size: 11, weight: .medium)).monospacedDigit().lineLimit(1)
                                    .foregroundStyle(GrafanaPaint.text(figure.look.color(for: figure.number), scheme) ?? .primary).frame(width: 74, alignment: .trailing)
                            }.frame(height: height)
                        }
                    }
                }
            }
        }
    }
}

/// A pie or donut, with its legend beside it: each value and its share.
struct PieTile: View {
    let tile: Grafana.Tile
    let frames: [Grafana.Frame]

    var body: some View {
        let figures = Grafana.figures(of: tile, frames).filter { ($0.number ?? 0) > 0 && ($0.number ?? 0).isFinite }
        let total = figures.compactMap(\.number).reduce(0, +)
        let donut = tile.options["pieType"] as? String == "donut"
        if figures.isEmpty {
            Text(L("No data")).font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 12) {
                Chart(figures) { figure in
                    SectorMark(angle: .value("Value", figure.number ?? 0), innerRadius: .ratio(donut ? 0.55 : 0), angularInset: 1)
                        .foregroundStyle(paint(figure).color)
                }.chartLegend(.hidden).aspectRatio(1, contentMode: .fit)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(figures) { figure in
                            HStack(spacing: 6) {
                                Circle().fill(paint(figure).color).frame(width: 8, height: 8)
                                Text(figure.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(figure.shown.full).monospacedDigit()
                                Text(Grafana.fixed((figure.number ?? 0) / total * 100, 1) + "%").monospacedDigit().foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
                            }.font(.system(size: 11))
                        }
                    }
                }
            }
        }
    }

    func paint(_ figure: Grafana.Figure) -> GrafanaPaint {
        (figure.look.colorMode == "fixed" ? GrafanaPaint(figure.look.fixedColor) : nil) ?? GrafanaPaint.palette[figure.id % GrafanaPaint.palette.count]
    }
}

/// A column chart (the company's Highcharts panel): one field as columns, another as a line on its own scale at the right.
struct ColumnTile: View {
    let tile: Grafana.Tile
    let frames: [Grafana.Frame]
    struct Bar: Identifiable { let id: Int; let label: String; let value: Double; let line: Double? }

    var body: some View {
        let frame = frames.first ?? Grafana.Frame(columns: [])
        let axis = frame.columns.first(where: \.isTime) ?? frame.columns.first { !$0.isNumber }
        let barName = tile.options["ColumnChartGetColumnValue"] as? String
        let bar = frame.columns.first { $0.isNumber && $0.name == barName } ?? frame.columns.first { $0.isNumber && $0.name != axis?.name }
        let line = (tile.options["LineChartGetColumnValue"] as? String).flatMap { name in frame.columns.first { $0.isNumber && $0.name == name && $0.name != bar?.name } }
        if let bar, frame.rows > 0 {
            chart(frame: frame, axis: axis, bar: bar, line: line)
        } else {
            Text(L("No data")).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    func label(_ column: Grafana.Column, row cell: Grafana.Cell) -> String {
        guard let number = cell.number else { return Grafana.text(of: cell) ?? "" }
        guard column.isTime else { return Grafana.plain(number) }
        // An hour of the day comes as seconds since 1970, which Grafana takes it for.
        if number < 100_000_000 { return Grafana.plain(number / 1000) }
        let date = Date(timeIntervalSince1970: number / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.startOfDay(for: date) == date ? "MM-dd" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    func chart(frame: Grafana.Frame, axis: Grafana.Column?, bar: Grafana.Column, line: Grafana.Column?) -> some View {
        let bars = (0 ..< frame.rows).map { row in
            Bar(id: row, label: axis.map { label($0, row: $0.at(row)) } ?? String(row), value: bar.at(row).number ?? 0, line: line?.at(row).number)
        }
        let barLook = Grafana.look(for: bar, in: tile.fieldConfig)
        let lineLook = line.map { Grafana.look(for: $0, in: tile.fieldConfig) }
        let barTop = bars.map { abs($0.value) }.max() ?? 1
        let lineTop = bars.compactMap { $0.line.map(abs) }.filter(\.isFinite).max() ?? 0
        let scale = lineTop > 0 && barTop > 0 ? barTop / lineTop : 1
        let ticks = lineTop > 0 ? (0 ... 4).map { lineTop * Double($0) / 4 } : []
        let barColor = GrafanaPaint(tile.options["columnColor"] as? String)?.color ?? GrafanaPaint.palette[1].color
        let lineColor = GrafanaPaint(tile.options["lineColor"] as? String)?.color ?? GrafanaPaint.palette[0].color
        return VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(bars) { item in
                    BarMark(x: .value("x", item.label), y: .value(bar.name, item.value)).foregroundStyle(barColor)
                }
                ForEach(bars.filter { $0.line?.isFinite == true }) { item in
                    LineMark(x: .value("x", item.label), y: .value(line?.name ?? "", (item.line ?? 0) * scale)).foregroundStyle(lineColor)
                    PointMark(x: .value("x", item.label), y: .value(line?.name ?? "", (item.line ?? 0) * scale)).foregroundStyle(lineColor).symbolSize(14)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 12)) { _ in AxisValueLabel().font(.system(size: 9)) } }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel { if let number = value.as(Double.self) { Text(Grafana.show(number, unit: barLook.unit, decimals: nil).full).font(.system(size: 9)) } }
                }
                AxisMarks(position: .trailing, values: ticks.map { $0 * scale }) { value in
                    AxisValueLabel { if let number = value.as(Double.self) { Text(Grafana.show(number / scale, unit: lineLook?.unit, decimals: nil).full).font(.system(size: 9)) } }
                }
            }
            HStack(spacing: 12) {
                Label { Text(barLook.displayName ?? bar.name) } icon: { RoundedRectangle(cornerRadius: 1).fill(barColor).frame(width: 10, height: 8) }
                if let line { Label { Text(lineLook?.displayName ?? line.name) } icon: { Circle().fill(lineColor).frame(width: 8, height: 8) } }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

/// A time series: a line for each number over time.
struct LineTile: View {
    let tile: Grafana.Tile
    let frames: [Grafana.Frame]
    struct Point: Identifiable { let id: Int; let time: Date; let value: Double; let series: String }

    var body: some View {
        let points = self.points()
        let names = points.reduce(into: [String]()) { if !$0.contains($1.series) { $0.append($1.series) } }
        if points.isEmpty {
            Text(L("No data")).font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            Chart(points) { point in
                LineMark(x: .value("Time", point.time), y: .value("Value", point.value), series: .value("Series", point.series))
                    .foregroundStyle(by: .value("Series", point.series))
            }
            .chartForegroundStyleScale(domain: names, range: names.indices.map { GrafanaPaint.palette[$0 % GrafanaPaint.palette.count].color })
            .chartLegend(position: .bottom)
        }
    }

    func points() -> [Point] {
        var points: [Point] = []
        for frame in frames {
            guard let time = frame.columns.first(where: \.isTime) else { continue }
            for column in frame.columns where column.isNumber {
                for row in 0 ..< frame.rows {
                    guard let at = time.at(row).number, let value = column.at(row).number, value.isFinite else { continue }
                    points.append(Point(id: points.count, time: Date(timeIntervalSince1970: at / 1000), value: value, series: column.name))
                }
            }
        }
        return points
    }
}

/// Grafana's clock panel: the time where the panel says, in its format.
struct ClockTile: View {
    let tile: Grafana.Tile

    var body: some View {
        let settings = tile.options["timeSettings"] as? [String: Any] ?? [:]
        let size = Double((settings["fontSize"] as? String ?? "26").filter { $0.isNumber || $0 == "." }) ?? 26
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: tile.options["timezone"] as? String ?? "") ?? .current
        switch tile.options["clockType"] as? String {
        case "custom"?: formatter.dateFormat = Grafana.dateFormat(settings["customFormat"] as? String ?? "HH:mm:ss")
        case "12 hour"?: formatter.dateFormat = "h:mm:ss a"
        default: formatter.dateFormat = "HH:mm:ss"
        }
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(formatter.string(from: context.date)).font(.system(size: size, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.4).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A text panel: its Markdown, or its HTML as plain lines.
struct TextTile: View {
    let tile: Grafana.Tile

    var body: some View {
        let content = tile.options["content"] as? String ?? ""
        let plain = tile.options["mode"] as? String == "html" || content.contains("</")
            ? Grafana.plainText(fromHTML: content)
            : content.replacingOccurrences(of: "(?m)^#+\\s*", with: "", options: .regularExpression)
        ScrollView(.vertical) {
            Text((try? AttributedString(markdown: plain, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(plain))
                .font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A filter as Grafana's chip: its label, then what is chosen; a click opens the values to pick from, searchable.
struct FilterChip: View {
    let variable: Grafana.Variable
    let choose: ([String]) -> Void
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 0) {
                if variable.hide == 0 {
                    Text(variable.label.isEmpty ? variable.name : variable.label).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8).frame(height: 24).background(Color.primary.opacity(0.06))
                }
                HStack(spacing: 5) {
                    Text(variable.shown).lineLimit(1).frame(maxWidth: 220, alignment: .leading)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }.padding(.horizontal, 8).frame(height: 24)
            }
            .font(.system(size: 12))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.14)))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            FilterPicker(variable: variable, choose: choose, close: { open = false })
        }
    }
}

/// The values of a filter, with All first when it has it. Several can be ticked when the filter takes several; they
/// are used when the list closes, as in Grafana. Unticking every value goes back to All.
struct FilterPicker: View {
    let variable: Grafana.Variable
    let choose: ([String]) -> Void
    let close: () -> Void
    @State private var picked: Set<String>
    @State private var search = ""

    init(variable: Grafana.Variable, choose: @escaping ([String]) -> Void, close: @escaping () -> Void) {
        self.variable = variable; self.choose = choose; self.close = close
        _picked = State(initialValue: Set(variable.current))
    }

    var body: some View {
        let shown = search.isEmpty ? variable.options : variable.options.filter { $0.localizedCaseInsensitiveContains(search) }
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Search"), text: $search).textFieldStyle(.roundedBorder)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if variable.includeAll && search.isEmpty { row(Grafana.Variable.all, L("All")) }
                    ForEach(shown, id: \.self) { value in row(value, value) }
                }
            }.frame(height: min(360, CGFloat(shown.count + (variable.includeAll ? 1 : 0)) * 24 + 4))
            if variable.options.isEmpty { Text(L("No values")).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .padding(10).frame(width: 300)
        .onDisappear { apply() }
    }

    func row(_ value: String, _ title: String) -> some View {
        let ticked = picked.contains(value)
        return Button { toggle(value) } label: {
            HStack(spacing: 8) {
                Image(systemName: variable.multi ? (ticked ? "checkmark.square.fill" : "square") : (ticked ? "checkmark" : ""))
                    .foregroundStyle(ticked ? Color.accentColor : .secondary).frame(width: 14)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }.font(.system(size: 12)).frame(height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    func toggle(_ value: String) {
        guard variable.multi else { picked = [value]; close(); return }
        if value == Grafana.Variable.all { picked = [value]; return }
        picked.remove(Grafana.Variable.all)
        if picked.remove(value) == nil { picked.insert(value) }
        if picked.isEmpty { picked = variable.includeAll ? [Grafana.Variable.all] : [value] }
    }

    func apply() {
        let values = picked.contains(Grafana.Variable.all) ? [Grafana.Variable.all] : variable.options.filter(picked.contains) + picked.subtracting(variable.options).sorted()
        if Set(values) != Set(variable.current) { choose(values) }
    }
}
