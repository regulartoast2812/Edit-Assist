import SwiftUI
import AppKit

/// Penny's own dashboard, from his copy of the ads' numbers (`PennyLedger`), not Grafana's: the products that ran in
/// the days you pick, and for the one you choose its totals, his read of it, its days, its hours, which creatives
/// sell in which hours, and its campaigns (2026-11-05). Hours are Alaska time, the company's day.
struct ProductsView: View {
    @ObservedObject var ledger: PennyLedger
    /// 0 today, -1 yesterday, -2 the dates you picked, else the last that many days. Picked in the product's header
    /// (`DayRangeSelector`).
    @AppStorage("pennyProductsRange") private var range = 7
    @AppStorage("pennyProductsFrom") private var from = ""
    @AppStorage("pennyProductsTo") private var to = ""
    @AppStorage("pennyProduct") private var chosen = ""
    @State private var search = ""
    /// The chosen product worked out off the main thread (2026-11-06: the page was slow when every redraw worked it
    /// out again); the last one stays up while the next is read.
    @State private var analysis: PennyAnalysis?

    /// The days in the range, newest first, and as many before them to compare with.
    static func days(range: Int, from: String, to: String, now: Date = Date()) -> (now: [String], before: [String]) {
        if range == -2, case let picked = Ledger.days(from: from, to: to), !picked.isEmpty {
            return (picked, Ledger.shift(picked, by: -1, now: now))
        }
        let count = range <= 0 ? 1 : range
        let all = Ledger.days(back: (range < 0 ? 1 : 0) + count * 2, from: now)
        let shift = range < 0 ? 1 : 0
        return (Array(all.dropFirst(shift).prefix(count)), Array(all.dropFirst(shift + count).prefix(count)))
    }

