import SwiftUI
import Charts
import AppKit

/// Penny's own dashboard, from his copy of the ads' numbers (`PennyLedger`), not Grafana's: the products that ran in
/// the days you pick, and for the one you choose its totals, his read of it, its days, its hours, which creatives
/// sell in which hours, and its campaigns (2026-11-05). Hours are Alaska time, the company's day.
struct ProductsView: View {
    @ObservedObject var ledger: PennyLedger
    /// 0 today, -1 yesterday, -2 the dates you picked, else the last that many days.
    @AppStorage("pennyProductsRange") private var range = 7
    @AppStorage("pennyProductsFrom") private var from = ""
    @AppStorage("pennyProductsTo") private var to = ""
    @State private var picking = false
    @AppStorage("pennyProduct") private var chosen = ""
    @State private var search = ""
    @State private var loaded: [Ledger.Day] = []
    @State private var loadedKey = ""

    static let ranges: [(days: Int, name: String)] = [(0, "Today"), (-1, "Yesterday"), (7, "Last 7 days"), (14, "Last 14 days"), (30, "Last 30 days")]

    /// The days in the range, and as many before them to compare with.
    var days: (now: [String], before: [String]) {
        if range == -2, case let picked = Ledger.days(from: from, to: to), let first = picked.last, let start = Ledger.start(of: first) {
            let before = Ledger.days(back: picked.count + 1, from: start).dropFirst()
            return (picked, Array(before))
        }
        let count = range <= 0 ? 1 : range
        let all = Ledger.days(back: (range < 0 ? 1 : 0) + count * 2, from: Date())
        let shift = range < 0 ? 1 : 0
        return (Array(all.dropFirst(shift).prefix(count)), Array(all.dropFirst(shift + count).prefix(count)))
    }

    var body: some View {
        let days = days
        let products = ledger.products(on: days.now)
        let product = products.first(where: { $0.name == chosen })?.name ?? products.first?.name
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            card(L("DATA")) { DataState(ledger: ledger, days: days.now) }
            if products.isEmpty {
                Text(ledger.summary.copied.isEmpty ? L("Penny is making his first copy of the ads' numbers; products show here as each day comes in.") : L("No product ran in these days."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    list(products, selected: product)
                    if let product { detail(product, days: days) }
                }
            }
        }
        .task(id: "\(product ?? "")|\(days.now.joined())|\(ledger.summary.copied.values.max()?.timeIntervalSince1970 ?? 0)") {
            guard let product else { loaded = []; return }
            let wanted = days.now
            let read = await Task.detached { PennyLedger.days(of: product, wanted) }.value
            loaded = read; loadedKey = product
        }
    }

