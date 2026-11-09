import SwiftUI
import Charts

/// Penny's media-buying charts, redrawn (2026-11-06) after you found the first ones cluttered: one measure per chart,
/// never two axes on one, stacked so a day or an hour lines up down the page. ROAS on top (green from the profitable
/// line, yellow from breakeven, red under it), then spend split by how each hour did, then CBH. The same three colours
/// mean the same thing everywhere, Penny's read included. Hovering only redraws a thin layer over the charts, never
/// the charts, so the page stays quick.
enum PennyStyle {
    static let green = Color(red: 12 / 255, green: 163 / 255, blue: 12 / 255)
    static let yellow = Color(red: 250 / 255, green: 178 / 255, blue: 25 / 255)
    static let red = Color(red: 222 / 255, green: 68 / 255, blue: 68 / 255)
    static let orange = Color(red: 236 / 255, green: 131 / 255, blue: 90 / 255)
    static let blue = Color(red: 57 / 255, green: 135 / 255, blue: 229 / 255)
    static let violet = Color(red: 144 / 255, green: 133 / 255, blue: 233 / 255)
    static let muted = Color(red: 137 / 255, green: 135 / 255, blue: 129 / 255)
    static let grid = Color(red: 44 / 255, green: 44 / 255, blue: 42 / 255)
    static let baseline = Color(red: 72 / 255, green: 72 / 255, blue: 68 / 255)
    static let surface = Color(red: 26 / 255, green: 26 / 255, blue: 25 / 255)
    static let panel = Color.white.opacity(0.035)

    static func tone(_ tone: Ledger.Tone?) -> Color {
        switch tone {
        case .good: return green
        case .fair: return yellow
        case .bad: return red
        case nil: return muted
        }
    }

    /// Green from the profitable line, yellow from breakeven, red under it.
    static func roas(_ value: Double?, _ profit: Ledger.Profit) -> Color { tone(Ledger.tone(roas: value, profit)) }

    static func money(_ value: Double) -> Color { value < 0 ? red : green }

    static func verdict(_ verdict: Ledger.HourRead.Verdict) -> Color {
        switch verdict {
        case .reliable: return green
        case .volatile: return blue
        case .thin: return yellow
        case .losing: return muted
        case .costly: return orange
        case .dead: return red
        case .few, .idle: return muted.opacity(0.6)
        }
    }

    /// Dollars as an axis writes them: $950, $1.2K, $3.4M.
    static func short(_ value: Double) -> String {
        let size = abs(value), sign = value < 0 ? "-" : ""
        if size >= 1_000_000 { return sign + String(format: "$%.1fM", size / 1_000_000) }
        if size >= 1000 { return sign + String(format: size >= 10000 ? "$%.0fK" : "$%.1fK", size / 1000) }
        return sign + String(format: "$%.0f", size)
    }

    static func times(_ value: Double?) -> String { value.map { String(format: "%.2f×", $0) } ?? "–" }

    /// An hour as an axis writes it: 12a, 3p.
    static func hour(_ hour: Int) -> String { "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "a" : "p")" }

    static func day(_ day: String) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = Ledger.zone
        return Ledger.start(of: day)?.formatted(style) ?? day
    }

    /// Round axis steps for a top value: 1, 2, 2.5 or 5 times a power of ten, about four of them.
    static func ticks(_ low: Double, _ high: Double) -> [Double] {
        let span = max(high - low, 1e-9), raw = span / 4
        let power = pow(10, floor(log10(raw)))
        let step = [1, 2, 2.5, 5, 10].map { $0 * power }.first { $0 >= raw } ?? raw
        let first = (low / step).rounded(.up) * step
        return Array(stride(from: first, through: high, by: step))
    }
}

/// A titled panel: a heading, a line on how to read it, then its content.
struct PennyPanel<Content: View, Accessory: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if let note { Text(md: note).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                accessory()
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(PennyStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.07)))
    }
}

extension PennyPanel where Accessory == EmptyView {
    init(title: String, note: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, note: note, accessory: { EmptyView() }, content: content)
    }
}

/// A legend entry: a swatch (a bar, a line, a dashed line or a dot) and its name.
struct LegendKey: View {
    enum Shape { case bar, line, dashed, dot, band, tones }
    let name: String
    let color: Color
    var shape = Shape.bar

    var body: some View {
        HStack(spacing: 5) {
            switch shape {
            case .bar: RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            case .line: Capsule().fill(color).frame(width: 14, height: 2)
            case .dashed: Path { $0.move(to: CGPoint(x: 0, y: 1)); $0.addLine(to: CGPoint(x: 14, y: 1)) }.stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 14, height: 2)
            case .dot: Circle().fill(color).frame(width: 8, height: 8)
            case .band: RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.3)).frame(width: 7, height: 13)
                    .overlay(Circle().fill(color).frame(width: 6, height: 6))
            case .tones: HStack(spacing: 1) { ForEach([PennyStyle.red, PennyStyle.yellow, PennyStyle.green], id: \.self) { Rectangle().fill($0).frame(width: 4, height: 9) } }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            Text(name).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}

/// A line in a chart's tip: a name, a value, and the value's colour when it has a verdict.
struct PennyTipLine {
    var name: String
    var value: String
    var color: Color? = nil
}

