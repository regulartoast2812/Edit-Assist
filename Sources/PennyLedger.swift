import Foundation

/// Penny's own copy of the Facebook ads' numbers, by product: each ad's spend, clicks, views, carts, checkouts, orders
/// and revenue, hour by hour, read from the same table the company's campaign dashboards sum up (ad_stats_ad, on
/// cms-replica2) and kept in penny/history/<product>/<day>.json.gz. Grafana keeps little history, so a day once copied
/// stays here; a day is copied again until it has been over for half a day, when its numbers have settled
/// (2026-11-05). Days are the company's: Alaska time, as the dashboards count them.
enum Ledger {
    static let zone = TimeZone(identifier: "America/Anchorage")!
    static var calendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; return calendar }
    /// cms-replica2, where Facebook Ads Manager Campaign V1.0 reads its campaign and hourly tables.
    static let source = Grafana.Source(uid: "0YhUzD17k", type: "grafana-postgresql-datasource", name: "cms-replica2")
    /// How many days back the copy reaches (today included).
    static let kept = 30
    /// A day is copied again until it has been over this long.
    static let settles: TimeInterval = 12 * 3600

    // MARK: Numbers

    /// An ad's (or a product's, an hour's) numbers. Revenue is after tax, as the campaign dashboard counts it.
    struct Numbers: Equatable, Codable {
        var spent = 0.0, impressions = 0.0, clicks = 0.0, access = 0.0, views = 0.0, carts = 0.0, checkouts = 0.0, orders = 0.0, revenue = 0.0
        /// The query's column for each number, in the order they are saved.
        static let columns = ["spent", "impressions", "clicks", "access", "views", "carts", "checkouts", "orders", "revenue"]

        init() {}
        init(_ values: [Double]) {
            let value = { (index: Int) in values.indices.contains(index) ? values[index] : 0 }
            (spent, impressions, clicks, access, views) = (value(0), value(1), value(2), value(3), value(4))
            (carts, checkouts, orders, revenue) = (value(5), value(6), value(7), value(8))
        }
        var values: [Double] { [spent, impressions, clicks, access, views, carts, checkouts, orders, revenue] }

        // Saved as a plain list: a day holds tens of thousands of them.
        init(from decoder: Decoder) throws { self.init(try decoder.singleValueContainer().decode([Double].self)) }
        func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(values) }

        static func + (a: Numbers, b: Numbers) -> Numbers { Numbers(zip(a.values, b.values).map(+)) }
        static func += (a: inout Numbers, b: Numbers) { a = a + b }

        var roas: Double? { spent > 0 ? revenue / spent : nil }
        var cpp: Double? { orders > 0 ? spent / orders : nil }
        var aov: Double? { orders > 0 ? revenue / orders : nil }
        var ctr: Double? { impressions > 0 ? clicks / impressions : nil }
        var cpm: Double? { impressions > 0 ? spent / impressions * 1000 : nil }
        var cpc: Double? { clicks > 0 ? spent / clicks : nil }
        var cpv: Double? { views > 0 ? spent / views : nil }
        /// Orders per product view, and its two steps: views to checkouts, checkouts to orders.
        var cr: Double? { views > 0 ? orders / views : nil }
        var cr1: Double? { views > 0 ? checkouts / views : nil }
        var cr2: Double? { checkouts > 0 ? orders / checkouts : nil }
    }

    /// An ad as it was that day: its campaign, who runs it, where it sends people.
    struct Ad: Equatable, Codable {
        var id: String
        var campaignID = "", campaign = "", name = "", creative = "", publisher = "", page = "", status = "", strategy = ""
        var budget: Double?
    }

    /// One ad's numbers in one hour of the day (0–23, Alaska time).
    struct Hour: Equatable, Codable {
        var ad: String, hour: Int, numbers: Numbers
        enum CodingKeys: String, CodingKey { case ad = "a", hour = "h", numbers = "n" }
    }

    /// One product's day: its ads and their hours.
    struct Day: Equatable, Codable {
        var product: String, day: String, copied: Date, ads: [Ad], hours: [Hour]
        var numbers: Numbers { hours.reduce(Numbers()) { $0 + $1.numbers } }
    }

    /// A product's day as the company's CBH counts it (2026-11-06): all its orders and ad spend, every source, from the
    /// tables Retail Operations V3.5 sums (stats_page, ad_stats_campaign) and the database's own `cbh_tax`. `beforeAds` is
    /// `cbh_tax` asked again with no ad spend: what the product kept before ads, so the cost of an ad dollar is measured,
    /// not assumed.
    struct Margin: Equatable, Codable {
        var orders = 0.0, revenue = 0.0, cost = 0.0, tax = 0.0, spent = 0.0, cbh = 0.0, beforeAds = 0.0
        /// The query's column for each number, in the order they are saved. Revenue is after tax, as the dashboard shows it.
        static let columns = ["po", "re", "pc", "tax", "me", "cbh", "cbh_before_ads"]

        init() {}
        init(_ values: [Double]) {
            let value = { (index: Int) in values.indices.contains(index) ? values[index] : 0 }
            (orders, revenue, cost, tax) = (value(0), value(1), value(2), value(3))
            (spent, cbh, beforeAds) = (value(4), value(5), value(6))
        }
        var values: [Double] { [orders, revenue, cost, tax, spent, cbh, beforeAds] }

        init(from decoder: Decoder) throws { self.init(try decoder.singleValueContainer().decode([Double].self)) }
        func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(values) }

        static func + (a: Margin, b: Margin) -> Margin { Margin(zip(a.values, b.values).map(+)) }
        /// CBH as a share of revenue, as %CBH on the dashboard.
        var share: Double? { revenue > 0 ? cbh / revenue : nil }
    }

    /// What has been copied: when each day was, and each product's totals by day (penny/history/summary.json).
    struct Summary: Equatable, Codable {
        var copied: [String: Date] = [:]
        var products: [String: [String: Numbers]] = [:]
        /// The last hour of each day with numbers in it, as last copied.
        var latest: [String: Int] = [:]
        /// Each product's CBH by day, and when each day's was copied (its own query, so a failure there leaves the ads' copy alone).
        var margins: [String: [String: Margin]] = [:]
        var margined: [String: Date] = [:]

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            copied = try container.decodeIfPresent([String: Date].self, forKey: .copied) ?? [:]
            products = try container.decodeIfPresent([String: [String: Numbers]].self, forKey: .products) ?? [:]
            latest = try container.decodeIfPresent([String: Int].self, forKey: .latest) ?? [:]
            margins = try container.decodeIfPresent([String: [String: Margin]].self, forKey: .margins) ?? [:]
            margined = try container.decodeIfPresent([String: Date].self, forKey: .margined) ?? [:]
        }

        func numbers(of product: String, on days: [String]) -> Numbers {
            days.reduce(Numbers()) { $0 + (products[product]?[$1] ?? Numbers()) }
        }

        /// The product's CBH over the days, and how many of them had it.
        func margin(of product: String, on days: [String]) -> (margin: Margin, days: Int) {
            let found = days.compactMap { margins[product]?[$0] }
            return (found.reduce(Margin()) { $0 + $1 }, found.count)
        }
    }

    // MARK: Days

    static func name(of date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func start(of day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The day as Grafana's time range: its first millisecond to its last.
    static func bounds(of day: String) -> (from: Date, to: Date)? {
        guard let start = start(of: day), let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, next.addingTimeInterval(-0.001))
    }

    /// The days counting back from the one `now` is in, newest first.
    static func days(back count: Int, from now: Date) -> [String] {
        let today = calendar.startOfDay(for: now)
        return (0 ..< max(0, count)).compactMap { calendar.date(byAdding: .day, value: -$0, to: today).map(name(of:)) }
    }

    /// The days from one to another, both included, newest first (either order; at most a year).
    static func days(from first: String, to last: String) -> [String] {
        guard let a = start(of: first), let b = start(of: last) else { return [] }
        let count = (calendar.dateComponents([.day], from: min(a, b), to: max(a, b)).day ?? 0) + 1
        return days(back: min(count, 366), from: max(a, b))
    }

    /// The same number of days just before (`direction` < 0) or after (> 0) `days` (newest first), never past the day
    /// `now` is in: the range selector's ‹ and › (2026-11-07, first in the Windows app). Stepping forward into today ends
    /// the window on today, keeping its length.
    static func shift(_ days: [String], by direction: Int, now: Date) -> [String] {
        guard let first = days.first, let last = days.last, direction != 0 else { return days }
        let count = days.count
        if direction < 0 {
            guard let oldest = start(of: last) else { return days }
            return self.days(back: count, from: oldest.addingTimeInterval(-12 * 3600))
        }
        // Middle of the day n days on, so a daylight-saving hour can't land it on the wrong day.
        guard let newest = start(of: first), let later = calendar.date(byAdding: .day, value: count, to: newest) else { return days }
        let end = later.addingTimeInterval(12 * 3600)
        return name(of: end) >= name(of: now) ? self.days(back: count, from: now) : self.days(back: count, from: end)
    }

    /// Whether `days` (newest first) already end on the day `now` is in.
    static func endsToday(_ days: [String], now: Date) -> Bool { days.first == name(of: now) }

    /// The days still to copy, newest first: never copied, or copied before they had settled.
    static func wanted(now: Date, summary: Summary, kept: Int = kept) -> [String] { wanted(now: now, copied: summary.copied, kept: kept) }

    static func wanted(now: Date, copied: [String: Date], kept: Int = kept) -> [String] {
        days(back: kept, from: now).filter { day in
            guard let copied = copied[day] else { return true }
            guard let end = bounds(of: day)?.to else { return false }
            return copied < end.addingTimeInterval(settles) && now >= copied.addingTimeInterval(60)
        }
    }

    /// How far a day's copy can be trusted: not copied, copied while its numbers still come in (copied again until
    /// `settles` after it ends), or copied after that and final.
    enum State: Equatable { case missing, live(copied: Date, until: Date), final(copied: Date) }

    static func state(of day: String, in summary: Summary) -> State {
        guard let copied = summary.copied[day], let end = bounds(of: day)?.to else { return .missing }
        let until = end.addingTimeInterval(settles)
        return copied >= until ? .final(copied: copied) : .live(copied: copied, until: until)
    }

    /// The last hour any product has numbers in.
    static func latest(_ products: [String: Day]) -> Int? {
        products.values.flatMap { $0.hours.filter { $0.numbers.spent > 0 || $0.numbers.orders > 0 }.map(\.hour) }.max()
    }

    /// A product as a folder name: what a folder can't hold becomes "-".
    static func folder(of product: String) -> String {
        let cleaned = product.map { "/:\\".contains($0) ? "-" : $0 }.reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "NA" + cleaned : cleaned
    }

    // MARK: Queries

    /// Only rows something happened in: spend, a product view or an order.
    private static let happened = """
        having sum(coalesce(s.stats_spend, 0)) > 0 or sum(coalesce(s.tk_stats_view, 0)) > 0 or sum(coalesce(s.tk_stats_purchase, 0)) > 0
        """

    /// Each ad that ran that day, by product, with its campaign.
    static let adsQuery = """
        select coalesce(nullif(s.pbase_code, ''), 'NA') as product,
               s.ad_id::text as ad_id,
               max(s.campaign_id::text) as campaign_id,
               max(cp.name) as campaign,
               max(ad.name) as ad,
               max(ad.creative_id::text) as creative_id,
               max(cp.publisher_email) as publisher,
               max(s.cta_url_domain || '/' || coalesce(s.cta_url_slug, '')) as page,
               max(cp.effective_status) as status,
               max(cp.strategy) as strategy,
               max(cp.daily_budget) / 100.0 as budget
        from ad_stats_ad s
            join fb_campaign cp on cp.id = s.campaign_id
            left join fb_ad ad on ad.id = s.ad_id
        where $__timeFilter(s.time) and s.ad_id is not null
        group by 1, 2
        \(happened)
        """

    /// Each ad's numbers hour by hour (Alaska time), by product.
    static let hoursQuery = """
        select coalesce(nullif(s.pbase_code, ''), 'NA') as product,
               s.ad_id::text as ad_id,
               extract(hour from timezone('america/anchorage', timezone('utc', s.time)))::int as hour,
               sum(coalesce(s.stats_spend, 0)) as spent,
               sum(coalesce(s.stats_impression, 0)) as impressions,
               sum(coalesce(s.stats_click, 0)) as clicks,
               sum(coalesce(s.tk_stats_access, 0)) as access,
               sum(coalesce(s.tk_stats_view, 0)) as views,
               sum(coalesce(s.tk_stats_addtocart, 0)) as carts,
               sum(coalesce(s.tk_stats_initcheckout, 0)) as checkouts,
               sum(coalesce(s.tk_stats_purchase, 0)) as orders,
               sum(coalesce(s.tk_stats_revenue, 0)) - sum(coalesce(s.tk_stats_tax_amount, 0)) as revenue
        from ad_stats_ad s
            join fb_campaign cp on cp.id = s.campaign_id
        where $__timeFilter(s.time) and s.ad_id is not null
        group by 1, 2, 3
        \(happened)
        """

    static var targets: [[String: Any]] {
        [("A", adsQuery), ("B", hoursQuery)].map { refId, sql in
            ["refId": refId, "rawSql": sql, "format": "table", "rawQuery": true, "editorMode": "code",
             "datasource": ["uid": source.uid, "type": source.type]]
        }
    }

    /// Each product's day as the company's CBH counts it: Retail Operations V3.5's product table with no filters, and
    /// `cbh_tax` asked a second time with no ad spend (`sum(me) * 0` keeps the argument's type).
    static let marginsQuery = """
        select product,
               sum(po) as po,
               sum(re) - sum(tax) as re,
               sum(pc) as pc,
               sum(tax) as tax,
               sum(me) as me,
               cbh_tax(sum(po), sum(re), sum(me), sum(pc), sum(tax)) as cbh,
               cbh_tax(sum(po), sum(re), sum(me) * 0, sum(pc), sum(tax)) as cbh_before_ads
        from (select coalesce(nullif(pbase_code, ''), 'NA') as product,
                     sum(stats_po) as po,
                     sum(stats_amount) as re,
                     sum(stats_cost_product) + sum(stats_cost_fulfillment) + sum(stats_cost_shipping_handling) as pc,
                     sum(stats_tax_amount) as tax,
                     0 as me
              from stats_page
              where $__timeFilter(time)
              group by 1
              union all
              select coalesce(nullif(pbase_code, ''), 'NA') as product, 0, 0, 0, 0, sum(coalesce(stats_spend, 0))
              from ad_stats_campaign
              where $__timeFilter(time)
              group by 1) t
        group by 1
        having sum(re) > 0 or sum(me) > 0
        """

    static var marginTargets: [[String: Any]] {
        [["refId": "C", "rawSql": marginsQuery, "format": "table", "rawQuery": true, "editorMode": "code",
          "datasource": ["uid": source.uid, "type": source.type]]]
    }

    /// The CBH answer by product.
    static func margins(from frames: [Grafana.Frame]) -> [String: Margin] {
        var result: [String: Margin] = [:]
        for frame in frames where frame.column("cbh") != nil {
            let columns = Margin.columns.map { frame.column($0) }
            for row in 0 ..< frame.rows {
                let name = frame.column("product").flatMap { Grafana.text(of: $0.at(row)) } ?? ""
                result[name.isEmpty ? "NA" : name] = Margin(columns.map { $0?.at(row).number ?? 0 })
            }
        }
        return result
    }

    /// The two answers sorted into each product's day. An ad with hours but no row of its own keeps just its id.
    static func products(from frames: [Grafana.Frame], day: String, copied: Date) -> [String: Day] {
        var result: [String: Day] = [:]
        func text(_ column: Grafana.Column?, _ row: Int) -> String { column.flatMap { Grafana.text(of: $0.at(row)) } ?? "" }
        func product(_ frame: Grafana.Frame, _ row: Int) -> String { let name = text(frame.column("product"), row); return name.isEmpty ? "NA" : name }
        for frame in frames where frame.column("campaign") != nil {
            for row in 0 ..< frame.rows {
                let id = text(frame.column("ad_id"), row)
                guard !id.isEmpty else { continue }
                let ad = Ad(id: id, campaignID: text(frame.column("campaign_id"), row), campaign: text(frame.column("campaign"), row),
                            name: text(frame.column("ad"), row), creative: text(frame.column("creative_id"), row),
                            publisher: text(frame.column("publisher"), row), page: text(frame.column("page"), row),
                            status: text(frame.column("status"), row), strategy: text(frame.column("strategy"), row),
                            budget: frame.column("budget")?.at(row).number)
                let name = product(frame, row)
                result[name, default: Day(product: name, day: day, copied: copied, ads: [], hours: [])].ads.append(ad)
            }
        }
        for frame in frames where frame.column("hour") != nil {
            let columns = Numbers.columns.map { frame.column($0) }
            for row in 0 ..< frame.rows {
                let id = text(frame.column("ad_id"), row)
                guard !id.isEmpty, let hour = frame.column("hour")?.at(row).number else { continue }
                let numbers = Numbers(columns.map { $0?.at(row).number ?? 0 })
                let name = product(frame, row)
                result[name, default: Day(product: name, day: day, copied: copied, ads: [], hours: [])].hours.append(Hour(ad: id, hour: Int(hour), numbers: numbers))
            }
        }
        for name in result.keys {
            let known = Set(result[name]!.ads.map(\.id))
            let missing = Set(result[name]!.hours.map(\.ad)).subtracting(known)
            result[name]!.ads += missing.sorted().map { Ad(id: $0) }
        }
        return result
    }

    // MARK: Breakdowns

    /// A row of a breakdown: a creative or a campaign, its numbers over the days read and hour by hour.
    struct Line: Identifiable, Equatable {
        var id: String
        var name: String
        /// The campaigns a creative ran in, or the ads a campaign ran.
        var count: Int
        var publisher = ""
        var numbers = Numbers()
        var hours = [Numbers](repeating: Numbers(), count: 24)

        /// The hours that sold best, by orders, then revenue.
        func bestHours(_ count: Int = 3) -> [Int] {
            hours.indices.filter { hours[$0].orders > 0 }
                .sorted { (hours[$0].orders, hours[$0].revenue) > (hours[$1].orders, hours[$1].revenue) }.prefix(count).map { $0 }
        }
    }

    /// The numbers summed over the days.
    static func total(_ days: [Day]) -> Numbers { days.reduce(Numbers()) { $0 + $1.numbers } }

    /// The days' numbers by hour of the day, 0–23.
    static func hours(_ days: [Day]) -> [Numbers] {
        var hours = [Numbers](repeating: Numbers(), count: 24)
        for day in days { for hour in day.hours where hours.indices.contains(hour.hour) { hours[hour.hour] += hour.numbers } }
        return hours
    }

    /// The creatives, as the ads' names: the same creative run in several campaigns is one line. Most spent first.
    static func creatives(_ days: [Day]) -> [Line] {
        lines(days) { ad in
            let name = ad.name.trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? ad.id : name, name.isEmpty ? ad.id : name, ad.campaignID)
        }
    }

    /// The campaigns, most spent first.
    static func campaigns(_ days: [Day]) -> [Line] {
        lines(days) { ad in
            let id = ad.campaignID.isEmpty ? ad.id : ad.campaignID
            return (id, ad.campaign.isEmpty ? id : ad.campaign, ad.id)
        }
    }

    /// Groups the ads' hours by a key: (key, the name shown, what is counted inside).
    private static func lines(_ days: [Day], by key: (Ad) -> (key: String, name: String, inner: String)) -> [Line] {
        var lines: [String: Line] = [:], inner: [String: Set<String>] = [:]
        for day in days {
            let ads = Dictionary(day.ads.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for hour in day.hours {
                let ad = ads[hour.ad] ?? Ad(id: hour.ad)
                let (id, name, counted) = key(ad)
                var line = lines[id] ?? Line(id: id, name: name, count: 0, publisher: ad.publisher)
                line.numbers += hour.numbers
                if line.hours.indices.contains(hour.hour) { line.hours[hour.hour] += hour.numbers }
                if line.publisher.isEmpty { line.publisher = ad.publisher }
                lines[id] = line
                inner[id, default: []].insert(counted)
            }
        }
        return lines.values.map { var line = $0; line.count = inner[$0.id]?.count ?? 0; return line }
            .sorted { ($0.numbers.spent, $0.numbers.revenue, $1.name) > ($1.numbers.spent, $1.numbers.revenue, $0.name) }
    }

    // MARK: Profit

    /// What a product keeps, from the company's CBH over the days (2026-11-06): of each revenue dollar before ads
    /// (`kept`), and what each ad dollar takes from CBH (`cost`, 1 when CBH is what's left after ads). Breakeven is the
    /// ROAS where an hour's CBH is zero. Without CBH, the usual 1.8× line.
    struct Profit: Equatable {
        var kept: Double, cost: Double
        /// True when it comes from CBH, not the usual line.
        var measured = true

        init(kept: Double, cost: Double, measured: Bool = true) { self.kept = kept; self.cost = cost; self.measured = measured }

        /// From a product's CBH; nil with no revenue or nothing kept before ads.
        init?(_ margin: Margin) {
            guard margin.revenue > 0, margin.beforeAds > 0 else { return nil }
            kept = margin.beforeAds / margin.revenue
            let measured = margin.spent > 0 ? (margin.beforeAds - margin.cbh) / margin.spent : 1
            cost = (0.5 ... 2).contains(measured) ? measured : 1
        }

        static let usual = Profit(kept: 1 / 1.8, cost: 1, measured: false)

        var breakeven: Double { cost / kept }
        /// The ROAS where CBH is that share of revenue.
        func roas(cbh share: Double) -> Double? { kept > share ? cost / (kept - share) : nil }
        /// The line above which an hour counts as profitable: CBH 5% of revenue (2.0× when breakeven is 1.8×, your old line).
        var profitable: Double { roas(cbh: 0.05) ?? breakeven * 1.11 }
        /// The CBH some ads' numbers make: what their revenue keeps, less what their spend takes.
        func cbh(_ numbers: Numbers) -> Double { kept * numbers.revenue - cost * numbers.spent }
    }

    /// An hour of the day over the days read, as a media buyer judges it: what it spends a day, its ROAS, its bad-day
    /// floor and good-day ceiling (the 10th and 90th percentile of its days' ROAS, so one lucky order doesn't count), the
    /// CBH it makes and a verdict. The rules are the Campaign Breakdown dashboard's, with breakeven from CBH.
    struct HourRead: Identifiable, Equatable {
        enum Verdict: String, CaseIterable { case reliable, volatile, thin, losing, costly, dead, few, idle }
        var hour: Int
        var id: Int { hour }
        var numbers = Numbers()
        /// Days it spent in.
        var days = 0
        var floor: Double?
        var ceiling: Double?
        var cbh = 0.0
        var verdict = Verdict.idle
        var spentPerDay: Double { days > 0 ? numbers.spent / Double(days) : 0 }
    }

    /// A day's hour counts toward the floor and ceiling when it spent $20, or $3 on a day under $300 (low signal).
    static func hourReads(_ days: [Day], profit: Profit) -> [HourRead] {
        var reads = (0 ..< 24).map { HourRead(hour: $0) }
        var roases = [[Double]](repeating: [], count: 24)
        for day in days {
            var hours = [Numbers](repeating: Numbers(), count: 24)
            for hour in day.hours where hours.indices.contains(hour.hour) { hours[hour.hour] += hour.numbers }
            let least = hours.reduce(0) { $0 + $1.spent } < 300 ? 3.0 : 20.0
            for (hour, numbers) in hours.enumerated() where numbers.spent > 0 || numbers.orders > 0 {
                reads[hour].numbers += numbers
                if numbers.spent > 0 { reads[hour].days += 1 }
                if numbers.spent >= least, let roas = numbers.roas { roases[hour].append(roas) }
            }
        }
        for hour in reads.indices {
            let sorted = roases[hour].sorted()
            reads[hour].floor = percentile(sorted, 0.1)
            reads[hour].ceiling = percentile(sorted, 0.9)
            reads[hour].cbh = profit.cbh(reads[hour].numbers)
            reads[hour].verdict = verdict(reads[hour], profit: profit)
        }
        return reads
    }

    /// The value a share of the way up sorted values, as the dashboard took it (no interpolation).
    static func percentile(_ sorted: [Double], _ share: Double) -> Double? {
        sorted.isEmpty ? nil : sorted[min(sorted.count - 1, Int(share * Double(sorted.count - 1)))]
    }

    static func verdict(_ read: HourRead, profit: Profit) -> HourRead.Verdict {
        guard read.days > 0, let roas = read.numbers.roas else { return .idle }
        if read.days < 3 { return .few }
        if roas < 1 { return .dead }
        if roas < profit.breakeven { return read.spentPerDay > 50 ? .costly : .losing }
        if roas < profit.profitable { return .thin }
        return (read.floor ?? 0) >= profit.breakeven ? .reliable : .volatile
    }

    /// Where the budget went: hours below breakeven, thin, and profitable, each with its numbers and CBH.
    struct Efficiency: Equatable {
        struct Part: Equatable { var hours: [Int] = []; var numbers = Numbers(); var cbh = 0.0 }
        var losing = Part(), thin = Part(), profitable = Part()
        var total: Numbers { losing.numbers + thin.numbers + profitable.numbers }
    }

    static func efficiency(_ reads: [HourRead], profit: Profit) -> Efficiency {
        var result = Efficiency()
        for read in reads where read.numbers.spent > 0 {
            let roas = read.numbers.roas ?? 0
            let add = { (part: inout Efficiency.Part) in part.hours.append(read.hour); part.numbers += read.numbers; part.cbh += read.cbh }
            if roas < profit.breakeven { add(&result.losing) } else if roas < profit.profitable { add(&result.thin) } else { add(&result.profitable) }
        }
        return result
    }

    /// A day as the dashboard's trend drew it (2026-11-06): its numbers hour by hour, its CBH, and its dead spend, the
    /// share spent in hours that brought back under 1× that day.
    struct DayRead: Identifiable, Equatable {
        var day: String
        var id: String { day }
        var hours = [Numbers](repeating: Numbers(), count: 24)
        var numbers = Numbers()
        var dead = 0.0
        var cbh = 0.0
        var weekend = false
    }

    /// The days, oldest first.
    static func dayReads(_ days: [Day], profit: Profit) -> [DayRead] {
        days.map { day in
            var read = DayRead(day: day.day)
            for hour in day.hours where read.hours.indices.contains(hour.hour) { read.hours[hour.hour] += hour.numbers }
            read.numbers = read.hours.reduce(Numbers()) { $0 + $1 }
            let dead = read.hours.filter { $0.spent > 0 && ($0.roas ?? 0) < 1 }.reduce(0) { $0 + $1.spent }
            read.dead = read.numbers.spent > 0 ? dead / read.numbers.spent : 0
            read.cbh = profit.cbh(read.numbers)
            read.weekend = start(of: day.day).map { [1, 7].contains(calendar.component(.weekday, from: $0)) } ?? false
            return read
        }.sorted { $0.day < $1.day }
    }

    /// A week from Monday, as the dashboard's weekly overview had it: its numbers, CPM, dead spend, and the night
    /// (12 AM–6 AM) against the peak (9 AM–9 PM).
    struct WeekRead: Identifiable, Equatable {
        var start: String
        var id: String { start }
        var days = 0
        var numbers = Numbers(), night = Numbers(), peak = Numbers()
        var deadSpent = 0.0
        var cbh = 0.0
        var dead: Double { numbers.spent > 0 ? deadSpent / numbers.spent : 0 }
    }

    static func weekReads(_ days: [DayRead]) -> [WeekRead] {
        var weeks: [String: WeekRead] = [:]
        for day in days {
            guard let date = start(of: day.day) else { continue }
            let back = (calendar.component(.weekday, from: date) + 5) % 7
            let monday = calendar.date(byAdding: .day, value: -back, to: date).map(name(of:)) ?? day.day
            var week = weeks[monday] ?? WeekRead(start: monday)
            week.days += 1
            week.numbers += day.numbers
            week.deadSpent += day.dead * day.numbers.spent
            week.cbh += day.cbh
            for hour in 0 ..< 6 { week.night += day.hours[hour] }
            for hour in 9 ..< 21 { week.peak += day.hours[hour] }
            weeks[monday] = week
        }
        return weeks.values.sorted { $0.start < $1.start }
    }

    /// Spend by the ROAS each hour of each day brought back, as the dashboard's budget efficiency bands, with breakeven
    /// and the profitable line from CBH.
    struct Band: Identifiable, Equatable {
        enum Kind: String, CaseIterable { case nothing, under1, belowBreakeven, thin, good, great }
        var kind: Kind
        var id: String { kind.rawValue }
        var low: Double, high: Double
        var numbers = Numbers()
        var cells = 0
    }

    static func bands(_ days: [Day], profit: Profit) -> [Band] {
        let top = max(3, profit.profitable)
        var bands = [Band(kind: .nothing, low: 0, high: 0), Band(kind: .under1, low: 0, high: 1), Band(kind: .belowBreakeven, low: 1, high: profit.breakeven),
                     Band(kind: .thin, low: profit.breakeven, high: profit.profitable), Band(kind: .good, low: profit.profitable, high: top),
                     Band(kind: .great, low: top, high: .infinity)]
        for day in dayReads(days, profit: profit) {
            for numbers in day.hours where numbers.spent > 0 {
                let roas = numbers.roas ?? 0
                let index = numbers.revenue <= 0 ? 0 : roas < 1 ? 1 : roas < profit.breakeven ? 2 : roas < profit.profitable ? 3 : roas < top ? 4 : 5
                bands[index].numbers += numbers
                bands[index].cells += 1
            }
        }
        return bands
    }

    // MARK: Report
    // MARK: Report

    /// Penny's read of a product over the days: how it did against the days before, which creatives sell and which
    /// only spend, and the hours that sell. Each finding a line, money in dollars, hours in Alaska time.
    static func report(_ days: [Day], before: Numbers? = nil, profit: Profit = .usual, against: Against? = nil) -> [String] {
        let total = total(days)
        guard total.spent > 0 || total.orders > 0 else { return [L("Nothing ran in these days.")] }
        var lines: [String] = []
        var first = L("Spent **%@**, **%@** orders, **%@** revenue: ROAS **%@**", money(total.spent), whole(total.orders), money(total.revenue),
                      tone(ratio(total.roas), tone(roas: total.roas, profit)))
        if let cpp = total.cpp { first += L(", %@ per order", money(cpp)) }
        lines.append(first)
        if let before, before.spent > 0, let now = total.roas, let then = before.roas {
            let change = then > 0 ? (now - then) / then : 0
            let moved = tone(L(change > 0 ? "up %@" : "down %@", percent(abs(change))), change > 0 ? .good : .bad)
            // Named and dated (2026-11-07: you asked what the 7 days were set against).
            let with = against?.said ?? L("the days before")
            lines.append(abs(change) < 0.05 ? L("ROAS about the same as %@: %@", with, ratio(then)) : L("ROAS %@ against %@: %@", moved, with, ratio(then)))
        }
        // Creatives worth naming spent at least 2% of the product's spend; one with no orders, twice what an order costs.
        let all = creatives(days), floor = max(total.spent * 0.02, 5), roas = total.roas ?? 0
        let creatives = all.filter { $0.numbers.spent >= floor }
        let selling = creatives.filter { $0.numbers.orders >= 2 }.sorted { ($0.numbers.roas ?? 0) > ($1.numbers.roas ?? 0) }
        for line in selling.prefix(3) where (line.numbers.roas ?? 0) >= roas {
            var text = L("Sells: **%@**: ROAS %@ on %@, %@ orders", line.name, tone(ratio(line.numbers.roas), tone(roas: line.numbers.roas, profit)), money(line.numbers.spent), whole(line.numbers.orders))
            let hours = line.bestHours()
            if !hours.isEmpty { text += L(", most orders at %@", hours.map(hourName).joined(separator: ", ")) }
            lines.append(text)
        }
        for line in creatives.filter({ $0.numbers.orders > 0 && ($0.numbers.roas ?? 0) < roas * 0.7 }).prefix(3) {
            lines.append(L("Below the product: **%@**: ROAS %@ on %@", line.name, tone(ratio(line.numbers.roas), tone(roas: line.numbers.roas, profit)), money(line.numbers.spent)))
        }
        let waste = max(2 * (total.cpp ?? 10), 20)
        for line in all.filter({ $0.numbers.orders == 0 && $0.numbers.spent >= waste }).prefix(3) {
            lines.append(L("No orders: **%@** spent %@", line.name, tone(money(line.numbers.spent), .bad)))
        }
        // The hours, as a media buyer reads them: breakeven, where the budget went, what to cut and where to put more.
        let reads = hourReads(days, profit: profit)
        lines.append(profit.measured
                     ? L("Breakeven ROAS **%@** from CBH: the product keeps %@ of revenue before ads; profitable from %@ (CBH 5%)", ratio(profit.breakeven), percent(profit.kept), ratio(profit.profitable))
                     : L("Breakeven ROAS **%@**, the usual line: no CBH copied for these days yet", ratio(profit.breakeven)))
        let parts = efficiency(reads, profit: profit), spent = parts.total.spent, revenue = parts.total.revenue
        if spent > 0, !parts.losing.hours.isEmpty {
            lines.append(L("**%@** of spend went to hours below breakeven, bringing back %@ of revenue: CBH **%@**", tone(percent(parts.losing.numbers.spent / spent), .bad),
                           percent(revenue > 0 ? parts.losing.numbers.revenue / revenue : 0), tone(money(parts.losing.cbh), tone(money: parts.losing.cbh))))
        }
        if spent > 0, !parts.profitable.hours.isEmpty {
            lines.append(L("**%@** of spend went to profitable hours and made %@ of revenue: CBH **%@**", tone(percent(parts.profitable.numbers.spent / spent), .good),
                           percent(revenue > 0 ? parts.profitable.numbers.revenue / revenue : 0), tone(money(parts.profitable.cbh), tone(money: parts.profitable.cbh))))
        }
        let more = reads.filter { $0.verdict == .reliable }.sorted { $0.cbh > $1.cbh }.prefix(3)
        if !more.isEmpty {
            lines.append(L("Put more in: %@", more.map { L("%@ (ROAS %@, bad days %@)", tone(hourName($0.hour), .good), tone(ratio($0.numbers.roas), .good), ratio($0.floor)) }.joined(separator: ", ")))
        }
        let cut = reads.filter { $0.verdict == .costly || $0.verdict == .dead }.sorted { $0.cbh < $1.cbh }.prefix(3)
        if !cut.isEmpty {
            lines.append(L("Cut back: %@", cut.map { L("%@ (ROAS %@, CBH %@ a day)", tone(hourName($0.hour), .bad), tone(ratio($0.numbers.roas), .bad), tone(money($0.cbh / Double(max($0.days, 1))), .bad)) }.joined(separator: ", ")))
        }
        return lines
    }

    /// A value Penny's read colours (2026-11-06): green good news, yellow so-so, red bad. The page draws it bold;
    /// `plain` gives the line without its marks.
    enum Tone: String { case good = "g", fair = "y", bad = "r" }

    static func tone(_ text: String, _ tone: Tone?) -> String { tone.map { "⟦\($0.rawValue)⟧\(text)⟦/⟧" } ?? text }

    /// Green from the profitable line, yellow from breakeven, red under it.
    static func tone(roas: Double?, _ profit: Profit) -> Tone? {
        guard let roas else { return nil }
        return roas >= profit.profitable ? .good : roas >= profit.breakeven ? .fair : .bad
    }

    static func tone(money: Double) -> Tone { money < 0 ? .bad : .good }

    /// The shade of an hour's column on the charts and its row in the table: its average against breakeven (2026-11-07:
    /// you asked to see at a glance which hours pay on average). None for an idle hour or one with too few days to judge.
    static func shade(_ read: HourRead, _ profit: Profit) -> Tone? {
        read.days > 0 && read.verdict != .few ? tone(roas: read.numbers.roas ?? 0, profit) : nil
    }

    /// An hour of a day opened hour by hour: shaded by how that hour does over all the days read, never by the day's own
    /// hour, which its bar already shows (2026-11-07). None without the days' hours (a range of one day).
    static func shade(_ overall: [HourRead]?, hour: Int, _ profit: Profit) -> Tone? {
        overall?.first(where: { $0.hour == hour }).flatMap { shade($0, profit) }
    }

    /// One day's hour: shaded by its ROAS when it spent.
    static func shade(_ hour: Numbers, _ profit: Profit) -> Tone? { hour.spent > 0 ? tone(roas: hour.roas ?? 0, profit) : nil }

    /// A day as the read and the header write it: "Oct 31".
    static func short(_ day: String) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = zone
        return start(of: day)?.formatted(style) ?? day
    }

    /// Days (any order) as a span: "Oct 25 – Oct 31", or "Oct 31" for one.
    static func span(_ days: [String]) -> String {
        let sorted = days.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "" }
        return first == last ? short(first) : "\(short(first)) – \(short(last))"
    }

    /// The days a range is set against, by how many: "the day before", "the week before", "the 14 days before".
    static func beforeName(_ count: Int) -> String {
        count == 1 ? L("the day before") : count == 7 ? L("the week before") : L("the %@ days before", count)
    }

    /// What a range is compared with (2026-11-07, you asked what the 7 days were set against): the same number of days
    /// just before it, named and dated. When the range ends on today, still coming in, the day it meets is cut to the
    /// same hours (`upTo`), so this morning is set against yesterday morning, not all of yesterday. When fewer of the
    /// earlier days were copied than the range has, totals are compared a day.
    struct Against: Equatable {
        var days: [String]
        var copied: Int
        var nowCopied: Int
        var upTo: Int?

        var name: String { Ledger.beforeName(days.count) }

        /// The change from then to now, or nil with nothing to compare; a total (spend, orders, CBH) a day when the two
        /// sides have different numbers of days copied.
        func change(_ now: Double?, _ then: Double?, total: Bool = false) -> Double? {
            guard copied > 0, var now, var then else { return nil }
            if total, copied != nowCopied, nowCopied > 0 { now /= Double(nowCopied); then /= Double(copied) }
            return then == 0 ? nil : (now - then) / abs(then)
        }

        /// As Penny says it: "the week before (Oct 25 – Oct 31)", and how it was cut or scaled.
        var said: String {
            var notes = [Ledger.span(days)]
            if let upTo {
                let hour = (upTo + 1) % 24
                notes.append(L("to %@ on its last day, as far as today has come", "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")"))
            }
            if copied > 0, copied < days.count { notes.append(L("only %@ of its %@ days copied, so totals a day", copied, days.count)) }
            return "\(name) (\(notes.joined(separator: "; ")))"
        }
    }

    /// The numbers of the days before a range, as `Against` compares them: the last of them cut to the hours today has
    /// (when today, still coming in, ends the range), from its hourly copy.
    static func before(_ product: String, now: [String], before: [String], summary: Summary, clock: Date, load: (String) -> Day?) -> (numbers: Numbers, against: Against) {
        let copied = before.filter { summary.copied[$0] != nil }.count
        let nowCopied = now.filter { summary.copied[$0] != nil }.count
        var upTo: Int?
        var numbers = summary.numbers(of: product, on: before)
        if let today = now.first, let met = before.first, case .live = state(of: today, in: summary), let bounds = bounds(of: today), clock < bounds.to,
           let hour = summary.latest[today], hour < 23, let last = load(met) {
            upTo = hour
            numbers = summary.numbers(of: product, on: Array(before.dropFirst())) + last.hours.filter { $0.hour <= hour }.reduce(Numbers()) { $0 + $1.numbers }
        }
        return (numbers, Against(days: before, copied: copied, nowCopied: nowCopied, upTo: upTo))
    }

    static func plain(_ line: String) -> String {
        line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "⟦[gyr/]⟧", with: "", options: .regularExpression)
    }

    /// An hour as the dashboards write it: "11 PM-12 AM".
    static func hourName(_ hour: Int) -> String {
        let written = { (h: Int) in "\(h % 12 == 0 ? 12 : h % 12) \(h % 24 < 12 ? "AM" : "PM")" }
        return "\(written(hour))-\(written(hour + 1))"
    }

    static func money(_ value: Double) -> String { Grafana.show(value, unit: "currencyUSD", decimals: 2).full }
    static func whole(_ value: Double) -> String { Grafana.show(value, unit: "locale", decimals: 0).full }
    static func ratio(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "–" }
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0 * 100) } ?? "–" }

    /// A day's file: gzipped JSON, a tenth of the size (the ads' names repeat on every row), opened by any tool.
    static func file(_ day: String) -> String { "\(day).json.gz" }

    /// Data as a gzip file: its header, the raw deflate Foundation makes, then the CRC-32 and size gzip ends with.
    static func gzip(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var file = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
        file += deflated
        for value in [crc32(data), UInt32(truncatingIfNeeded: data.count)] { withUnsafeBytes(of: value.littleEndian) { file += $0 } }
        return file
    }

    /// A gzip file Penny wrote (no name or extra fields in its header) back to its data.
    static func gunzip(_ file: Data) throws -> Data {
        guard file.count >= 18, file[file.startIndex] == 0x1f, file[file.startIndex + 1] == 0x8b, file[file.startIndex + 3] == 0 else { throw CocoaError(.fileReadCorruptFile) }
        return try (file.subdata(in: file.startIndex + 10 ..< file.endIndex - 8) as NSData).decompressed(using: .zlib) as Data
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 }
        }
        return ~crc
    }

    static let encoder: JSONEncoder = { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .sortedKeys; return encoder }()
    static let decoder: JSONDecoder = { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }()
}