    var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(Self.ranges, id: \.days) { item in Button(L(item.name)) { range = item.days } }
                Divider()
                Button(L("Pick dates…")) { picking = true }
            } label: {
                Label(rangeName, systemImage: "clock")
            }.fixedSize()
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                DatesPicker(from: Ledger.start(of: from) ?? Date(), to: Ledger.start(of: to) ?? Date()) { first, last in
                    from = Ledger.name(of: first); to = Ledger.name(of: last); range = -2; picking = false
                    ledger.ask(for: Ledger.days(from: from, to: to))
                }
            }
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([PennyLedger.folder]) } label: { Label(L("Show in Finder"), systemImage: "folder") }
        }.controlSize(.small)
    }

    var rangeName: String {
        guard range == -2, case let picked = Ledger.days(from: from, to: to), let first = picked.last, let last = picked.first else {
            return L(Self.ranges.first(where: { $0.days == range })?.name ?? "Last 7 days")
        }
        let written = { (day: String) in Ledger.start(of: day)?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: Ledger.zone)) ?? day }
        return first == last ? written(first) : "\(written(first)) – \(written(last))"
    }

    func list(_ products: [(name: String, numbers: Ledger.Numbers)], selected: String?) -> some View {
        let shown = search.isEmpty ? products : products.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 6) {
            TextField(L("Search"), text: $search).textFieldStyle(.roundedBorder).controlSize(.small)
            HStack {
                Text(L("%@ products", shown.count)).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text(L("SPENT · ROAS")).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(shown, id: \.name) { item in
                        Button { chosen = item.name } label: {
                            HStack(spacing: 6) {
                                Text(item.name).font(.system(size: 11, weight: item.name == selected ? .semibold : .regular)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Ledger.money(item.numbers.spent)).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                                Text(Ledger.ratio(item.numbers.roas)).font(.system(size: 10, weight: .medium).monospacedDigit()).frame(width: 34, alignment: .trailing)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(item.name == selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 640)
        }.frame(width: 250)
    }

    @ViewBuilder func detail(_ product: String, days: (now: [String], before: [String])) -> some View {
        let ready = loadedKey == product
        let total = Ledger.total(loaded)
        let before = ledger.summary.numbers(of: product, on: days.before)
        let profit = ledger.profit(of: product, on: days.now)
        let margin = ledger.summary.margin(of: product, on: days.now)
        VStack(alignment: .leading, spacing: 14) {
            Text(product).font(.system(size: 18, weight: .semibold)).textSelection(.enabled)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                figure("Spent", Ledger.money(total.spent))
                figure("Revenue", Ledger.money(total.revenue))
                figure("ROAS", Ledger.ratio(total.roas))
                figure("Orders", Ledger.whole(total.orders))
                figure("Cost per order", total.cpp.map(Ledger.money) ?? "–")
                figure("Order value", total.aov.map(Ledger.money) ?? "–")
                figure("CR", Ledger.percent(total.cr))
                figure("CTR", Ledger.percent(total.ctr))
                figure("CPM", total.cpm.map(Ledger.money) ?? "–")
                if margin.days > 0 {
                    figure("CBH", Ledger.money(margin.margin.cbh))
                    figure("%CBH", Ledger.percent(margin.margin.share))
                }
                figure("Breakeven ROAS", Ledger.ratio(profit.breakeven))
            }
            if ready {
                card(L("PENNY'S READ")) {
                    let lines = Ledger.report(loaded, before: before.spent > 0 ? before : nil, profit: profit)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(md: line).fixedSize(horizontal: false, vertical: true)
                            }.font(.system(size: 12))
                        }
                    }.textSelection(.enabled)
                }
                card(L("HOURS · MEDIA BUYING (ALASKA TIME)")) { HoursEfficiency(reads: Ledger.hourReads(loaded, profit: profit), profit: profit) }
                if loaded.count > 1 { card(L("BY DAY")) { DaysChart(days: loaded) } }
                card(L("BY HOUR (ALASKA TIME)")) { HoursChart(hours: Ledger.hours(loaded)) }
                let creatives = Ledger.creatives(loaded)
                card(L("CREATIVES BY HOUR · ORDERS")) { CreativeHours(lines: Array(creatives.prefix(12))) }
                card(L("CREATIVES")) { LedgerTable(lines: creatives, counted: L("Campaigns")) }
                card(L("CAMPAIGNS")) { LedgerTable(lines: Ledger.campaigns(loaded), counted: L("Ads")) }
            } else {
                ProgressView().controlSize(.small)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    func figure(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L(name)).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }

    func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
            content()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Whether Penny's copy is up to date: when he last copied and copies next, how far today's numbers reach in Grafana,
/// and each day you're looking at: final, updated in the last hour, behind, or not copied. A day still coming in counts
/// as up to date when it was copied in the last hour.
struct DataState: View {
    @ObservedObject var ledger: PennyLedger
    let days: [String]
    static let fresh: TimeInterval = 3600

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let today = Ledger.name(of: context.date)
            VStack(alignment: .leading, spacing: 8) {
                headline(today: today, now: context.date).font(.system(size: 11))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                    ForEach(days.reversed(), id: \.self) { day in tile(day, today: today, now: context.date) }
                }
            }
        }
    }

    @ViewBuilder func headline(today: String, now: Date) -> some View {
        let summary = ledger.summary
        HStack(spacing: 6) {
            if let failure = ledger.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).lineLimit(2)
            } else if let day = ledger.copying {
                ProgressView().controlSize(.mini)
                Text(L("Copying %@…", Self.written(day)))
            } else if let last = summary.copied[today], now.timeIntervalSince(last) < Self.fresh {
                Label(ledger.next.map { L("Up to date: copied at %@, next copy at %@", Self.time(last), Self.time($0)) } ?? L("Up to date: copied at %@", Self.time(last)),
                      systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if let last = summary.copied.values.max() {
                Label(L("Not copied since %@", last.formatted(date: .abbreviated, time: .shortened)), systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
            } else {
                Text(L("No copy yet")).foregroundStyle(.secondary)
            }
            if let hour = summary.latest[today] {
                Text("·").foregroundStyle(.secondary)
                Text(L("Grafana has today up to %@, Alaska time", Ledger.hourName(hour))).foregroundStyle(.secondary)
            }
        }
    }

    func tile(_ day: String, today: String, now: Date) -> some View {
        let state = Ledger.state(of: day, in: ledger.summary)
        let (mark, color, note, help): (String, Color, String, String) = {
            if ledger.copying == day { return ("arrow.triangle.2.circlepath", .secondary, L("Copying…"), L("Copying now")) }
            switch state {
            case .missing:
                return ("circle.dashed", .secondary, L("Not copied"), L("Not copied yet"))
            case let .live(copied, until):
                let help = L("Copied %@; its numbers still come in, so Penny copies it again until %@", copied.formatted(date: .abbreviated, time: .shortened), until.formatted(date: .abbreviated, time: .shortened))
                return now.timeIntervalSince(copied) < Self.fresh
                    ? ("checkmark.circle.fill", .green, L("Updated · %@", Self.time(copied)), help)
                    : ("clock.badge.exclamationmark", .orange, L("Behind · %@", Self.time(copied)), help)
            case let .final(copied):
                return ("checkmark.circle.fill", .green, L("Final"), L("Copied %@, after its numbers had settled", copied.formatted(date: .abbreviated, time: .shortened)))
            }
        }()
        return VStack(alignment: .leading, spacing: 2) {
            Text(day == today ? L("Today") : Self.written(day)).font(.system(size: 10, weight: .semibold))
            Label(note, systemImage: mark).font(.system(size: 9)).foregroundStyle(color).lineLimit(1)
        }
        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        .help(help)
    }

    static func written(_ day: String) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = Ledger.zone
        return Ledger.start(of: day)?.formatted(style) ?? day
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

/// The hours as a media buyer reads them (2026-11-06), the Campaign Breakdown dashboard's way with breakeven from CBH:
/// where the budget went against breakeven, then each hour's spend a day, ROAS, bad-day floor and good-day ceiling,
/// orders, CBH and verdict.
struct HoursEfficiency: View {
    let reads: [Ledger.HourRead]
    let profit: Ledger.Profit
    @State private var sort = "Hour"

    static func name(_ verdict: Ledger.HourRead.Verdict) -> String {
        switch verdict {
        case .reliable: return L("Reliable win")
        case .volatile: return L("High ceiling")
        case .thin: return L("Thin profit")
        case .losing: return L("Below breakeven")
        case .costly: return L("Costly waste")
        case .dead: return L("Dead")
        case .few: return L("Too few days")
        case .idle: return ""
        }
    }

    static func meaning(_ verdict: Ledger.HourRead.Verdict) -> String {
        switch verdict {
        case .reliable: return L("Profitable on average, and its bad days still break even")
        case .volatile: return L("Profitable on average, but its bad days lose money")
        case .thin: return L("Above breakeven, under 5% CBH: not worth more budget")
        case .losing: return L("Below breakeven, on little spend")
        case .costly: return L("Below breakeven while spending over $50 a day")
        case .dead: return L("Under 1×: less comes back than is spent")
        case .few: return L("Spent on fewer than 3 days: too few to judge")
        case .idle: return ""
        }
    }

    static func color(_ verdict: Ledger.HourRead.Verdict) -> Color {
        switch verdict {
        case .reliable: return .green
        case .volatile: return .blue
        case .thin: return .yellow
        case .losing: return .gray
        case .costly: return .orange
        case .dead: return .red
        case .few, .idle: return .secondary
        }
    }

    func color(_ roas: Double?) -> Color {
        guard let roas else { return .secondary }
        return roas < profit.breakeven ? .orange : roas < profit.profitable ? .yellow : .green
    }

    struct Column { var name: String; var width: CGFloat; var value: (Ledger.HourRead) -> Double?; var text: (Ledger.HourRead) -> String }

    var columns: [Column] {
        [Column(name: "Days", width: 36, value: { Double($0.days) }, text: { "\($0.days)" }),
         Column(name: "Spent a day", width: 76, value: { $0.spentPerDay }, text: { Ledger.money($0.spentPerDay) }),
         Column(name: "ROAS", width: 46, value: { $0.numbers.roas }, text: { Ledger.ratio($0.numbers.roas) }),
         Column(name: "Bad → good day", width: 96, value: { $0.floor }, text: { "\(Ledger.ratio($0.floor)) → \(Ledger.ratio($0.ceiling))" }),
         Column(name: "Orders a day", width: 76, value: { $0.days > 0 ? $0.numbers.orders / Double($0.days) : nil },
                text: { $0.days > 0 ? String(format: "%.1f", $0.numbers.orders / Double($0.days)) : "–" }),
         Column(name: "CBH", width: 76, value: { $0.cbh }, text: { Ledger.money($0.cbh) })]
    }

    var body: some View {
        let parts = Ledger.efficiency(reads, profit: profit)
        let total = parts.total
        VStack(alignment: .leading, spacing: 10) {
            Text(md: profit.measured
                 ? L("Breakeven **%@** (CBH 0), profitable from **%@** (CBH 5%%): from this product's CBH, it keeps %@ of revenue before ads.",
                     Ledger.ratio(profit.breakeven), Ledger.ratio(profit.profitable), Ledger.percent(profit.kept))
                 : L("Breakeven **%@**, profitable from **%@**: the usual lines, until Penny has this product's CBH for these days.",
                     Ledger.ratio(profit.breakeven), Ledger.ratio(profit.profitable)))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                part(L("Below breakeven"), parts.losing, of: total, color: .orange)
                part(L("Thin profit"), parts.thin, of: total, color: .yellow)
                part(L("Profitable"), parts.profitable, of: total, color: .green)
            }
            table
        }
    }

    func part(_ title: String, _ part: Ledger.Efficiency.Part, of total: Ledger.Numbers, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(L("%@ of spend", Ledger.percent(total.spent > 0 ? part.numbers.spent / total.spent : 0))).font(.system(size: 16, weight: .semibold).monospacedDigit())
            Text(L("%@ spent, %@ of revenue back", Ledger.money(part.numbers.spent), Ledger.percent(total.revenue > 0 ? part.numbers.revenue / total.revenue : 0)))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text(L("CBH %@", Ledger.money(part.cbh))).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(part.cbh < 0 ? .orange : .primary)
            if !part.hours.isEmpty {
                Text(part.hours.map(Ledger.hourName).joined(separator: ", ")).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    var table: some View {
        let columns = columns
        let order = columns.first { $0.name == sort }
        let shown = reads.filter { $0.days > 0 }
        let sorted = order.map { order in shown.sorted { (order.value($0) ?? -.infinity) > (order.value($1) ?? -.infinity) } } ?? shown
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button { sort = "Hour" } label: { Text(L("Hour") + (sort == "Hour" ? " ↓" : "")).frame(width: 96, alignment: .leading) }.buttonStyle(.plain)
                ForEach(columns, id: \.name) { column in
                    Button { sort = column.name } label: {
                        Text(L(column.name) + (sort == column.name ? " ↓" : "")).frame(width: column.width, alignment: .trailing)
                    }.buttonStyle(.plain)
                }
                Text(L("Verdict")).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.vertical, 4)
            Divider()
            ForEach(sorted) { read in
                HStack(spacing: 6) {
                    Text(Ledger.hourName(read.hour)).frame(width: 96, alignment: .leading)
                    ForEach(columns, id: \.name) { column in
                        Text(column.text(read)).frame(width: column.width, alignment: .trailing).lineLimit(1)
                            .foregroundStyle(column.name == "ROAS" ? color(read.numbers.roas) : column.name == "CBH" && read.cbh < 0 ? .orange : .primary)
                    }
                    Text(Self.name(read.verdict)).font(.system(size: 10, weight: .semibold)).foregroundStyle(Self.color(read.verdict))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8).help(Self.meaning(read.verdict))
                }.font(.system(size: 11).monospacedDigit()).padding(.vertical, 3).textSelection(.enabled)
                Divider().opacity(0.4)
            }
        }
    }
}