    var body: some View {
        let days = Self.days(range: range, from: from, to: to)
        let products = ledger.products(on: days.now)
        let product = products.first(where: { $0.name == chosen })?.name ?? products.first?.name
        let copied = ledger.summary.copied.values.max()?.timeIntervalSince1970 ?? 0
        let key = PennyAnalysis.key(product ?? "", days.now, copied)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // With a product open the range lives in its header; here only while no product ran in it.
                if products.isEmpty { DayRangeSelector(ledger: ledger) }
                Spacer()
                Button { NSWorkspace.shared.activateFileViewerSelecting([PennyLedger.folder]) } label: { Label(L("Show in Finder"), systemImage: "folder") }
            }.controlSize(.small)
            card(L("DATA")) { DataState(ledger: ledger, days: days.now) }
            if products.isEmpty {
                Text(ledger.summary.copied.isEmpty ? L("Penny is making his first copy of the ads' numbers; products show here as each day comes in.") : L("No product ran in these days."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                // A gap under the Data card, so the search and the product's header don't touch it.
                HStack(alignment: .top, spacing: 16) {
                    list(products, selected: product)
                    if let analysis, product != nil {
                        ProductDetail(analysis: analysis, loading: analysis.key != key, ledger: ledger).equatable()
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    }
                }.padding(.top, 2)
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
    /// What `before` is: which days, and how they were cut or scaled to compare fairly.
    let against: Ledger.Against
    let profit: Ledger.Profit
    let margin: (margin: Ledger.Margin, days: Int)
    let marginBefore: (margin: Ledger.Margin, days: Int)
    let report: [String]
    let dayReads: [Ledger.DayRead]
    /// The hours over every day copied for the product, not just the range (2026-11-09: on Today each hour had one day
    /// and every verdict was "too few days"), judged against those days' own breakeven.
    let history: [String]
    let hourProfit: Ledger.Profit
    let hourReads: [Ledger.HourRead]
    /// The range's own hours, for where its budget went.
    let rangeHours: [Ledger.HourRead]
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
        (before, against) = Ledger.before(product, now: days.now, before: days.before, summary: summary, clock: Date(),
                                          load: { PennyLedger.days(of: product, [$0]).first })
        margin = summary.margin(of: product, on: days.now)
        marginBefore = summary.margin(of: product, on: days.before)
        profit = Ledger.Profit(margin.margin) ?? .usual
        dayReads = Ledger.dayReads(loaded, profit: profit)
        let copied = (summary.products[product] ?? [:]).filter { $0.value.spent > 0 }.keys.sorted(by: >)
        let past = (Set(days.now) == Set(copied) ? loaded : PennyLedger.days(of: product, copied)).filter(Ledger.ran)
        history = past.map(\.day).sorted(by: >)
        hourProfit = Ledger.Profit(summary.margin(of: product, on: history).margin) ?? .usual
        hourReads = Ledger.hourReads(past, profit: hourProfit)
        hourSlots = PennySlot.hours(hourReads, days: Ledger.dayReads(past, profit: hourProfit), profit: hourProfit)
        report = Ledger.report(loaded, before: before.spent > 0 ? before : nil, profit: profit, against: against,
                               hours: (hourReads, history.count))
        daySlots = PennySlot.days(dayReads, profit: profit)
        rangeHours = Ledger.hourReads(loaded, profit: profit)
        efficiency = Ledger.efficiency(rangeHours, profit: profit)
        bands = Ledger.bands(loaded, profit: profit)
        weeks = Ledger.weekReads(dayReads)
        creatives = Ledger.creatives(loaded)
        campaigns = Ledger.campaigns(loaded)
    }
}

/// The chosen product's page. It redraws only when its analysis changes or you open a day: typing in the search,
/// a copy coming in for another day and the minute ticking on the data strip leave it alone. Its panels sit two to a
/// row in a wide window (`PanelFlow`). New days or another product grow the charts in; a fresh copy of the same days
/// only redraws them, keeping the day you had open.
struct ProductDetail: View, Equatable {
    let analysis: PennyAnalysis
    let loading: Bool
    /// For the range selector in the header, which watches the range itself.
    let ledger: PennyLedger
    /// The day opened hour by hour, from the chart or the calendar.
    @State private var openDay: String?
    /// The day's column or calendar day under the pointer, shared by the days' charts and the calendar.
    @State private var dayHover = PennyHover()

    static func == (a: Self, b: Self) -> Bool { a.analysis === b.analysis && a.loading == b.loading }

    /// Another product or other days: the page starts again (charts grow in, no day open).
    var shown: String { analysis.product + "|" + analysis.days.joined(separator: ",") }

    var body: some View {
        let a = analysis, profit = a.profit, total = a.total, before = a.before, against = a.against
        // Against the days before, named in the header; a total (spend, orders) a day when fewer of those days were copied.
        let change = { (now: Double?, then: Double?, totalled: Bool) -> Double? in before.spent > 0 ? against.change(now, then, total: totalled) : nil }
        let was = { (then: String) in L("Against %@: %@", against.said, then) }
        // CBH comes a whole day at a time, so it can't be cut to today's hours; a day when the two sides differ.
        let cbhChange = { (now: Double, then: Double) -> Double? in
            guard against.upTo == nil, a.marginBefore.days > 0, a.margin.days > 0 else { return nil }
            var (now, then) = (now, then)
            if a.margin.days != a.marginBefore.days { now /= Double(a.margin.days); then /= Double(a.marginBefore.days) }
            return then == 0 ? nil : (now - then) / abs(then)
        }
        VStack(alignment: .leading, spacing: 16) {
            header
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                PennyFigure(name: "Spent", value: Ledger.money(total.spent), change: change(total.spent, before.spent, true), neutral: true, was: was(Ledger.money(before.spent)))
                PennyFigure(name: "Revenue", value: Ledger.money(total.revenue), change: change(total.revenue, before.revenue, true), was: was(Ledger.money(before.revenue)))
                PennyFigure(name: "ROAS", value: PennyStyle.times(total.roas), color: PennyStyle.roas(total.roas, profit), change: change(total.roas, before.roas, false), was: was(PennyStyle.times(before.roas)))
                if a.margin.days > 0 {
                    PennyFigure(name: "CBH", value: Ledger.money(a.margin.margin.cbh), color: PennyStyle.money(a.margin.margin.cbh),
                                change: cbhChange(a.margin.margin.cbh, a.marginBefore.margin.cbh), was: was(Ledger.money(a.marginBefore.margin.cbh)))
                    PennyFigure(name: "%CBH", value: Ledger.percent(a.margin.margin.share),
                                change: a.marginBefore.days > 0 ? change(a.margin.margin.share, a.marginBefore.margin.share, false) : nil, was: was(Ledger.percent(a.marginBefore.margin.share)))
                }
                PennyFigure(name: "Orders", value: Ledger.whole(total.orders), change: change(total.orders, before.orders, true), was: was(Ledger.whole(before.orders)))
                PennyFigure(name: "Cost per order", value: total.cpp.map(Ledger.money) ?? "–", change: change(total.cpp, before.cpp, false), upIsGood: false, was: was(before.cpp.map(Ledger.money) ?? "–"))
                PennyFigure(name: "Order value", value: total.aov.map(Ledger.money) ?? "–", change: change(total.aov, before.aov, false), was: was(before.aov.map(Ledger.money) ?? "–"))
                PennyFigure(name: "CR", value: Ledger.percent(total.cr), change: change(total.cr, before.cr, false), was: was(Ledger.percent(before.cr)))
                PennyFigure(name: "CTR", value: Ledger.percent(total.ctr), change: change(total.ctr, before.ctr, false), was: was(Ledger.percent(before.ctr)))
                PennyFigure(name: "CPM", value: total.cpm.map(Ledger.money) ?? "–", change: change(total.cpm, before.cpm, false), upIsGood: false, was: was(before.cpm.map(Ledger.money) ?? "–"))
            }
            panels.id(shown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: shown) { _, _ in openDay = nil }
    }

    /// Two to a row when the window is wide enough (`PanelFlow`); in this order one under the other when it isn't.
    var panels: some View {
        let a = analysis, profit = a.profit
        // The hours are judged over every day copied, not the range; their notes say which days and which breakeven.
        let hoursOver = L(a.hourProfit.measured ? "The %@ days the ads ran, %@ – %@ (in 12 hours or $300 spent), against breakeven %@ from their CBH"
                                                : "The %@ days the ads ran, %@ – %@ (in 12 hours or $300 spent), against the usual breakeven %@",
                          String(a.history.count), PennyStyle.day(a.history.last ?? ""), PennyStyle.day(a.history.first ?? ""), PennyStyle.times(a.hourProfit.breakeven)) + ". "
        return PanelFlow {
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
            PennyPanel(title: L("Where the budget went"), note: L("Each hour's average against breakeven, then every hour of every day by the ROAS it brought back")) {
                HoursEfficiency(reads: a.rangeHours, profit: profit, shows: .budget)
                Divider().opacity(0.4)
                BandsView(bands: a.bands, profit: profit)
            }
            PennyPanel(title: L("Days"), note: L("Press a day, on the charts or the calendar, to see it hour by hour")) {
                if a.dayReads.count == 1, let day = a.dayReads.first {
                    DayDrill(day: day, profit: profit, overall: a.hourReads, days: a.history.count)
                } else {
                    PennyColumns(slots: a.daySlots, profit: profit, selected: $openDay, grow: true, hover: dayHover)
                    DaysCalendar(days: a.dayReads, profit: profit, selected: $openDay, hover: dayHover)
                }
            }
            // The day opened hour by hour: the whole width, under the row the Days panel is in.
            if a.dayReads.count > 1, let open = openDay, let day = a.dayReads.first(where: { $0.day == open }) {
                DayDrill(day: day, profit: profit, overall: a.hourReads, days: a.history.count) { openDay = nil }
                    .id(open)
                    .layoutValue(key: PanelFull.self, value: true)
            }
            PennyPanel(title: L("Hours of the day"),
                       note: hoursOver + L("Each hour, Alaska time: its average ROAS (the dot) and its bad to good stretch (the band: its days cut into runs long enough for about 3 orders, 10th to 90th percentile, coloured where it falls against breakeven), what it spends a day and the CBH it makes a day. Each hour's column is shaded by its average: green profitable, yellow above breakeven, red below")) {
                PennyColumns(slots: a.hourSlots, profit: a.hourProfit, ranges: true, perDay: true, height: 170, grow: true)
            }
            PennyPanel(title: L("Hour by hour"), note: hoursOver + L("Press a column to sort by it; hold the pointer on a verdict for what it means. Each row is shaded by the hour's average: green profitable, yellow above breakeven, red below")) {
                HoursEfficiency(reads: a.hourReads, profit: a.hourProfit, shows: .table)
                VerdictLegend().padding(.top, 6)
            }
            if a.weeks.count >= 2 {
                PennyPanel(title: L("Weeks"), note: L("Weeks from Monday, as many as the days read reach")) { WeeksView(weeks: a.weeks, profit: profit, grow: true) }
            }
            PennyPanel(title: L("Creatives by hour"), note: L("Each creative's orders hour by hour, darker for more")) { CreativeHours(lines: Array(a.creatives.prefix(12))) }
            PennyPanel(title: L("Creatives")) { LedgerTable(lines: a.creatives, counted: L("Campaigns")) }
            PennyPanel(title: L("Campaigns")) { LedgerTable(lines: a.campaigns, counted: L("Ads")) }
        }
    }

    var header: some View {
        let a = analysis, profit = a.profit
        let name = Text(a.product).font(.system(size: 24, weight: .bold)).textSelection(.enabled)
        let pill = Text(profit.measured ? L("Breakeven %@ from CBH", PennyStyle.times(profit.breakeven)) : L("Breakeven %@ (usual line)", PennyStyle.times(profit.breakeven)))
            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
            .background(PennyStyle.red.opacity(0.16), in: Capsule()).foregroundStyle(PennyStyle.red)
            .help(L("Profitable from %@ (CBH 5%)", PennyStyle.times(profit.profitable)))
        var span = a.days.count == 1 ? L("%@ · Alaska time", PennyStyle.day(a.days.first ?? ""))
            : L("%@ days · %@ – %@ · Alaska time", a.days.count, PennyStyle.day(a.days.last ?? ""), PennyStyle.day(a.days.first ?? ""))
        // What the ▲ and ▼ under the figures are against (2026-11-07: you asked what the 7 days were set against).
        if a.before.spent > 0 { span += L(" · ▲▼ against %@", a.against.said) }
        return VStack(alignment: .leading, spacing: 6) {
            // The range selector sits in the name's row, right after the breakeven pill (2026-11-07: you pointed there);
            // on its own line, flush with the name, when the row hasn't room.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    name; pill
                    DayRangeSelector(ledger: ledger).padding(.leading, 4)
                    if loading { ProgressView().controlSize(.small) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        name; pill
                        if loading { ProgressView().controlSize(.small) }
                    }
                    DayRangeSelector(ledger: ledger)
                }
            }
            Text(span).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 4)
    }
}

