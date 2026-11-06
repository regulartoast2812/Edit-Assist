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
    /// The chosen product worked out off the main thread (2026-11-06: the page was slow when every redraw worked it
    /// out again); the last one stays up while the next is read.
    @State private var analysis: PennyAnalysis?

    static let ranges: [(days: Int, name: String)] = [(0, "Today"), (-1, "Yesterday"), (7, "Last 7 days"), (14, "Last 14 days"), (30, "Last 30 days")]

    /// The days in the range, newest first, and as many before them to compare with.
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
        let copied = ledger.summary.copied.values.max()?.timeIntervalSince1970 ?? 0
        let key = PennyAnalysis.key(product ?? "", days.now, copied)
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            card(L("DATA")) { DataState(ledger: ledger, days: days.now) }
            if products.isEmpty {
                Text(ledger.summary.copied.isEmpty ? L("Penny is making his first copy of the ads' numbers; products show here as each day comes in.") : L("No product ran in these days."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    list(products, selected: product)
                    if let analysis, product != nil {
                        ProductDetail(analysis: analysis, loading: analysis.key != key).equatable()
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .task(id: key) {
            guard let product else { analysis = nil; return }
            if analysis?.key == key { return }
            let summary = ledger.summary
            let read = await Task.detached(priority: .userInitiated) { PennyAnalysis(product: product, days: days, summary: summary, key: key) }.value
            if !Task.isCancelled { analysis = read }
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

    func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
            content()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Everything the product's page shows, worked out once from Penny's copy when the product, the days or the copy
/// change, never while you scroll, hover or type.
final class PennyAnalysis {
    let key: String
    let product: String
    let days: [String]
    let total: Ledger.Numbers
    let before: Ledger.Numbers
    let profit: Ledger.Profit
    let margin: (margin: Ledger.Margin, days: Int)
    let marginBefore: (margin: Ledger.Margin, days: Int)
    let report: [String]
    let dayReads: [Ledger.DayRead]
    let hourReads: [Ledger.HourRead]
    let daySlots: [PennySlot]
    let hourSlots: [PennySlot]
    let efficiency: Ledger.Efficiency
    let bands: [Ledger.Band]
    let weeks: [Ledger.WeekRead]
    let creatives: [Ledger.Line]
    let campaigns: [Ledger.Line]

    static func key(_ product: String, _ days: [String], _ copied: Double) -> String { "\(product)|\(days.joined(separator: ","))|\(copied)" }

    init(product: String, days: (now: [String], before: [String]), summary: Ledger.Summary, key: String) {
        self.key = key
        self.product = product
        self.days = days.now
        let loaded = PennyLedger.days(of: product, days.now)
        total = Ledger.total(loaded)
        before = summary.numbers(of: product, on: days.before)
        margin = summary.margin(of: product, on: days.now)
        marginBefore = summary.margin(of: product, on: days.before)
        profit = Ledger.Profit(margin.margin) ?? .usual
        report = Ledger.report(loaded, before: before.spent > 0 ? before : nil, profit: profit)
        dayReads = Ledger.dayReads(loaded, profit: profit)
        hourReads = Ledger.hourReads(loaded, profit: profit)
        daySlots = PennySlot.days(dayReads, profit: profit)
        hourSlots = PennySlot.hours(hourReads, days: dayReads, profit: profit)
        efficiency = Ledger.efficiency(hourReads, profit: profit)
        bands = Ledger.bands(loaded, profit: profit)
        weeks = Ledger.weekReads(dayReads)
        creatives = Ledger.creatives(loaded)
        campaigns = Ledger.campaigns(loaded)
    }
}

/// The chosen product's page. It redraws only when its analysis changes or you open a day: typing in the search,
/// a copy coming in for another day and the minute ticking on the data strip leave it alone.
struct ProductDetail: View, Equatable {
    let analysis: PennyAnalysis
    let loading: Bool
    /// The day opened hour by hour, from the chart or the calendar.
    @State private var openDay: String?

    static func == (a: Self, b: Self) -> Bool { a.analysis === b.analysis && a.loading == b.loading }

    var body: some View {
        let a = analysis, profit = a.profit, total = a.total, before = a.before
        let change = { (now: Double?, then: Double?) -> Double? in
            guard before.spent > 0, let now, let then, then != 0 else { return nil }
            return (now - then) / abs(then)
        }
        VStack(alignment: .leading, spacing: 16) {
            header
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                PennyFigure(name: "Spent", value: Ledger.money(total.spent), change: change(total.spent, before.spent), neutral: true)
                PennyFigure(name: "Revenue", value: Ledger.money(total.revenue), change: change(total.revenue, before.revenue))
                PennyFigure(name: "ROAS", value: PennyStyle.times(total.roas), color: PennyStyle.roas(total.roas, profit), change: change(total.roas, before.roas))
                if a.margin.days > 0 {
                    PennyFigure(name: "CBH", value: Ledger.money(a.margin.margin.cbh), color: PennyStyle.money(a.margin.margin.cbh),
                                change: a.marginBefore.days > 0 ? change(a.margin.margin.cbh, a.marginBefore.margin.cbh) : nil)
                    PennyFigure(name: "%CBH", value: Ledger.percent(a.margin.margin.share), change: a.marginBefore.days > 0 ? change(a.margin.margin.share, a.marginBefore.margin.share) : nil)
                }
                PennyFigure(name: "Orders", value: Ledger.whole(total.orders), change: change(total.orders, before.orders))
                PennyFigure(name: "Cost per order", value: total.cpp.map(Ledger.money) ?? "–", change: change(total.cpp, before.cpp), upIsGood: false)
                PennyFigure(name: "Order value", value: total.aov.map(Ledger.money) ?? "–", change: change(total.aov, before.aov))
                PennyFigure(name: "CR", value: Ledger.percent(total.cr), change: change(total.cr, before.cr))
                PennyFigure(name: "CTR", value: Ledger.percent(total.ctr), change: change(total.ctr, before.ctr))
                PennyFigure(name: "CPM", value: total.cpm.map(Ledger.money) ?? "–", change: change(total.cpm, before.cpm), upIsGood: false)
            }
            PennyPanel(title: L("Penny's read")) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(a.report.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(PixelPenny.theme).frame(width: 5, height: 5).offset(y: -2)
                            PennyReadLine(line: line).fixedSize(horizontal: false, vertical: true)
                        }.font(.system(size: 12.5))
                    }
                }.textSelection(.enabled)
            }
            PennyPanel(title: L("Days"), note: L("Press a day, on the charts or the calendar, to see it hour by hour")) {
                if a.dayReads.count == 1, let day = a.dayReads.first {
                    DayDrill(day: day, profit: profit)
                } else {
                    PennyColumns(slots: a.daySlots, profit: profit, selected: $openDay)
                    if let open = openDay, let day = a.dayReads.first(where: { $0.day == open }) {
                        DayDrill(day: day, profit: profit) { openDay = nil }
                    }
                    DaysCalendar(days: a.dayReads, profit: profit, selected: $openDay)
                }
            }
            PennyPanel(title: L("Hours of the day"),
                       note: L("Each hour over the days read, Alaska time: its average ROAS and its bad to good day (10th to 90th percentile of its days), what it spends a day and the CBH it makes a day")) {
                PennyColumns(slots: a.hourSlots, profit: profit, ranges: true, perDay: true, height: 170)
            }
            PennyPanel(title: L("Where the budget went"), note: L("Each hour's average against breakeven, then every hour of every day by the ROAS it brought back")) {
                HoursEfficiency(reads: a.hourReads, profit: profit, shows: .budget)
                Divider().opacity(0.4)
                BandsView(bands: a.bands, profit: profit)
            }
            PennyPanel(title: L("Hour by hour"), note: L("Press a column to sort by it; hold the pointer on a verdict for what it means")) {
                HoursEfficiency(reads: a.hourReads, profit: profit, shows: .table)
                VerdictLegend().padding(.top, 6)
            }
            if a.weeks.count >= 2 {
                PennyPanel(title: L("Weeks"), note: L("Weeks from Monday, as many as the days read reach")) { WeeksView(weeks: a.weeks, profit: profit) }
            }
            PennyPanel(title: L("Creatives by hour"), note: L("Each creative's orders hour by hour, darker for more")) { CreativeHours(lines: Array(a.creatives.prefix(12))) }
            PennyPanel(title: L("Creatives")) { LedgerTable(lines: a.creatives, counted: L("Campaigns")) }
            PennyPanel(title: L("Campaigns")) { LedgerTable(lines: a.campaigns, counted: L("Ads")) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: analysis.product) { _, _ in openDay = nil }
    }

    var header: some View {
        let a = analysis, profit = a.profit
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(a.product).font(.system(size: 24, weight: .bold)).textSelection(.enabled)
                Text(profit.measured ? L("Breakeven %@ from CBH", PennyStyle.times(profit.breakeven)) : L("Breakeven %@ (usual line)", PennyStyle.times(profit.breakeven)))
                    .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(PennyStyle.red.opacity(0.16), in: Capsule()).foregroundStyle(PennyStyle.red)
                    .help(L("Profitable from %@ (CBH 5%)", PennyStyle.times(profit.profitable)))
                if loading { ProgressView().controlSize(.small) }
            }
            Text(a.days.count == 1 ? L("%@ · Alaska time", PennyStyle.day(a.days.first ?? ""))
                 : L("%@ days · %@ – %@ · Alaska time", a.days.count, PennyStyle.day(a.days.last ?? ""), PennyStyle.day(a.days.first ?? "")))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
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
                    ForEach(days, id: \.self) { day in tile(day, today: today, now: context.date) }
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
    enum Shows { case budget, table }
    var shows = Shows.budget
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

    static func color(_ verdict: Ledger.HourRead.Verdict) -> Color { PennyStyle.verdict(verdict) }

    func color(_ roas: Double?) -> Color { PennyStyle.roas(roas, profit) }

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
        if shows == .table { table } else {
        VStack(alignment: .leading, spacing: 10) {
            Text(md: profit.measured
                 ? L("Breakeven **%@** (CBH 0), profitable from **%@** (CBH 5%): from this product's CBH, it keeps %@ of revenue before ads.",
                     Ledger.ratio(profit.breakeven), Ledger.ratio(profit.profitable), Ledger.percent(profit.kept))
                 : L("Breakeven **%@**, profitable from **%@**: the usual lines, until Penny has this product's CBH for these days.",
                     Ledger.ratio(profit.breakeven), Ledger.ratio(profit.profitable)))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            BudgetBar(parts: parts)
            HStack(alignment: .top, spacing: 8) {
                part(L("Below breakeven"), parts.losing, of: total, color: PennyStyle.red)
                part(L("Thin profit"), parts.thin, of: total, color: PennyStyle.yellow)
                part(L("Profitable"), parts.profitable, of: total, color: PennyStyle.green)
            }
        }
        }
    }

    func part(_ title: String, _ part: Ledger.Efficiency.Part, of total: Ledger.Numbers, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(L("%@ of spend", Ledger.percent(total.spent > 0 ? part.numbers.spent / total.spent : 0))).font(.system(size: 16, weight: .semibold).monospacedDigit())
            Text(L("%@ spent, %@ of revenue back", Ledger.money(part.numbers.spent), Ledger.percent(total.revenue > 0 ? part.numbers.revenue / total.revenue : 0)))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text(L("CBH %@", Ledger.money(part.cbh))).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(PennyStyle.money(part.cbh))
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
                Text(L("Range")).frame(width: 120, alignment: .center)
                Text(L("Verdict")).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.vertical, 4)
            Divider()
            ForEach(sorted) { read in
                HStack(spacing: 6) {
                    Text(Ledger.hourName(read.hour)).frame(width: 96, alignment: .leading)
                    ForEach(columns, id: \.name) { column in
                        Text(column.text(read)).frame(width: column.width, alignment: .trailing).lineLimit(1)
                            .foregroundStyle(column.name == "ROAS" ? color(read.numbers.roas) : column.name == "CBH" ? PennyStyle.money(read.cbh) : .primary)
                    }
                    RangeBar(read: read, profit: profit).frame(width: 120, height: 14)
                    Text(Self.name(read.verdict)).font(.system(size: 10, weight: .semibold)).foregroundStyle(Self.color(read.verdict))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8).help(Self.meaning(read.verdict))
                }.font(.system(size: 11).monospacedDigit()).padding(.vertical, 4).padding(.horizontal, 4)
                .background(Self.color(read.verdict).opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                .textSelection(.enabled)
            }
        }
    }
}