/// Spend and revenue each day.
struct DaysChart: View {
    let days: [Ledger.Day]

    var body: some View {
        let points = days.sorted { $0.day < $1.day }.flatMap { day -> [(String, String, Double)] in
            let numbers = day.numbers
            return [(String(day.day.dropFirst(5)), L("Spent"), numbers.spent), (String(day.day.dropFirst(5)), L("Revenue"), numbers.revenue)]
        }
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            BarMark(x: .value("Day", point.0), y: .value("$", point.2))
                .foregroundStyle(by: .value("", point.1))
                .position(by: .value("", point.1))
        }
        .chartForegroundStyleScale([L("Spent"): Color.orange, L("Revenue"): Color.green])
        .frame(height: 180)
    }
}

/// Spend and revenue in each hour of the day, with the orders over the bars.
struct HoursChart: View {
    let hours: [Ledger.Numbers]

    var body: some View {
        let points = hours.enumerated().flatMap { hour, numbers in [(hour, L("Spent"), numbers.spent), (hour, L("Revenue"), numbers.revenue)] }
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                BarMark(x: .value("Hour", point.0), y: .value("$", point.2), width: .fixed(7))
                    .foregroundStyle(by: .value("", point.1))
                    .position(by: .value("", point.1))
            }
        }
        .chartForegroundStyleScale([L("Spent"): Color.orange, L("Revenue"): Color.green])
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, to: 24, by: 2))) { value in
                AxisGridLine()
                AxisValueLabel { if let hour = value.as(Int.self) { Text(hour % 12 == 0 ? (hour == 0 ? "12a" : "12p") : "\(hour % 12)\(hour < 12 ? "a" : "p")") } }
            }
        }
        .chartXScale(domain: -0.5 ... 23.5)
        .frame(height: 180)
    }
}

