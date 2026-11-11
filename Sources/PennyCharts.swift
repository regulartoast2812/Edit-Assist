import SwiftUI

/// Penny's media-buying charts, redrawn (2026-11-06) after you found the first ones cluttered: one measure per chart,
/// never two axes on one, stacked so a day or an hour lines up down the page. ROAS on top (green from the profitable
/// line, yellow from breakeven, red under it), then spend split by how each hour did, then CBH. The same three colours
/// mean the same thing everywhere, Penny's read included. Hovering only redraws a thin layer over the charts, never
/// the charts, so the page stays quick. Finished 2026-11-07 (first in the Windows app, drawn the same way here): each
/// column's wash runs down all three charts, bars are rounded at their end only, values sit on the bars when they fit,
/// breakeven and the profitable line carry their numbers on the axis, and the bars grow in on new days.
enum PennyStyle {
    static let green = Color(red: 12 / 255, green: 163 / 255, blue: 12 / 255)
    static let yellow = Color(red: 250 / 255, green: 178 / 255, blue: 25 / 255)
    static let red = Color(red: 222 / 255, green: 68 / 255, blue: 68 / 255)
    static let orange = Color(red: 236 / 255, green: 131 / 255, blue: 90 / 255)
    static let blue = Color(red: 57 / 255, green: 135 / 255, blue: 229 / 255)
    static let violet = Color(red: 144 / 255, green: 133 / 255, blue: 233 / 255)
    static let pink = Color(red: 225 / 255, green: 110 / 255, blue: 175 / 255)
    static let teal = Color(red: 45 / 255, green: 185 / 255, blue: 175 / 255)
    static let muted = Color(red: 137 / 255, green: 135 / 255, blue: 129 / 255)
    static let grid = Color(red: 44 / 255, green: 44 / 255, blue: 42 / 255)
    static let baseline = Color(red: 72 / 255, green: 72 / 255, blue: 68 / 255)
    static let surface = Color(red: 26 / 255, green: 26 / 255, blue: 25 / 255)
    static let panel = Color.white.opacity(0.035)
    /// Plain words in Penny's read, and the values over the bars.
    static let words = Color(red: 195 / 255, green: 194 / 255, blue: 183 / 255)

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
    /// A colour a third of the way to white, for words on a wash of itself: a pill's (2026-11-11: the shares' pills, in
    /// their own colours at full strength, were hard to read on the dark).
    static func light(_ color: Color) -> Color { Color(nsColor: NSColor(color).usingColorSpace(.sRGB)?.blended(withFraction: 0.35, of: .white) ?? NSColor(color)) }

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

    static func day(_ day: String) -> String { Ledger.short(day) }

    /// A day's weekday: Sun, Mon.
    static func weekday(_ day: String) -> String {
        guard let start = Ledger.start(of: day) else { return "" }
        return L(DaysCalendar.weekdays[(Ledger.calendar.component(.weekday, from: start) + 6) % 7])
    }

    /// A bar rounded at its end only (the top, or the bottom for one hanging under zero), square on its baseline.
    static func column(_ rect: CGRect, radius: CGFloat, up: Bool) -> Path {
        let radius = max(0, min(radius, rect.width / 2, rect.height))
        return UnevenRoundedRectangle(topLeadingRadius: up ? radius : 0, bottomLeadingRadius: up ? 0 : radius,
                                      bottomTrailingRadius: up ? 0 : radius, topTrailingRadius: up ? radius : 0).path(in: rect)
    }

    /// Text for a chart drawn on a canvas.
    static func write(_ context: GraphicsContext, _ text: String, _ size: CGFloat, _ color: Color, _ weight: Font.Weight = .regular) -> GraphicsContext.ResolvedText {
        context.resolve(Text(text).font(.system(size: size, weight: weight).monospacedDigit()).foregroundColor(color))
    }

    static func width(_ text: GraphicsContext.ResolvedText) -> CGFloat { text.measure(in: CGSize(width: 10_000, height: 1000)).width }

    /// Text that fits the width, cut in the middle when it doesn't ("NQ1569_v1…t4.0_b3.0"), as a table cell writes it.
    static func fit(_ context: GraphicsContext, _ string: String, _ size: CGFloat, _ color: Color, _ weight: Font.Weight, width room: CGFloat) -> GraphicsContext.ResolvedText {
        let whole = write(context, string, size, color, weight)
        guard room > 0, width(whole) > room else { return whole }
        let characters = Array(string)
        func cut(_ keep: Int) -> String { String(characters.prefix((keep + 1) / 2)) + "…" + String(characters.suffix(keep / 2)) }
        var low = 0, high = characters.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if width(write(context, cut(middle), size, color, weight)) <= room { low = middle } else { high = middle - 1 }
        }
        return write(context, cut(low), size, color, weight)
    }

    /// Round axis steps for a top value: 1, 2, 2.5 or 5 times a power of ten, about four of them.
    static func ticks(_ low: Double, _ high: Double) -> [Double] {
        let span = max(high - low, 1e-9), raw = span / 4
        let power = pow(10, floor(log10(raw)))
        let step = [1, 2, 2.5, 5, 10].map { $0 * power }.first { $0 >= raw } ?? raw
        let first = (low / step).rounded(.up) * step
        return Array(stride(from: first, through: high, by: step))
    }

    /// How far a chart has grown in, 0 to 1, eased.
    static func eased(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }
}

/// A titled panel: a heading, a line on how to read it, then its content. It fills the height it is given, so two
/// panels side by side line up (`PanelFlow`).
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
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PennyStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.07)))
    }
}

extension PennyPanel where Accessory == EmptyView {
    init(title: String, note: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, note: note, accessory: { EmptyView() }, content: content)
    }
}

/// A legend entry: a swatch (a bar, a line, a dashed line, a dot, or a column's wash) and its name.
struct LegendKey: View {
    /// Wash: a column's shading behind the bars; in muted, the three verdict colours side by side.
    enum Shape { case bar, line, dashed, dot, band, wash, tones }
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
            case .wash where color == PennyStyle.muted:
                HStack(spacing: 1) {
                    ForEach([PennyStyle.green, PennyStyle.yellow, PennyStyle.red], id: \.self) { RoundedRectangle(cornerRadius: 2).fill($0.opacity(0.35)).frame(width: 7, height: 12) }
                }
            case .wash: RoundedRectangle(cornerRadius: 2).fill(color.opacity(color == .white ? 0.14 : 0.35)).frame(width: 9, height: 12)
            // Bars coloured by verdict: the three colours, solid.
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
    /// A sentence under the title, as what a verdict means.
    var note: String? = nil
    static let width: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if let note { Text(note).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
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
    /// The bad and good stretch (10th and 90th percentile over runs of days) of an hour.
    var floor: Double? = nil
    var ceiling: Double? = nil
    /// The spend (a day, for an hour over the days) in hours that were profitable, above breakeven and below it.
    var good = 0.0, fair = 0.0, bad = 0.0
    var cbh = 0.0
    /// An hour with too few days to judge, drawn fainter.
    var faint = false
    /// A Saturday or Sunday, shaded behind its column.
    var weekend = false
    /// The hour's average over all the days read against breakeven, washed behind its column down all three charts and
    /// on its label (2026-11-07: you asked to see at a glance which hours pay on average). On a day opened hour by hour
    /// it is still the hour over all the days, never that day's own (its bar already says that). Nil for none: days,
    /// idle hours, hours with too few days.
    var wash: Ledger.Tone? = nil
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
                                 title: PennyStyle.weekday(day.day) + ", " + PennyStyle.day(day.day))
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