/// The floating box beside a chart's pointer: a title and lines of numbers.
struct ChartTip: View {
    let title: String
    let lines: [PennyTipLine]
    static let width: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold))
            Divider().opacity(0.5)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 10) {
                    Text(line.name).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(line.value).fontWeight(.semibold).foregroundStyle(line.color ?? .primary)
                }.font(.system(size: 11).monospacedDigit())
            }
        }
        .padding(10).frame(width: Self.width)
        .background(Color(red: 30 / 255, green: 30 / 255, blue: 29 / 255), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .allowsHitTesting(false)
    }
}

// MARK: Columns

/// A column of Penny's stacked charts: a day, or an hour of the day.
struct PennySlot: Identifiable {
    var id: String
    /// The axis label; empty to leave the column unlabelled.
    var label: String
    var roas: Double?
    /// The bad and good day (10th and 90th percentile) of an hour over the days.
    var floor: Double? = nil
    var ceiling: Double? = nil
    /// The spend (a day, for an hour over the days) in hours that were profitable, above breakeven and below it.
    var good = 0.0, fair = 0.0, bad = 0.0
    var cbh = 0.0
    /// An hour with too few days to judge, drawn fainter.
    var faint = false
    /// A Saturday or Sunday, shaded behind its column.
    var weekend = false
    var title: String
    var tip: [PennyTipLine] = []
    var spent: Double { good + fair + bad }

    static func split(_ numbers: Ledger.Numbers, _ profit: Ledger.Profit, into slot: inout PennySlot, share: Double = 1) {
        guard numbers.spent > 0 else { return }
        switch Ledger.tone(roas: numbers.roas ?? 0, profit) {
        case .good: slot.good += numbers.spent * share
        case .fair: slot.fair += numbers.spent * share
        default: slot.bad += numbers.spent * share
        }
    }

    /// The days, oldest first: each day's spend split by how its hours did.
    static func days(_ reads: [Ledger.DayRead], profit: Ledger.Profit) -> [PennySlot] {
        let every = max(1, Int((Double(reads.count) / 14).rounded(.up)))
        return reads.enumerated().map { index, day in
            var slot = PennySlot(id: day.day, label: (reads.count - 1 - index) % every == 0 ? PennyStyle.day(day.day) : "",
                                 roas: day.numbers.spent > 0 ? day.numbers.roas : nil, cbh: day.cbh, weekend: day.weekend,
                                 title: PennyStyle.day(day.day) + (day.weekend ? " · " + L("weekend") : ""))
            for hour in day.hours { split(hour, profit, into: &slot) }
            slot.tip = [PennyTipLine(name: L("Spent"), value: Ledger.money(day.numbers.spent)),
                        PennyTipLine(name: L("Revenue"), value: Ledger.money(day.numbers.revenue)),
                        PennyTipLine(name: L("ROAS"), value: PennyStyle.times(day.numbers.roas), color: PennyStyle.roas(day.numbers.roas, profit)),
                        PennyTipLine(name: L("CBH"), value: Ledger.money(day.cbh), color: PennyStyle.money(day.cbh)),
                        PennyTipLine(name: L("Orders"), value: Ledger.whole(day.numbers.orders)),
                        PennyTipLine(name: L("Below breakeven"), value: Ledger.percent(day.numbers.spent > 0 ? slot.bad / day.numbers.spent : 0), color: slot.bad > slot.spent * 0.5 ? PennyStyle.red : nil),
                        PennyTipLine(name: L("Dead spend"), value: Ledger.percent(day.dead), color: day.dead > 0.3 ? PennyStyle.red : nil)]
            return slot
        }
    }

    /// One day hour by hour.
    static func hours(of day: Ledger.DayRead, profit: Ledger.Profit) -> [PennySlot] {
        (0 ..< 24).map { hour in
            let numbers = day.hours[hour]
            var slot = PennySlot(id: PennyStyle.hour(hour), label: PennyStyle.hour(hour), roas: numbers.spent > 0 ? numbers.roas : nil,
                                 cbh: profit.cbh(numbers), title: Ledger.hourName(hour))
            split(numbers, profit, into: &slot)
            slot.tip = [PennyTipLine(name: L("Spent"), value: Ledger.money(numbers.spent)),
                        PennyTipLine(name: L("Revenue"), value: Ledger.money(numbers.revenue)),
                        PennyTipLine(name: L("ROAS"), value: PennyStyle.times(numbers.roas), color: PennyStyle.roas(numbers.roas, profit)),
                        PennyTipLine(name: L("CBH"), value: Ledger.money(slot.cbh), color: PennyStyle.money(slot.cbh)),
                        PennyTipLine(name: L("Orders"), value: Ledger.whole(numbers.orders))]
            return slot
        }
    }

