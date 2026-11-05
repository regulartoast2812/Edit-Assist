import Foundation

/// A dashboard as Penny draws it, read from Grafana's own dashboard JSON: its filters (template variables), its rows and
/// panels on the 24-column grid, each panel's queries run the way Grafana runs them (the filters written in here, the
/// SQL macros like $__timeFilter left to Grafana), the panel's transformations, and how its fields are written and
/// coloured. Only what the company's dashboards use is followed (2026-11-05).
extension Grafana {
    // MARK: Data sources

    /// A data source: dashboards name them by uid, older panels by name.
    struct Source: Equatable { var uid: String; var type: String; var name = ""; var isDefault = false }

    static func sources(from data: Data) -> [Source] {
        ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []).compactMap { item in
            guard let uid = item["uid"] as? String else { return nil }
            return Source(uid: uid, type: item["type"] as? String ?? "", name: item["name"] as? String ?? "", isDefault: item["isDefault"] as? Bool ?? false)
        }
    }

    static func source(_ value: Any?) -> Source? {
        if let object = value as? [String: Any] { return Source(uid: object["uid"] as? String ?? "", type: object["type"] as? String ?? "") }
        if let name = value as? String, !name.isEmpty { return Source(uid: "", type: "", name: name) }
        return nil
    }

    /// Sources a panel names but that hold no data of their own: mixed, another panel's, Grafana's test data.
    static let unrunnable: Set<String> = ["-- Mixed --", "-- Dashboard --", "-- Grafana --", "grafana"]

    /// The source a reference means: by uid, by name, a filter holding either, or the default one.
    static func resolve(_ reference: Source?, variables: [Variable], sources: [Source]) -> Source? {
        guard var reference else { return sources.first(where: \.isDefault) }
        reference.uid = interpolate(reference.uid, with: variables, raw: true)
        reference.name = interpolate(reference.name, with: variables, raw: true)
        if !reference.uid.isEmpty {
            return sources.first { $0.uid == reference.uid || $0.name == reference.uid } ?? (reference.type.isEmpty ? nil : reference)
        }
        if !reference.name.isEmpty { return sources.first { $0.name == reference.name || $0.uid == reference.name } }
        if !reference.type.isEmpty { return sources.first { $0.type == reference.type && $0.isDefault } ?? sources.first { $0.type == reference.type } }
        return sources.first(where: \.isDefault)
    }

    // MARK: Answers

    enum Cell: Equatable {
        case number(Double), text(String), none
        var number: Double? { if case .number(let value) = self { return value }; return nil }
    }

    struct Column: Equatable {
        var name: String
        /// Grafana's field type: number, string, time or boolean. Times are milliseconds.
        var kind: String
        var cells: [Cell]
        var isNumber: Bool { kind == "number" }
        var isTime: Bool { kind == "time" }
        func at(_ row: Int) -> Cell { cells.indices.contains(row) ? cells[row] : .none }
    }

    struct Frame: Equatable {
        var columns: [Column]
        var rows: Int { columns.map(\.cells.count).max() ?? 0 }
        func column(_ name: String) -> Column? { columns.first { $0.name == name } }
    }

    /// One query's answer: its frames, or why Grafana could not run it.
    struct Reply: Equatable { var frames: [Frame]; var error: String? }

    /// An /api/ds/query answer, by query (refId). NaN and infinities come as entities beside the values, as Grafana sends them.
    static func replies(from data: Data) -> [String: Reply] {
        let results = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["results"] as? [String: Any] ?? [:]
        return results.reduce(into: [:]) { replies, item in
            guard let result = item.value as? [String: Any] else { return }
            let error = (result["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            replies[item.key] = Reply(frames: (result["frames"] as? [[String: Any]] ?? []).map(frame), error: error)
        }
    }

    static func frame(_ object: [String: Any]) -> Frame {
        let fields = (object["schema"] as? [String: Any])?["fields"] as? [[String: Any]] ?? []
        let data = object["data"] as? [String: Any]
        let values = data?["values"] as? [[Any]] ?? []
        let entities = data?["entities"] as? [Any] ?? []
        return Frame(columns: fields.enumerated().map { index, field in
            var cells = (index < values.count ? values[index] : []).map(cell)
            if index < entities.count, let special = entities[index] as? [String: Any] {
                for (key, value) in [("NaN", Double.nan), ("Inf", .infinity), ("NegInf", -.infinity)] {
                    for row in special[key] as? [Int] ?? [] where cells.indices.contains(row) { cells[row] = .number(value) }
                }
            }
            var name = field["name"] as? String ?? ""
            if let shown = (field["config"] as? [String: Any])?["displayNameFromDS"] as? String, !shown.isEmpty { name = shown }
            if let labels = field["labels"] as? [String: String], !labels.isEmpty {
                let written = labels.keys.sorted().compactMap { labels[$0] }.joined(separator: " ")
                name = ["", "value", "Value"].contains(name) ? written : "\(name) \(written)"
            }
            var kind = field["type"] as? String ?? ""
            if kind.isEmpty { kind = cells.contains { $0.number != nil } ? "number" : "string" }
            return Column(name: name, kind: kind, cells: cells)
        })
    }

    static func cell(_ value: Any) -> Cell {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .text(number.boolValue ? "true" : "false") }
            return .number(number.doubleValue)
        }
        if let text = value as? String { return .text(text) }
        return .none
    }

    static func text(of cell: Cell) -> String? {
        switch cell {
        case .text(let text): return text
        case .number(let number): return plain(number)
        case .none: return nil
        }
    }

    static func plain(_ number: Double) -> String {
        number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
    }

    // MARK: Dashboards

    /// A filter: Grafana's template variable, the values it may take and the ones chosen.
    struct Variable: Identifiable, Equatable {
        static let all = "$__all"
        var id: String { name }
        var name: String
        var label = ""
        var type = "query"
        /// 0 shown, 1 shown without its label, 2 hidden.
        var hide = 0
        var multi = false
        var includeAll = false
        var allValue: String?
        var query = ""
        var source: Source?
        var regex = ""
        var sort = 0
        /// 1 read when the dashboard opens, 2 also when the time changes.
        var refresh = 1
        var current: [String] = []
        var options: [String] = []

        var isAll: Bool { current.contains(Self.all) }
        /// The values the filter stands for: those chosen, or for All every value it has.
        var values: [String] { isAll ? options : current }

        /// What the filter puts in a query, written the way Grafana writes it for SQL: each value quoted, several joined by
        /// commas; All as the filter's own all-value, unquoted, when it has one.
        func written(_ format: String?) -> String {
            if isAll, let allValue { return allValue }
            let values = self.values
            func quoted(_ quote: String, _ escape: String) -> String {
                values.map { quote + $0.replacingOccurrences(of: quote, with: escape) + quote }.joined(separator: ",")
            }
            switch format {
            case nil, "sqlstring"?:
                if format == nil, !multi, !includeAll { return (values.first ?? "").replacingOccurrences(of: "'", with: "''") }
                return values.isEmpty ? "''" : quoted("'", "''")
            case "singlequote"?: return quoted("'", "\\'")
            case "doublequote"?: return quoted("\"", "\\\"")
            case "pipe"?: return values.joined(separator: "|")
            case "text"?: return values.joined(separator: " + ")
            case "regex"?:
                let escaped = values.map(NSRegularExpression.escapedPattern)
                return escaped.count == 1 ? escaped[0] : "(" + escaped.joined(separator: "|") + ")"
            default: return values.joined(separator: ",")
            }
        }

        /// The filter as its chip reads: All, one value, or several joined by +.
        var shown: String { isAll ? L("All") : current.isEmpty ? L("None") : current.joined(separator: " + ") }

        /// The values Grafana now has for it; what was chosen stays chosen where it still exists.
        mutating func settle(_ values: [String]) {
            options = values
            guard !isAll else { return }
            let kept = current.filter(values.contains)
            current = !kept.isEmpty ? kept : includeAll ? [Self.all] : Array(values.prefix(1))
        }
    }

    /// A panel: where it sits on the 24-column grid and the settings it is drawn with, as the dashboard has them.
    final class Tile: Identifiable {
        let id: Int
        let type: String
        let title: String
        let note: String
        let x: Int, y: Int, w: Int, h: Int
        let source: Source?
        let targets: [[String: Any]]
        let options: [String: Any]
        let fieldConfig: [String: Any]
        let steps: [[String: Any]]
        let maxDataPoints: Int?

        init(_ panel: [String: Any]) {
            id = (panel["id"] as? NSNumber)?.intValue ?? 0
            type = panel["type"] as? String ?? ""
            title = (panel["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            note = panel["description"] as? String ?? ""
            let spot = panel["gridPos"] as? [String: Any] ?? [:]
            func number(_ key: String, _ fallback: Int) -> Int { (spot[key] as? NSNumber)?.intValue ?? fallback }
            x = max(0, min(23, number("x", 0)))
            w = max(1, min(24 - x, number("w", 12)))
            y = max(0, number("y", 0))
            h = max(1, number("h", 8))
            source = Grafana.source(panel["datasource"])
            targets = (panel["targets"] as? [[String: Any]] ?? []).filter { $0["hide"] as? Bool != true }
            options = panel["options"] as? [String: Any] ?? [:]
            fieldConfig = panel["fieldConfig"] as? [String: Any] ?? [:]
            steps = panel["transformations"] as? [[String: Any]] ?? []
            maxDataPoints = (panel["maxDataPoints"] as? NSNumber)?.intValue
        }

        /// Panels that run queries; text and the clock draw on their own.
        var queries: Bool { !["text", "grafana-clock-panel", "row", "news", "dashlist", "alertlist", "annolist"].contains(type) && !targets.isEmpty }
    }

    /// A dashboard row and its panels; the panels above the first row are a section without a title.
    struct Section: Identifiable {
        let id: Int
        let title: String
        let collapsed: Bool
        var tiles: [Tile]
    }

    struct Dashboard: Identifiable {
        var id: String { uid }
        let uid: String
        let title: String
        let folder: String
        let version: Int
        /// The dashboard's own timezone; "" leaves it to your preferences.
        let timezone: String
        let span: Span
        let variables: [Variable]
        let sections: [Section]
    }

    static func dashboard(from data: Data) -> Dashboard? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let dashboard = object["dashboard"] as? [String: Any], let uid = dashboard["uid"] as? String else { return nil }
        let time = dashboard["time"] as? [String: Any]
        let variables = ((dashboard["templating"] as? [String: Any])?["list"] as? [[String: Any]] ?? []).compactMap(variable)
        func spot(_ panel: [String: Any]) -> (Int, Int) {
            let grid = panel["gridPos"] as? [String: Any]
            return ((grid?["y"] as? NSNumber)?.intValue ?? 0, (grid?["x"] as? NSNumber)?.intValue ?? 0)
        }
        var sections = [Section(id: -1, title: "", collapsed: false, tiles: [])]
        for panel in (dashboard["panels"] as? [[String: Any]] ?? []).sorted(by: { spot($0) < spot($1) }) {
            if panel["type"] as? String == "row" {
                sections.append(Section(id: (panel["id"] as? NSNumber)?.intValue ?? -2 - sections.count, title: panel["title"] as? String ?? "",
                                        collapsed: panel["collapsed"] as? Bool ?? false,
                                        tiles: (panel["panels"] as? [[String: Any]] ?? []).sorted { spot($0) < spot($1) }.map(Tile.init)))
            } else {
                sections[sections.count - 1].tiles.append(Tile(panel))
            }
        }
        return Dashboard(uid: uid, title: dashboard["title"] as? String ?? uid, folder: (object["meta"] as? [String: Any])?["folderTitle"] as? String ?? "",
                         version: (dashboard["version"] as? NSNumber)?.intValue ?? 0, timezone: dashboard["timezone"] as? String ?? "",
                         span: Span(from: time?["from"] as? String ?? "now-6h", to: time?["to"] as? String ?? "now"),
                         variables: variables, sections: sections.filter { $0.id != -1 || !$0.tiles.isEmpty })
    }

    static func variable(_ object: [String: Any]) -> Variable? {
        guard let name = object["name"] as? String, !name.isEmpty else { return nil }
        var variable = Variable(name: name)
        variable.label = object["label"] as? String ?? ""
        variable.type = object["type"] as? String ?? "query"
        variable.hide = (object["hide"] as? NSNumber)?.intValue ?? 0
        variable.multi = object["multi"] as? Bool ?? false
        variable.includeAll = object["includeAll"] as? Bool ?? false
        variable.allValue = (object["allValue"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let query = object["query"] as? String { variable.query = query }
        else if let query = object["query"] as? [String: Any] { variable.query = query["rawSql"] as? String ?? query["query"] as? String ?? "" }
        if variable.query.isEmpty { variable.query = object["definition"] as? String ?? "" }
        variable.source = source(object["datasource"])
        variable.regex = object["regex"] as? String ?? ""
        variable.sort = (object["sort"] as? NSNumber)?.intValue ?? 0
        variable.refresh = (object["refresh"] as? NSNumber)?.intValue ?? 1
        let current = (object["current"] as? [String: Any])?["value"]
        variable.current = (current as? [String]) ?? (current as? String).map { [$0] } ?? []
        switch variable.type {
        case "custom": variable.options = customOptions(variable.query)
        case "constant", "textbox": variable.options = [variable.query]
        default: variable.options = (object["options"] as? [[String: Any]] ?? []).compactMap { $0["value"] as? String }.filter { $0 != Variable.all }
        }
        if variable.current.isEmpty || variable.current == [""] && variable.type != "textbox" {
            variable.current = variable.includeAll ? [Variable.all] : Array(variable.options.prefix(1))
        }
        return variable
    }

    /// A custom filter's values: split on commas not escaped with a backslash; "text : value" keeps the value.
    static func customOptions(_ query: String) -> [String] {
        var items: [String] = [], item = "", escaped = false
        for character in query {
            if escaped { item.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "," { items.append(item); item = "" }
            else { item.append(character) }
        }
        items.append(item)
        return items.map { part -> String in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let split = trimmed.range(of: " : ") { return String(trimmed[split.upperBound...]).trimmingCharacters(in: .whitespaces) }
            return trimmed
        }.filter { !$0.isEmpty }
    }

    private static let variablePattern = try! NSRegularExpression(pattern: #"\$(\w+)|\[\[(\w+?)(?::(\w+))?\]\]|\$\{(\w+)(?:\.([^:^\}]+))?(?::([^\}]+))?\}"#)

    /// The filters written into a query ($name, ${name}, ${name:format}, [[name]]). `display` writes them as their chips
    /// read, for titles; `raw` joins values with commas, for data source names. Anything that isn't a filter, Grafana's
    /// own macros included, is left for Grafana.
    static func interpolate(_ text: String, with variables: [Variable], display: Bool = false, raw: Bool = false) -> String {
        guard text.contains("$") || text.contains("[[") else { return text }
        let source = text as NSString
        var written = "", last = 0
        for match in variablePattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            func group(_ index: Int) -> String? { match.range(at: index).location == NSNotFound ? nil : source.substring(with: match.range(at: index)) }
            let name = group(1) ?? group(2) ?? group(4) ?? ""
            written += source.substring(with: NSRange(location: last, length: match.range.location - last))
            if let variable = variables.first(where: { $0.name == name }) {
                written += display ? variable.shown : variable.written(raw ? "csv" : group(3) ?? group(6))
            } else {
                written += source.substring(with: match.range)
            }
            last = match.range.location + match.range.length
        }
        return written + source.substring(from: last)
    }

    /// Whether a query uses a filter, so changing that filter means reading the query's values again.
    static func mentions(_ text: String, _ name: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return text.range(of: #"\$"# + escaped + #"(?![A-Za-z0-9_])|\$\{"# + escaped + #"[}:.]|\[\["# + escaped + #"[\]:]"#, options: .regularExpression) != nil
    }

    // MARK: Time

    /// The timezone Grafana counts "today" in and writes times in: the dashboard's own, else yours, your team's, then the
    /// company's (Grafana's preferences), else this Mac's. The company works in Alaska time (GMT-8/-9), so a day on this
    /// Mac's Vietnam clock would start 15 or 16 hours late (2026-11-05). Set when a dashboard is drawn.
    nonisolated(unsafe) static var zone = TimeZone.current

    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = zone
        return calendar
    }

    /// The first timezone set among the choices, as Grafana names them: an IANA name, "utc", or "browser" for this Mac's.
    static func zone(_ choices: [String?]) -> TimeZone {
        for choice in choices {
            guard let name = choice?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            switch name.lowercased() {
            case "browser": return .current
            case "utc": return TimeZone(identifier: "UTC") ?? .current
            default: return TimeZone(identifier: name) ?? .current
            }
        }
        return .current
    }

    /// The timezone a preferences answer (yours, a team's, the company's) sets, or nil.
    static func preferredZone(from data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["timezone"] as? String
    }

    /// A time range written the way Grafana writes it: now, now-7d, now/d (the day's start, or its end for `to`), now-1M/M.
    struct Span: Equatable {
        var from: String
        var to: String
        func dates(now: Date = Date(), calendar: Calendar = Grafana.calendar) -> (from: Date, to: Date) {
            (Grafana.moment(from, end: false, now: now, calendar: calendar) ?? now.addingTimeInterval(-86_400),
             Grafana.moment(to, end: true, now: now, calendar: calendar) ?? now)
        }
    }

    /// Grafana's quick ranges, the ones a campaign sheet needs.
    static let spans: [(name: String, span: Span)] = [
        ("Today", Span(from: "now/d", to: "now/d")), ("Today so far", Span(from: "now/d", to: "now")),
        ("Yesterday", Span(from: "now-1d/d", to: "now-1d/d")), ("Last 7 days", Span(from: "now-7d", to: "now")),
        ("This week", Span(from: "now/w", to: "now/w")), ("This month", Span(from: "now/M", to: "now/M")),
        ("This month so far", Span(from: "now/M", to: "now")), ("Last month", Span(from: "now-1M/M", to: "now-1M/M")),
        ("Last 30 days", Span(from: "now-30d", to: "now")), ("Last 90 days", Span(from: "now-90d", to: "now")),
    ]

    static func name(of span: Span) -> String {
        spans.first { $0.span == span }.map { L($0.name) } ?? "\(span.from) → \(span.to)"
    }

    static func moment(_ text: String, end: Bool, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard text.hasPrefix("now") else {
            if let milliseconds = Double(text) { return Date(timeIntervalSince1970: milliseconds / 1000) }
            return ISO8601DateFormatter().date(from: text)
        }
        let units: [Character: Calendar.Component] = ["s": .second, "m": .minute, "h": .hour, "d": .day, "w": .weekOfYear, "M": .month, "y": .year]
        var date = now
        var rest = text.dropFirst(3)
        while let sign = rest.first {
            rest = rest.dropFirst()
            if sign == "/" {
                guard let letter = rest.first, let unit = units[letter], let interval = calendar.dateInterval(of: unit, for: date) else { return nil }
                rest = rest.dropFirst()
                date = end ? interval.end.addingTimeInterval(-0.001) : interval.start
            } else if sign == "+" || sign == "-" {
                let digits = rest.prefix { $0.isNumber }
                rest = rest.dropFirst(digits.count)
                guard let letter = rest.first, let unit = units[letter],
                      let moved = calendar.date(byAdding: unit, value: (Int(digits) ?? 1) * (sign == "-" ? -1 : 1), to: date) else { return nil }
                rest = rest.dropFirst()
                date = moved
            } else {
                return nil
            }
        }
        return date
    }

    /// The step Grafana would group a panel's points by ($__interval): the span over the points it draws, rounded.
    static func interval(span milliseconds: Double, points: Int) -> Int {
        let steps: [Double] = [1, 5, 10, 15, 30, 60, 300, 600, 900, 1800, 3600, 10_800, 21_600, 43_200, 86_400, 604_800, 2_592_000].map { $0 * 1000 }
        let wanted = milliseconds / Double(max(points, 1))
        return Int(steps.first { $0 >= wanted } ?? steps[steps.count - 1])
    }

    // MARK: Filter values

    /// A filter query's answer as its values: __value when it has one, otherwise every value in every column, then the
    /// filter's regex (its first group when it has one), duplicates dropped, sorted as the filter says.
    static func values(from frames: [Frame], regex: String, sort: Int) -> [String] {
        var values: [String] = []
        for frame in frames {
            if let column = frame.column("__value") { values += column.cells.compactMap(text) }
            else { for column in frame.columns { values += column.cells.compactMap(text) } }
        }
        if !regex.isEmpty, let pattern = jsRegex(regex) {
            values = values.compactMap { value in
                let whole = NSRange(location: 0, length: (value as NSString).length)
                guard let match = pattern.firstMatch(in: value, range: whole) else { return nil }
                return match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound ? (value as NSString).substring(with: match.range(at: 1)) : value
            }
        }
        var seen = Set<String>()
        values = values.filter { seen.insert($0).inserted }
        switch sort {
        case 1: values.sort()
        case 2: values.sort(by: >)
        case 3: values.sort { (Double($0) ?? 0) < (Double($1) ?? 0) }
        case 4: values.sort { (Double($0) ?? 0) > (Double($1) ?? 0) }
        case 5: values.sort { $0.lowercased() < $1.lowercased() }
        case 6: values.sort { $0.lowercased() > $1.lowercased() }
        case 7: values.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        case 8: values.sort { $0.localizedStandardCompare($1) == .orderedDescending }
        default: break
        }
        return values
    }

    /// A pattern written the way Grafana takes them: "/pattern/flags" or a bare pattern.
    static func jsRegex(_ text: String) -> NSRegularExpression? {
        if text.hasPrefix("/"), let end = text.lastIndex(of: "/"), end > text.startIndex {
            let pattern = String(text[text.index(after: text.startIndex) ..< end])
            return try? NSRegularExpression(pattern: pattern, options: text[text.index(after: end)...].contains("i") ? .caseInsensitive : [])
        }
        return try? NSRegularExpression(pattern: text)
    }

    static func finds(_ pattern: NSRegularExpression, in text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    // MARK: Transformations

    /// The panel's transformations, the ones the company's dashboards use: calculateField (binary, reduceRow, index),
    /// organize and concatenate. Any other is passed over and the frames go on as they were.
    static func transform(_ frames: [Frame], _ steps: [[String: Any]]) -> [Frame] {
        steps.reduce(frames) { frames, step in
            guard step["disabled"] as? Bool != true else { return frames }
            let options = step["options"] as? [String: Any] ?? [:]
            switch step["id"] as? String {
            case "calculateField":
                // Grafana first joins time series by their time, so a field from one query can be worked with another's.
                var frames = frames
                if frames.count > 1, options["timeSeries"] as? Bool != false, frames.allSatisfy({ $0.columns.contains(where: \.isTime) }) {
                    frames = [joinByTime(frames)]
                }
                return frames.map { calculate($0, options) }
            case "organize": return frames.map { organize($0, options) }
            case "concatenate": return [Frame(columns: frames.flatMap(\.columns))]
            default: return frames
            }
        }
    }

    static func joinByTime(_ frames: [Frame]) -> Frame {
        var times: [Double] = [], seen = Set<Double>()
        for frame in frames {
            for cell in frame.columns.first(where: \.isTime)?.cells ?? [] { if let time = cell.number, seen.insert(time).inserted { times.append(time) } }
        }
        times.sort()
        var columns = [Column(name: frames.first?.columns.first(where: \.isTime)?.name ?? "Time", kind: "time", cells: times.map { .number($0) })]
        for frame in frames {
            guard let time = frame.columns.first(where: \.isTime) else { continue }
            var row: [Double: Int] = [:]
            for (index, cell) in time.cells.enumerated() { if let value = cell.number, row[value] == nil { row[value] = index } }
            for column in frame.columns where !column.isTime {
                columns.append(Column(name: column.name, kind: column.kind, cells: times.map { row[$0].map(column.at) ?? .none }))
            }
        }
        return Frame(columns: columns)
    }

    static func calculate(_ frame: Frame, _ options: [String: Any]) -> Frame {
        let rows = frame.rows
        var name = options["alias"] as? String ?? ""
        let cells: [Cell]
        switch options["mode"] as? String ?? "reduceRow" {
        case "binary":
            let binary = options["binary"] as? [String: Any] ?? [:]
            let sign = binary["operator"] as? String ?? "+"
            func operand(_ value: Any?) -> String? {
                if let text = value as? String { return text }
                guard let object = value as? [String: Any] else { return nil }
                return object["fixed"] as? String ?? (object["matcher"] as? [String: Any])?["options"] as? String
            }
            // A missing value counts as 0 and a field that isn't there leaves the frame as it was, as in Grafana.
            func series(_ text: String?) -> [Double]? {
                guard let text else { return nil }
                if let column = frame.column(text) { return (0 ..< rows).map { column.at($0).number ?? 0 } }
                return Double(text).map { Array(repeating: $0, count: rows) }
            }
            guard let left = operand(binary["left"]), let right = operand(binary["right"]),
                  let lefts = series(left), let rights = series(right) else { return frame }
            cells = zip(lefts, rights).map { a, b in
                switch sign {
                case "-": return .number(a - b)
                case "*": return .number(a * b)
                case "/": return .number(a / b)
                case "%": return .number(a.truncatingRemainder(dividingBy: b))
                case "^": return .number(pow(a, b))
                default: return .number(a + b)
                }
            }
            if name.isEmpty { name = "\(left) \(sign) \(right)" }
        case "reduceRow":
            let reduce = options["reduce"] as? [String: Any] ?? [:]
            let reducer = reduce["reducer"] as? String ?? "sum"
            let include = reduce["include"] as? [String] ?? []
            let columns = frame.columns.filter { $0.isNumber && (include.isEmpty || include.contains($0.name)) }
            cells = (0 ..< rows).map { row in Grafana.reduce(columns.map { $0.at(row) }, reducer).map(Cell.number) ?? .none }
            if name.isEmpty { name = ["sum": "Total", "mean": "Mean", "max": "Max", "min": "Min", "first": "First", "last": "Last", "count": "Count"][reducer] ?? reducer }
        case "index":
            cells = (0 ..< rows).map { .number(Double($0)) }
            if name.isEmpty { name = "Row" }
        default:
            return frame
        }
        let column = Column(name: name, kind: "number", cells: cells)
        if options["replaceFields"] as? Bool == true { return Frame(columns: frame.columns.filter(\.isTime) + [column]) }
        return Frame(columns: frame.columns + [column])
    }

    static func organize(_ frame: Frame, _ options: [String: Any]) -> Frame {
        let exclude = options["excludeByName"] as? [String: Bool] ?? [:]
        let include = (options["includeByName"] as? [String: Bool] ?? [:]).filter(\.value)
        let index = options["indexByName"] as? [String: Int] ?? [:]
        let rename = options["renameByName"] as? [String: String] ?? [:]
        let kept = frame.columns.filter { exclude[$0.name] != true && (include.isEmpty || include[$0.name] == true) }
        let ordered = kept.enumerated().sorted { (index[$0.element.name] ?? Int.max, $0.offset) < (index[$1.element.name] ?? Int.max, $1.offset) }
        return Frame(columns: ordered.map { item in
            var column = item.element
            if let name = rename[column.name], !name.isEmpty { column.name = name }
            return column
        })
    }

    static func reduce(_ cells: [Cell], _ calculation: String) -> Double? {
        let numbers = cells.compactMap(\.number).filter { !$0.isNaN }
        switch calculation {
        case "sum": return cells.isEmpty ? nil : numbers.reduce(0, +)
        case "mean": return numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
        case "max": return numbers.max()
        case "min": return numbers.min()
        case "last": return cells.last?.number
        case "first": return cells.first?.number
        case "firstNotNull": return numbers.first
        case "count": return Double(cells.count)
        case "range": return numbers.max().flatMap { high in numbers.min().map { high - $0 } }
        case "diff": return numbers.last.flatMap { last in numbers.first.map { last - $0 } }
        case "distinctCount": return Double(Set(numbers).count)
        case "median":
            let sorted = numbers.sorted()
            return sorted.isEmpty ? nil : sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        default: return numbers.last
        }
    }

    // MARK: How fields are written

    struct Step: Equatable { var value: Double?; var color: String }

    /// How a field is drawn, from the panel's field defaults and then each override that matches it, later ones winning.
    struct Look: Equatable {
        var displayName: String?
        var unit: String?
        var decimals: Int?
        var min: Double?
        var max: Double?
        var steps: [Step] = []
        var percentageSteps = false
        var colorMode: String?
        var fixedColor: String?
        /// The table cell: auto, color-text, color-background.
        var cell: String?
        var width: Double?
        var align: String?
        var hidden = false
        var noValue: String?

        mutating func apply(_ id: String, _ value: Any?) {
            switch id {
            case "displayName", "displayNameFromDS": displayName = (value as? String).flatMap { $0.isEmpty ? nil : $0 }
            case "unit": unit = value as? String
            case "decimals": decimals = (value as? NSNumber)?.intValue
            case "min": min = (value as? NSNumber)?.doubleValue
            case "max": max = (value as? NSNumber)?.doubleValue
            case "noValue": noValue = value as? String
            case "thresholds":
                let thresholds = value as? [String: Any] ?? [:]
                percentageSteps = thresholds["mode"] as? String == "percentage"
                steps = (thresholds["steps"] as? [[String: Any]] ?? []).map { Step(value: ($0["value"] as? NSNumber)?.doubleValue, color: $0["color"] as? String ?? "") }
            case "color":
                let color = value as? [String: Any] ?? [:]
                colorMode = color["mode"] as? String
                fixedColor = color["fixedColor"] as? String
            case "custom.width": width = (value as? NSNumber)?.doubleValue
            case "custom.align": align = value as? String
            case "custom.hidden": hidden = value as? Bool ?? false
            case "custom.cellOptions": cell = (value as? [String: Any])?["type"] as? String
            case "custom.displayMode": cell = value as? String
            default: break
            }
        }

        /// Grafana's colour for a value: the fixed colour, or the threshold step it reaches (the base one for text).
        func color(for value: Double?) -> String? {
            if colorMode == "fixed" || colorMode == "shades" { return fixedColor }
            guard let base = steps.first else { return nil }
            guard var value, !value.isNaN else { return base.color }
            if percentageSteps {
                let low = min ?? 0, high = max ?? 100
                value = high == low ? 0 : (value - low) / (high - low) * 100
            }
            var color = base.color
            for step in steps.dropFirst() {
                guard let at = step.value, value >= at else { break }
                color = step.color
            }
            return color
        }
    }

    static func look(for column: Column, in fieldConfig: [String: Any]) -> Look {
        var look = Look()
        let defaults = fieldConfig["defaults"] as? [String: Any] ?? [:]
        for (key, value) in defaults where key != "custom" { look.apply(key, value) }
        for (key, value) in defaults["custom"] as? [String: Any] ?? [:] { look.apply("custom." + key, value) }
        for override in fieldConfig["overrides"] as? [[String: Any]] ?? [] {
            guard let matcher = override["matcher"] as? [String: Any], matches(matcher, column) else { continue }
            for property in override["properties"] as? [[String: Any]] ?? [] {
                if let id = property["id"] as? String { look.apply(id, property["value"]) }
            }
        }
        return look
    }

    static func matches(_ matcher: [String: Any], _ column: Column) -> Bool {
        let options = matcher["options"]
        switch matcher["id"] as? String {
        case "byName": return options as? String == column.name
        case "byNames": return ((options as? [String: Any])?["names"] as? [String] ?? []).contains(column.name)
        case "byRegexp": return (options as? String).flatMap(jsRegex).map { finds($0, in: column.name) } ?? false
        case "byType": return options as? String == column.kind
        default: return false
        }
    }

    /// A value written for a unit as Grafana writes it, in parts: the suffix (K, %) is drawn smaller.
    struct Shown: Equatable {
        var prefix = ""
        var text: String
        var suffix = ""
        var full: String { prefix + text + suffix }
    }

    private static let currencies = ["currencyUSD": "$", "currencyEUR": "€", "currencyGBP": "£", "currencyJPY": "¥", "currencyVND": "₫"]

    static func show(_ value: Double, unit: String?, decimals: Int?) -> Shown {
        if value.isNaN { return Shown(text: "–") }
        let unit = unit ?? "none"
        if value.isInfinite { return Shown(text: value > 0 ? "∞" : "-∞", suffix: ["percent", "percentunit"].contains(unit) ? "%" : "") }
        switch unit {
        case "percent": return Shown(text: fixed(value, decimals), suffix: "%")
        case "percentunit": return Shown(text: fixed(value * 100, decimals), suffix: "%")
        case "short": return scaled(value, decimals, ["", " K", " Mil", " Bil", " Tri", " Quadr"])
        case "locale":
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = decimals ?? 3
            return Shown(text: formatter.string(from: NSNumber(value: value)) ?? fixed(value, decimals))
        default:
            if let symbol = currencies[unit] ?? (unit.hasPrefix("currency:") ? String(unit.dropFirst(9)) : nil) {
                var shown = scaled(abs(value), decimals, ["", "K", "M", "B", "T"])
                shown.prefix = (value < 0 ? "-" : "") + symbol
                return shown
            }
            if unit.hasPrefix("prefix:") { return Shown(prefix: String(unit.dropFirst(7)), text: fixed(value, decimals)) }
            if unit.hasPrefix("suffix:") { return Shown(text: fixed(value, decimals), suffix: String(unit.dropFirst(7))) }
            return Shown(text: fixed(value, decimals))
        }
    }

    static func scaled(_ value: Double, _ decimals: Int?, _ units: [String]) -> Shown {
        var size = value, step = 0
        while abs(size) >= 1000, step < units.count - 1 { size /= 1000; step += 1 }
        return Shown(text: fixed(size, decimals), suffix: units[step])
    }

    /// Grafana's toFixed: the decimals asked for, or as many as the value's size calls for.
    static func fixed(_ value: Double, _ decimals: Int?) -> String {
        let places = Swift.max(0, Swift.min(decimals ?? autoDecimals(value), 12))
        let text = String(format: "%.\(places)f", value)
        return text.hasPrefix("-") && (Double(text) ?? 0) == 0 ? String(text.dropFirst()) : text
    }

    static func autoDecimals(_ value: Double) -> Int {
        guard value.isFinite, value != 0, value.truncatingRemainder(dividingBy: 1) != 0 else { return 0 }
        let size = abs(value)
        var decimals = -Int(floor(log10(size))) + 1
        if size / pow(10, Double(-decimals)) > 2.25 { decimals += 1 }
        return Swift.max(0, decimals)
    }

    /// A cell as the table writes it: numbers by the field's unit, times by its time unit or as dates, text as it is.
    static func written(_ cell: Cell, in column: Column, look: Look) -> String {
        switch cell {
        case .none: return look.noValue ?? ""
        case .text(let text): return text
        case .number(let number):
            if column.isTime { return time(number, unit: look.unit) }
            return show(number, unit: look.unit, decimals: look.decimals).full
        }
    }

    static func time(_ milliseconds: Double, unit: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        switch unit {
        case let unit? where unit.hasPrefix("time:"): formatter.dateFormat = dateFormat(String(unit.dropFirst(5)))
        case "dateTimeAsUS"?: formatter.dateFormat = "MM/dd/yyyy h:mm:ss a"
        default:
            let midnight = calendar.startOfDay(for: date) == date
            formatter.dateFormat = midnight ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm:ss"
        }
        return formatter.string(from: date)
    }

    /// A moment.js date format (Grafana's) as a DateFormatter one.
    static func dateFormat(_ moment: String) -> String {
        [("dddd", "EEEE"), ("ddd", "EEE"), ("YYYY", "yyyy"), ("YY", "yy"), ("DD", "dd"), ("Do", "d"), ("D", "d"), ("A", "a")]
            .reduce(moment) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// The values a stat, bar gauge or pie shows: each numeric field reduced by the panel's calculation, or with "all
    /// values" each row, named by its text fields.
    struct Figure: Identifiable {
        let id: Int
        let name: String
        let number: Double?
        let look: Look
        var shown: Shown { number.map { Grafana.show($0, unit: look.unit, decimals: look.decimals) } ?? Shown(text: look.noValue ?? L("No data")) }
    }

    static func figures(of tile: Tile, _ frames: [Frame]) -> [Figure] {
        let reduce = tile.options["reduceOptions"] as? [String: Any] ?? [:]
        let calculation = (reduce["calcs"] as? [String])?.first ?? "lastNotNull"
        let pattern = reduce["fields"] as? String ?? ""
        let regex = pattern.hasPrefix("/") ? jsRegex(pattern) : nil
        let everyRow = reduce["values"] as? Bool ?? false
        let limit = (reduce["limit"] as? NSNumber)?.intValue ?? (everyRow ? 5000 : Int.max)
        var figures: [Figure] = []
        for frame in frames {
            let picked = frame.columns.filter { column in
                guard column.isNumber else { return false }
                if pattern.isEmpty || pattern == "/.*/" { return true }
                return regex.map { finds($0, in: column.name) } ?? (column.name == pattern)
            }.map { ($0, look(for: $0, in: tile.fieldConfig)) }
            if everyRow {
                let labels = frame.columns.filter { !$0.isNumber && !$0.isTime }
                for row in 0 ..< Swift.min(frame.rows, limit) {
                    let label = labels.compactMap { text(of: $0.at(row)) }.joined(separator: " ")
                    for (column, look) in picked {
                        let field = look.displayName ?? column.name
                        let name = picked.count > 1 ? [label, field].filter { !$0.isEmpty }.joined(separator: " ") : label.isEmpty ? field : label
                        figures.append(Figure(id: figures.count, name: name, number: column.at(row).number, look: look))
                    }
                }
            } else {
                for (column, look) in picked.prefix(limit) {
                    figures.append(Figure(id: figures.count, name: look.displayName ?? column.name, number: Grafana.reduce(column.cells, calculation), look: look))
                }
            }
        }
        return figures
    }

    /// A text panel's HTML as plain lines, list items as bullets.
    static func plainText(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(of: "<li[^>]*>", with: "\n• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<br\\s*/?>|</(p|div|h\\d|li|ul|ol)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: "[ \\t]*\\n\\s*", with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One dashboard on Penny's page: its filters, the time it covers and each panel's answer. Filters are read first (a
/// filter whose query uses another waits for it), then the panels of the open rows, six at a time; a closed row's
/// panels are read when it is opened, as in Grafana. Your filters and time are kept per dashboard.
@MainActor
final class PennyBoard: ObservableObject {
    enum Outcome { case frames([Grafana.Frame]), failed(String), signedOut }

    let dashboard: Grafana.Dashboard
    private let sources: [Grafana.Source]
    @Published private(set) var variables: [Grafana.Variable]
    @Published private(set) var span: Grafana.Span
    @Published private(set) var outcomes: [Int: Outcome] = [:]
    @Published private(set) var reading: Set<Int> = [] { didSet { onBusy?(busy) } }
    @Published private(set) var settling = false { didSet { onBusy?(busy) } }
    @Published private(set) var open: Set<Int>
    @Published private(set) var trouble: String?
    @Published private(set) var updated: Date?
    var onBusy: ((Bool) -> Void)?
    var onSignedOut: (() -> Void)?
    private var generation = 0

    var busy: Bool { settling || !reading.isEmpty }

    init(dashboard: Grafana.Dashboard, sources: [Grafana.Source]) {
        self.dashboard = dashboard
        self.sources = sources
        let chosen = UserDefaults.standard.dictionary(forKey: Self.key("filters", dashboard.uid)) as? [String: [String]] ?? [:]
        variables = dashboard.variables.map { variable in
            var variable = variable
            if let values = chosen[variable.name], !values.isEmpty { variable.current = values }
            return variable
        }
        let saved = UserDefaults.standard.string(forKey: Self.key("span", dashboard.uid))?.components(separatedBy: "|")
        span = saved?.count == 2 ? Grafana.Span(from: saved![0], to: saved![1]) : dashboard.span
        open = Set(dashboard.sections.filter { !$0.collapsed }.map(\.id))
    }

    static func key(_ what: String, _ uid: String) -> String { "penny.\(what).\(uid)" }

    /// Reads the filters named (nil: all of them, the first time), then every panel in an open row.
    func load(settle names: Set<String>? = nil) {
        generation += 1
        let generation = self.generation
        reading = []
        trouble = nil
        settling = true
        Task {
            await settle(names, generation)
            guard generation == self.generation else { return }
            settling = false
            await read(dashboard.sections.filter { open.contains($0.id) }.flatMap(\.tiles), generation)
            guard generation == self.generation else { return }
            updated = Date()
            saveSummary()
        }
    }

    func choose(_ values: [String], for name: String) {
        guard let index = variables.firstIndex(where: { $0.name == name }), variables[index].current != values else { return }
        variables[index].current = values
        save()
        load(settle: dependents(of: name))
    }

    func choose(span: Grafana.Span) {
        guard span != self.span else { return }
        self.span = span
        save()
        load(settle: Set(variables.filter { $0.type == "query" && ($0.refresh == 2 || $0.query.contains("$__time")) }.map(\.name)))
    }

    func toggle(_ section: Int) {
        if open.remove(section) != nil { return }
        open.insert(section)
        guard !settling, let tiles = dashboard.sections.first(where: { $0.id == section })?.tiles else { return }
        let generation = self.generation
        Task { await read(tiles.filter { outcomes[$0.id] == nil }, generation) }
    }

    /// The dashboard (or one panel of it) in the browser, with your filters and time.
    func link(panel: Int? = nil) -> URL {
        guard var parts = URLComponents(url: Grafana.base.appendingPathComponent("d/\(dashboard.uid)"), resolvingAgainstBaseURL: false) else { return Grafana.base }
        var items = [URLQueryItem(name: "from", value: span.from), URLQueryItem(name: "to", value: span.to)]
        for variable in variables { items += variable.current.map { URLQueryItem(name: "var-\(variable.name)", value: $0) } }
        if let panel { items.append(URLQueryItem(name: "viewPanel", value: String(panel))) }
        parts.queryItems = items
        return parts.url ?? Grafana.base
    }

    /// The filters whose values come from a query that uses this one, and those that use them.
    func dependents(of name: String) -> Set<String> {
        var found = Set<String>(), waiting = [name]
        while let next = waiting.popLast() {
            for variable in variables where variable.type == "query" && !found.contains(variable.name) && Grafana.mentions(variable.query, next) {
                found.insert(variable.name)
                waiting.append(variable.name)
            }
        }
        return found
    }

    private func settle(_ names: Set<String>?, _ generation: Int) async {
        let dates = span.dates()
        for name in variables.filter({ $0.type == "query" && (names?.contains($0.name) ?? true) }).map(\.name) {
            guard generation == self.generation, let variable = variables.first(where: { $0.name == name }) else { return }
            do {
                let values = try await Self.options(for: variable, variables: variables, dates: dates, sources: sources)
                guard generation == self.generation, let index = variables.firstIndex(where: { $0.name == name }) else { return }
                variables[index].settle(values)
            } catch Grafana.Failure.signedOut {
                onSignedOut?()
                return
            } catch {
                trouble = L("The %@ filter could not be read: %@", variable.label.isEmpty ? name : variable.label, PennyDesk.describe(error))
            }
        }
    }

    private func read(_ tiles: [Grafana.Tile], _ generation: Int) async {
        let tiles = tiles.filter(\.queries)
        guard !tiles.isEmpty else { return }
        reading.formUnion(tiles.map(\.id))
        let variables = self.variables, sources = self.sources, dates = span.dates()
        await withTaskGroup(of: (Int, Outcome).self) { group in
            var next = 0
            func start(_ group: inout TaskGroup<(Int, Outcome)>) {
                guard next < tiles.count else { return }
                let tile = tiles[next]
                next += 1
                group.addTask { (tile.id, await Self.outcome(of: tile, variables: variables, dates: dates, sources: sources)) }
            }
            for _ in 0 ..< 6 { start(&group) }
            while let result = await group.next() {
                let (id, outcome) = result
                if generation == self.generation {
                    outcomes[id] = outcome
                    reading.remove(id)
                    if case .signedOut = outcome { onSignedOut?() }
                }
                start(&group)
            }
        }
    }

    nonisolated static func outcome(of tile: Grafana.Tile, variables: [Grafana.Variable], dates: (from: Date, to: Date), sources: [Grafana.Source]) async -> Outcome {
        do {
            let frames = try await run(tile.targets, panel: tile.source, variables: variables, dates: dates, sources: sources, points: tile.maxDataPoints ?? 1000)
            return .frames(Grafana.transform(frames, tile.steps))
        } catch Grafana.Failure.signedOut {
            return .signedOut
        } catch {
            return .failed(PennyDesk.describe(error))
        }
    }

    nonisolated static func options(for variable: Grafana.Variable, variables: [Grafana.Variable], dates: (from: Date, to: Date), sources: [Grafana.Source]) async throws -> [String] {
        // Filter queries Penny can run are SQL ones; any other keeps the values the dashboard was saved with.
        guard let source = Grafana.resolve(variable.source, variables: variables, sources: sources),
              ["sql", "postgres", "mysql"].contains(where: source.type.contains) else { return variable.options }
        let target: [String: Any] = ["refId": "A", "rawSql": variable.query, "format": "table", "rawQuery": true, "editorMode": "code",
                                     "datasource": ["uid": source.uid, "type": source.type]]
        let frames = try await run([target], panel: nil, variables: variables, dates: dates, sources: sources, points: 1000)
        return Grafana.values(from: frames, regex: variable.regex, sort: variable.sort)
    }

    /// Runs a panel's queries through Grafana (/api/ds/query), one request per data source, the filters written in.
    nonisolated static func run(_ targets: [[String: Any]], panel: Grafana.Source?, variables: [Grafana.Variable], dates: (from: Date, to: Date),
                                sources: [Grafana.Source], points: Int) async throws -> [Grafana.Frame] {
        let from = Int64(dates.from.timeIntervalSince1970 * 1000), to = Int64(dates.to.timeIntervalSince1970 * 1000)
        let interval = Grafana.interval(span: Double(to - from), points: points)
        var groups: [(uid: String, queries: [[String: Any]])] = []
        for (index, target) in targets.enumerated() {
            var reference = Grafana.source(target["datasource"]) ?? panel
            if let wanted = reference, Grafana.unrunnable.contains(wanted.uid) || wanted.type == "datasource" {
                guard Grafana.source(target["datasource"]) == nil, wanted.uid == "-- Mixed --" else { continue }
                reference = nil
            }
            guard let source = Grafana.resolve(reference, variables: variables, sources: sources) else { continue }
            var query = target
            query["refId"] = target["refId"] as? String ?? String(UnicodeScalar(UInt8(65 + index % 26)))
            query["datasource"] = ["uid": source.uid, "type": source.type]
            for key in ["rawSql", "query", "expr"] { if let text = target[key] as? String { query[key] = Grafana.interpolate(text, with: variables) } }
            query["intervalMs"] = interval
            query["maxDataPoints"] = points
            if let at = groups.firstIndex(where: { $0.uid == source.uid }) { groups[at].queries.append(query) } else { groups.append((source.uid, [query])) }
        }
        var frames: [Grafana.Frame] = []
        for group in groups {
            let body = try JSONSerialization.data(withJSONObject: ["queries": group.queries, "from": String(from), "to": String(to)])
            let replies = Grafana.replies(from: try await Grafana.request("api/ds/query", body: body))
            for query in group.queries {
                guard let reply = replies[query["refId"] as? String ?? ""] else { continue }
                if let error = reply.error { throw Grafana.Failure.refused(0, error) }
                frames += reply.frames
            }
        }
        return frames
    }

    private func save() {
        UserDefaults.standard.set(Dictionary(variables.map { ($0.name, $0.current) }, uniquingKeysWith: { a, _ in a }), forKey: Self.key("filters", dashboard.uid))
        UserDefaults.standard.set(span.from + "|" + span.to, forKey: Self.key("span", dashboard.uid))
    }

    /// What each panel last answered, written beside the dashboards (penny/answers), so a panel that reads wrong can be
    /// checked against what Grafana sent: its columns and rows, a stat's values, or the error.
    private func saveSummary() {
        var panels: [[String: Any]] = []
        for tile in dashboard.sections.flatMap(\.tiles) {
            guard let outcome = outcomes[tile.id] else { continue }
            var entry: [String: Any] = ["id": tile.id, "title": tile.title, "type": tile.type]
            switch outcome {
            case .frames(let frames):
                entry["frames"] = frames.map { ["rows": $0.rows, "columns": $0.columns.map { "\($0.name): \($0.kind)" }] }
                if ["stat", "gauge"].contains(tile.type) { entry["shown"] = Grafana.figures(of: tile, frames).map(\.shown.full) }
            case .failed(let reason): entry["error"] = reason
            case .signedOut: entry["error"] = "signed out"
            }
            panels.append(entry)
        }
        let folder = PennyDesk.folder.appendingPathComponent("answers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let summary: [String: Any] = ["read": ISO8601DateFormatter().string(from: Date()), "span": [span.from, span.to], "panels": panels]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("\(dashboard.uid).json"))
        }
    }
}