    /// One day hour by hour; each hour washed by how it does over all the days read (`overall`), if given.
    static func hours(of day: Ledger.DayRead, profit: Ledger.Profit, overall: [Ledger.HourRead]? = nil) -> [PennySlot] {
        (0 ..< 24).map { hour in
            let numbers = day.hours[hour]
            var slot = PennySlot(id: PennyStyle.hour(hour), label: PennyStyle.hour(hour), roas: numbers.spent > 0 ? numbers.roas : nil,
                                 cbh: profit.cbh(numbers), wash: Ledger.shade(overall, hour: hour, profit), title: Ledger.hourName(hour))
            split(numbers, profit, into: &slot)
            slot.tip = [PennyTipLine(name: L("Spent"), value: Ledger.money(numbers.spent)),
                        PennyTipLine(name: L("Revenue"), value: Ledger.money(numbers.revenue)),
                        PennyTipLine(name: L("ROAS"), value: PennyStyle.times(numbers.roas), color: PennyStyle.roas(numbers.roas, profit)),
                        PennyTipLine(name: L("CBH"), value: Ledger.money(slot.cbh), color: PennyStyle.money(slot.cbh)),
                        PennyTipLine(name: L("Orders"), value: Ledger.whole(numbers.orders))]
            return slot
        }
    }

    /// The hours over the days: spend a day, split by how the hour did on each day; CBH a day; the bad and good stretch.
    static func hours(_ reads: [Ledger.HourRead], days: [Ledger.DayRead], profit: Ledger.Profit) -> [PennySlot] {
        reads.map { read in
            let count = Double(max(read.days, 1))
            var slot = PennySlot(id: PennyStyle.hour(read.hour), label: PennyStyle.hour(read.hour), roas: read.days > 0 ? read.numbers.roas : nil,
                                 floor: read.floor, ceiling: read.ceiling, cbh: read.cbh / count, faint: read.verdict == .few,
                                 wash: Ledger.shade(read, profit),
                                 title: Ledger.hourName(read.hour) + (read.verdict == .idle ? "" : " · " + HoursEfficiency.name(read.verdict)))
            for day in days { split(day.hours[read.hour], profit, into: &slot, share: 1 / count) }
            slot.tip = [PennyTipLine(name: L("Days"), value: "\(read.days)"),
                        PennyTipLine(name: L("Spent a day"), value: Ledger.money(read.spentPerDay)),
                        PennyTipLine(name: L("ROAS"), value: PennyStyle.times(read.numbers.roas), color: PennyStyle.roas(read.numbers.roas, profit)),
                        PennyTipLine(name: L("Bad stretch"), value: PennyStyle.times(read.floor), color: read.floor.map { PennyStyle.roas($0, profit) }),
                        PennyTipLine(name: L("Good stretch"), value: PennyStyle.times(read.ceiling), color: read.ceiling.map { PennyStyle.roas($0, profit) }),
                        PennyTipLine(name: L("Orders a day"), value: String(format: "%.1f", read.numbers.orders / count)),
                        PennyTipLine(name: L("CBH a day"), value: Ledger.money(slot.cbh), color: PennyStyle.money(slot.cbh))]
            return slot
        }
    }
}

/// Which column the pointer is on, from the charts or the calendar under them. Only the hover layers watch it, so
/// moving the pointer never redraws a chart.
final class PennyHover: ObservableObject {
    @Published private(set) var id: String?
    /// Whether the charts draw their tip: not for a day under the pointer on the calendar, which shows its own numbers.
    @Published private(set) var tip = true

    func set(_ id: String?, tip: Bool = true) {
        if self.tip != tip { self.tip = tip }
        if self.id != id { self.id = id }
    }
}

/// Where a stacked chart draws: its plot between the axis and the right edge, a band for each column.
struct ColumnFrame {
    /// Room over the plot for the values printed over the bars.
    static let head: CGFloat = 16
    var left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat
    var count: Int
    var band: CGFloat { (right - left) / CGFloat(max(count, 1)) }
    func center(_ index: Int) -> CGFloat { left + band * (CGFloat(index) + 0.5) }
    var barWidth: CGFloat { max(3, min(36, band * 0.58)) }
    func index(at x: CGFloat) -> Int? { count == 0 || x < left || x >= right ? nil : min(count - 1, Int((x - left) / band)) }
    /// The whole column, from over the plot to under it (its label too, on the chart that has them).
    func column(_ index: Int, under: CGFloat = 0) -> CGRect {
        CGRect(x: center(index) - band / 2 + 1, y: top - Self.head + 4, width: max(1, band - 2), height: bottom - top + Self.head - 4 + under)
    }

    static func of(_ size: CGSize, count: Int, labels: Bool) -> ColumnFrame {
        ColumnFrame(left: PennyColumns.axisWidth, right: max(PennyColumns.axisWidth + 1, size.width - 4), top: head,
                    bottom: max(head + 10, size.height - (labels ? 18 : 2)), count: count)
    }
}

/// ROAS, spend and CBH for the same days or hours, one chart each, stacked so the columns line up. With `ranges`,
/// ROAS is each hour's average as a dot on its bad-to-good-day band, the band coloured where it falls. A press on a
/// column picks it when `selected` is given. Each column's wash (an hour's average, or a weekend) runs down all three
/// charts; bars are rounded at their end only and spend stacks as one column; values sit over the bars when they fit;
/// breakeven and the profitable line carry their numbers on the axis; a value past the top of the chart says so; and
/// the bars grow in when the page opens on new days.
struct PennyColumns: View {
    enum Kind { case roas, spend, cbh }
    let slots: [PennySlot]
    let profit: Ledger.Profit
    var ranges = false
    var selected: Binding<String?>? = nil
    var perDay = false
    var height: CGFloat = 150
    /// What the columns' wash means, for the legend.
    var washName = L("column: the hour's average")
    /// Shared with the calendar under the days' charts; the charts' own otherwise.
    var hover: PennyHover? = nil
    @State private var own = PennyHover()
    /// When the bars started growing in; nil once they have.
    @State private var growFrom: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let axisWidth: CGFloat = 44
    static let growTime = 0.52, stagger = 0.22