    /// The hours over the days: spend a day, split by how the hour did on each day; CBH a day; the bad and good day.
    static func hours(_ reads: [Ledger.HourRead], days: [Ledger.DayRead], profit: Ledger.Profit) -> [PennySlot] {
        reads.map { read in
            let count = Double(max(read.days, 1))
            var slot = PennySlot(id: PennyStyle.hour(read.hour), label: PennyStyle.hour(read.hour), roas: read.days > 0 ? read.numbers.roas : nil,
                                 floor: read.floor, ceiling: read.ceiling, cbh: read.cbh / count, faint: read.verdict == .few,
                                 title: Ledger.hourName(read.hour) + (read.verdict == .idle ? "" : " · " + HoursEfficiency.name(read.verdict)))
            for day in days { split(day.hours[read.hour], profit, into: &slot, share: 1 / count) }
            slot.tip = [PennyTipLine(name: L("Days"), value: "\(read.days)"),
                        PennyTipLine(name: L("Spent a day"), value: Ledger.money(read.spentPerDay)),
                        PennyTipLine(name: L("ROAS"), value: PennyStyle.times(read.numbers.roas), color: PennyStyle.roas(read.numbers.roas, profit)),
                        PennyTipLine(name: L("Bad day"), value: PennyStyle.times(read.floor), color: read.floor.map { PennyStyle.roas($0, profit) }),
                        PennyTipLine(name: L("Good day"), value: PennyStyle.times(read.ceiling), color: read.ceiling.map { PennyStyle.roas($0, profit) }),
                        PennyTipLine(name: L("Orders a day"), value: String(format: "%.1f", read.numbers.orders / count)),
                        PennyTipLine(name: L("CBH a day"), value: Ledger.money(slot.cbh), color: PennyStyle.money(slot.cbh))]
            return slot
        }
    }
}

/// Which column the pointer is on. Only the hover layers watch it, so moving the pointer never redraws a chart.
final class PennyHover: ObservableObject {
    @Published var id: String?
}

/// ROAS, spend and CBH for the same days or hours, one chart each, stacked so the columns line up. With `ranges`,
/// ROAS is each hour's average as a dot on its bad-to-good-day band. A press on a column picks it when `selected` is
/// given.
struct PennyColumns: View {
    let slots: [PennySlot]
    let profit: Ledger.Profit
    var ranges = false
    var selected: Binding<String?>? = nil
    var perDay = false
    var height: CGFloat = 150
    @State private var hover = PennyHover()
    @State private var width: CGFloat = 900

    static let axisWidth: CGFloat = 44

    var picked: String? { selected?.wrappedValue }