/// Which creatives sell in which hours: each creative's orders hour by hour, darker for more.
struct CreativeHours: View {
    let lines: [Ledger.Line]

    var body: some View {
        let most = max(1, lines.flatMap { $0.hours.map(\.orders) }.max() ?? 1)
        Grid(alignment: .leading, horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                ForEach(0 ..< 24, id: \.self) { hour in
                    Text(hour % 3 == 0 ? "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "a" : "p")" : "")
                        .font(.system(size: 8)).foregroundStyle(.secondary).frame(width: 22)
                }
            }
            ForEach(lines) { line in
                GridRow {
                    Text(line.name).font(.system(size: 10)).lineLimit(1).truncationMode(.middle).frame(width: 220, alignment: .leading).help(line.name)
                    ForEach(0 ..< 24, id: \.self) { hour in
                        let numbers = line.hours[hour]
                        RoundedRectangle(cornerRadius: 3)
                            .fill(numbers.orders > 0 ? Color.green.opacity(0.2 + 0.8 * numbers.orders / most) : (numbers.spent > 0 ? Color.white.opacity(0.06) : .clear))
                            .overlay { if numbers.orders > 0 { Text(Ledger.whole(numbers.orders)).font(.system(size: 8, weight: .semibold)) } }
                            .frame(width: 22, height: 18)
                            .help(L("%@: spent %@, %@ orders, ROAS %@", Ledger.hourName(hour), Ledger.money(numbers.spent), Ledger.whole(numbers.orders), Ledger.ratio(numbers.roas)))
                    }
                }
            }
        }
    }
}