    /// `grow`: bars rise from the baseline when shown: the page opened on a product or days it wasn't showing.
    init(slots: [PennySlot], profit: Ledger.Profit, ranges: Bool = false, selected: Binding<String?>? = nil, perDay: Bool = false, height: CGFloat = 150,
         grow: Bool = false, washName: String = L("column: the hour's average"), hover: PennyHover? = nil) {
        self.slots = slots; self.profit = profit; self.ranges = ranges; self.selected = selected; self.perDay = perDay; self.height = height
        self.washName = washName; self.hover = hover
        _growFrom = State(initialValue: grow && !slots.isEmpty ? Date() : nil)
    }

    var pointer: PennyHover { hover ?? own }
    var picked: String? { selected?.wrappedValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(L("ROAS")) {
                LegendKey(name: L("profitable"), color: PennyStyle.green)
                LegendKey(name: L("above breakeven"), color: PennyStyle.yellow)
                LegendKey(name: L("below breakeven"), color: PennyStyle.red)
                LegendKey(name: L("profitable %@", PennyStyle.times(profit.profitable)), color: PennyStyle.green, shape: .dashed)
                LegendKey(name: L("breakeven %@", PennyStyle.times(profit.breakeven)), color: PennyStyle.red, shape: .dashed)
                if ranges {
                    LegendKey(name: L("average"), color: PennyStyle.words, shape: .dot)
                    Text(L("band: bad stretch to good, coloured where it falls")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                if slots.contains(where: { $0.wash != nil }) { LegendKey(name: washName, color: PennyStyle.muted, shape: .wash) }
                if slots.contains(where: \.weekend) { LegendKey(name: L("weekend"), color: .white, shape: .wash) }
            } chart: { chart(.roas, height: height + ColumnFrame.head) }
            // Over the charts under it, so the tip can reach down past its own.
            .zIndex(1)
            row(perDay ? L("Spend a day") : L("Spend")) {
                LegendKey(name: L("in profitable hours"), color: PennyStyle.green)
                LegendKey(name: L("above breakeven"), color: PennyStyle.yellow)
                LegendKey(name: L("below breakeven"), color: PennyStyle.red)
            } chart: { chart(.spend, height: height * 0.8 + ColumnFrame.head) }
            row(perDay ? L("CBH a day") : L("CBH")) {
                LegendKey(name: L("made money"), color: PennyStyle.green)
                LegendKey(name: L("lost money"), color: PennyStyle.red)
            } chart: { chart(.cbh, height: height * 0.7 + 16 + ColumnFrame.head) }
        }
        .onAppear { if reduceMotion { growFrom = nil } }
        .task {
            guard growFrom != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64((Self.growTime + Self.stagger + 0.05) * 1_000_000_000))
            growFrom = nil
        }
    }

