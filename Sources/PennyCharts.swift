import SwiftUI
import Charts

/// Penny's media-buying charts (2026-11-06), drawn as the Campaign Breakdown dashboard drew them (you asked for its
/// detail): the days as spend bars coloured by ROAS with the ROAS line, dead spend and breakeven; a calendar; one day
/// hour by hour; the hours with their bad-to-good-day range; spend by the ROAS it brought back; and the weeks. ROAS
/// lines share the chart with dollars on a second axis. Breakeven and the profitable line come from CBH.
enum PennyStyle {
    static let green = Color(red: 27 / 255, green: 175 / 255, blue: 122 / 255)
    static let yellow = Color(red: 237 / 255, green: 161 / 255, blue: 0)
    static let red = Color(red: 227 / 255, green: 73 / 255, blue: 72 / 255)
    static let orange = Color(red: 235 / 255, green: 104 / 255, blue: 52 / 255)
    static let blue = Color(red: 42 / 255, green: 120 / 255, blue: 214 / 255)
    static let muted = Color(red: 137 / 255, green: 135 / 255, blue: 129 / 255)
    static let panel = Color.white.opacity(0.035)

    /// Green from the profitable line, yellow from breakeven, red under it.
    static func roas(_ value: Double?, _ profit: Ledger.Profit) -> Color {
        guard let value else { return muted }
        return value >= profit.profitable ? green : value >= profit.breakeven ? yellow : red
    }

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

    /// The ROAS axis beside dollars: its top, and what one ROAS is worth in dollars on the chart.
    static func scale(dollars: Double, roas: [Double]) -> (top: Double, roasTop: Double, perRoas: Double) {
        let top = max(dollars * 1.12, 1)
        let roasTop = min(6, max(3, ((roas.max() ?? 0) * 1.1).rounded(.up)))
        return (top, roasTop, top / roasTop)
    }
}

/// A titled panel: a heading, a line on how to read it, then its content.
struct PennyPanel<Content: View, Accessory: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let note { Text(md: note).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                accessory()
            }
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(PennyStyle.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06)))
    }
}

extension PennyPanel where Accessory == EmptyView {
    init(title: String, note: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, note: note, accessory: { EmptyView() }, content: content)
    }
}

/// A legend entry: a swatch (a bar, a line or a dashed line) and its name.
struct LegendKey: View {
    enum Shape { case bar, line, dashed, dot }
    let name: String
    let color: Color
    var shape = Shape.bar

    var body: some View {
        HStack(spacing: 5) {
            switch shape {
            case .bar: RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            case .line: Capsule().fill(color).frame(width: 14, height: 2.5)
            case .dashed: Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 14, y: 0)) }.stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 14, height: 2)
            case .dot: Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

/// The floating box beside a chart's pointer: a title and lines of numbers.
struct ChartTip: View {
    let title: String
    let lines: [(String, String, Color?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(PennyStyle.muted)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 10) {
                    Text(line.0).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(line.1).fontWeight(.medium).foregroundStyle(line.2 ?? .primary)
                }.font(.system(size: 11).monospacedDigit())
            }
        }
        .padding(8).frame(width: 190)
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 26 / 255).opacity(0.97), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .allowsHitTesting(false)
    }
}

/// Places a tip over a chart at the pointer's x, kept inside the chart.
struct TipPlacement<Tip: View>: View {
    let x: CGFloat
    let width: CGFloat
    @ViewBuilder var tip: () -> Tip

    var body: some View {
        tip().position(x: min(max(x + 105, 100), width - 100), y: 62)
    }
}

// MARK: Days

/// Spend each day as a bar coloured by its ROAS, the ROAS line, the share of spend in hours under 1× (dashed), and
/// breakeven. A press on a day opens it hour by hour.
struct TrendChart: View {
    let days: [Ledger.DayRead]
    let profit: Ledger.Profit
    @Binding var selected: String?
    @State private var hovered: String?

