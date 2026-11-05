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

    /// What has been copied: when each day was, and each product's totals by day (penny/history/summary.json).
    struct Summary: Equatable, Codable {
        var copied: [String: Date] = [:]
        var products: [String: [String: Numbers]] = [:]

        func numbers(of product: String, on days: [String]) -> Numbers {
            days.reduce(Numbers()) { $0 + (products[product]?[$1] ?? Numbers()) }
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

    /// The days still to copy, newest first: never copied, or copied before they had settled.
    static func wanted(now: Date, summary: Summary, kept: Int = kept) -> [String] {
        days(back: kept, from: now).filter { day in
            guard let copied = summary.copied[day] else { return true }
            guard let end = bounds(of: day)?.to else { return false }
            return copied < end.addingTimeInterval(settles) && now >= copied.addingTimeInterval(60)
        }
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

    // MARK: Report

    /// Penny's read of a product over the days: how it did against the days before, which creatives sell and which
    /// only spend, and the hours that sell. Each finding a line, money in dollars, hours in Alaska time.
    static func report(_ days: [Day], before: Numbers? = nil) -> [String] {
        let total = total(days)
        guard total.spent > 0 || total.orders > 0 else { return [L("Nothing ran in these days.")] }
        var lines: [String] = []
        var first = L("Spent **%@**, **%@** orders, **%@** revenue: ROAS **%@**", money(total.spent), whole(total.orders), money(total.revenue), ratio(total.roas))
        if let cpp = total.cpp { first += L(", %@ per order", money(cpp)) }
        lines.append(first)
        if let before, before.spent > 0, let now = total.roas, let then = before.roas {
            let change = then > 0 ? (now - then) / then : 0
            lines.append(abs(change) < 0.05 ? L("ROAS about the same as the days before (%@)", ratio(then))
                         : L(change > 0 ? "ROAS **up %@** on the days before (%@)" : "ROAS **down %@** on the days before (%@)", percent(abs(change)), ratio(then)))
        }
        // Creatives worth naming spent at least 2% of the product's spend; one with no orders, twice what an order costs.
        let all = creatives(days), floor = max(total.spent * 0.02, 5), roas = total.roas ?? 0
        let creatives = all.filter { $0.numbers.spent >= floor }
        let selling = creatives.filter { $0.numbers.orders >= 2 }.sorted { ($0.numbers.roas ?? 0) > ($1.numbers.roas ?? 0) }
        for line in selling.prefix(3) where (line.numbers.roas ?? 0) >= roas {
            var text = L("Sells: **%@**: ROAS %@ on %@, %@ orders", line.name, ratio(line.numbers.roas), money(line.numbers.spent), whole(line.numbers.orders))
            let hours = line.bestHours()
            if !hours.isEmpty { text += L(", most orders at %@", hours.map(hourName).joined(separator: ", ")) }
            lines.append(text)
        }
        for line in creatives.filter({ $0.numbers.orders > 0 && ($0.numbers.roas ?? 0) < roas * 0.7 }).prefix(3) {
            lines.append(L("Below the product: **%@**: ROAS %@ on %@", line.name, ratio(line.numbers.roas), money(line.numbers.spent)))
        }
        let waste = max(2 * (total.cpp ?? 10), 20)
        for line in all.filter({ $0.numbers.orders == 0 && $0.numbers.spent >= waste }).prefix(3) {
            lines.append(L("No orders: **%@** spent %@", line.name, money(line.numbers.spent)))
        }
        // Hours worth naming: at least 3% of the spend.
        let hours = hours(days).enumerated().filter { $0.element.spent >= total.spent * 0.03 && $0.element.spent > 0 }
        let ranked = hours.sorted { ($0.element.roas ?? 0) > ($1.element.roas ?? 0) }
        if ranked.count >= 4 {
            let best = ranked.prefix(3).map { L("%@ (ROAS %@)", hourName($0.offset), ratio($0.element.roas)) }
            let worst = ranked.suffix(3).reversed().map { L("%@ (ROAS %@)", hourName($0.offset), ratio($0.element.roas)) }
            lines.append(L("Best hours: %@", best.joined(separator: ", ")))
            lines.append(L("Weakest hours: %@", worst.joined(separator: ", ")))
        }
        return lines
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
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil; copying = nil }

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
        copying = nil
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