    func row<Keys: View, Content: View>(_ title: String, @ViewBuilder keys: () -> Keys, @ViewBuilder chart: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            FlowLayout(spacing: 12) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                keys()
            }
            chart()
        }
    }

    func chart(_ kind: Kind, height: CGFloat) -> some View {
        TimelineView(.animation(paused: growFrom == nil)) { context in
            let clock = growFrom.map { context.date.timeIntervalSince($0) }
            Canvas { canvas, size in draw(kind, in: canvas, size: size, clock: clock) }
        }
        .frame(height: height)
        .overlay { PennyHoverLayer(slots: slots, labels: kind == .cbh, hover: pointer, tips: kind == .roas, selected: selected) }
    }

    /// How far column `index` has grown in, 0 to 1, eased; the columns start a little apart, left to right.
    func grown(_ index: Int, _ clock: Double?) -> Double {
        guard let clock else { return 1 }
        let delay = slots.count > 1 ? Self.stagger * Double(index) / Double(slots.count - 1) : 0
        return PennyStyle.eased((clock - delay) / Self.growTime)
    }

    func faded(_ slot: PennySlot) -> Double {
        if let picked { return picked == slot.id ? 1 : 0.4 }
        // Fainter only beside hours that can be judged: on one day every hour is "too few", and dimming all greys the chart.
        return slot.faint && slots.contains(where: { !$0.faint }) ? 0.55 : 1
    }

    func domain(_ kind: Kind) -> (low: Double, high: Double, ticks: [Double]) {
        switch kind {
        case .roas:
            let highest = slots.compactMap { ranges ? ($0.ceiling ?? $0.roas) : $0.roas }.max() ?? 0
            let top = min(6, max(profit.profitable * 1.25, highest * 1.04, 1))
            return (0, top, PennyStyle.ticks(0, top))
        case .spend:
            let most = max((slots.map(\.spent).max() ?? 0) * 1.04, 1)
            return (0, most, PennyStyle.ticks(0, most))
        case .cbh:
            // Under zero, room for the value printed under a loss.
            let low = min(0, (slots.map(\.cbh).min() ?? 0) * 1.3), high = max(0, (slots.map(\.cbh).max() ?? 0) * 1.04)
            let ticks = PennyStyle.ticks(low, high), span = max(high - low, 1)
            return high - low < 1 ? (low - span / 2, high + span / 2, ticks) : (low, high, ticks)
        }
    }

    func draw(_ kind: Kind, in context: GraphicsContext, size: CGSize, clock: Double?) {
        let labels = kind == .cbh
        let frame = ColumnFrame.of(size, count: slots.count, labels: labels)
        let (low, high, ticks) = domain(kind)
        func y(_ value: Double) -> CGFloat { frame.bottom - CGFloat((min(max(value, low), high) - low) / max(high - low, 1e-9)) * (frame.bottom - frame.top) }
        let bar = frame.barWidth

        // Behind everything, each column's wash, so a column reads as one down the three charts.
        for (index, slot) in slots.enumerated() {
            let area = Path(roundedRect: frame.column(index, under: labels ? 16 : 0), cornerRadius: 4)
            if let tone = slot.wash { context.fill(area, with: .color(PennyStyle.tone(tone).opacity(0.085 * grown(index, clock)))) }
            else if slot.weekend { context.fill(area, with: .color(.white.opacity(0.035))) }
        }

        // Breakeven and the profitable line write their numbers on the axis, pushed apart when they're close, in place
        // of the grid's labels they would cover.
        var profitableY = y(profit.profitable), breakevenY = y(profit.breakeven)
        if kind == .roas, breakevenY - profitableY < 12 {
            let push = (12 - (breakevenY - profitableY)) / 2
            profitableY -= push; breakevenY += push
        }
        for tick in ticks {
            let at = y(tick)
            var line = Path(); line.move(to: CGPoint(x: frame.left, y: at)); line.addLine(to: CGPoint(x: frame.right, y: at))
            context.stroke(line, with: .color(PennyStyle.grid), lineWidth: 1)
            if kind == .roas, abs(at - profitableY) < 11 || abs(at - breakevenY) < 11 { continue }
            let label = kind == .roas ? String(format: tick < 10 && tick != tick.rounded() ? "%.1f×" : "%.0f×", tick) : PennyStyle.short(tick)
            context.draw(PennyStyle.write(context, label, 9.5, PennyStyle.muted), at: CGPoint(x: Self.axisWidth - 6, y: at), anchor: .trailing)
        }

        for (index, slot) in slots.enumerated() {
            let x = frame.center(index), faded = faded(slot), grown = grown(index, clock)
            let shown = faded * min(max(grown * 1.6 - 0.6, 0), 1)
            // A value over the bar, when it fits in the column.
            func value(_ text: String, _ color: Color, _ at: CGFloat, above: Bool, shorter: String? = nil) {
                var written = PennyStyle.write(context, text, 9.5, color.opacity(shown), .semibold)
                if PennyStyle.width(written) > frame.band - 4, let shorter { written = PennyStyle.write(context, shorter, 9.5, color.opacity(shown), .semibold) }
                guard PennyStyle.width(written) <= frame.band - 4 else { return }
                // Under a loss, only when it stays clear of the hours' labels.
                if !above, at + 1 + written.measure(in: CGSize(width: 1000, height: 100)).height > frame.bottom + 3 { return }
                context.draw(written, at: CGPoint(x: x, y: above ? at - 1 : at + 1), anchor: above ? .bottom : .top)
            }
            switch kind {
            case .roas:
                guard let roas = slot.roas else { break }
                let color = PennyStyle.roas(roas, profit)
                if ranges {
                    let middle = y(min(roas, high))
                    if let floor = slot.floor, let ceiling = slot.ceiling, ceiling > floor {
                        // The band opens out from the average, and is coloured where it falls: red under breakeven, yellow
                        // to the profitable line, green over it, so you see how much of an hour's spread loses money.
                        // (2026-11-07: one colour for the band, the dot and the wash said the same thing three times.)
                        var a = y(min(floor, high)), b = y(min(max(ceiling, floor + 0.04), high))
                        a = middle + (a - middle) * grown; b = middle + (b - middle) * grown
                        let band = CGRect(x: x - bar / 2, y: min(a, b), width: bar, height: max(1, abs(a - b)))
                        var layer = context
                        layer.clip(to: Path(roundedRect: band, cornerRadius: 4))
                        let profitableAt = y(profit.profitable), breakevenAt = y(profit.breakeven)
                        layer.fill(Path(CGRect(x: band.minX, y: band.minY, width: bar, height: max(0, profitableAt - band.minY))), with: .color(PennyStyle.green.opacity(0.42 * faded)))
                        layer.fill(Path(CGRect(x: band.minX, y: profitableAt, width: bar, height: max(0, breakevenAt - profitableAt))), with: .color(PennyStyle.yellow.opacity(0.42 * faded)))
                        layer.fill(Path(CGRect(x: band.minX, y: breakevenAt, width: bar, height: max(0, band.maxY - breakevenAt))), with: .color(PennyStyle.red.opacity(0.42 * faded)))
                        if ceiling > high { past(context, x: x, top: frame.top, PennyStyle.times(ceiling), PennyStyle.roas(ceiling, profit), faded * grown, band: frame.band) }
                    }
                    // The average, light on a dark ring: where it sits against the lines says how the hour does.
                    let ring = 6 * grown, dot = 4.2 * grown
                    context.fill(Path(ellipseIn: CGRect(x: x - ring, y: middle - ring, width: ring * 2, height: ring * 2)), with: .color(PennyStyle.surface.opacity(grown)))
                    context.fill(Path(ellipseIn: CGRect(x: x - dot, y: middle - dot, width: dot * 2, height: dot * 2)), with: .color(PennyStyle.words.opacity(faded)))
                } else {
                    // Nothing back still shows: a red stub on the baseline.
                    let top = y(max(min(roas, high), high * 0.015) * grown)
                    context.fill(PennyStyle.column(CGRect(x: x - bar / 2, y: top, width: bar, height: max(1, frame.bottom - top)), radius: 4, up: true),
                                 with: .color(color.opacity(0.9 * faded)))
                    if roas > high { past(context, x: x, top: frame.top, PennyStyle.times(roas), color, faded * grown, band: frame.band) }
                    else { value(PennyStyle.times(roas), color, top, above: true, shorter: String(format: "%.2f", roas)) }
                }
            case .spend:
                guard slot.spent > 0 else { break }
                // One column, rounded at the top only; its parts stack inside it.
                let columnTop = y(slot.spent * grown)
                var layer = context
                layer.clip(to: PennyStyle.column(CGRect(x: x - bar / 2, y: columnTop, width: bar, height: max(0.5, frame.bottom - columnTop)), radius: 4, up: true))
                var below = 0.0
                for (part, color) in [(slot.good, PennyStyle.green), (slot.fair, PennyStyle.yellow), (slot.bad, PennyStyle.red)] where part > 0 {
                    let from = y(below * grown), to = y((below + part) * grown)
                    layer.fill(Path(CGRect(x: x - bar / 2, y: to, width: bar, height: max(0.5, from - to + (below > 0 ? 0 : 0.5)))), with: .color(color.opacity(0.88 * faded)))
                    below += part
                }
                value(PennyStyle.short(slot.spent), PennyStyle.words, columnTop, above: true)
            case .cbh:
                if slot.spent > 0 || slot.cbh != 0 {
                    let zero = y(0), end = y(slot.cbh * grown), up = slot.cbh >= 0, money = PennyStyle.money(slot.cbh)
                    context.fill(PennyStyle.column(CGRect(x: x - bar / 2, y: min(zero, end), width: bar, height: max(0.5, abs(zero - end))), radius: 3, up: up),
                                 with: .color(money.opacity(0.88 * faded)))
                    if abs(slot.cbh) >= 0.5 { value(PennyStyle.short(slot.cbh), money, end, above: up) }
                }
                if !slot.label.isEmpty {
                    let label = PennyStyle.write(context, slot.label, 9.5, slot.wash.map(PennyStyle.tone) ?? PennyStyle.muted, slot.wash != nil ? .semibold : .regular)
                    context.draw(label, at: CGPoint(x: x, y: frame.bottom + 3), anchor: .top)
                }
            }
        }

        if kind == .roas {
            for (line, at, color) in [(profit.profitable, profitableY, PennyStyle.green), (profit.breakeven, breakevenY, PennyStyle.red)] {
                var rule = Path(); rule.move(to: CGPoint(x: frame.left, y: y(line))); rule.addLine(to: CGPoint(x: frame.right, y: y(line)))
                context.stroke(rule, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                context.draw(PennyStyle.write(context, PennyStyle.times(line), 9.5, color, .semibold), at: CGPoint(x: Self.axisWidth - 6, y: at), anchor: .trailing)
            }
        } else if kind == .cbh {
            var zero = Path(); zero.move(to: CGPoint(x: frame.left, y: y(0))); zero.addLine(to: CGPoint(x: frame.right, y: y(0)))
            context.stroke(zero, with: .color(PennyStyle.baseline), lineWidth: 1)
        }
    }

    /// A value past the top of the chart: a small arrow at the top of its column and the value over it.
    func past(_ context: GraphicsContext, x: CGFloat, top: CGFloat, _ value: String, _ color: Color, _ opacity: Double, band: CGFloat) {
        var arrow = Path()
        arrow.move(to: CGPoint(x: x - 3.5, y: top + 1)); arrow.addLine(to: CGPoint(x: x, y: top - 3)); arrow.addLine(to: CGPoint(x: x + 3.5, y: top + 1)); arrow.closeSubpath()
        context.fill(arrow, with: .color(color.opacity(opacity)))
        var text = PennyStyle.write(context, value, 9, color.opacity(opacity), .semibold)
        if PennyStyle.width(text) > band - 2 { text = PennyStyle.write(context, value.replacingOccurrences(of: "×", with: ""), 9, color.opacity(opacity), .semibold) }
        if PennyStyle.width(text) <= band - 2 { context.draw(text, at: CGPoint(x: x, y: top - 4), anchor: .bottom) }
    }
}