/// The product page's panels, two to a row when the width holds two (2026-11-07, first in the Windows app: one panel
/// stretched across a wide window looked ridiculous), one under the other when it doesn't. Panels pair in order; a
/// full-width one (`PanelFull`: the day opened hour by hour) waits for the row being filled and goes under it; a panel
/// left over takes the whole row. The two in a row take its height, so their edges line up.
struct PanelFlow: Layout {
    /// The narrowest a panel gets beside another: the Hour by hour table and Creatives by hour (904 points of cells
    /// and names here, 860 was the Windows app's) fit at this.
    var minColumn: CGFloat = 940
    var gap: CGFloat = 14

    func rows(_ subviews: Subviews, two: Bool) -> [[Int]] {
        guard two else { return subviews.indices.map { [$0] } }
        var rows: [[Int]] = [], waiting: Int?, after: [Int] = []
        for index in subviews.indices {
            if subviews[index][PanelFull.self] {
                if waiting != nil { after.append(index) } else { rows.append([index]) }
            } else if let first = waiting {
                rows.append([first, index]); waiting = nil
                rows += after.map { [$0] }; after = []
            } else {
                waiting = index
            }
        }
        if let waiting { rows.append([waiting]) }
        return rows + after.map { [$0] }
    }

    func width(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(proposal, subviews), two = width >= minColumn * 2 + gap
        var height: CGFloat = 0
        for (number, row) in rows(subviews, two: two).enumerated() {
            let column = row.count == 2 ? (width - gap) / 2 : width
            height += (row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0) + (number > 0 ? gap : 0)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let two = bounds.width >= minColumn * 2 + gap
        var y = bounds.minY
        for row in rows(subviews, two: two) {
            let column = row.count == 2 ? (bounds.width - gap) / 2 : bounds.width
            let tallest = row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
            for (place, index) in row.enumerated() {
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(place) * (column + gap), y: y), proposal: ProposedViewSize(width: column, height: tallest))
            }
            y += tallest + gap
        }
    }
}