/// Keeps Penny's copy up to date while the app is open and you are signed in: every half hour, the days not yet copied
/// or not yet settled, newest first, one day at a time. Grafana answering nothing for a day already copied leaves
/// the copy as it was.
@MainActor
final class PennyLedger: ObservableObject {
    @Published private(set) var summary: Ledger.Summary
    /// The day being copied now.
    @Published private(set) var copying: String?
    @Published private(set) var failure: String?
    /// When the copy runs again by itself.
    @Published private(set) var next: Date?
    /// Days you picked that are older than the copy keeps: copied once, and kept.
    private var asked: Set<String> = []
    var onSignedOut: (() -> Void)?
    private var loop: Task<Void, Never>?

    nonisolated static var folder: URL { Studio.folder.appendingPathComponent("penny/history", isDirectory: true) }
    private static var summaryFile: URL { folder.appendingPathComponent("summary.json") }

    init() {
        summary = (try? Data(contentsOf: Self.summaryFile)).flatMap { try? Ledger.decoder.decode(Ledger.Summary.self, from: $0) } ?? Ledger.Summary()
    }

    /// The products copied, most spent over the days first.
    func products(on days: [String]) -> [(name: String, numbers: Ledger.Numbers)] {
        summary.products.keys.map { ($0, summary.numbers(of: $0, on: days)) }
            .filter { $0.1.spent > 0 || $0.1.orders > 0 }
            .sorted { ($0.1.spent, $1.0) > ($1.1.spent, $0.0) }
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                self?.next = Date().addingTimeInterval(30 * 60)
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil; copying = nil; next = nil }