/// The layer over one of the stacked charts: the column under the pointer washed lighter, the picked one outlined, the
/// tip on the top chart, and a press to pick a column.
struct PennyHoverLayer: View {
    let slots: [PennySlot]
    let labels: Bool
    @ObservedObject var hover: PennyHover
    var tips = false
    var selected: Binding<String?>? = nil

    var body: some View {
        GeometryReader { geometry in
            let frame = ColumnFrame.of(geometry.size, count: slots.count, labels: labels)
            let under: CGFloat = labels ? 16 : 0
            let hovered = slots.firstIndex { $0.id == hover.id }
            let picked = slots.firstIndex { $0.id == selected?.wrappedValue }
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    if let hovered { context.fill(Path(roundedRect: frame.column(hovered, under: under), cornerRadius: 4), with: .color(.white.opacity(0.06))) }
                    if let picked {
                        context.stroke(Path(roundedRect: frame.column(picked, under: under).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4), with: .color(.white.opacity(0.4)), lineWidth: 1)
                    }
                }
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        var id: String?
                        if case let .active(point) = phase, let index = frame.index(at: point.x) { id = slots[index].id }
                        if hover.id != id || !hover.tip { hover.set(id) }
                    }
                    .onTapGesture { point in
                        guard let selected, let index = frame.index(at: point.x), slots[index].spent > 0 else { return }
                        selected.wrappedValue = selected.wrappedValue == slots[index].id ? nil : slots[index].id
                    }
                if tips, hover.tip, let hovered {
                    let x = frame.center(hovered), right = x + frame.band / 2 + 8
                    ChartTip(title: slots[hovered].title, lines: slots[hovered].tip)
                        .offset(x: max(0, right + ChartTip.width > geometry.size.width ? x - frame.band / 2 - 8 - ChartTip.width : right), y: frame.top)
                }
            }
        }
    }
}

// MARK: Days

/// The days on a calendar, each coloured by its ROAS with its spend and revenue; a press opens the day. It sits under
/// the charts' plot, past their axis, so a week of it lines up with their columns; a day under the pointer here lights
/// its column on the charts, and a column under the pointer there lights its day here.
struct DaysCalendar: View {
    let days: [Ledger.DayRead]
    let profit: Ledger.Profit
    @Binding var selected: String?
    var hover: PennyHover

    var body: some View {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(Self.weekdays, id: \.self) { name in
                Text(L(name)).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(PennyStyle.muted).padding(.bottom, 3)
            }
            ForEach(Self.cells(days.map(\.day)), id: \.self) { day in cell(day, byDay[day]).padding(3) }
        }
        // The cells' own 3 points taken off, so their edges meet the plot's.
        .padding(.leading, PennyColumns.axisWidth - 3).padding(.trailing, 1).padding(.top, 16)
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
        .background { if read == nil { RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.015)) } else { CalendarLight(day: day, hover: hover) } }
        .overlay(alignment: .leading) { if ran { UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7).fill(color).frame(width: 3) } }
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(chosen ? Color.white.opacity(0.6) : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { if ran { selected = chosen ? nil : day } }
        .onHover { inside in
            guard ran else { return }
            if inside { hover.set(day, tip: false) } else if hover.id == day { hover.set(nil) }
        }
    }
}

/// A calendar day's face, lighter while its column (or the day itself) is under the pointer. Only this watches the
/// pointer, so moving it redraws no more than the faces.
struct CalendarLight: View {
    let day: String
    @ObservedObject var hover: PennyHover
    var body: some View {
        RoundedRectangle(cornerRadius: 7).fill(.white.opacity(hover.id == day ? 0.08 : 0.035)).animation(.easeOut(duration: 0.12), value: hover.id == day)
    }
}

/// One day hour by hour: its totals, then ROAS, spend and CBH each hour, each hour's column washed by how it does over
/// all the days read (`overall`; nil with one day).
struct DayDrill: View {
    let day: Ledger.DayRead
    let profit: Ledger.Profit
    var overall: [Ledger.HourRead]? = nil
    var days = 0
    var grow = true
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
            PennyColumns(slots: PennySlot.hours(of: day, profit: profit, overall: overall), profit: profit, height: 120, grow: grow,
                         washName: L("column: the hour over all %@ days", days))
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
/// one measure per chart. Spend and revenue are a day's (2026-11-07): the first and last weeks of a range are often a
/// day or two, and their totals put beside a whole week's said nothing. Each chart has a tip under the pointer.
struct WeeksView: View {
    let weeks: [Ledger.WeekRead]
    let profit: Ledger.Profit
    var grow = false

    static func label(_ week: Ledger.WeekRead) -> String { PennyStyle.day(week.start) }