/// An hour's bad-to-good-day range on a 0–4× track, its average as a dot, breakeven as a red tick.
struct RangeBar: View {
    let read: Ledger.HourRead
    let profit: Ledger.Profit
    static let top = 4.0

    var body: some View {
        GeometryReader { geometry in
            let x = { (roas: Double) in geometry.size.width * min(max(roas, 0), Self.top) / Self.top }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06)).frame(height: 4)
                if let floor = read.floor, let ceiling = read.ceiling {
                    Capsule().fill(PennyStyle.verdict(read.verdict).opacity(0.55)).frame(width: max(2, x(ceiling) - x(floor)), height: 4).offset(x: x(floor))
                }
                Rectangle().fill(PennyStyle.red).frame(width: 1.5, height: 12).offset(x: x(profit.breakeven))
                if let roas = read.numbers.roas {
                    Circle().fill(PennyStyle.orange).frame(width: 7, height: 7).offset(x: x(roas) - 3.5)
                }
            }.frame(maxHeight: .infinity)
        }
        .help(L("Bad day %@, good day %@, average %@; the red tick is breakeven", PennyStyle.times(read.floor), PennyStyle.times(read.ceiling), PennyStyle.times(read.numbers.roas)))
    }
}

/// Which creatives sell in which hours: each creative's orders hour by hour, darker for more. Drawn as one canvas
/// with one hover tip (2026-11-06): a view and a tooltip for each of its 288 cells made the page slow.
struct CreativeHours: View {
    let lines: [Ledger.Line]
    @State private var hovered: CGPoint?
    static let cell = CGSize(width: 26, height: 20)
    static let gap: CGFloat = 2
    static let nameWidth: CGFloat = 230