    /// What the product keeps over the days, from its CBH; the usual 1.8× line when none is copied for them.
    func profit(of product: String, on days: [String]) -> Ledger.Profit {
        Ledger.Profit(summary.margin(of: product, on: days).margin) ?? .usual
    }

    /// Days you picked: the ones not yet copied are copied now, newest first.
    func ask(for days: [String]) {
        let missing = days.filter { summary.copied[$0] == nil }
        guard !missing.isEmpty else { return }
        asked.formUnion(missing)
        Task { await sync() }
    }

    /// Copies what is still wanted, now: the days the copy keeps, then the ones you picked.
    func sync() async {
        guard copying == nil else { return }
        failure = nil
        var tried: Set<String> = []
        func next() -> String? {
            (Ledger.wanted(now: Date(), summary: summary) + asked.filter { summary.copied[$0] == nil }.sorted(by: >)).first { !tried.contains($0) }
        }
        while loop != nil, !Task.isCancelled, let day = next() {
            tried.insert(day)
            copying = day
            do {
                try await copy(day)
            } catch Grafana.Failure.signedOut {
                copying = nil; stop(); onSignedOut?(); return
            } catch {
                failure = L("Could not copy %@: %@", day, PennyDesk.describe(error))
                break
            }
        }
        // CBH after the ads, in its own requests: a day it fails for keeps the ads' copy and is tried again next time.
        var priced: Set<String> = []
        while failure == nil, loop != nil, !Task.isCancelled,
              let day = (Ledger.wanted(now: Date(), copied: summary.margined) + asked.filter { summary.margined[$0] == nil }.sorted(by: >)).first(where: { !priced.contains($0) }) {
            priced.insert(day)
            copying = day
            do {
                try await copyMargins(day)
            } catch Grafana.Failure.signedOut {
                copying = nil; stop(); onSignedOut?(); return
            } catch {
                failure = L("Could not read CBH for %@: %@", day, PennyDesk.describe(error))
            }
        }
        copying = nil
    }