    var barWidth: CGFloat {
        let band = (width - Self.axisWidth - 8) / CGFloat(max(slots.count, 1))
        return max(3, min(24, band * 0.62))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            row(L("ROAS"), keys: {
                LegendKey(name: L("profitable"), color: PennyStyle.green, shape: ranges ? .band : .bar)
                LegendKey(name: L("above breakeven"), color: PennyStyle.yellow, shape: ranges ? .band : .bar)
                LegendKey(name: L("below breakeven"), color: PennyStyle.red, shape: ranges ? .band : .bar)
                LegendKey(name: L("profitable %@", PennyStyle.times(profit.profitable)), color: PennyStyle.green, shape: .dashed)
                LegendKey(name: L("breakeven %@", PennyStyle.times(profit.breakeven)), color: PennyStyle.red, shape: .dashed)
                if ranges { Text(L("dot: average · band: bad day to good day")).font(.system(size: 10.5)).foregroundStyle(PennyStyle.muted) }
            }) { roasChart.frame(height: height) }
            row(perDay ? L("Spend a day") : L("Spend"), keys: {
                LegendKey(name: L("in profitable hours"), color: PennyStyle.green)
                LegendKey(name: L("above breakeven"), color: PennyStyle.yellow)
                LegendKey(name: L("below breakeven"), color: PennyStyle.red)
            }) { spendChart.frame(height: height * 0.8) }
            row(perDay ? L("CBH a day") : L("CBH"), keys: {
                LegendKey(name: L("made money"), color: PennyStyle.green)
                LegendKey(name: L("lost money"), color: PennyStyle.red)
            }) { cbhChart.frame(height: height * 0.7) }
        }
        .background(GeometryReader { geometry in
            Color.clear.onAppear { width = geometry.size.width }.onChange(of: geometry.size.width) { _, new in width = new }
        })
    }

    func row<Keys: View, Content: View>(_ title: String, @ViewBuilder keys: () -> Keys, @ViewBuilder chart: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                keys()
            }
            chart()
        }
    }

    func faded(_ slot: PennySlot) -> Double {
        if let picked { return picked == slot.id ? 1 : 0.35 }
        return slot.faint && slots.contains(where: { !$0.faint }) ? 0.55 : 1
    }

    /// A ROAS past the chart's top, written on its mark so a capped bar or dot still says what it was.
    static func capped(_ roas: Double) -> String { String(format: roas >= 10 ? "%.0f×" : "%.1f×", roas) }

    var roasTop: Double {
        let highest = slots.compactMap { ranges ? ($0.ceiling ?? $0.roas) : $0.roas }.max() ?? 0
        return min(6, max(profit.profitable * 1.3, highest * 1.08, 1))
    }

    var roasChart: some View {
        let top = roasTop
        return Chart {
            ForEach(slots) { slot in roasMarks(slot, top: top) }
            RuleMark(y: .value("Profitable", profit.profitable))
                .foregroundStyle(PennyStyle.green.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            RuleMark(y: .value("Breakeven", profit.breakeven))
                .foregroundStyle(PennyStyle.red.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXScale(domain: slots.map(\.id))
        .chartYScale(domain: 0 ... top)
        .chartXAxis(.hidden)
        .chartYAxis { yAxis(values: PennyStyle.ticks(0, top)) { String(format: $0 < 10 && $0 != $0.rounded() ? "%.1f×" : "%.0f×", $0) } }
        .chartOverlay { proxy in PennyHoverLayer(proxy: proxy, slots: slots, hover: hover, tips: true, selected: selected) }
    }

    @ChartContentBuilder func roasMarks(_ slot: PennySlot, top: Double) -> some ChartContent {
        let color = PennyStyle.roas(slot.roas, profit)
        if slot.weekend, slots.count > 1 {
            RectangleMark(x: .value("Column", slot.id), yStart: .value("", 0), yEnd: .value("", top)).foregroundStyle(.white.opacity(0.03))
        }
        if ranges, let floor = slot.floor, let ceiling = slot.ceiling, ceiling > floor {
            RectangleMark(x: .value("Column", slot.id), yStart: .value("Bad day", min(floor, top)), yEnd: .value("Good day", min(max(ceiling, floor + 0.04), top)),
                          width: .fixed(barWidth))
                .foregroundStyle(color.opacity(0.28 * faded(slot))).cornerRadius(4)
        }
        if let roas = slot.roas {
            if ranges {
                PointMark(x: .value("Column", slot.id), y: .value("ROAS", min(roas, top))).foregroundStyle(PennyStyle.surface).symbolSize(120)
                PointMark(x: .value("Column", slot.id), y: .value("ROAS", min(roas, top))).foregroundStyle(color.opacity(faded(slot))).symbolSize(58)
                    .annotation(position: .bottom, spacing: 3) {
                        if roas > top { Text(Self.capped(roas)).font(.system(size: 8.5, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary) }
                    }
            } else {
                // Nothing back still shows: a red stub on the baseline.
                BarMark(x: .value("Column", slot.id), y: .value("ROAS", max(min(roas, top), top * 0.015)), width: .fixed(barWidth))
                    .foregroundStyle(color.opacity(0.9 * faded(slot))).cornerRadius(roas < top * 0.03 ? 1 : 4)
                    .annotation(position: .overlay, alignment: .top, spacing: 3) {
                        if roas > top { Text(Self.capped(roas)).font(.system(size: 8.5, weight: .bold).monospacedDigit()).foregroundStyle(.white).fixedSize() }
                    }
            }
        }
    }

    var spendChart: some View {
        let top = max((slots.map(\.spent).max() ?? 0) * 1.1, 1)
        return Chart {
            ForEach(slots) { slot in
                let parts = [(slot.good, PennyStyle.green), (slot.fair, PennyStyle.yellow), (slot.bad, PennyStyle.red)]
                ForEach(0 ..< 3, id: \.self) { index in
                    let below = parts[..<index].reduce(0) { $0 + $1.0 }
                    if parts[index].0 > 0 {
                        BarMark(x: .value("Column", slot.id), yStart: .value("From", below), yEnd: .value("To", below + parts[index].0), width: .fixed(barWidth))
                            .foregroundStyle(parts[index].1.opacity(0.85 * faded(slot))).cornerRadius(2)
                    }
                }
            }
        }
        .chartXScale(domain: slots.map(\.id))
        .chartYScale(domain: 0 ... top)
        .chartXAxis(.hidden)
        .chartYAxis { yAxis(values: PennyStyle.ticks(0, top), PennyStyle.short) }
        .chartOverlay { proxy in PennyHoverLayer(proxy: proxy, slots: slots, hover: hover, selected: selected) }
    }

    var cbhChart: some View {
        let low = min(0, (slots.map(\.cbh).min() ?? 0) * 1.12), high = max(0, (slots.map(\.cbh).max() ?? 0) * 1.12)
        let span = max(high - low, 1)
        return Chart {
            ForEach(slots.filter { $0.spent > 0 || $0.cbh != 0 }) { slot in
                BarMark(x: .value("Column", slot.id), y: .value("CBH", slot.cbh), width: .fixed(barWidth))
                    .foregroundStyle(PennyStyle.money(slot.cbh).opacity(0.85 * faded(slot))).cornerRadius(3)
            }
            RuleMark(y: .value("Zero", 0)).foregroundStyle(PennyStyle.baseline).lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartXScale(domain: slots.map(\.id))
        .chartYScale(domain: (high - low < 1 ? low - span / 2 : low) ... (high - low < 1 ? high + span / 2 : high))
        .chartXAxis {
            AxisMarks(values: slots.filter { !$0.label.isEmpty }.map(\.id)) { value in
                AxisValueLabel(collisionResolution: .disabled) {
                    if let id = value.as(String.self), let slot = slots.first(where: { $0.id == id }) {
                        Text(slot.label).foregroundStyle(PennyStyle.muted)
                    }
                }.font(.system(size: 9.5))
            }
        }
        .chartYAxis { yAxis(values: PennyStyle.ticks(low, high), PennyStyle.short) }
        .chartOverlay { proxy in PennyHoverLayer(proxy: proxy, slots: slots, hover: hover, selected: selected) }
    }

    func yAxis(values: [Double], _ text: @escaping (Double) -> String) -> some AxisContent {
        AxisMarks(position: .leading, values: values) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(PennyStyle.grid)
            AxisValueLabel {
                if let number = value.as(Double.self) { Text(text(number)).frame(width: Self.axisWidth - 6, alignment: .trailing) }
            }.font(.system(size: 9.5).monospacedDigit()).foregroundStyle(PennyStyle.muted)
        }
    }
}

/// The layer over one of the stacked charts: the column under the pointer washed lighter, the tip on the top chart,
/// and a press to pick a column.
struct PennyHoverLayer: View {
    let proxy: ChartProxy
    let slots: [PennySlot]
    @ObservedObject var hover: PennyHover
    var tips = false
    var selected: Binding<String?>? = nil

    var body: some View {
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
            let band = plot.width / CGFloat(max(slots.count, 1))
            ZStack(alignment: .topLeading) {
                if let picked = selected?.wrappedValue, let x = proxy.position(forX: picked) {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        .frame(width: band, height: plot.height).offset(x: plot.minX + x - band / 2, y: plot.minY)
                }
                if let id = hover.id, let x = proxy.position(forX: id) {
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.07))
                        .frame(width: band, height: plot.height).offset(x: plot.minX + x - band / 2, y: plot.minY)
                    if tips, let slot = slots.first(where: { $0.id == id }) {
                        let right = plot.minX + x + band / 2 + 8
                        ChartTip(title: slot.title, lines: slot.tip)
                            .offset(x: right + ChartTip.width > geometry.size.width ? plot.minX + x - band / 2 - 8 - ChartTip.width : right, y: plot.minY)
                            .zIndex(1)
                    }
                }
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        var id: String?
                        if case let .active(point) = phase { id = proxy.value(atX: point.x - plot.minX, as: String.self) }
                        if hover.id != id { hover.id = id }
                    }
                    .onTapGesture { point in
                        guard let selected, let id = proxy.value(atX: point.x - plot.minX, as: String.self),
                              slots.contains(where: { $0.id == id && $0.spent > 0 }) else { return }
                        selected.wrappedValue = selected.wrappedValue == id ? nil : id
                    }
            }
        }
    }
}