    static func days(_ count: Int) -> String { count == 1 ? L("1 day") : L("%@ days", count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                ForEach(weeks) { week in card(week) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], alignment: .leading, spacing: 22) {
                small(L("Spend and revenue a day"), keys: {
                    LegendKey(name: L("Spent"), color: PennyStyle.muted)
                    LegendKey(name: L("Revenue"), color: PennyStyle.blue)
                }) { WeekChart(weeks: weeks, profit: profit, kind: .spendAndRevenue, grow: grow) }
                small(L("Night against peak"), keys: {
                    LegendKey(name: L("12 AM–6 AM"), color: PennyStyle.violet)
                    LegendKey(name: L("9 AM–9 PM"), color: PennyStyle.blue)
                    LegendKey(name: L("breakeven"), color: PennyStyle.red, shape: .dashed)
                }) { WeekChart(weeks: weeks, profit: profit, kind: .nightAgainstPeak, grow: grow) }
                small(L("Dead spend"), keys: { Text(L("share of spend in hours under 1×")).font(.system(size: 10.5)).foregroundStyle(.secondary) }) {
                    WeekChart(weeks: weeks, profit: profit, kind: .deadSpend, grow: grow)
                }
                small(L("CPM"), keys: { Text(L("what a thousand impressions cost: lower is better")).font(.system(size: 10.5)).foregroundStyle(.secondary) }) {
                    WeekChart(weeks: weeks, profit: profit, kind: .cpm, grow: grow)
                }
            }
        }
    }