/// A view that takes the whole row in `PanelFlow`, under the row being filled.
struct PanelFull: LayoutValueKey { static let defaultValue = false }

/// The day range selector in the product's header, beside its name (2026-11-07, first in the Windows app): ‹ steps back
/// a range, › forward (never past today); Today, Yesterday, 7D, 14D, 30D pick one; Custom opens `RangePicker`. The
/// highlight slides from the old choice to the new one. It reads and writes the range itself, so it moves even while
/// the product's page waits for its new days.
struct DayRangeSelector: View {
    let ledger: PennyLedger
    @AppStorage("pennyProductsRange") private var range = 7
    @AppStorage("pennyProductsFrom") private var from = ""
    @AppStorage("pennyProductsTo") private var to = ""
    @State private var picking = false
    @Namespace private var slide

    /// The choices, as the range counts them: 0 today, -1 yesterday, else the last that many days; -2 picked dates.
    static let choices: [(days: Int, short: String, long: String)] = [(0, "Today", "Today"), (-1, "Yesterday", "Yesterday"), (7, "7D", "Last 7 days"),
                                                                       (14, "14D", "Last 14 days"), (30, "30D", "Last 30 days")]
    static let motion = Animation.spring(response: 0.32, dampingFraction: 0.86)

    var body: some View {
        let now = Date()
        let shown = ProductsView.days(range: range, from: from, to: to, now: now).now
        let endsToday = Ledger.endsToday(shown, now: now)
        HStack(spacing: 0) {
            arrow("chevron.left", L("The same number of days before")) { step(-1) }
            HStack(spacing: 0) {
                ForEach(Self.choices, id: \.days) { choice in
                    RangeSegment(label: L(choice.short), tip: L(choice.long), on: range == choice.days, slide: slide) {
                        withAnimation(Self.motion) { range = choice.days }
                    }
                }
                RangeSegment(label: range == -2 ? pickedName(now: now) : L("Custom"), icon: "calendar", tip: L("Pick the first and last day"), on: range == -2, slide: slide) {
                    picking = true
                }
            }
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                // Opens on the days you're looking at, not dates picked some time before.
                RangePicker(from: shown.last, to: shown.first, apply: { first, last in
                    picking = false
                    withAnimation(Self.motion) { from = first; to = last; range = -2 }
                    ledger.ask(for: Ledger.days(from: first, to: last))
                }, cancel: { picking = false })
            }
            arrow("chevron.right", L("The same number of days after")) { step(1) }
                .disabled(endsToday).opacity(endsToday ? 0.35 : 1)
        }
        .padding(3)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.1)))
        .fixedSize()
    }

    func arrow(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(tip)
    }

    /// ‹ and ›: the same number of days before or after, as picked dates; back on a preset when it lands on one.
    func step(_ direction: Int) {
        let now = Date()
        let days = Ledger.shift(ProductsView.days(range: range, from: from, to: to, now: now).now, by: direction, now: now)
        guard let newest = days.first, let oldest = days.last else { return }
        let today = Ledger.endsToday(days, now: now)
        withAnimation(Self.motion) {
            if today, days.count > 1, Self.choices.contains(where: { $0.days == days.count }) { range = days.count }
            else if today, days.count == 1 { range = 0 }
            else if days.count == 1, newest == Ledger.days(back: 2, from: now).last { range = -1 }
            else { from = oldest; to = newest; range = -2 }
        }
        ledger.ask(for: days)
    }

    /// The picked dates: no year when it's this year ("Oct 25 – Oct 31"), so the selector stays narrow.
    func pickedName(now: Date) -> String {
        let picked = Ledger.days(from: from, to: to)
        guard let first = picked.last, let last = picked.first else { return L("Custom") }
        let year = Ledger.calendar.component(.year, from: now)
        func written(_ day: String) -> String {
            guard let start = Ledger.start(of: day) else { return day }
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            if Ledger.calendar.component(.year, from: start) != year { style = style.year() }
            style.timeZone = Ledger.zone
            return start.formatted(style)
        }
        return first == last ? written(first) : "\(written(first)) – \(written(last))"
    }
}