// MARK: Days

/// The days on a calendar, each coloured by its ROAS with its spend and revenue; a press opens the day.
struct DaysCalendar: View {
    let days: [Ledger.DayRead]
    let profit: Ledger.Profit
    @Binding var selected: String?

    var body: some View {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Self.weekdays, id: \.self) { name in
                Text(L(name)).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(PennyStyle.muted)
            }
            ForEach(Self.cells(days.map(\.day)), id: \.self) { day in cell(day, byDay[day]) }
        }
    }

    static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Every day of the weeks the days fall in, Sunday to Saturday.
    static func cells(_ days: [String]) -> [String] {
        guard let first = days.min().flatMap(Ledger.start(of:)), let last = days.max().flatMap(Ledger.start(of:)),
              let start = Ledger.calendar.date(byAdding: .day, value: 1 - Ledger.calendar.component(.weekday, from: first), to: first),
              let end = Ledger.calendar.date(byAdding: .day, value: 7 - Ledger.calendar.component(.weekday, from: last), to: last) else { return [] }
        let count = (Ledger.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return (0 ..< count).compactMap { Ledger.calendar.date(byAdding: .day, value: $0, to: start).map(Ledger.name(of:)) }
    }

    func cell(_ day: String, _ read: Ledger.DayRead?) -> some View {
        let ran = (read?.numbers.spent ?? 0) > 0
        let color = ran ? PennyStyle.roas(read?.numbers.roas, profit) : PennyStyle.muted
        let chosen = selected == day
        return VStack(alignment: .leading, spacing: 2) {
            Text(day.hasSuffix("-01") || read?.day == days.first?.day ? PennyStyle.day(day) : String(Int(day.suffix(2)) ?? 0))
                .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(read == nil ? PennyStyle.muted.opacity(0.5) : .secondary)
            if let read, ran {
                Text(PennyStyle.times(read.numbers.roas)).font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(color)
                HStack(spacing: 4) {
                    Text(PennyStyle.short(read.numbers.spent)).foregroundStyle(.secondary)
                    Text("CBH " + PennyStyle.short(read.cbh)).foregroundStyle(PennyStyle.money(read.cbh))
                }.font(.system(size: 9).monospacedDigit()).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(6).frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .topLeading)
        .background(read == nil ? Color.white.opacity(0.015) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) { if ran { UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7).fill(color).frame(width: 3) } }
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(chosen ? Color.white.opacity(0.6) : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { if ran { selected = chosen ? nil : day } }
    }
}

/// One day hour by hour: its totals, then ROAS, spend and CBH each hour.
struct DayDrill: View {
    let day: Ledger.DayRead
    let profit: Ledger.Profit
    var close: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(PennyStyle.day(day.day) + " · " + L("hour by hour")).font(.system(size: 13, weight: .semibold))
                stat(L("Spent"), Ledger.money(day.numbers.spent), nil)
                stat(L("Revenue"), Ledger.money(day.numbers.revenue), nil)
                stat(L("ROAS"), PennyStyle.times(day.numbers.roas), PennyStyle.roas(day.numbers.roas, profit))
                stat(L("CBH"), Ledger.money(day.cbh), PennyStyle.money(day.cbh))
                stat(L("Orders"), Ledger.whole(day.numbers.orders), nil)
                Spacer()
                if let close { Button { close() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help(L("Close")) }
            }
            PennyColumns(slots: PennySlot.hours(of: day, profit: profit), profit: profit, height: 120)
        }
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14)))
    }

    func stat(_ name: String, _ value: String, _ color: Color?) -> some View {
        HStack(spacing: 4) {
            Text(name).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(color ?? .primary)
        }
    }
}