/// Creatives or campaigns with their numbers, sorted by any column (spend first).
struct LedgerTable: View {
    let lines: [Ledger.Line]
    let counted: String
    @State private var sort = "Spent"
    @State private var shown = 25

    struct Column { var name: String; var width: CGFloat; var value: (Ledger.Line) -> Double?; var text: (Ledger.Line) -> String }

    var columns: [Column] {
        [Column(name: counted, width: 64, value: { Double($0.count) }, text: { "\($0.count)" }),
         Column(name: "Spent", width: 76, value: { $0.numbers.spent }, text: { Ledger.money($0.numbers.spent) }),
         Column(name: "Revenue", width: 76, value: { $0.numbers.revenue }, text: { Ledger.money($0.numbers.revenue) }),
         Column(name: "ROAS", width: 46, value: { $0.numbers.roas }, text: { Ledger.ratio($0.numbers.roas) }),
         Column(name: "Orders", width: 50, value: { $0.numbers.orders }, text: { Ledger.whole($0.numbers.orders) }),
         Column(name: "CPP", width: 64, value: { $0.numbers.cpp }, text: { $0.numbers.cpp.map(Ledger.money) ?? "–" }),
         Column(name: "CTR", width: 50, value: { $0.numbers.ctr }, text: { Ledger.percent($0.numbers.ctr) }),
         Column(name: "CR", width: 50, value: { $0.numbers.cr }, text: { Ledger.percent($0.numbers.cr) }),
         Column(name: "Most orders at", width: 150, value: { line in line.bestHours(1).first.map(Double.init) }, text: { $0.bestHours().map(Ledger.hourName).joined(separator: ", ") })]
    }