/// A choice in the range selector: the highlight (shared by all of them, so it slides) when it is on, a faint wash
/// under the pointer.
struct RangeSegment: View {
    let label: String
    var icon: String? = nil
    let tip: String
    let on: Bool
    let slide: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 10.5)) }
            Text(label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(on ? Color.primary : Color.secondary)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background {
            if on {
                RoundedRectangle(cornerRadius: 7).fill(PixelPenny.theme.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(PixelPenny.theme.opacity(0.55)))
                    .shadow(color: PixelPenny.theme.opacity(0.18), radius: 4)
                    .matchedGeometryEffect(id: "on", in: slide)
            } else if hovering {
                RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.05))
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .onTapGesture(perform: action)
        .help(tip)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(tip)
    }
}

/// Custom range (2026-11-07, first in the Windows app): two months side by side, the first day then the last picked
/// with two clicks, the days between shaded as you hover, a rounded ribbon for the range; quick picks for whole months,
/// which the selector's buttons don't cover; Cancel and Apply. Days are Alaska's, as the dashboards count them; days
/// after today can't be picked.
struct RangePicker: View {
    let apply: (String, String) -> Void
    let cancel: () -> Void
    let today: String
    @State private var start: String?
    @State private var end: String?
    @State private var hover: String?
    /// The first day of the right-hand month.
    @State private var month: Date
    static let cell = CGSize(width: 36, height: 34)
    static let dot: CGFloat = 28, ribbon: CGFloat = 26

    init(from: String?, to: String?, apply: @escaping (String, String) -> Void, cancel: @escaping () -> Void) {
        self.apply = apply; self.cancel = cancel
        today = Ledger.name(of: Date())
        _start = State(initialValue: from); _end = State(initialValue: to)
        _month = State(initialValue: Self.first(of: Ledger.start(of: to ?? Ledger.name(of: Date())) ?? Date()))
    }