// MARK: Hours

/// The verdicts as a legend, each with what it means.
struct VerdictLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8, alignment: .topLeading)], alignment: .leading, spacing: 8) {
            ForEach([Ledger.HourRead.Verdict.reliable, .volatile, .thin, .losing, .costly, .dead, .few], id: \.self) { verdict in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(PennyStyle.verdict(verdict)).frame(width: 8, height: 8).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(HoursEfficiency.name(verdict)).font(.system(size: 10.5, weight: .semibold))
                        Text(HoursEfficiency.meaning(verdict)).font(.system(size: 9.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: Budget

/// The budget as one bar split into hours below breakeven, thin profit and profitable, each part's share printed in it.
struct BudgetBar: View {
    let parts: Ledger.Efficiency

    var body: some View {
        let spent = max(parts.total.spent, 0.0001)
        let pieces = [(parts.losing, PennyStyle.red, L("Below breakeven")), (parts.thin, PennyStyle.yellow, L("Thin profit")), (parts.profitable, PennyStyle.green, L("Profitable"))]
            .filter { $0.0.numbers.spent > 0 }
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    let share = piece.0.numbers.spent / spent
                    let width = max(2, (geometry.size.width - CGFloat(pieces.count - 1) * 2) * share)
                    RoundedRectangle(cornerRadius: 4).fill(piece.1)
                        .frame(width: width)
                        .overlay(alignment: .leading) {
                            if width > 48 {
                                Text(Ledger.percent(share)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(piece.1 == PennyStyle.yellow ? Color.black : .white).padding(.leading, 7)
                            }
                        }
                        .help(L("%@: %@ of spend, %@", piece.2, Ledger.percent(share), Ledger.money(piece.0.numbers.spent)))
                }
            }
        }.frame(height: 26)
    }
}

/// Spend by the ROAS each hour of each day brought back: a bar for each band's share of spend, its share of revenue
/// beside it, and what came back.
struct BandsView: View {
    let bands: [Ledger.Band]
    let profit: Ledger.Profit

    func name(_ band: Ledger.Band) -> String {
        switch band.kind {
        case .nothing: return L("Nothing back (0×)")
        case .under1: return L("Under 1×")
        case .belowBreakeven: return L("1× to %@", PennyStyle.times(band.high))
        case .thin: return L("%@ to %@", PennyStyle.times(band.low), PennyStyle.times(band.high))
        case .good: return L("%@ to %@", PennyStyle.times(band.low), PennyStyle.times(band.high))
        case .great: return L("%@ and up", PennyStyle.times(band.low))
        }
    }

    func color(_ band: Ledger.Band) -> Color {
        switch band.kind {
        case .nothing, .under1, .belowBreakeven: return PennyStyle.red
        case .thin: return PennyStyle.yellow
        case .good, .great: return PennyStyle.green
        }
    }

    var body: some View {
        let spent = bands.reduce(0) { $0 + $1.numbers.spent }, revenue = bands.reduce(0) { $0 + $1.numbers.revenue }
        let widest = max(bands.map { spent > 0 ? $0.numbers.spent / spent : 0 }.max() ?? 0, bands.map { revenue > 0 ? $0.numbers.revenue / revenue : 0 }.max() ?? 0, 0.01)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Text(L("Every hour of every day, by the ROAS it brought back")).font(.system(size: 11.5, weight: .semibold))
                LegendKey(name: L("share of spend"), color: PennyStyle.muted, shape: .tones)
                LegendKey(name: L("share of revenue"), color: PennyStyle.blue)
            }
            HStack(spacing: 10) {
                Spacer()
                Text(L("of spend")).frame(width: 48, alignment: .trailing)
                Text(L("Spent")).frame(width: 80, alignment: .trailing)
                Text(L("came back")).frame(width: 88, alignment: .trailing)
                Text(L("of revenue")).frame(width: 66, alignment: .trailing)
            }.font(.system(size: 9.5, weight: .semibold)).foregroundStyle(PennyStyle.muted)
            ForEach(bands) { band in
                let spendShare = spent > 0 ? band.numbers.spent / spent : 0
                let revenueShare = revenue > 0 ? band.numbers.revenue / revenue : 0
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(color(band)).frame(width: 7, height: 7)
                        Text(name(band)).font(.system(size: 11, weight: .medium))
                    }.frame(width: 140, alignment: .leading)
                    GeometryReader { geometry in
                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: 3).fill(color(band).opacity(0.85)).frame(width: max(spendShare > 0 ? 2 : 0, geometry.size.width * spendShare / widest), height: 10)
                            RoundedRectangle(cornerRadius: 2).fill(PennyStyle.blue).frame(width: max(revenueShare > 0 ? 2 : 0, geometry.size.width * revenueShare / widest), height: 5)
                        }.frame(maxHeight: .infinity, alignment: .center)
                    }.frame(height: 22)
                    Text(Ledger.percent(spendShare)).font(.system(size: 11, weight: .semibold).monospacedDigit()).frame(width: 48, alignment: .trailing)
                    Text(Ledger.money(band.numbers.spent)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    Text("→ " + Ledger.money(band.numbers.revenue)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary).frame(width: 88, alignment: .trailing)
                    Text(Ledger.percent(revenueShare)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary).frame(width: 66, alignment: .trailing)
                }
                .help(L("%@ hours of a day spent in this band", band.cells))
            }
        }
    }
}