    var body: some View {
        let columns = columns
        let order = columns.first(where: { $0.name == sort }) ?? columns[1]
        let sorted = lines.sorted { (order.value($0) ?? -.infinity) > (order.value($1) ?? -.infinity) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(L("Name")).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns, id: \.name) { column in
                    Button { sort = column.name } label: {
                        Text(L(column.name) + (sort == column.name ? " ↓" : "")).frame(width: column.width, alignment: .trailing)
                    }.buttonStyle(.plain)
                }
            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.vertical, 4)
            Divider()
            ForEach(sorted.prefix(shown)) { line in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.name).lineLimit(1).truncationMode(.middle).help(line.name)
                        if !line.publisher.isEmpty { Text(line.publisher).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(columns, id: \.name) { column in
                        Text(column.text(line)).frame(width: column.width, alignment: .trailing).lineLimit(1)
                    }
                }.font(.system(size: 11).monospacedDigit()).padding(.vertical, 3).textSelection(.enabled)
                Divider().opacity(0.4)
            }
            if sorted.count > shown {
                Button(L("Show %@ more", min(25, sorted.count - shown))) { shown += 25 }.buttonStyle(.link).font(.system(size: 11)).padding(.top, 6)
            }
        }
    }
}

/// From and To on two calendars, as Grafana's absolute time range, in the company's (Alaska) days. Dates older than
/// the copy are copied from Grafana when applied, if Grafana still has them.
struct DatesPicker: View {
    @State var from: Date
    @State var to: Date
    let apply: (Date, Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("From")).font(.system(size: 11, weight: .semibold))
                    DatePicker("", selection: $from, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("To")).font(.system(size: 11, weight: .semibold))
                    DatePicker("", selection: $to, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                }
            }
            HStack {
                Text(L("Alaska time, as the dashboards count days")).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(L("Apply dates")) { apply(min(from, to), max(from, to)) }.keyboardShortcut(.defaultAction)
            }
        }
        .environment(\.timeZone, Ledger.zone)
        .environment(\.calendar, Ledger.calendar)
        .padding(14)
    }
}