    static func first(of date: Date) -> Date { Ledger.calendar.date(from: Ledger.calendar.dateComponents([.year, .month], from: date)) ?? date }
    static func month(_ count: Int, from date: Date) -> Date { Ledger.calendar.date(byAdding: .month, value: count, to: date) ?? date }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                presets.frame(width: 118, alignment: .leading).padding(.trailing, 16)
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1).padding(.trailing, 16)
                monthView(Self.month(-1, from: month), back: true)
                Spacer().frame(width: 22)
                monthView(month, back: false)
            }
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1).padding(.top, 14)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary).font(.system(size: 12)).foregroundStyle(start == nil ? .secondary : .primary)
                    Text(L("Alaska time, as the dashboards count days")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button(L("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(L("Apply")) { done() }.keyboardShortcut(.defaultAction).disabled(start == nil)
            }.padding(.top, 14)
        }
        .padding(16)
    }

    var presets: some View {
        let thisMonth = Self.first(of: Ledger.start(of: today) ?? Date())
        let dayBefore = { (date: Date) in Ledger.name(of: date.addingTimeInterval(-12 * 3600)) }
        return VStack(alignment: .leading, spacing: 2) {
            Text(L("QUICK PICKS")).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.leading, 8).padding(.bottom, 6)
            preset(L("This month"), Ledger.name(of: thisMonth), today)
            preset(L("Last month"), Ledger.name(of: Self.month(-1, from: thisMonth)), dayBefore(thisMonth))
            preset(L("Month before"), Ledger.name(of: Self.month(-2, from: thisMonth)), dayBefore(Self.month(-1, from: thisMonth)))
        }.padding(.top, 2)
    }

    func preset(_ name: String, _ first: String, _ last: String) -> some View {
        PresetRow(name: name) {
            let last = min(last, today)
            start = first; end = last; hover = nil
            month = Self.first(of: Ledger.start(of: last) ?? Date())
        }
    }

    func monthView(_ first: Date, back: Bool) -> some View {
        var title = Date.FormatStyle.dateTime.month(.wide).year()
        title.timeZone = Ledger.zone
        let later = month < Self.first(of: Ledger.start(of: today) ?? Date())
        let lead = (Ledger.calendar.component(.weekday, from: first) + 5) % 7  // Monday first, as Penny's weeks are
        let count = Ledger.calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let parts = Ledger.calendar.dateComponents([.year, .month], from: first)
        return VStack(spacing: 0) {
            ZStack {
                Text(first.formatted(title)).font(.system(size: 13, weight: .semibold))
                HStack {
                    if back { nav("chevron.left", L("Earlier months")) { month = Self.month(-1, from: month) } }
                    Spacer()
                    if !back { nav("chevron.right", L("Later months")) { month = Self.month(1, from: month) }.disabled(!later).opacity(later ? 1 : 0.3) }
                }
            }.frame(height: 30).padding(.bottom, 6)
            HStack(spacing: 0) {
                ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], id: \.self) {
                    Text(L($0)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary).frame(width: Self.cell.width)
                }
            }.padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(0 ..< 6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0 ..< 7, id: \.self) { column in
                            let number = row * 7 + column - lead + 1
                            if number >= 1, number <= count {
                                cell(String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, number), number: number, column: column, last: count)
                            } else {
                                Color.clear.frame(width: Self.cell.width, height: Self.cell.height)
                            }
                        }
                    }
                }
            }
        }
    }

    func nav(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(tip)
    }

    /// The range being shown: the one picked, or the one being picked as the pointer moves.
    var shownRange: (low: String?, high: String?, previewing: Bool) {
        guard let start else { return (nil, nil, false) }
        if end == nil, let hover { return (min(hover, start), max(hover, start), true) }
        return (start, end ?? start, false)
    }

    func cell(_ day: String, number: Int, column: Int, last: Int) -> some View {
        let (low, high, previewing) = shownRange
        let future = day > today
        let isEnd = low != nil && (day == low || day == high)
        let inside = low.map { day > $0 } == true && high.map { day < $0 } == true
        // Ends are solid; while previewing, the hovered end is only outlined until it's clicked.
        let solid = isEnd && !(previewing && day == hover && day != start)
        let theme = PixelPenny.theme
        return ZStack {
            if let low, let high, low != high, inside || isEnd {
                // Rounded where a week or the month starts and ends, so a range reads as one ribbon, not stacked bricks.
                let opens = (column == 0 || number == 1) && day != low, closes = (column == 6 || number == last) && day != high
                let radius = Self.ribbon / 2
                UnevenRoundedRectangle(topLeadingRadius: opens ? radius : 0, bottomLeadingRadius: opens ? radius : 0,
                                       bottomTrailingRadius: closes ? radius : 0, topTrailingRadius: closes ? radius : 0)
                    .fill(theme.opacity(previewing ? 0.1 : 0.2))
                    .frame(height: Self.ribbon)
                    .padding(.leading, day == low ? Self.cell.width / 2 : 0).padding(.trailing, day == high ? Self.cell.width / 2 : 0)
            }
            Circle().fill(solid ? theme : .clear).frame(width: Self.dot, height: Self.dot)
                .overlay(Circle().strokeBorder(day == hover && !future ? theme : day == today && !solid ? PennyStyle.muted : .clear, lineWidth: 1.5))
            Text("\(number)").font(.system(size: 12, weight: solid || day == today ? .bold : .regular).monospacedDigit())
                .foregroundStyle(solid ? Color.black : Color.primary).opacity(future ? 0.35 : 1)
        }
        .frame(width: Self.cell.width, height: Self.cell.height)
        .contentShape(Rectangle())
        .onHover { inside in
            guard !future else { return }
            if inside { hover = day } else if hover == day { hover = nil }
        }
        .onTapGesture { if !future { pick(day) } }
    }

    /// First click starts a range, the second ends it (either order); a third starts a new one.
    func pick(_ day: String) {
        if start == nil || end != nil { start = day; end = nil }
        else if let first = start, day < first { end = first; start = day }
        else { end = day }
    }

    func done() {
        guard let start else { return }
        let last = end ?? start
        apply(min(start, last), max(start, last))
    }

    var summary: String {
        let year = Ledger.calendar.component(.year, from: Date())
        func name(_ day: String) -> String {
            guard let date = Ledger.start(of: day) else { return day }
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            if Ledger.calendar.component(.year, from: date) != year { style = style.year() }
            style.timeZone = Ledger.zone
            return date.formatted(style)
        }
        guard let start else { return L("Pick the first day") }
        guard let end else { return L("%@ – now pick the last day", name(start)) }
        return start == end ? name(start) : L("%@ – %@  ·  %@ days", name(start), name(end), Ledger.days(from: start, to: end).count)
    }
}