    var body: some View {
        let most = max(1, lines.flatMap { $0.hours.map(\.orders) }.max() ?? 1)
        let width = 24 * (Self.cell.width + Self.gap), height = CGFloat(lines.count) * (Self.cell.height + Self.gap)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Self.gap) {
                Color.clear.frame(width: Self.nameWidth, height: 1)
                ForEach(0 ..< 24, id: \.self) { hour in
                    Text(hour % 3 == 0 ? PennyStyle.hour(hour) : "").font(.system(size: 9)).foregroundStyle(PennyStyle.muted).frame(width: Self.cell.width)
                }
            }
            HStack(alignment: .top, spacing: Self.gap) {
                VStack(alignment: .leading, spacing: Self.gap) {
                    ForEach(lines) { line in
                        Text(line.name).font(.system(size: 10.5)).lineLimit(1).truncationMode(.middle).frame(width: Self.nameWidth, height: Self.cell.height, alignment: .leading)
                    }
                }
                Canvas { context, _ in
                    for (row, line) in lines.enumerated() {
                        for hour in 0 ..< 24 {
                            let numbers = line.hours[hour]
                            let rect = CGRect(x: CGFloat(hour) * (Self.cell.width + Self.gap), y: CGFloat(row) * (Self.cell.height + Self.gap),
                                              width: Self.cell.width, height: Self.cell.height)
                            let fill: Color = numbers.orders > 0 ? PennyStyle.green.opacity(0.45 + 0.55 * numbers.orders / most) : numbers.spent > 0 ? .white.opacity(0.06) : .white.opacity(0.015)
                            context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(fill))
                            if numbers.orders > 0 {
                                context.draw(Text(Ledger.whole(numbers.orders)).font(.system(size: 9, weight: .semibold)).foregroundColor(.white), at: CGPoint(x: rect.midX, y: rect.midY))
                            }
                        }
                    }
                }
                .frame(width: width, height: height)
                .onContinuousHover { phase in
                    if case let .active(point) = phase { hovered = point } else { hovered = nil }
                }
                .overlay(alignment: .topLeading) {
                    if let hovered, case let row = Int(hovered.y / (Self.cell.height + Self.gap)), case let hour = Int(hovered.x / (Self.cell.width + Self.gap)),
                       lines.indices.contains(row), (0 ..< 24).contains(hour) {
                        let numbers = lines[row].hours[hour]
                        ChartTip(title: Ledger.hourName(hour), lines: [
                            PennyTipLine(name: L("Spent"), value: Ledger.money(numbers.spent)),
                            PennyTipLine(name: L("Orders"), value: Ledger.whole(numbers.orders)),
                            PennyTipLine(name: L("ROAS"), value: PennyStyle.times(numbers.roas))])
                        .offset(x: min(CGFloat(hour + 1) * (Self.cell.width + Self.gap) + 6, width - ChartTip.width), y: CGFloat(row + 1) * (Self.cell.height + Self.gap))
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