// MARK: Weeks

/// The weeks from Monday: a card each, then spend against revenue, the night against the peak, dead spend and CPM,
/// one measure per chart.
struct WeeksView: View {
    let weeks: [Ledger.WeekRead]
    let profit: Ledger.Profit

    func label(_ week: Ledger.WeekRead) -> String { PennyStyle.day(week.start) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                ForEach(weeks) { week in card(week) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], alignment: .leading, spacing: 20) {
                small(L("Spend and revenue"), keys: {
                    LegendKey(name: L("Spent"), color: PennyStyle.muted)
                    LegendKey(name: L("Revenue"), color: PennyStyle.blue)
                }) { spendAndRevenue }
                small(L("Night against peak"), keys: {
                    LegendKey(name: L("12 AM–6 AM"), color: PennyStyle.violet)
                    LegendKey(name: L("9 AM–9 PM"), color: PennyStyle.blue)
                    LegendKey(name: L("breakeven"), color: PennyStyle.red, shape: .dashed)
                }) { nightAgainstPeak }
                small(L("Dead spend"), keys: { Text(L("share of spend in hours under 1×")).font(.system(size: 10.5)).foregroundStyle(.secondary) }) { deadSpend }
                small(L("CPM"), keys: { Text(L("what a thousand impressions cost: lower is better")).font(.system(size: 10.5)).foregroundStyle(.secondary) }) { cpm }
            }
        }
    }

    func card(_ week: Ledger.WeekRead) -> some View {
        let color = PennyStyle.roas(week.numbers.roas, profit)
        return VStack(alignment: .leading, spacing: 4) {
            Text(L("Week of %@", label(week))).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(PennyStyle.times(week.numbers.roas)).font(.system(size: 22, weight: .bold)).foregroundStyle(color)
            Group {
                Text(L("%@ spent · %@ back", PennyStyle.short(week.numbers.spent), PennyStyle.short(week.numbers.revenue)))
                Text(week.days == 1 ? L("%@ orders · 1 day", Ledger.whole(week.numbers.orders)) : L("%@ orders · %@ days", Ledger.whole(week.numbers.orders), week.days))
                HStack(spacing: 0) {
                    Text("CBH ")
                    Text(PennyStyle.short(week.cbh)).fontWeight(.semibold).foregroundStyle(PennyStyle.money(week.cbh))
                    Text(" · CPM " + (week.numbers.cpm.map(Ledger.money) ?? "–"))
                }
            }.font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9).fill(color).frame(width: 3) }
    }

    func small<Keys: View, Content: View>(_ title: String, @ViewBuilder keys: () -> Keys, @ViewBuilder chart: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 12) { keys() }
            chart().frame(height: 160)
        }
    }

    var spendAndRevenue: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Week", label(week)), y: .value("Dollars", week.numbers.spent), width: .fixed(24))
                    .foregroundStyle(PennyStyle.muted).position(by: .value("What", "spent"), span: .fixed(68)).cornerRadius(4)
                    .annotation(position: .top, spacing: 2) { valueLabel(PennyStyle.short(week.numbers.spent)) }
                BarMark(x: .value("Week", label(week)), y: .value("Dollars", week.numbers.revenue), width: .fixed(24))
                    .foregroundStyle(PennyStyle.blue).position(by: .value("What", "revenue"), span: .fixed(68)).cornerRadius(4)
                    .annotation(position: .top, spacing: 2) { valueLabel(PennyStyle.short(week.numbers.revenue)) }
            }
        }
        .chartYScale(domain: 0 ... max(1, weeks.map { max($0.numbers.spent, $0.numbers.revenue) }.max() ?? 0) * 1.15)
        .chartXAxis { weekAxis }
        .chartYAxis { dollarAxis }
    }

    var nightAgainstPeak: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Week", label(week)), y: .value("ROAS", week.night.roas ?? 0), width: .fixed(24))
                    .foregroundStyle(PennyStyle.violet).position(by: .value("When", "night"), span: .fixed(68)).cornerRadius(4)
                    .annotation(position: .top, spacing: 2) { valueLabel(PennyStyle.times(week.night.roas)) }
                BarMark(x: .value("Week", label(week)), y: .value("ROAS", week.peak.roas ?? 0), width: .fixed(24))
                    .foregroundStyle(PennyStyle.blue).position(by: .value("When", "peak"), span: .fixed(68)).cornerRadius(4)
                    .annotation(position: .top, spacing: 2) { valueLabel(PennyStyle.times(week.peak.roas)) }
            }
            RuleMark(y: .value("Breakeven", profit.breakeven)).foregroundStyle(PennyStyle.red.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: 0 ... max(profit.breakeven * 1.3, weeks.flatMap { [$0.night.roas ?? 0, $0.peak.roas ?? 0] }.max() ?? 0) * 1.15)
        .chartXAxis { weekAxis }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(PennyStyle.grid)
                AxisValueLabel { if let roas = value.as(Double.self) { Text(String(format: "%.0f×", roas)) } }.font(.system(size: 9.5)).foregroundStyle(PennyStyle.muted)
            }
        }
    }

    var deadSpend: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Week", label(week)), y: .value("Dead", week.dead), width: .fixed(24))
                    .foregroundStyle(week.dead > 0.3 ? PennyStyle.red : week.dead > 0.2 ? PennyStyle.yellow : PennyStyle.green).cornerRadius(4)
                    .annotation(position: .top, spacing: 2) { valueLabel(Ledger.percent(week.dead)) }
            }
        }
        .chartYScale(domain: 0 ... max(0.5, (weeks.map(\.dead).max() ?? 0) * 1.2))
        .chartXAxis { weekAxis }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(PennyStyle.grid)
                AxisValueLabel { if let share = value.as(Double.self) { Text(String(format: "%.0f%%", share * 100)) } }.font(.system(size: 9.5)).foregroundStyle(PennyStyle.muted)
            }
        }
    }

    var cpm: some View {
        let shown = weeks.filter { $0.numbers.cpm != nil }
        let values = shown.compactMap(\.numbers.cpm)
        let low = (values.min() ?? 0) * 0.8, high = max((values.max() ?? 1) * 1.12, low + 1)
        return Chart {
            ForEach(shown) { week in
                LineMark(x: .value("Week", label(week)), y: .value("CPM", week.numbers.cpm ?? 0)).foregroundStyle(PennyStyle.blue).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Week", label(week)), y: .value("CPM", week.numbers.cpm ?? 0)).foregroundStyle(PennyStyle.surface).symbolSize(110)
                PointMark(x: .value("Week", label(week)), y: .value("CPM", week.numbers.cpm ?? 0)).foregroundStyle(PennyStyle.blue).symbolSize(50)
                    .annotation(position: .top, spacing: 4) { valueLabel(Ledger.money(week.numbers.cpm ?? 0)) }
            }
        }
        .chartYScale(domain: low ... high)
        .chartXAxis { weekAxis }
        .chartYAxis {
            AxisMarks(position: .leading, values: PennyStyle.ticks(low, high)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(PennyStyle.grid)
                AxisValueLabel { if let dollars = value.as(Double.self) { Text(String(format: "$%.0f", dollars)) } }.font(.system(size: 9.5)).foregroundStyle(PennyStyle.muted)
            }
        }
    }

    func valueLabel(_ text: String) -> some View { Text(text).font(.system(size: 9.5, weight: .medium).monospacedDigit()).foregroundStyle(.secondary).fixedSize() }

    var dollarAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(PennyStyle.grid)
            AxisValueLabel { if let dollars = value.as(Double.self) { Text(PennyStyle.short(dollars)) } }.font(.system(size: 9.5)).foregroundStyle(PennyStyle.muted)
        }
    }

    var weekAxis: some AxisContent {
        AxisMarks { value in
            AxisValueLabel { if let name = value.as(String.self) { Text(name) } }
                .font(.system(size: 9.5)).foregroundStyle(PennyStyle.muted)
        }
    }
}