/// A quick pick in the range picker: a row that lights under the pointer.
struct PresetRow: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Text(name).font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

/// Whether Penny's copy is up to date: when he last copied and copies next, how far today's numbers reach in Grafana,
/// and each day you're looking at: final, updated in the last hour, behind, or not copied. A day still coming in counts
/// as up to date when it was copied in the last hour. The days are one row, newest first, so the latest end is what you
/// see first, with arrows either side when there are more than fit (2026-11-07, first in the Windows app: thirty days
/// wrapped into four rows). The minute's refresh keeps where you scrolled; a new range goes back to the newest day.
struct DataState: View {
    @ObservedObject var ledger: PennyLedger
    let days: [String]
    @State private var offset: CGFloat = 0
    @State private var viewport: CGFloat = 0
    static let fresh: TimeInterval = 3600
    static let tile: CGFloat = 104, gap: CGFloat = 6

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let today = Ledger.name(of: context.date)
            VStack(alignment: .leading, spacing: 8) {
                headline(today: today, now: context.date).font(.system(size: 11))
                strip(today: today, now: context.date)
            }
        }
    }

    func strip(today: String, now: Date) -> some View {
        let content = CGFloat(days.count) * (Self.tile + Self.gap) - Self.gap
        let more = content > viewport + 1
        let atStart = offset >= -1, atEnd = offset <= -(content - viewport) + 1
        let edge = min(0.45, 36 / max(viewport, 1))
        return ScrollViewReader { reader in
            HStack(spacing: 6) {
                if more { pager("chevron.left", L("Newer days"), enabled: !atStart) { page(-1, reader) } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.gap) {
                        ForEach(days, id: \.self) { day in tile(day, today: today, now: now).frame(width: Self.tile).id(day) }
                    }
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: StripOffset.self, value: geometry.frame(in: .named("strip")).minX)
                    })
                }
                .coordinateSpace(name: "strip")
                .background(GeometryReader { geometry in Color.clear.onAppear { viewport = geometry.size.width }.onChange(of: geometry.size.width) { _, width in viewport = width } })
                .onPreferenceChange(StripOffset.self) { offset = $0 }
                // The edge with more days fades out.
                .mask(LinearGradient(stops: [.init(color: more && !atStart ? .clear : .black, location: 0), .init(color: .black, location: more && !atStart ? edge : 0),
                                             .init(color: .black, location: more && !atEnd ? 1 - edge : 1), .init(color: more && !atEnd ? .clear : .black, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                if more { pager("chevron.right", L("Older days"), enabled: !atEnd) { page(1, reader) } }
            }
            .onChange(of: days) { _, new in if let first = new.first { reader.scrollTo(first, anchor: .leading) } }
        }
    }

    func pager(_ symbol: String, _ tip: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 22).frame(maxHeight: .infinity).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.secondary).disabled(!enabled).opacity(enabled ? 1 : 0.3).help(tip)
    }

    /// A page at a time, less one tile so the last one seen stays in view.
    func page(_ direction: Int, _ reader: ScrollViewProxy) {
        let step = Self.tile + Self.gap
        let first = Int((-offset / step).rounded())
        let pageSize = max(1, Int((viewport - step) / step))
        let target = min(max(first + direction * pageSize, 0), max(days.count - 1, 0))
        guard days.indices.contains(target) else { return }
        withAnimation(.easeOut(duration: 0.35)) { reader.scrollTo(days[target], anchor: .leading) }
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

    static func written(_ day: String) -> String { Ledger.short(day) }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

/// Where the Data strip's row sits as it scrolls.
struct StripOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
        case .reliable: return L("Profitable on average, and its bad stretches still break even")
        case .volatile: return L("Profitable on average, but its bad stretches lose money")
        case .thin: return L("Above breakeven, under 5% CBH: not worth more budget")
        case .losing: return L("Below breakeven, on little spend")
        case .costly: return L("Below breakeven while spending over $50 a day")
        case .dead: return L("Under 1×: less comes back than is spent")
        case .few: return L("Too few days or orders yet to judge")
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
         Column(name: "Bad → good stretch", width: 118, value: { $0.floor }, text: { "\(Ledger.ratio($0.floor)) → \(Ledger.ratio($0.ceiling))" }),
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
                }.font(.system(size: 11).monospacedDigit()).padding(.vertical, 4).padding(.horizontal, 4).padding(.leading, 3)
                // Shaded by the hour's average against breakeven (2026-11-07: you asked to see at a glance which hours pay
                // on average), with a stripe in the same colour; an hour with too few days to judge stays plain.
                .background {
                    let shade = Ledger.shade(read, profit).map(PennyStyle.tone)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(shade?.opacity(0.1) ?? Color.white.opacity(0.02))
                        if let shade { UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4).fill(shade.opacity(0.9)).frame(width: 3) }
                    }
                }
                .padding(.vertical, 1)
                .textSelection(.enabled)
            }
        }
    }
}