    var body: some View {
        let scale = PennyStyle.scale(dollars: days.map(\.numbers.spent).max() ?? 0, roas: days.compactMap(\.numbers.roas))
        let k = scale.perRoas
        Chart {
            ForEach(days) { day in
                if day.weekend {
                    RectangleMark(x: .value("Day", day.day), yStart: .value("", 0), yEnd: .value("", scale.top))
                        .foregroundStyle(.white.opacity(0.025))
                }
                BarMark(x: .value("Day", day.day), y: .value("Spent", day.numbers.spent), width: .ratio(0.62))
                    .foregroundStyle(PennyStyle.roas(day.numbers.roas, profit).opacity(selected == nil || selected == day.day ? 0.6 : 0.25))
                    .cornerRadius(3)
            }
            ForEach(days) { day in
                LineMark(x: .value("Day", day.day), y: .value("Dead", day.dead * scale.top), series: .value("", "dead"))
                    .foregroundStyle(PennyStyle.muted.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                    .interpolationMethod(.monotone)
            }
            ForEach(days.filter { $0.numbers.roas != nil }) { day in
                let roas = min(day.numbers.roas ?? 0, scale.roasTop)
                LineMark(x: .value("Day", day.day), y: .value("ROAS", roas * k), series: .value("", "roas"))
                    .foregroundStyle(PennyStyle.orange).lineStyle(StrokeStyle(lineWidth: 2.4)).interpolationMethod(.monotone)
                PointMark(x: .value("Day", day.day), y: .value("ROAS", roas * k))
                    .foregroundStyle(PennyStyle.roas(day.numbers.roas, profit)).symbolSize(hovered == day.day ? 90 : 45)
            }
            RuleMark(y: .value("Breakeven", profit.breakeven * k))
                .foregroundStyle(PennyStyle.red.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text(L("breakeven %@", PennyStyle.times(profit.breakeven))).font(.system(size: 9)).foregroundStyle(PennyStyle.red.opacity(0.9))
                }
            if let hovered { RuleMark(x: .value("Day", hovered)).foregroundStyle(.white.opacity(0.18)) }
        }
        .chartYScale(domain: 0 ... scale.top)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let day = value.as(String.self) {
                        Text(PennyStyle.day(day)).foregroundStyle(days.first { $0.day == day }?.weekend == true ? Color.white.opacity(0.4) : PennyStyle.muted)
                    }
                }.font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                AxisValueLabel { if let dollars = value.as(Double.self) { Text(PennyStyle.short(dollars)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
            }
            AxisMarks(position: .trailing, values: Array(stride(from: 0.0, through: scale.roasTop, by: 1)).map { $0 * k }) { value in
                AxisValueLabel { if let y = value.as(Double.self) { Text(String(format: "%.0f×", y / k)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.orange)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case let .active(point) = phase { hovered = proxy.value(atX: point.x - plot.minX, as: String.self) } else { hovered = nil }
                    }
                    .onTapGesture { point in
                        if let day = proxy.value(atX: point.x - plot.minX, as: String.self) { selected = selected == day ? nil : day }
                    }
                if let hovered, let day = days.first(where: { $0.day == hovered }), let x = proxy.position(forX: hovered) {
                    TipPlacement(x: plot.minX + x, width: geometry.size.width) {
                        ChartTip(title: PennyStyle.day(day.day) + (day.weekend ? " · " + L("weekend") : ""), lines: [
                            (L("Spent"), Ledger.money(day.numbers.spent), nil),
                            (L("Revenue"), Ledger.money(day.numbers.revenue), nil),
                            (L("ROAS"), PennyStyle.times(day.numbers.roas), PennyStyle.roas(day.numbers.roas, profit)),
                            (L("CBH"), Ledger.money(day.cbh), day.cbh < 0 ? PennyStyle.red : PennyStyle.green),
                            (L("Orders"), Ledger.whole(day.numbers.orders), nil),
                            (L("Dead spend"), Ledger.percent(day.dead), day.dead > 0.3 ? PennyStyle.red : nil)])
                    }
                }
            }
        }
        .frame(height: 250)
    }
}

/// The days on a calendar, each coloured by its ROAS with its spend and revenue; a press opens the day.
struct DaysCalendar: View {
    let days: [Ledger.DayRead]
    let profit: Ledger.Profit
    @Binding var selected: String?

    var body: some View {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
            ForEach(Self.weekdays, id: \.self) { name in
                Text(L(name)).font(.system(size: 9, weight: .semibold)).foregroundStyle(PennyStyle.muted)
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
        let color = read.map { PennyStyle.roas($0.numbers.roas, profit) } ?? .clear
        let chosen = selected == day
        return VStack(alignment: .leading, spacing: 1) {
            Text(day.hasSuffix("-01") || read?.day == days.first?.day ? PennyStyle.day(day) : String(Int(day.suffix(2)) ?? 0))
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(read == nil ? PennyStyle.muted.opacity(0.5) : .secondary)
            if let read, read.numbers.spent > 0 {
                Text(PennyStyle.times(read.numbers.roas)).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(color)
                Text("\(PennyStyle.short(read.numbers.spent)) → \(PennyStyle.short(read.numbers.revenue))").font(.system(size: 8.5).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(5).frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .topLeading)
        .background(read == nil ? Color.white.opacity(0.015) : color.opacity(chosen ? 0.32 : 0.13), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(chosen ? color : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { if read != nil { selected = chosen ? nil : day } }
    }
}

/// One day hour by hour: spend bars coloured by each hour's ROAS, the ROAS line and breakeven, with its totals.
struct DayDrill: View {
    let day: Ledger.DayRead
    let profit: Ledger.Profit
    var close: (() -> Void)? = nil
    @State private var hovered: Int?

    var body: some View {
        let scale = PennyStyle.scale(dollars: day.hours.map(\.spent).max() ?? 0, roas: day.hours.compactMap(\.roas))
        let k = scale.perRoas
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(PennyStyle.day(day.day) + " · " + L("hour by hour")).font(.system(size: 12, weight: .semibold))
                stat(L("Spent"), Ledger.money(day.numbers.spent), nil)
                stat(L("Revenue"), Ledger.money(day.numbers.revenue), nil)
                stat(L("ROAS"), PennyStyle.times(day.numbers.roas), PennyStyle.roas(day.numbers.roas, profit))
                stat(L("CBH"), Ledger.money(day.cbh), day.cbh < 0 ? PennyStyle.red : PennyStyle.green)
                stat(L("Orders"), Ledger.whole(day.numbers.orders), nil)
                Spacer()
                if let close { Button { close() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help(L("Close")) }
            }
            Chart {
                ForEach(0 ..< 24, id: \.self) { hour in
                    let numbers = day.hours[hour]
                    BarMark(x: .value("Hour", hour), y: .value("Spent", numbers.spent), width: .fixed(18))
                        .foregroundStyle(PennyStyle.roas(numbers.spent > 0 ? numbers.roas : nil, profit).opacity(0.6)).cornerRadius(3)
                }
                ForEach((0 ..< 24).filter { day.hours[$0].spent > 0 }, id: \.self) { hour in
                    let roas = min(day.hours[hour].roas ?? 0, scale.roasTop)
                    LineMark(x: .value("Hour", hour), y: .value("ROAS", roas * k)).foregroundStyle(PennyStyle.orange).interpolationMethod(.monotone)
                    PointMark(x: .value("Hour", hour), y: .value("ROAS", roas * k)).foregroundStyle(PennyStyle.roas(day.hours[hour].roas, profit)).symbolSize(35)
                }
                RuleMark(y: .value("Breakeven", profit.breakeven * k)).foregroundStyle(PennyStyle.red.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .chartXScale(domain: -0.5 ... 23.5)
            .chartYScale(domain: 0 ... scale.top)
            .chartXAxis {
                AxisMarks(values: Array(stride(from: 0, to: 24, by: 3))) { value in
                    AxisValueLabel { if let hour = value.as(Int.self) { Text(PennyStyle.hour(hour)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel { if let dollars = value.as(Double.self) { Text(PennyStyle.short(dollars)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
                }
                AxisMarks(position: .trailing, values: Array(stride(from: 0.0, through: scale.roasTop, by: 1)).map { $0 * k }) { value in
                    AxisValueLabel { if let y = value.as(Double.self) { Text(String(format: "%.0f×", y / k)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.orange)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case let .active(point) = phase, let x = proxy.value(atX: point.x - plot.minX, as: Double.self) {
                                hovered = min(23, max(0, Int(x.rounded())))
                            } else { hovered = nil }
                        }
                    if let hovered, let x = proxy.position(forX: hovered) {
                        let numbers = day.hours[hovered]
                        TipPlacement(x: plot.minX + x, width: geometry.size.width) {
                            ChartTip(title: Ledger.hourName(hovered), lines: [
                                (L("Spent"), Ledger.money(numbers.spent), nil), (L("Revenue"), Ledger.money(numbers.revenue), nil),
                                (L("ROAS"), PennyStyle.times(numbers.roas), PennyStyle.roas(numbers.roas, profit)),
                                (L("Orders"), Ledger.whole(numbers.orders), nil), (L("CBH"), Ledger.money(profit.cbh(numbers)), profit.cbh(numbers) < 0 ? PennyStyle.red : nil)])
                        }
                    }
                }
            }
            .frame(height: 190)
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PennyStyle.orange.opacity(0.35)))
    }

    func stat(_ name: String, _ value: String, _ color: Color?) -> some View {
        HStack(spacing: 4) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(color ?? .primary)
        }
    }
}

// MARK: Hours

/// The hours over the days read: spend a day as bars coloured by verdict, the average ROAS line with each hour's
/// bad-to-good-day range as a whisker, breakeven and the profitable line.
struct HoursRangeChart: View {
    let reads: [Ledger.HourRead]
    let profit: Ledger.Profit
    @State private var hovered: Int?

    var body: some View {
        let ran = reads.filter { $0.days > 0 }
        let scale = PennyStyle.scale(dollars: ran.map(\.spentPerDay).max() ?? 0, roas: ran.compactMap { $0.ceiling ?? $0.numbers.roas })
        let k = scale.perRoas, cap = scale.roasTop
        Chart {
            ForEach(ran) { read in
                BarMark(x: .value("Hour", read.hour), y: .value("Spent a day", read.spentPerDay), width: .fixed(20))
                    .foregroundStyle(PennyStyle.verdict(read.verdict).opacity(hovered == nil || hovered == read.hour ? 0.42 : 0.2)).cornerRadius(3)
            }
            ForEach(ran.filter { $0.floor != nil && $0.ceiling != nil }) { read in
                RuleMark(x: .value("Hour", read.hour), yStart: .value("Bad day", min(read.floor!, cap) * k), yEnd: .value("Good day", min(read.ceiling!, cap) * k))
                    .foregroundStyle(.white.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.5))
                RectangleMark(x: .value("Hour", read.hour), y: .value("Bad day", min(read.floor!, cap) * k), width: 8, height: 1.5).foregroundStyle(.white.opacity(0.55))
                RectangleMark(x: .value("Hour", read.hour), y: .value("Good day", min(read.ceiling!, cap) * k), width: 8, height: 1.5).foregroundStyle(.white.opacity(0.55))
            }
            ForEach(ran.filter { $0.numbers.roas != nil }) { read in
                let roas = min(read.numbers.roas ?? 0, cap)
                LineMark(x: .value("Hour", read.hour), y: .value("ROAS", roas * k)).foregroundStyle(PennyStyle.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2.4)).interpolationMethod(.monotone)
                PointMark(x: .value("Hour", read.hour), y: .value("ROAS", roas * k))
                    .foregroundStyle(PennyStyle.verdict(read.verdict)).symbolSize(hovered == read.hour ? 110 : 55)
            }
            RuleMark(y: .value("Breakeven", profit.breakeven * k)).foregroundStyle(PennyStyle.red.opacity(0.75)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text(L("breakeven %@", PennyStyle.times(profit.breakeven))).font(.system(size: 9)).foregroundStyle(PennyStyle.red.opacity(0.9))
                }
            RuleMark(y: .value("Profitable", profit.profitable * k)).foregroundStyle(PennyStyle.green.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text(L("profitable %@", PennyStyle.times(profit.profitable))).font(.system(size: 9)).foregroundStyle(PennyStyle.green.opacity(0.9))
                }
        }
        .chartXScale(domain: -0.5 ... 23.5)
        .chartYScale(domain: 0 ... scale.top)
        .chartXAxis {
            AxisMarks(values: Array(0 ..< 24)) { value in
                AxisValueLabel { if let hour = value.as(Int.self) { Text(PennyStyle.hour(hour)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                AxisValueLabel { if let dollars = value.as(Double.self) { Text(PennyStyle.short(dollars)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
            }
            AxisMarks(position: .trailing, values: Array(stride(from: 0.0, through: cap, by: 1)).map { $0 * k }) { value in
                AxisValueLabel { if let y = value.as(Double.self) { Text(String(format: "%.0f×", y / k)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.orange)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case let .active(point) = phase, let x = proxy.value(atX: point.x - plot.minX, as: Double.self) {
                            hovered = min(23, max(0, Int(x.rounded())))
                        } else { hovered = nil }
                    }
                if let hovered, let read = reads.first(where: { $0.hour == hovered && $0.days > 0 }), let x = proxy.position(forX: hovered) {
                    TipPlacement(x: plot.minX + x, width: geometry.size.width) {
                        ChartTip(title: Ledger.hourName(read.hour) + " · " + HoursEfficiency.name(read.verdict), lines: [
                            (L("Days"), "\(read.days)", nil),
                            (L("Spent a day"), Ledger.money(read.spentPerDay), nil),
                            (L("ROAS"), PennyStyle.times(read.numbers.roas), PennyStyle.roas(read.numbers.roas, profit)),
                            (L("Bad → good day"), "\(PennyStyle.times(read.floor)) → \(PennyStyle.times(read.ceiling))", nil),
                            (L("Orders a day"), String(format: "%.1f", read.numbers.orders / Double(max(read.days, 1))), nil),
                            (L("CBH"), Ledger.money(read.cbh), read.cbh < 0 ? PennyStyle.red : PennyStyle.green)])
                    }
                }
            }
        }
        .frame(height: 270)
    }
}

/// The verdicts as a legend, each with what it means.
struct VerdictLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], alignment: .leading, spacing: 6) {
            ForEach([Ledger.HourRead.Verdict.reliable, .volatile, .thin, .losing, .costly, .dead], id: \.self) { verdict in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(PennyStyle.verdict(verdict)).frame(width: 8, height: 8).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(HoursEfficiency.name(verdict)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(PennyStyle.verdict(verdict))
                        Text(HoursEfficiency.meaning(verdict)).font(.system(size: 9.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: Budget

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
        case .nothing: return PennyStyle.red.opacity(0.95)
        case .under1: return PennyStyle.red.opacity(0.6)
        case .belowBreakeven: return PennyStyle.orange.opacity(0.75)
        case .thin: return PennyStyle.yellow.opacity(0.8)
        case .good: return PennyStyle.green.opacity(0.65)
        case .great: return PennyStyle.green
        }
    }

    var body: some View {
        let spent = bands.reduce(0) { $0 + $1.numbers.spent }, revenue = bands.reduce(0) { $0 + $1.numbers.revenue }
        let widest = max(bands.map { spent > 0 ? $0.numbers.spent / spent : 0 }.max() ?? 0, bands.map { revenue > 0 ? $0.numbers.revenue / revenue : 0 }.max() ?? 0, 0.01)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                LegendKey(name: L("share of spend"), color: PennyStyle.muted)
                LegendKey(name: L("share of revenue"), color: PennyStyle.blue)
            }
            ForEach(bands) { band in
                let spendShare = spent > 0 ? band.numbers.spent / spent : 0
                let revenueShare = revenue > 0 ? band.numbers.revenue / revenue : 0
                HStack(spacing: 10) {
                    Text(name(band)).font(.system(size: 11, weight: .medium)).frame(width: 128, alignment: .leading)
                    GeometryReader { geometry in
                        VStack(alignment: .leading, spacing: 2) {
                            RoundedRectangle(cornerRadius: 3).fill(color(band)).frame(width: max(2, geometry.size.width * spendShare / widest), height: 11)
                            RoundedRectangle(cornerRadius: 2).fill(PennyStyle.blue.opacity(0.75)).frame(width: max(revenueShare > 0 ? 2 : 0, geometry.size.width * revenueShare / widest), height: 5)
                        }.frame(maxHeight: .infinity, alignment: .center)
                    }.frame(height: 20)
                    Text(Ledger.percent(spendShare)).font(.system(size: 11, weight: .semibold).monospacedDigit()).frame(width: 48, alignment: .trailing)
                    Text(Ledger.money(band.numbers.spent)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary).frame(width: 78, alignment: .trailing)
                    Text("→ " + Ledger.money(band.numbers.revenue)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary).frame(width: 86, alignment: .trailing)
                    Text(Ledger.percent(revenueShare)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(PennyStyle.blue).frame(width: 46, alignment: .trailing)
                }
                .help(L("%@ hours of a day spent in this band", band.cells))
            }
        }
    }
}

// MARK: Weeks

/// The weeks from Monday: a card each, then their ROAS against dead spend, the night against the peak, spend and
/// revenue, and CPM.
struct WeeksView: View {
    let weeks: [Ledger.WeekRead]
    let profit: Ledger.Profit

    func label(_ week: Ledger.WeekRead) -> String { PennyStyle.day(week.start) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(weeks) { week in card(week) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                small(L("ROAS against dead spend"), L("bars: share of spend in hours under 1× · line: ROAS")) { roasAgainstDead }
                small(L("Night against peak"), L("ROAS 12 AM–6 AM against 9 AM–9 PM, Alaska time")) { nightAgainstPeak }
                small(L("Spend and revenue"), L("bars: spend, coloured by ROAS · line: revenue")) { spendAndRevenue }
                small(L("CPM"), L("what a thousand impressions cost: lower is Meta finding buyers for less")) { cpm }
            }
        }
    }

    func card(_ week: Ledger.WeekRead) -> some View {
        let color = PennyStyle.roas(week.numbers.roas, profit)
        return VStack(alignment: .leading, spacing: 3) {
            Text(L("Week of %@", label(week))).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
            Text(PennyStyle.times(week.numbers.roas)).font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(color)
            Group {
                Text(L("%@ spent · %@ back", PennyStyle.short(week.numbers.spent), PennyStyle.short(week.numbers.revenue)))
                Text(L("%@ orders · %@ days", Ledger.whole(week.numbers.orders), week.days))
                Text(L("CBH %@ · CPM %@", PennyStyle.short(week.cbh), week.numbers.cpm.map(Ledger.money) ?? "–"))
                Text(L("Dead spend %@", Ledger.percent(week.dead))).foregroundStyle(week.dead > 0.3 ? PennyStyle.red : week.dead > 0.2 ? PennyStyle.yellow : .secondary)
            }.font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .top) { UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).fill(color).frame(height: 3) }
    }

    func small<Content: View>(_ title: String, _ note: String, @ViewBuilder chart: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Text(note).font(.system(size: 9.5)).foregroundStyle(.secondary)
            chart().frame(height: 170)
        }
    }

    var roasAgainstDead: some View {
        let top = max(0.6, (weeks.map(\.dead).max() ?? 0) * 1.2)
        let roasTop = max(3, ((weeks.compactMap(\.numbers.roas).max() ?? 0) * 1.15).rounded(.up))
        let k = top / roasTop
        return Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Week", label(week)), y: .value("Dead", week.dead), width: .ratio(0.5))
                    .foregroundStyle((week.dead > 0.3 ? PennyStyle.red : week.dead > 0.2 ? PennyStyle.yellow : PennyStyle.green).opacity(0.5)).cornerRadius(4)
                LineMark(x: .value("Week", label(week)), y: .value("ROAS", (week.numbers.roas ?? 0) * k)).foregroundStyle(PennyStyle.orange).lineStyle(StrokeStyle(lineWidth: 2.4))
                PointMark(x: .value("Week", label(week)), y: .value("ROAS", (week.numbers.roas ?? 0) * k)).foregroundStyle(PennyStyle.roas(week.numbers.roas, profit)).symbolSize(70)
                    .annotation(position: .top) { Text(PennyStyle.times(week.numbers.roas)).font(.system(size: 9, weight: .semibold)).foregroundStyle(PennyStyle.orange) }
            }
            RuleMark(y: .value("Breakeven", profit.breakeven * k)).foregroundStyle(PennyStyle.red.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .chartYScale(domain: 0 ... top)
        .chartXAxis { weekAxis }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                AxisValueLabel { if let share = value.as(Double.self) { Text(String(format: "%.0f%%", share * 100)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
            }
            AxisMarks(position: .trailing, values: Array(stride(from: 0.0, through: roasTop, by: 1)).map { $0 * k }) { value in
                AxisValueLabel { if let y = value.as(Double.self) { Text(String(format: "%.0f×", y / k)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.orange)
            }
        }
    }

    var nightAgainstPeak: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Week", label(week)), y: .value("ROAS", week.night.roas ?? 0))
                    .foregroundStyle(by: .value("", L("12 AM–6 AM"))).position(by: .value("", L("12 AM–6 AM"))).cornerRadius(4)
                BarMark(x: .value("Week", label(week)), y: .value("ROAS", week.peak.roas ?? 0))
                    .foregroundStyle(by: .value("", L("9 AM–9 PM"))).position(by: .value("", L("9 AM–9 PM"))).cornerRadius(4)
            }
            RuleMark(y: .value("Breakeven", profit.breakeven)).foregroundStyle(PennyStyle.red.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .chartForegroundStyleScale([L("12 AM–6 AM"): PennyStyle.red.opacity(0.65), L("9 AM–9 PM"): PennyStyle.green.opacity(0.7)])
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis { weekAxis }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                AxisValueLabel { if let roas = value.as(Double.self) { Text(String(format: "%.1f×", roas)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
            }
        }
    }

    var spendAndRevenue: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Week", label(week)), y: .value("Spent", week.numbers.spent), width: .ratio(0.5))
                    .foregroundStyle(PennyStyle.roas(week.numbers.roas, profit).opacity(0.5)).cornerRadius(4)
                LineMark(x: .value("Week", label(week)), y: .value("Revenue", week.numbers.revenue)).foregroundStyle(PennyStyle.blue).lineStyle(StrokeStyle(lineWidth: 2.4))
                PointMark(x: .value("Week", label(week)), y: .value("Revenue", week.numbers.revenue)).foregroundStyle(PennyStyle.blue).symbolSize(60)
            }
        }
        .chartXAxis { weekAxis }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                AxisValueLabel { if let dollars = value.as(Double.self) { Text(PennyStyle.short(dollars)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
            }
        }
    }

    var cpm: some View {
        let shown = weeks.filter { $0.numbers.cpm != nil }
        let average = shown.compactMap(\.numbers.cpm).reduce(0, +) / Double(max(shown.count, 1))
        let low = (shown.compactMap(\.numbers.cpm).min() ?? 0) * 0.85, high = (shown.compactMap(\.numbers.cpm).max() ?? 1) * 1.1
        return Chart {
            ForEach(shown) { week in
                AreaMark(x: .value("Week", label(week)), yStart: .value("", low), yEnd: .value("CPM", week.numbers.cpm ?? 0))
                    .foregroundStyle(LinearGradient(colors: [PennyStyle.blue.opacity(0.22), PennyStyle.blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Week", label(week)), y: .value("CPM", week.numbers.cpm ?? 0)).foregroundStyle(PennyStyle.blue).lineStyle(StrokeStyle(lineWidth: 2.4))
                PointMark(x: .value("Week", label(week)), y: .value("CPM", week.numbers.cpm ?? 0))
                    .foregroundStyle((week.numbers.cpm ?? 0) <= average * 0.95 ? PennyStyle.green : (week.numbers.cpm ?? 0) >= average * 1.05 ? PennyStyle.red : PennyStyle.yellow)
                    .symbolSize(70)
                    .annotation(position: .top) { Text(Ledger.money(week.numbers.cpm ?? 0)).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
            }
        }
        .chartYScale(domain: low ... max(high, low + 1))
        .chartXAxis { weekAxis }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                AxisValueLabel { if let dollars = value.as(Double.self) { Text(String(format: "$%.0f", dollars)) } }.font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
            }
        }
    }

    var weekAxis: some AxisContent {
        AxisMarks { value in
            AxisValueLabel { if let name = value.as(String.self) { Text(name) } }
                .font(.system(size: 9)).foregroundStyle(PennyStyle.muted)
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
            Text(L(name)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .semibold).monospacedDigit()).foregroundStyle(color ?? .primary).lineLimit(1).minimumScaleFactor(0.6)
            if let change, change.isFinite, abs(change) >= 0.005 {
                let good = (change > 0) == upIsGood
                Text((change > 0 ? "▲ " : "▼ ") + Ledger.percent(abs(change))).font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(neutral ? PennyStyle.muted : good ? PennyStyle.green : PennyStyle.red)
            } else {
                Text(" ").font(.system(size: 9.5))
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) { if let color { UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8).fill(color).frame(width: 3) } }
    }
}