// MARK: Figures

/// A headline number: its name, value (coloured when it has a verdict) and the change on the days before.
struct PennyFigure: View {
    let name: String
    let value: String
    var color: Color? = nil
    /// The change against the days before, and whether up is good.
    var change: Double? = nil
    var upIsGood = true
    /// A change that is neither good nor bad by itself (spend), shown grey.
    var neutral = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(name)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(color ?? .primary).lineLimit(1).minimumScaleFactor(0.6)
            if let change, change.isFinite, abs(change) >= 0.005 {
                let good = (change > 0) == upIsGood
                Text((change > 0 ? "▲ " : "▼ ") + Ledger.percent(abs(change))).font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(neutral ? PennyStyle.muted : good ? PennyStyle.green : PennyStyle.red)
            } else {
                Text(" ").font(.system(size: 10))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .leading) { if let color { UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9).fill(color).frame(width: 3) } }
    }
}

/// A line of Penny's read: plain words grey, bold words white, and the values with a verdict bold in green, yellow or
/// red.
struct PennyReadLine: View {
    let line: String

    var body: some View { Self.text(line) }

    static func text(_ line: String) -> Text {
        var result = Text("")
        var bold = false, tone: Ledger.Tone?
        var rest = Substring(line)
        let marks = ["**", "⟦g⟧", "⟦y⟧", "⟦r⟧", "⟦/⟧"]
        func add(_ piece: Substring) {
            guard !piece.isEmpty else { return }
            var text = Text(String(piece))
            if let tone {
                text = text.fontWeight(.bold).foregroundColor(PennyStyle.tone(tone))
            } else if bold {
                text = text.fontWeight(.semibold).foregroundColor(.primary)
            } else {
                text = text.foregroundColor(Color(red: 195 / 255, green: 194 / 255, blue: 183 / 255))
            }
            result = result + text
        }
        while !rest.isEmpty {
            let next = marks.compactMap { mark in rest.range(of: mark).map { (mark, $0) } }.min { $0.1.lowerBound < $1.1.lowerBound }
            guard let (mark, range) = next else { add(rest); break }
            add(rest[..<range.lowerBound])
            switch mark {
            case "**": bold.toggle()
            case "⟦/⟧": tone = nil
            default: tone = Ledger.Tone(rawValue: String(mark.dropFirst().prefix(1)))
            }
            rest = rest[range.upperBound...]
        }
        return result
    }
}