/// An hour's ROAS as a filled slider (2026-11-09: the old one drew only a faint range, invisible on one day): the fill
/// runs from 0 to the hour's average in its colour (green profitable, yellow above breakeven, red under), a lighter
/// band behind it spans the bad stretch to the good, and a white tick marks breakeven. Past the right end it is capped.
struct RangeBar: View {
    let read: Ledger.HourRead
    let profit: Ledger.Profit
    var top: Double { max(4, (profit.profitable * 2).rounded(.up)) }

    var body: some View {
        let color = PennyStyle.roas(read.numbers.roas, profit)
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = { (roas: Double) in width * min(max(roas, 0), top) / top }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                if let floor = read.floor, let ceiling = read.ceiling, ceiling > floor {
                    let start = max(0, x(floor) - 4), end = min(width, x(ceiling) + 4)
                    Capsule().fill(color.opacity(0.28)).frame(width: max(8, end - start), height: 10).offset(x: min(start, width - 8))
                }
                if let roas = read.numbers.roas {
                    Capsule().fill(color).frame(width: max(6, x(roas)), height: 6)
                }
                Rectangle().fill(Color.white.opacity(0.7)).frame(width: 1.5, height: 12).offset(x: x(profit.breakeven) - 0.75)
                if let roas = read.numbers.roas {
                    Circle().fill(color).frame(width: 10, height: 10).overlay(Circle().stroke(PennyStyle.surface, lineWidth: 2))
                        .offset(x: min(max(x(roas) - 5, 0), width - 10))
                }
            }.frame(maxHeight: .infinity)
        }
        .help(read.floor == nil
              ? L("Average %@; too few orders yet to tell its bad stretches from its good; the white tick is breakeven", PennyStyle.times(read.numbers.roas))
              : L("Over %@ stretches of %@ days: bad %@, good %@, average %@; the white tick is breakeven", String(read.stretches), String(read.stretch),
                  PennyStyle.times(read.floor), PennyStyle.times(read.ceiling), PennyStyle.times(read.numbers.roas)))
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