    func card(_ week: Ledger.WeekRead) -> some View {
        let color = PennyStyle.roas(week.numbers.roas, profit)
        return VStack(alignment: .leading, spacing: 4) {
            Text(L("Week of %@", Self.label(week)) + (week.days < 7 ? " · " + Self.days(week.days) : "")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(PennyStyle.times(week.numbers.roas)).font(.system(size: 22, weight: .bold)).foregroundStyle(color)
            Group {
                Text(L("%@ spent · %@ back", PennyStyle.short(week.numbers.spent), PennyStyle.short(week.numbers.revenue)))
                Text(L("%@ orders · %@ a day", Ledger.whole(week.numbers.orders), PennyStyle.short(week.numbers.spent / Double(max(week.days, 1)))))
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            FlowLayout(spacing: 12) { keys() }
            chart().frame(height: 176)
        }
    }
}

/// One of the weeks' charts, one measure each; the week under the pointer washed lighter with its numbers beside it.
struct WeekChart: View {
    enum Kind { case spendAndRevenue, nightAgainstPeak, deadSpend, cpm }
    let weeks: [Ledger.WeekRead]
    let profit: Ledger.Profit
    let kind: Kind
    @State private var hover: Int?
    @State private var growFrom: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let left = PennyColumns.axisWidth, top: CGFloat = 18, growTime = 0.52

    init(weeks: [Ledger.WeekRead], profit: Ledger.Profit, kind: Kind, grow: Bool) {
        self.weeks = weeks; self.profit = profit; self.kind = kind
        _growFrom = State(initialValue: grow ? Date() : nil)
    }

    var shown: [Ledger.WeekRead] { kind == .cpm ? weeks.filter { $0.numbers.cpm != nil } : weeks }

    static func perDay(_ week: Ledger.WeekRead, _ value: Double) -> Double { value / Double(max(week.days, 1)) }

    func index(_ x: CGFloat, width: CGFloat) -> Int? {
        let count = shown.count, right = width - 4
        guard count > 0, x >= Self.left, x < right else { return nil }
        return min(count - 1, Int((x - Self.left) / ((right - Self.left) / CGFloat(count))))
    }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(paused: growFrom == nil)) { context in
                let grown = growFrom.map { PennyStyle.eased(context.date.timeIntervalSince($0) / Self.growTime) } ?? 1
                Canvas { canvas, size in draw(canvas, size: size, grown: grown) }
            }
            .overlay(alignment: .topLeading) {
                if let hover, hover < shown.count {
                    let band = (geometry.size.width - 4 - Self.left) / CGFloat(shown.count), x = Self.left + band * (CGFloat(hover) + 0.5)
                    let beside = x + band / 2 + 6
                    ChartTip(title: L("Week of %@", WeeksView.label(shown[hover])), lines: tip(shown[hover]))
                        .offset(x: beside + ChartTip.width <= geometry.size.width ? beside : max(0, x - band / 2 - 6 - ChartTip.width), y: Self.top - 14)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                var at: Int?
                if case let .active(point) = phase { at = index(point.x, width: geometry.size.width) }
                if hover != at { hover = at }
            }
        }
        .zIndex(hover == nil ? 0 : 1)
        .onAppear { if reduceMotion { growFrom = nil } }
        .task {
            guard growFrom != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64((Self.growTime + 0.05) * 1_000_000_000))
            growFrom = nil
        }
    }

    func draw(_ context: GraphicsContext, size: CGSize, grown: Double) {
        let left = Self.left, right = size.width - 4, top = Self.top, bottom = size.height - 30
        let shown = shown
        guard !shown.isEmpty, right > left, bottom > top else { return }
        var low = 0.0, high: Double
        switch kind {
        case .spendAndRevenue: high = max((shown.map { Self.perDay($0, max($0.numbers.spent, $0.numbers.revenue)) }.max() ?? 0) * 1.04, 1)
        case .nightAgainstPeak: high = max(max(shown.map { max($0.night.roas ?? 0, $0.peak.roas ?? 0) }.max() ?? 0, profit.breakeven) * 1.06, 1)
        case .deadSpend: high = max(0.5, (shown.map(\.dead).max() ?? 0) * 1.06)
        case .cpm:
            let values = shown.map { $0.numbers.cpm ?? 0 }, most = values.max() ?? 0, least = values.min() ?? 0
            let spread = max(most - least, most * 0.1)
            low = max(0, least - spread * 0.8)
            high = max(most + spread * 0.5, low + 1)
        }
        func y(_ value: Double) -> CGFloat { bottom - CGFloat((min(max(value, low), high) - low) / (high - low)) * (bottom - top) }
        let band = (right - left) / CGFloat(shown.count)
        func center(_ index: Int) -> CGFloat { left + band * (CGFloat(index) + 0.5) }
        if let hover, hover < shown.count {
            context.fill(Path(roundedRect: CGRect(x: center(hover) - band / 2 + 1, y: top - 14, width: band - 2, height: bottom - top + 14 + 28), cornerRadius: 4), with: .color(.white.opacity(0.06)))
        }
        for tick in PennyStyle.ticks(low, high) {
            let at = y(tick)
            var line = Path(); line.move(to: CGPoint(x: left, y: at)); line.addLine(to: CGPoint(x: right, y: at))
            context.stroke(line, with: .color(PennyStyle.grid), lineWidth: 1)
            let label: String
            switch kind {
            case .spendAndRevenue: label = PennyStyle.short(tick)
            case .nightAgainstPeak: label = String(format: tick != tick.rounded() ? "%.1f×" : "%.0f×", tick)
            case .deadSpend: label = String(format: "%.0f%%", tick * 100)
            case .cpm: label = String(format: high - low < 4 ? "$%.1f" : "$%.0f", tick)
            }
            context.draw(PennyStyle.write(context, label, 9.5, PennyStyle.muted), at: CGPoint(x: left - 6, y: at), anchor: .trailing)
        }
        func bar(_ x: CGFloat, _ width: CGFloat, _ value: Double, _ color: Color) {
            let at = y(low + (value - low) * grown)
            if bottom - at > 0.5 { context.fill(PennyStyle.column(CGRect(x: x - width / 2, y: at, width: width, height: bottom - at), radius: 4, up: true), with: .color(color.opacity(0.9))) }
        }
        func note(_ text: String, _ x: CGFloat, _ at: CGFloat, _ color: Color = PennyStyle.words) {
            let written = PennyStyle.write(context, text, 9.5, color.opacity(min(max(grown * 1.6 - 0.6, 0), 1)), .semibold)
            if PennyStyle.width(written) <= band - 4 || shown.count == 1 { context.draw(written, at: CGPoint(x: x, y: at - 1), anchor: .bottom) }
        }
        let width = max(4, min(30, band * 0.28))
        var points: [CGPoint] = []
        for (index, week) in shown.enumerated() {
            let x = center(index)
            switch kind {
            case .spendAndRevenue:
                let spent = Self.perDay(week, week.numbers.spent), revenue = Self.perDay(week, week.numbers.revenue)
                bar(x - width / 2 - 1.5, width, spent, PennyStyle.muted)
                bar(x + width / 2 + 1.5, width, revenue, PennyStyle.blue)
                note(PennyStyle.short(revenue), x + width / 2 + 1.5, y(revenue * grown), PennyStyle.blue)
            case .nightAgainstPeak:
                bar(x - width / 2 - 1.5, width, week.night.roas ?? 0, PennyStyle.violet)
                bar(x + width / 2 + 1.5, width, week.peak.roas ?? 0, PennyStyle.blue)
            case .deadSpend:
                let color = week.dead > 0.3 ? PennyStyle.red : week.dead > 0.2 ? PennyStyle.yellow : PennyStyle.green
                bar(x, max(4, min(40, band * 0.42)), week.dead, color)
                note(Ledger.percent(week.dead), x, y(week.dead * grown), color)
            case .cpm:
                points.append(CGPoint(x: x, y: y(week.numbers.cpm ?? 0)))
            }
            context.draw(PennyStyle.write(context, WeeksView.label(week), 9.5, hover == index ? .primary : PennyStyle.muted), at: CGPoint(x: x, y: bottom + 3), anchor: .top)
            if week.days < 7 {
                // A week the range cuts short says so under its date.
                context.draw(PennyStyle.write(context, WeeksView.days(week.days), 8.5, PennyStyle.muted.opacity(0.7)), at: CGPoint(x: x, y: bottom + 15), anchor: .top)
            }
        }
        if kind == .nightAgainstPeak {
            var rule = Path(); rule.move(to: CGPoint(x: left, y: y(profit.breakeven))); rule.addLine(to: CGPoint(x: right, y: y(profit.breakeven)))
            context.stroke(rule, with: .color(PennyStyle.red.opacity(0.85)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        if kind == .cpm, let first = points.first, let last = points.last {
            // The line draws in from the left as it grows.
            var layer = context
            layer.clip(to: Path(CGRect(x: 0, y: 0, width: left + (right - left) * grown + 8, height: size.height)))
            var area = Path(); area.move(to: CGPoint(x: first.x, y: bottom))
            for point in points { area.addLine(to: point) }
            area.addLine(to: CGPoint(x: last.x, y: bottom)); area.closeSubpath()
            layer.fill(area, with: .linearGradient(Gradient(colors: [PennyStyle.blue.opacity(0.18), PennyStyle.blue.opacity(0)]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
            var line = Path(); line.addLines(points)
            layer.stroke(line, with: .color(PennyStyle.blue), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for (index, point) in points.enumerated() {
                let scale: CGFloat = hover == index ? 1.25 : 1
                layer.fill(Path(ellipseIn: CGRect(x: point.x - 5.5 * scale, y: point.y - 5.5 * scale, width: 11 * scale, height: 11 * scale)), with: .color(PennyStyle.surface))
                layer.fill(Path(ellipseIn: CGRect(x: point.x - 3.6 * scale, y: point.y - 3.6 * scale, width: 7.2 * scale, height: 7.2 * scale)), with: .color(PennyStyle.blue))
                let written = PennyStyle.write(layer, Ledger.money(shown[index].numbers.cpm ?? 0), 9.5, PennyStyle.blue.opacity(min(max(grown * 1.6 - 0.6, 0), 1)), .semibold)
                if PennyStyle.width(written) <= band - 4 || shown.count == 1 { layer.draw(written, at: CGPoint(x: point.x, y: point.y - 6), anchor: .bottom) }
            }
        }
    }

    func tip(_ week: Ledger.WeekRead) -> [PennyTipLine] {
        switch kind {
        case .spendAndRevenue:
            return [PennyTipLine(name: L("Spent a day"), value: Ledger.money(Self.perDay(week, week.numbers.spent))),
                    PennyTipLine(name: L("Revenue a day"), value: Ledger.money(Self.perDay(week, week.numbers.revenue))),
                    PennyTipLine(name: L("ROAS"), value: PennyStyle.times(week.numbers.roas), color: PennyStyle.roas(week.numbers.roas, profit)),
                    PennyTipLine(name: L("Days"), value: "\(week.days)")]
        case .nightAgainstPeak:
            return [PennyTipLine(name: L("12 AM–6 AM ROAS"), value: PennyStyle.times(week.night.roas), color: PennyStyle.roas(week.night.roas, profit)),
                    PennyTipLine(name: L("9 AM–9 PM ROAS"), value: PennyStyle.times(week.peak.roas), color: PennyStyle.roas(week.peak.roas, profit)),
                    PennyTipLine(name: L("Night spent"), value: Ledger.money(week.night.spent)),
                    PennyTipLine(name: L("Peak spent"), value: Ledger.money(week.peak.spent))]
        case .deadSpend:
            return [PennyTipLine(name: L("Dead spend"), value: Ledger.percent(week.dead), color: week.dead > 0.3 ? PennyStyle.red : nil),
                    PennyTipLine(name: L("Spent under 1×"), value: Ledger.money(week.deadSpent)),
                    PennyTipLine(name: L("Spent in all"), value: Ledger.money(week.numbers.spent))]
        case .cpm:
            return [PennyTipLine(name: L("CPM"), value: week.numbers.cpm.map(Ledger.money) ?? "–"),
                    PennyTipLine(name: L("Impressions"), value: Ledger.whole(week.numbers.impressions)),
                    PennyTipLine(name: L("Spent"), value: Ledger.money(week.numbers.spent))]
        }
    }
}

// MARK: Figures

/// A headline number: its name, value (coloured when it has a verdict) and the change on the days before; under the
/// pointer, what the change is against and the value then (`was`).
struct PennyFigure: View {
    let name: String
    let value: String
    var color: Color? = nil
    /// The change against the days before, and whether up is good.
    var change: Double? = nil
    var upIsGood = true
    /// A change that is neither good nor bad by itself (spend), shown grey.
    var neutral = false
    var was: String? = nil
    /// A smaller figure that belongs with this one, in a pill at the top right: CBH's share of revenue, spend and
    /// revenue an order (2026-11-10: they were cards of their own, and the page read as two rows of sixteen).
    var pill: String? = nil
    var pillColor: Color? = nil
    var pillTip: String? = nil
    /// Its share of revenue, in a pill right after its name (2026-11-10, you asked: every money figure with its %).
    var share: String? = nil
    var shareColor: Color? = nil
    var shareTip: String? = nil
    /// A smaller figure on the bottom line, right of the change: the ads' own spend and revenue beside every source's.
    var aside: String? = nil
    var asideTip: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // The name keeps its room; a pill too long for what's left shrinks a little, then cuts.
                Text(L(name)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                if let share { Self.pill(share, shareColor, shareTip).fixedSize() }
                Spacer(minLength: 0)
                if let pill { Self.pill(pill, pillColor, pillTip) }
            }
            .frame(height: 16)
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(color ?? .primary).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                Self.change(change, upIsGood: upIsGood, neutral: neutral, was: was)
                if let aside {
                    Spacer(minLength: 0)
                    Text(aside).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(PennyStyle.muted).lineLimit(1)
                        .minimumScaleFactor(0.75).help(asideTip ?? "")
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .leading) { if let color { UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9).fill(color).frame(width: 3) } }
    }

    static func pill(_ text: String, _ color: Color?, _ tip: String?) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.75)
            .foregroundStyle(color.map(PennyStyle.light) ?? PennyStyle.words)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background((color ?? .white).opacity(color == nil ? 0.08 : 0.26), in: Capsule())
            .help(tip ?? "")
    }

    /// "▲ 12.0%" in green or red by whether that's good (grey when neither), its tip what it was; a blank line without one.
    @ViewBuilder static func change(_ change: Double?, upIsGood: Bool = true, neutral: Bool = false, was: String?) -> some View {
        if let change, change.isFinite, abs(change) >= 0.005 {
            let good = (change > 0) == upIsGood
            Text(said(change)).font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(neutral ? PennyStyle.muted : good ? PennyStyle.green : PennyStyle.red)
                .help(was ?? "")
        } else {
            Text(" ").font(.system(size: 10))
        }
    }

    static func said(_ change: Double) -> String { (change > 0 ? "▲ " : "▼ ") + Ledger.percent(abs(change)) }
}

/// Figures that read together in one card, side by side, each with its change: CPM, CTR and CR (2026-11-10).
struct PennyFigures: View {
    struct Part { var name: String; var value: String; var change: Double?; var upIsGood = true; var was: String? }
    let parts: [Part]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(part.name)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).frame(height: 16)
                    Text(part.value).font(.system(size: 20, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    PennyFigure.change(part.change, upIsGood: part.upIsGood, was: part.was)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// How many of a figures row's columns a card takes.
struct FigureSpan: LayoutValueKey { static let defaultValue = 1 }

/// An arrow between two cards of a row that reads in → out: drawn in the gap before the next card, or not at all when
/// that card starts a row.
struct FigureLink: LayoutValueKey { static let defaultValue = false }

/// Figure cards in rows of 6 equal columns, or 3 or 2 when the window is narrower. A card takes `FigureSpan` columns;
/// the cards in a row take its height; `FigureLink` arrows sit in the gaps.
struct FigureFlow: Layout {
    var narrowest: CGFloat = 150
    var gap: CGFloat = 8

    func columns(_ width: CGFloat) -> Int { [6, 3, 2].first { (width - gap * CGFloat($0 - 1)) / CGFloat($0) >= narrowest } ?? 1 }

    typealias Cell = (index: Int, at: Int, span: Int, link: Int?)

    func rows(_ subviews: Subviews, columns: Int) -> [[Cell]] {
        var rows: [[Cell]] = [[]], used = 0, link: Int?
        for index in subviews.indices {
            if subviews[index][FigureLink.self] { link = index; continue }
            let span = min(columns, max(1, subviews[index][FigureSpan.self]))
            if used + span > columns { rows.append([]); used = 0 }
            rows[rows.count - 1].append((index, used, span, link)); used += span; link = nil
        }
        return rows.filter { !$0.isEmpty }
    }

    func layout(_ width: CGFloat, _ subviews: Subviews, place: ((Int, CGRect) -> Void)? = nil) -> CGFloat {
        let count = columns(width), unit = (width - gap * CGFloat(count - 1)) / CGFloat(count)
        var y: CGFloat = 0, shown = Set<Int>()
        for (number, row) in rows(subviews, columns: count).enumerated() {
            if number > 0 { y += gap }
            let widths = row.map { unit * CGFloat($0.span) + gap * CGFloat($0.span - 1) }
            let tallest = zip(row, widths).map { subviews[$0.index].sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
            for (cell, cellWidth) in zip(row, widths) {
                let x = CGFloat(cell.at) * (unit + gap)
                place?(cell.index, CGRect(x: x, y: y, width: cellWidth, height: tallest))
                if let link = cell.link, cell.at > 0 {
                    let side = min(10, gap - 4)
                    place?(link, CGRect(x: x - gap / 2 - side / 2, y: y + tallest / 2 - side / 2, width: side, height: side))
                    shown.insert(link)
                }
            }
            y += tallest
        }
        for index in subviews.indices where subviews[index][FigureLink.self] && !shown.contains(index) { place?(index, .zero) }
        return y
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? narrowest * 6 + gap * 5
        return CGSize(width: width, height: layout(width, subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = layout(bounds.width, subviews) { index, frame in
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

/// The arrow between two cards of a money row; it takes the size it is given, none when it isn't drawn.
struct FigureArrow: View {
    var body: some View {
        Image(systemName: "arrow.right").resizable().scaledToFit().fontWeight(.semibold).foregroundStyle(PennyStyle.muted)
            .layoutValue(key: FigureLink.self, value: true)
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
                text = text.foregroundColor(PennyStyle.words)
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