    /// One day's CBH by product. An empty answer for a day that had some leaves it as it was.
    func copyMargins(_ day: String) async throws {
        guard let bounds = Ledger.bounds(of: day) else { return }
        let frames = try await PennyBoard.run(Ledger.marginTargets, panel: Ledger.source, variables: [], dates: bounds, sources: [Ledger.source], points: 1000)
        let margins = Ledger.margins(from: frames)
        let had = summary.margins.contains { $0.value[day] != nil }
        if !margins.isEmpty || !had {
            for product in summary.margins.keys where margins[product] == nil { summary.margins[product]?[day] = nil }
            for (product, margin) in margins { summary.margins[product, default: [:]][day] = margin }
        }
        summary.margined[day] = Date()
        saveSummary()
    }

    /// One day from Grafana, written by product.
    func copy(_ day: String) async throws {
        guard let bounds = Ledger.bounds(of: day) else { return }
        let frames = try await PennyBoard.run(Ledger.targets, panel: Ledger.source, variables: [], dates: bounds, sources: [Ledger.source], points: 1000)
        let copied = Date()
        let products = Ledger.products(from: frames, day: day, copied: copied)
        let had = summary.products.filter { $0.value[day] != nil }.map(\.key)
        // Grafana no longer has a day this copy keeps: the copy stays as it was.
        if products.isEmpty && !had.isEmpty { summary.copied[day] = copied; saveSummary(); return }
        let folder = Self.folder
        try await Task.detached {
            for (product, numbers) in products {
                let place = folder.appendingPathComponent(Ledger.folder(of: product), isDirectory: true)
                try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
                try Ledger.gzip(Ledger.encoder.encode(numbers)).write(to: place.appendingPathComponent(Ledger.file(day)), options: .atomic)
            }
            for product in had where products[product] == nil {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(Ledger.folder(of: product)).appendingPathComponent(Ledger.file(day)))
            }
        }.value
        for product in had where products[product] == nil { summary.products[product]?[day] = nil }
        for (product, numbers) in products { summary.products[product, default: [:]][day] = numbers.numbers }
        summary.copied[day] = copied
        summary.latest[day] = Ledger.latest(products)
        saveSummary()
    }

    private func saveSummary() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? Ledger.encoder.encode(summary).write(to: Self.summaryFile, options: .atomic)
    }

    /// A product's days, as copied.
    nonisolated static func days(of product: String, _ days: [String]) -> [Ledger.Day] {
        let place = folder.appendingPathComponent(Ledger.folder(of: product), isDirectory: true)
        return days.compactMap { day in
            (try? Data(contentsOf: place.appendingPathComponent(Ledger.file(day)))).flatMap { try? Ledger.decoder.decode(Ledger.Day.self, from: Ledger.gunzip($0)) }
        }
    }
}
