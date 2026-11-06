import AppKit
import Foundation

/// Don and Pix working together (2026-11-04): Don reads a script into a brief; Pix takes his jobs from it. Only the CTA
/// is queued by itself; anything else Pix or Don suggests waits for you to queue it. Kept beside projects.json, one
/// file per script (`don/<script>.json`, `pix/<script>.json`), never in projects.json.
@MainActor
final class Studio {
    let don = DonReader()
    let pix = PixDesk()
    init() {
        don.onBrief = { [pix] script, brief in pix.briefed(brief, script: script) }
    }

    nonisolated static var folder: URL {
        ProcessInfo.processInfo.environment["EDIT_ASSIST_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Edit Assist", isDirectory: true)
    }
}

/// Don's brief for one script: the vibe, voice, music and graphic style the others work to, the CTA, and the lines the
/// script gives no media for, which would need AI video.
struct DonBrief: Codable, Equatable {
    struct Shot: Codable, Equatable, Identifiable {
        var id = UUID()
        var line: String
        var idea: String
    }
    var product: String
    var vibe: String
    var voice: String
    var music: String
    var graphicStyle: String
    /// The script's call-to-action words, and how the end card should look.
    var cta: String
    var ctaLook: String
    var videoShots: [Shot]
    /// The script's words when Don read it, to tell when it changed after.
    var from: String
    var project: String
    var script: String
    /// The script sheet's version it was read from; nil for the script pasted in the project.
    var sheet: String?
    var read = Date()

    init(product: String = "", vibe: String = "", voice: String = "", music: String = "", graphicStyle: String = "", cta: String = "",
         ctaLook: String = "", videoShots: [Shot] = [], from: String, project: String, script: String) {
        self.product = product; self.vibe = vibe; self.voice = voice; self.music = music; self.graphicStyle = graphicStyle
        self.cta = cta; self.ctaLook = ctaLook; self.videoShots = videoShots; self.from = from; self.project = project; self.script = script
    }

    /// From Don's answer (see `DonReader.schema`).
    init(answer: [String: Any], from: String, project: String, script: String) throws {
        let text = { (key: String) in (answer[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !text("vibe").isEmpty || !text("graphicStyle").isEmpty else { throw AssistError.message(L("Don's answer had no brief in it.")) }
        let shots = (answer["videoShots"] as? [[String: Any]] ?? []).compactMap { shot -> Shot? in
            let line = (shot["line"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : Shot(line: line, idea: (shot["idea"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        self.init(product: text("product"), vibe: text("vibe"), voice: text("voice"), music: text("music"), graphicStyle: text("graphicStyle"),
                  cta: text("cta"), ctaLook: text("ctaLook"), videoShots: shots, from: from, project: project, script: script)
    }

    /// The script's lines as Don reads them: their words, without the **bold** marks.
    static func lines(_ script: String) -> [String] {
        ((try? ScriptParser.parse(script)) ?? []).map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static func words(_ script: String) -> String { lines(script).joined(separator: "\n") }
    func outdated(by script: String) -> Bool { Self.words(script) != from }

    static func file(_ script: UUID) -> URL { Studio.folder.appendingPathComponent("don/\(script.uuidString).json") }
    static func load(_ script: UUID) -> DonBrief? {
        (try? Data(contentsOf: file(script))).flatMap { try? JSONDecoder().decode(DonBrief.self, from: $0) }
    }
}

/// The team's script sheet in Google Sheets (2026-11-05): one tab of ad versions, a row per scene with its voice-over,
/// effect, cut and source footage. Read with the Claude CLI's Google Sheets connector (`SheetsConnector`), only read;
/// kept per project in `don/sheet-<project>.json`, never in projects.json. A line with no source needs AI video.
struct DonSheet: Codable, Equatable {
    struct Line: Codable, Equatable {
        var scene = "", text = "", effect = "", cut = "", source = "", notes = ""
    }
    struct Version: Codable, Equatable, Identifiable {
        var name: String
        var lines: [Line]
        var id: String { name }
        /// Its words, as a brief's `from`.
        var words: String { lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n") }
        var unfilmed: Int { lines.filter { $0.source.isEmpty }.count }
    }
    var link: String
    var title = ""
    var tab = ""
    var versions: [Version] = []
    var read: Date?
    /// The version each of the project's scripts is read from, by script id; "" for the script pasted in the project.
    var picks: [String: String] = [:]

    static func file(_ project: UUID) -> URL { Studio.folder.appendingPathComponent("don/sheet-\(project.uuidString).json") }
    static func load(_ project: UUID) -> DonSheet? {
        (try? Data(contentsOf: file(project))).flatMap { try? JSONDecoder().decode(DonSheet.self, from: $0) }
    }
    func save(_ project: UUID) {
        try? FileManager.default.createDirectory(at: Self.file(project).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.file(project), options: .atomic)
    }

    /// The version a script is read from: the one you picked; else the one named as the script's tab is ("v1.1");
    /// else, with nothing pasted in the project, the first.
    func version(for script: ScriptTab) -> Version? {
        if let pick = picks[script.id.uuidString] { return versions.first { $0.name == pick } }
        let name = Self.fold(script.name)
        if let named = versions.first(where: { Self.fold($0.name).split(separator: " ").first.map(String.init) == name }) { return named }
        return DonBrief.lines(script.script).isEmpty ? versions.first : nil
    }

    /// The spreadsheet's id and the tab (gid) in a Google Sheets link; a bare id works too.
    static func address(_ link: String) -> (id: String, tab: Int?)? {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = link.firstMatch(of: #/spreadsheets/d/([A-Za-z0-9_-]{20,})/#) else {
            return link.wholeMatch(of: #/[A-Za-z0-9_-]{30,}/#) != nil ? (link, nil) : nil
        }
        return (String(match.1), link.firstMatch(of: #/[#&?]gid=(\d+)/#).flatMap { Int($0.1) })
    }

    /// Lowercase, without accents (Cảnh → canh), single-spaced: for reading headers and names.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).replacingOccurrences(of: "đ", with: "d")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    enum Column { case version, scene, cut, effect, text, source, notes }
    /// What a header names, in English or Vietnamese. Cut comes before source: "Khoảng cut từ source" is the cut.
    static func column(_ header: String) -> Column? {
        let h = fold(header)
        let has = { (words: [String]) in words.contains { h.contains($0) } }
        if h.isEmpty { return nil }
        if has(["version", "phien ban"]) || h == "ver" { return .version }
        if has(["canh", "scene", "shot"]) || ["#", "stt", "no", "no."].contains(h) { return .scene }
        if has(["cut", "khoang", "timecode", "thoi gian", "duration"]) || h == "time" { return .cut }
        if has(["hieu ung", "effect", "fx"]) { return .effect }
        if has(["voiceover", "voice over", "text", "script", "kich ban", "loi thoai"]) || h == "vo" { return .text }
        if has(["source", "nguon", "footage", "media", "clip"]) { return .source }
        if has(["comment", "note", "ghi chu"]) { return .notes }
        return nil
    }

    /// The versions in a tab's cells: the header row is the first of five naming a words column (Text, Voiceover,
    /// Script); a filled Version cell starts the next version; rows with neither words nor source are skipped.
    static func versions(_ rows: [[String]], tab: String) -> [Version] {
        guard let header = rows.prefix(5).firstIndex(where: { $0.contains { column($0) == .text } }) else { return [] }
        var columns: [Column: Int] = [:], notes: [Int] = []
        for (index, cell) in rows[header].enumerated() {
            guard let kind = column(cell) else { continue }
            if kind == .notes { notes.append(index) } else if columns[kind] == nil { columns[kind] = index }
        }
        let value = { (row: [String], index: Int?) -> String in
            index.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var versions: [Version] = []
        for row in rows.dropFirst(header + 1) {
            var name = value(row, columns[.version]).split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !name.isEmpty {
                let base = name
                var number = 2
                while versions.contains(where: { $0.name == name }) { name = "\(base) (\(number))"; number += 1 }
                versions.append(Version(name: name, lines: []))
            }
            let line = Line(scene: value(row, columns[.scene]), text: value(row, columns[.text]), effect: value(row, columns[.effect]),
                            cut: value(row, columns[.cut]), source: value(row, columns[.source]),
                            notes: notes.map { value(row, $0) }.filter { !$0.isEmpty }.joined(separator: " · "))
            guard !line.text.isEmpty || !line.source.isEmpty else { continue }
            if versions.isEmpty { versions.append(Version(name: tab, lines: [])) }
            versions[versions.count - 1].lines.append(line)
        }
        return versions.filter { !$0.words.isEmpty }
    }

    /// A sheet line as Don is told it: its words, then what the sheet gives it.
    static func described(_ line: Line) -> String {
        let flat = { (text: String) in text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " / ") }
        var said = line.text.isEmpty ? "(no words)" : flat(line.text)
        said += line.source.isEmpty ? " [no media]" : " [media: \(flat(line.source))]"
        if !line.effect.isEmpty { said += " [effect: \(flat(line.effect))]" }
        if !line.notes.isEmpty { said += " [editor notes: \(flat(line.notes))]" }
        return said
    }
}

/// Reads one tab of a Google Sheet with the Claude CLI's Google Sheets connector (the one connected to your Claude
/// account): get_spreadsheet and get_values, both read only, and nothing else is allowed. The cells are taken from the
/// connector's own answer in the CLI's output, never retyped by the model. Codex has no Google connector, so a sheet is
/// always read with Claude, whichever brain Don thinks with.
enum SheetsConnector {
    static let reads = ["mcp__claude_ai_Google_Sheets__get_spreadsheet", "mcp__claude_ai_Google_Sheets__get_values"]
    static let writes = ["append_values", "batch_clear_values", "copy_sheet_to_another_spreadsheet", "insert_dimension",
                         "update_formulas", "update_spreadsheet", "update_values"].map { "mcp__claude_ai_Google_Sheets__" + $0 }

    static func read(id: String, tab: Int?) async throws -> (title: String, tab: String, rows: [[String]]) {
        guard let executable = CLIProvider.claude.executable else {
            throw AssistError.message(L("Reading a sheet needs the Claude CLI, signed in to the Claude account that has Google Sheets connected."))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("edit-assist-sheet-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let prompt = """
        Spreadsheet \(id). Call get_spreadsheet once with fields ["properties.title","sheets.properties.sheetId","sheets.properties.title"]. \
        Then call get_values once, with range set to the title of \(tab.map { "the tab whose sheetId is \($0)" } ?? "the first tab") in single quotes. \
        Call nothing else and change nothing. Then answer only: done.
        """
        // The CLI waits for its connectors only when told to; without it the Sheets tools may not be there yet.
        let request = CLIRequest(executable: executable, arguments: ["--print", "--model", "haiku", "--tools", "", "--allowedTools", reads.joined(separator: ","),
                                                                     "--disallowedTools", writes.joined(separator: ","), "--no-session-persistence",
                                                                     "--output-format", "stream-json", "--verbose"],
                                 input: Data(prompt.utf8), environment: ["MCP_CONNECTION_NONBLOCKING": "false", "ENABLE_CLAUDEAI_MCP_SERVERS": "true"])
        return try cells(in: try await CLIProcess.run(request, directory: directory, timeout: 120))
    }

    /// The tab's title and cells in the CLI's stream: from get_values' own result, with the file's title from get_spreadsheet.
    static func cells(in stream: Data) throws -> (title: String, tab: String, rows: [[String]]) {
        var tools: [String: String] = [:], title = "", values: [String: Any]?, refused: String?, connected: Bool?
        for line in stream.split(separator: 10) {
            guard let event = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
            if event["type"] as? String == "system", event["subtype"] as? String == "init", let servers = event["mcp_servers"] as? [[String: Any]] {
                connected = servers.contains { $0["name"] as? String == "claude.ai Google Sheets" && $0["status"] as? String == "connected" }
            }
            for part in ((event["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? [] {
                if part["type"] as? String == "tool_use", let id = part["id"] as? String { tools[id] = part["name"] as? String }
                guard part["type"] as? String == "tool_result", let tool = (part["tool_use_id"] as? String).flatMap({ tools[$0] }) else { continue }
                let text = part["content"] as? String ?? (part["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
                if part["is_error"] as? Bool == true { refused = text; continue }
                let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
                if tool.hasSuffix("get_spreadsheet") { title = (object?["properties"] as? [String: Any])?["title"] as? String ?? title }
                if tool.hasSuffix("get_values"), let object { values = object }
            }
        }
        guard let values else {
            if connected == false {
                throw AssistError.message(L("Google Sheets isn't connected to your Claude account. Connect it in claude.ai → Settings → Connectors, then read again."))
            }
            throw AssistError.message(refused.map { L("Google Sheets: %@", $0) } ?? L("Claude didn't read the sheet. Read again."))
        }
        let range = values["range"] as? String ?? ""
        var tab = range.range(of: "!", options: .backwards).map { String(range[..<$0.lowerBound]) } ?? range
        if tab.count >= 2, tab.hasPrefix("'"), tab.hasSuffix("'") { tab = String(tab.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return (title, tab, (values["values"] as? [[Any]] ?? []).map { $0.map { "\($0)" } })
    }
}

/// Don reading the open script into a brief, with the helper brain (Claude by default). Only when you ask: a read is
/// one CLI call of a minute or two. The script is the one pasted in the project, or the version of the project's script
/// sheet it is read from.
@MainActor
final class DonReader: ObservableObject {
    @Published private(set) var brief: DonBrief?
    /// The script being read.
    @Published private(set) var reading: UUID?
    @Published private(set) var failure: String?
    /// The open project's script sheet, its reading and why one failed.
    @Published private(set) var sheet: DonSheet?
    @Published private(set) var sheetReading = false
    @Published private(set) var sheetFailure: String?
    private var script: UUID?
    private var project: UUID?
    var onBrief: ((UUID, DonBrief) -> Void)?

    func load(script id: UUID) {
        guard script != id else { return }
        script = id; failure = nil
        brief = DonBrief.load(id)
    }

    func load(project id: UUID) {
        guard project != id else { return }
        project = id; sheetFailure = nil
        sheet = DonSheet.load(id)
    }

    /// What Don reads for the project's open script: the sheet's version it is read from, or the pasted script.
    func source(_ project: Project) -> (lines: [String], words: String, version: String?) {
        if self.project == project.id, let version = sheet?.version(for: project.openScript) {
            return (version.lines.map(DonSheet.described), version.words, version.name)
        }
        let lines = DonBrief.lines(project.script)
        return (lines, lines.joined(separator: "\n"), nil)
    }

    func outdated(_ project: Project) -> Bool { brief.map { $0.from != source(project).words } ?? false }

    /// Reads the sheet's tab (the one in the link) with Claude's Google Sheets connector; your picks stay for the same sheet.
    func readSheet(_ link: String, project id: UUID) {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sheetReading else { return }
        guard let address = DonSheet.address(link) else {
            sheetFailure = L("That isn't a Google Sheets link. Copy it from the address bar with the script's tab open.")
            return
        }
        sheetReading = true; sheetFailure = nil
        Task {
            do {
                let read = try await SheetsConnector.read(id: address.id, tab: address.tab)
                let versions = DonSheet.versions(read.rows, tab: read.tab)
                guard !versions.isEmpty else {
                    throw AssistError.message(L("Don found no script in “%@”: it needs a column named Text, Voiceover or Script.", read.tab))
                }
                var sheet = DonSheet.load(id).flatMap { DonSheet.address($0.link)?.id == address.id ? $0 : nil } ?? DonSheet(link: link)
                sheet.link = link; sheet.title = read.title; sheet.tab = read.tab; sheet.versions = versions; sheet.read = Date()
                sheet.save(id)
                if project == id { self.sheet = sheet }
            } catch {
                if project == id { sheetFailure = error.localizedDescription }
            }
            sheetReading = false
        }
    }

    /// Reads a script from the sheet's version named, or from the pasted script when nil.
    func pick(_ version: String?, script id: UUID) {
        guard var sheet, let project else { return }
        sheet.picks[id.uuidString] = version ?? ""
        sheet.save(project)
        self.sheet = sheet
    }

    func read(_ project: Project) {
        load(project: project.id)
        let id = project.openScript.id, name = project.openScript.name, source = source(project)
        guard reading == nil, !source.lines.isEmpty else { return }
        reading = id
        if script == id { failure = nil }
        Task {
            do {
                let answer = try await HelperBrain.ask(Self.prompt(source.lines, project: project.name, sheet: source.version != nil), schema: Self.schema, timeout: 240)
                var brief = try DonBrief(answer: answer, from: source.words, project: project.name, script: name)
                brief.sheet = source.version
                try? FileManager.default.createDirectory(at: DonBrief.file(id).deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(brief).write(to: DonBrief.file(id), options: .atomic)
                if script == id { self.brief = brief }
                onBrief?(id, brief)
            } catch {
                if script == id { failure = error.localizedDescription }
            }
            reading = nil
        }
    }

    static var schema: [String: Any] {
        let s = HelperBrain.string
        return HelperBrain.object(["product": s, "vibe": s, "voice": s, "music": s, "graphicStyle": s, "cta": s, "ctaLook": s,
                                   "videoShots": ["type": "array", "items": HelperBrain.object(["line": s, "idea": s])]])
    }

    static func prompt(_ lines: [String], project: String, sheet: Bool = false) -> String {
        """
        You are Don, an ads expert for short direct-response video ads that sell e-commerce products (TikTok, Reels, Shorts). \
        Read this ad script and brief the other helpers: Tala (voice-over and music), Pix (the CTA end card and pictures) and Kino (AI video clips).
        - product: what is sold, in a few words, as the script names it ("" if it never does).
        - vibe: the ad's feel, in one line.
        - voice: who should voice it and how (age, tone, pace).
        - music: genre, tempo and energy.
        - graphicStyle: the look of on-screen graphics and the CTA (palette, type, shapes), suited to the product and its buyers.
        - cta: the script's call-to-action words as written, usually its last line ("" if it has none).
        - ctaLook: what the CTA end card must say (offer, urgency, button words) and how it should look. Never invent an offer, price or percentage the script does not make.
        - videoShots: the lines whose picture the script does not give (it names no footage, UGC clip, screen recording, product shot or other media for them) \
        and that would need an AI-generated video clip; for each, the line as written and a short idea for the clip. Empty when the script gives media for every line.
        Write in English, plainly and briefly. Project: \(project).\(sheet ? """

        This script comes from the team's script sheet. After each line, in brackets: the footage the sheet gives it ([media: …]) \
        or [no media], and its effect and the editor's notes when there are any. videoShots are exactly the [no media] lines that \
        have words, each written as the line alone, without the brackets.
        """ : "")
        The script, one line each:
        \(lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        """
    }
}

/// One of Pix's jobs. The CTA is designed by the helper brain as an SVG that opens editable in Illustrator (three
/// variants, as your CTA files have them); schematics and pictures are made with GPT Image and cost OpenAI credit.
struct PixJob: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case cta, schematic, picture }
    enum State: String, Codable { case queued, needsPictures, working, done, failed }
    var id = UUID()
    var kind: Kind
    var title: String
    /// What to do, beyond what the kind does anyway: your changes, the lines a schematic is for.
    var detail: String
    /// Product pictures for it, by file name in the script's Pix folder.
    var pictures: [String] = []
    /// What was made: full paths.
    var outputs: [String] = []
    var state: State
    var note: String?
    var project: String
    var script: String
    var queued = Date()

    /// A schematic is made from product pictures, so it waits for some.
    var waitsForPictures: Bool { kind == .schematic && pictures.isEmpty }
}

/// A line in Pix's chat; his can carry jobs he proposes, each queued only when you press it.
struct PixMessage: Codable, Equatable, Identifiable {
    var id = UUID()
    var fromPix: Bool
    var text: String
    var pictures: [String] = []
    var proposals: [PixJob] = []
    /// The proposals you queued.
    var taken: [UUID] = []
    var date = Date()
}

/// A chat with Pix kept in the script's history (New chat keeps the one before), titled by your first message (2026-11-06).
struct PixChat: Codable, Equatable, Identifiable {
    var id = UUID()
    var messages: [PixMessage] = []
    var updated = Date()

    var title: String {
        let first = messages.first { !$0.fromPix && !$0.text.isEmpty }?.text ?? ""
        let line = first.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.count > 60 ? String(line.prefix(57)).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}

struct PixBoard: Codable, Equatable {
    var jobs: [PixJob] = []
    var chat: [PixMessage] = []
    /// The script's earlier chats, newest first.
    var past: [PixChat] = []
    /// The CTA words, look and style the last automatic CTA was made from: a new brief with the same ones queues none.
    var ctaFrom: String?

    init() {}

    /// Boards saved before there was a history read as they were.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobs = try container.decodeIfPresent([PixJob].self, forKey: .jobs) ?? []
        chat = try container.decodeIfPresent([PixMessage].self, forKey: .chat) ?? []
        past = try container.decodeIfPresent([PixChat].self, forKey: .past) ?? []
        ctaFrom = try container.decodeIfPresent(String.self, forKey: .ctaFrom)
    }
}

/// Pix's desk: the jobs and chat of each script, the job being made, and the OpenAI key for GPT Image.
@MainActor
final class PixDesk: ObservableObject {
    enum Key: Equatable { case none, checking, ready, failed(String) }
    @Published private(set) var board = PixBoard()
    /// The job being made, one at a time, in queue order.
    @Published private(set) var working: UUID?
    /// A chat answer on its way.
    @Published private(set) var thinking = false
    @Published private(set) var key: Key = OpenAIImages.key == nil ? .none : .checking
    @Published private(set) var imageModel: String?
    @Published var brain = HelperBrain.provider { didSet { HelperBrain.provider = brain } }
    private(set) var script: UUID?
    private var boards: [UUID: PixBoard] = [:]

    static func file(_ script: UUID) -> URL { Studio.folder.appendingPathComponent("pix/\(script.uuidString).json") }
    static func pictures(_ script: UUID) -> URL { Studio.folder.appendingPathComponent("pix/\(script.uuidString)", isDirectory: true) }
    func picture(_ name: String) -> URL? { script.map { Self.pictures($0).appendingPathComponent(name) } }

    func load(script id: UUID) {
        script = id
        board = stored(id)
        next()
    }

    private func stored(_ id: UUID) -> PixBoard {
        if let board = boards[id] { return board }
        var board = (try? Data(contentsOf: Self.file(id))).flatMap { try? JSONDecoder().decode(PixBoard.self, from: $0) } ?? PixBoard()
        // A job cut off when the app quit is not made again by itself: a picture may already have cost credit.
        for index in board.jobs.indices where board.jobs[index].state == .working {
            board.jobs[index].state = .failed; board.jobs[index].note = L("Stopped when the app quit. Press Make again to retry.")
        }
        boards[id] = board
        return board
    }

    private func change(_ id: UUID, _ edit: (inout PixBoard) -> Void) {
        var board = stored(id)
        edit(&board)
        boards[id] = board
        if script == id { self.board = board }
        try? FileManager.default.createDirectory(at: Self.file(id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(board).write(to: Self.file(id), options: .atomic)
    }

    private func change(job: UUID, in id: UUID, _ edit: (inout PixJob) -> Void) {
        change(id) { board in
            if let index = board.jobs.firstIndex(where: { $0.id == job }) { edit(&board.jobs[index]) }
        }
    }

    // MARK: Jobs

    /// Don's brief came in: the CTA is queued (unless one was made from the same words and look), and lines needing
    /// AI video bring a schematic Pix proposes and the product pictures he asks for.
    func briefed(_ brief: DonBrief, script id: UUID) {
        var said: [String] = [], proposals: [PixJob] = []
        let ctaKey = [brief.cta, brief.ctaLook, brief.graphicStyle].joined(separator: "\n")
        change(id) { board in
            if !brief.cta.isEmpty, board.ctaFrom != ctaKey {
                board.ctaFrom = ctaKey
                board.jobs.append(PixJob(kind: .cta, title: L("CTA, three variants"), detail: "", state: .queued, project: brief.project, script: brief.script))
                said.append(L("Don's brief is in, so I've queued the CTA from “%@”.", brief.cta))
            }
            if !brief.videoShots.isEmpty {
                proposals.append(PixJob(kind: .schematic, title: L("Product schematic for AI video"),
                                        detail: "For these lines, which need AI video:\n" + brief.videoShots.map { "- \($0.line)" }.joined(separator: "\n"),
                                        state: .needsPictures, project: brief.project, script: brief.script))
                said.append(L("%@ lines have no media and need AI video. A product schematic keeps the product right in every clip: queue it if you want one, and send me product pictures (front, back, sides, close-ups of the details).", brief.videoShots.count))
            }
            if !said.isEmpty { board.chat.append(PixMessage(fromPix: true, text: said.joined(separator: " "), proposals: proposals)) }
        }
        next()
    }

    /// Queues a job Pix proposed in a chat message.
    func queue(_ proposal: PixJob, from message: UUID) {
        guard let script else { return }
        change(script) { board in
            guard let index = board.chat.firstIndex(where: { $0.id == message }), !board.chat[index].taken.contains(proposal.id) else { return }
            board.chat[index].taken.append(proposal.id)
            var job = proposal
            job.id = UUID(); job.queued = Date()
            job.state = job.waitsForPictures ? .needsPictures : .queued
            board.jobs.append(job)
        }
        next()
    }

    /// Makes a finished or failed job again, as a new file.
    func again(_ job: PixJob) {
        guard let script, job.state == .done || job.state == .failed else { return }
        change(job: job.id, in: script) { $0.state = $0.waitsForPictures ? .needsPictures : .queued; $0.note = nil }
        next()
    }

    func remove(_ job: PixJob) {
        guard let script, job.id != working else { return }
        change(script) { $0.jobs.removeAll { $0.id == job.id } }
    }

    /// Product pictures for a job; a schematic waiting for them is then queued.
    func add(_ urls: [URL], to job: PixJob) {
        guard let script else { return }
        let names = keep(urls, script: script)
        guard !names.isEmpty else { return }
        change(job: job.id, in: script) {
            $0.pictures += names
            if $0.state == .needsPictures { $0.state = .queued }
        }
        next()
    }

    /// Copies pictures into the script's Pix folder, so a job still has them if the originals move.
    private func keep(_ urls: [URL], script: UUID) -> [String] {
        let folder = Self.pictures(script)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return urls.compactMap { url in
            guard NSImage(contentsOf: url) != nil else { return nil }
            let name = UUID().uuidString.prefix(8) + "-" + url.lastPathComponent
            return (try? FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(String(name)))).map { String(name) }
        }
    }

    /// Starts the first queued job when none is being made.
    private func next() {
        guard working == nil else { return }
        for (id, board) in boards {
            for job in board.jobs where job.state == .queued {
                if job.kind != .cta, OpenAIImages.key == nil {
                    change(job: job.id, in: id) { $0.state = .failed; $0.note = L("Pix needs your OpenAI API key for GPT Image: add it below, then press Make again.") }
                    continue
                }
                make(job, script: id)
                return
            }
        }
    }

    private func make(_ job: PixJob, script id: UUID) {
        working = job.id
        change(job: job.id, in: id) { $0.state = .working; $0.note = nil }
        let brief = DonBrief.load(id)
        let pictures = job.pictures.map { Self.pictures(id).appendingPathComponent($0) }
        let fonts = NSFontManager.shared.availableFontFamilies
        Task {
            do {
                let made: (URL, String?)
                if job.kind == .cta {
                    made = try await cta(job, brief: brief, pictures: pictures, fonts: fonts)
                } else {
                    made = try await picture(job, brief: brief, pictures: pictures)
                }
                change(job: job.id, in: id) { $0.state = .done; $0.outputs.append(made.0.path); $0.note = made.1 }
            } catch {
                change(job: job.id, in: id) { $0.state = .failed; $0.note = error.localizedDescription }
            }
            working = nil
            next()
        }
    }

    private func cta(_ job: PixJob, brief: DonBrief?, pictures: [URL], fonts: [String]) async throws -> (URL, String?) {
        let answer = try await HelperBrain.ask(Self.ctaPrompt(job, brief: brief, pictures: pictures.count, fonts: fonts), schema: Self.ctaSchema,
                                               pictures: pictures, timeout: 420)
        let svg = Self.embed(answer["svg"] as? String ?? "", pictures: pictures.map { HelperBrain.jpeg($0, longest: 2048) ?? Data() })
        guard Self.isSVG(svg) else { throw AssistError.message(L("The CTA came back as SVG that does not open. Press Make again.")) }
        let url = Self.file(project: job.project, script: job.script, what: "CTA", ext: "svg")
        try Data(svg.utf8).write(to: url)
        return (url, answer["note"] as? String)
    }

    private func picture(_ job: PixJob, brief: DonBrief?, pictures: [URL]) async throws -> (URL, String?) {
        guard let key = OpenAIImages.key else { throw AssistError.message(L("Pix needs your OpenAI API key for GPT Image.")) }
        let model: String
        if let imageModel { model = imageModel } else { model = try await OpenAIImages.model(key: key); imageModel = model }
        let png = try await OpenAIImages.make(prompt: Self.picturePrompt(job, brief: brief), pictures: pictures,
                                              size: job.kind == .schematic ? "1536x1024" : "auto", model: model, key: key)
        let url = Self.file(project: job.project, script: job.script, what: job.kind == .schematic ? "schematic" : job.title, ext: "png")
        try png.write(to: url)
        return (url, nil)
    }

    // MARK: Chat

    /// Your message, with any pictures; Pix answers and may propose jobs, and pictures sent for a job waiting for them go to it.
    func send(_ text: String, pictures urls: [URL], project: String, name: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let script, !thinking, !(text.isEmpty && urls.isEmpty) else { return }
        let names = keep(urls, script: script)
        let mine = PixMessage(fromPix: false, text: text, pictures: names)
        change(script) { $0.chat.append(mine) }
        let prompt = Self.chatPrompt(stored(script), brief: DonBrief.load(script), pictures: names.count)
        let pictures = names.map { Self.pictures(script).appendingPathComponent($0) }
        thinking = true
        Task {
            var reply: PixMessage
            do {
                let answer = try await HelperBrain.ask(prompt, schema: Self.chatSchema, pictures: pictures, timeout: 150)
                reply = PixMessage(fromPix: true, text: answer["reply"] as? String ?? "")
                reply.proposals = (answer["proposals"] as? [[String: Any]] ?? []).compactMap { proposal in
                    guard let kind = (proposal["kind"] as? String).flatMap(PixJob.Kind.init(rawValue:)) else { return nil }
                    var job = PixJob(kind: kind, title: proposal["title"] as? String ?? "", detail: proposal["detail"] as? String ?? "",
                                     state: .queued, project: project, script: name)
                    if proposal["usePictures"] as? Bool == true { job.pictures = names }
                    return job.title.isEmpty ? nil : job
                }
                let target = (answer["attachPicturesTo"] as? String ?? "").lowercased()
                if !names.isEmpty, !target.isEmpty {
                    change(script) { board in
                        if let index = board.jobs.firstIndex(where: { $0.id.uuidString.lowercased().hasPrefix(target) && $0.state == .needsPictures }) {
                            board.jobs[index].pictures += names; board.jobs[index].state = .queued
                        }
                    }
                }
            } catch {
                reply = PixMessage(fromPix: true, text: L("I couldn't answer that: %@", error.localizedDescription))
            }
            change(script) { $0.chat.append(reply) }
            thinking = false
            next()
        }
    }

    func clearChat() {
        guard let script, !thinking else { return }
        change(script) { $0.chat.removeAll() }
    }

    /// A new, empty chat; the one before goes into the script's history.
    func newChat() {
        guard let script, !thinking else { return }
        change(script) { board in
            if !board.chat.isEmpty { board.past.insert(PixChat(messages: board.chat, updated: board.chat.last?.date ?? Date()), at: 0) }
            board.chat = []
        }
    }

    /// An earlier chat opened to carry on; the one open goes into the history.
    func openChat(_ id: UUID) {
        guard let script, !thinking else { return }
        change(script) { board in
            guard let index = board.past.firstIndex(where: { $0.id == id }) else { return }
            let opened = board.past.remove(at: index)
            if !board.chat.isEmpty { board.past.insert(PixChat(messages: board.chat, updated: board.chat.last?.date ?? Date()), at: 0) }
            board.chat = opened.messages
        }
    }

    func deleteChat(_ id: UUID) {
        guard let script else { return }
        change(script) { $0.past.removeAll { $0.id == id } }
    }

    // MARK: OpenAI key

    func checkKey() {
        guard let key = OpenAIImages.key else { self.key = .none; return }
        guard self.key != .ready || imageModel == nil else { return }
        self.key = .checking
        Task {
            do { imageModel = try await OpenAIImages.model(key: key); self.key = .ready }
            catch { self.key = .failed(error.localizedDescription) }
        }
    }

    func connect(key: String) {
        OpenAIImages.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        imageModel = nil; self.key = .checking
        checkKey()
    }

    func disconnect() {
        OpenAIImages.key = nil; imageModel = nil; key = .none
    }

    // MARK: What Pix sends

    static var ctaSchema: [String: Any] { HelperBrain.object(["svg": HelperBrain.string, "note": HelperBrain.string]) }

    static var chatSchema: [String: Any] {
        let s = HelperBrain.string
        return HelperBrain.object(["reply": s, "attachPicturesTo": s,
                                   "proposals": ["type": "array", "items": HelperBrain.object([
                                       "kind": ["type": "string", "enum": PixJob.Kind.allCases.map(\.rawValue)], "title": s, "detail": s,
                                       "usePictures": ["type": "boolean"]])]])
    }

    static func briefLines(_ brief: DonBrief?) -> String {
        guard let brief else { return "Don has not briefed this script yet." }
        return """
        Product: \(brief.product)
        Vibe: \(brief.vibe)
        Graphic style: \(brief.graphicStyle)
        CTA words in the script: \(brief.cta)
        How the CTA should look: \(brief.ctaLook)
        """
    }

    static func ctaPrompt(_ job: PixJob, brief: DonBrief?, pictures: Int, fonts: [String]) -> String {
        let placing = pictures == 0
            ? "No product picture yet: in each variant leave a rect with id=\"Product-area-A\" (then -B, -C) and a light dashed outline where the product goes."
            : "\(pictures) product picture\(pictures == 1 ? " is" : "s are") attached, PICTURE1 to PICTURE\(pictures) in that order. Place them with "
              + "<image href=\"PICTUREn\" x=\"…\" y=\"…\" width=\"…\" height=\"…\" preserveAspectRatio=\"xMidYMid meet\"/> wherever the product shows "
              + "(Pix puts the picture in for the name). Take the palette from the product."
        return """
        You are Pix, the CTA designer for short vertical video ads (TikTok, Reels, Shorts). Design the end card (the CTA) as one SVG that opens \
        editable in Adobe Illustrator.
        - Canvas: width="3560" height="1920" viewBox="0 0 3560 1920", a white rect over all of it. Three variants side by side, each a 1080×1920 \
        frame with its own background: A at x=0, B at x=1240, C at x=2480. Each variant in <g id="A - its wording">, then B, then C.
        - Every word is a real <text> element (a <tspan> per line), never outlined. Fonts only from the installed families below, \
        with font-weight and font-style. Colours as hex. No external files, no CSS @import, no foreignObject, no filters.
        - Keep the words and the button between y=250 and y=1500 of each frame: the top and the bottom are under the app's buttons and captions.
        - Each variant: the brand or product name, the offer, and a button (rounded rect with its words, e.g. SHOP NOW); arrows or small icons as \
        simple paths where they help. A keeps closest to the script's CTA words; B and C try other honest wordings of the same offer. \
        Never invent an offer, price, percentage or claim the script does not make.
        - \(placing)
        Don's brief:
        \(briefLines(brief))
        \(job.detail.isEmpty ? "" : "Asked for this time: \(job.detail)\n")\
        Answer with svg (the whole SVG) and note (one short line per variant on what it tries).
        Installed font families: \(fonts.joined(separator: ", "))
        """
    }

    static func picturePrompt(_ job: PixJob, brief: DonBrief?) -> String {
        let style = brief.map { "Ad style: \($0.graphicStyle)." } ?? ""
        guard job.kind == .schematic else { return [job.title + ". " + job.detail, style].joined(separator: "\n") }
        return """
        A product reference sheet (schematic) for AI video generation. Show exactly the product in the reference pictures: the same shape, \
        proportions, colours, materials, printed words and logos; never redesign it. Views: front, back, left side, right side and three-quarter, \
        plus close-ups of its key details, each labelled in small plain capitals (FRONT, BACK…), laid out evenly on a plain light grey background, \
        in soft even studio light, with no props, hands, people or other text.
        \(job.detail)
        \(brief.map { "The product: \($0.product)." } ?? "")
        """
    }

    static func chatPrompt(_ board: PixBoard, brief: DonBrief?, pictures: Int) -> String {
        let jobs = board.jobs.suffix(20).map { "- [\($0.id.uuidString.prefix(8).lowercased())] \($0.kind.rawValue): \($0.title) (\($0.state.rawValue))" }
        let chat = board.chat.suffix(16).map { ($0.fromPix ? "Pix: " : "You: ") + $0.text + ($0.pictures.isEmpty ? "" : " [\($0.pictures.count) pictures]") }
        return """
        You are Pix, the CTA and picture helper in Edit Assist, chatting with the video editor you work for. Your jobs:
        - cta: the end card of the ad, three variants in one SVG that opens editable in Illustrator, designed by you (free).
        - schematic: a product reference sheet made with GPT Image from product pictures, so AI video (Kino's job) keeps the product right. Costs OpenAI credit.
        - picture: any other picture made with GPT Image, from words and any pictures sent. Costs OpenAI credit.
        You never start a job yourself: put what you would make in proposals (kind, a short title, and in detail exactly what to change or make) \
        and the editor queues it with one press. To redo the CTA with changes, propose a new cta. Set usePictures when the pictures sent with \
        this message are for the proposal. A schematic needs product pictures: ask for them when none were sent. If this message brings \
        pictures for a job in the queue waiting for pictures (needsPictures), put that job's id in attachPicturesTo; otherwise "".
        Reply briefly and warmly, in the editor's language. Don (the ads expert) briefs you:
        \(briefLines(brief))
        The queue:
        \(jobs.isEmpty ? "(empty)" : jobs.joined(separator: "\n"))
        The chat so far (the last line is the editor's new message\(pictures > 0 ? ", with \(pictures) pictures attached" : "")):
        \(chat.joined(separator: "\n"))
        """
    }

    /// The SVG with each PICTUREn name swapped for that picture as a data URL.
    static func embed(_ svg: String, pictures: [Data]) -> String {
        var svg = svg
        for (index, data) in pictures.enumerated().reversed() where !data.isEmpty {
            svg = svg.replacingOccurrences(of: "\"PICTURE\(index + 1)\"", with: "\"data:image/jpeg;base64,\(data.base64EncodedString())\"")
        }
        return svg
    }

    /// Well-formed XML whose root is <svg>.
    static func isSVG(_ text: String) -> Bool {
        final class Root: NSObject, XMLParserDelegate {
            var name: String?
            func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
                if name == nil { name = element }
            }
        }
        let parser = XMLParser(data: Data(text.utf8)), root = Root()
        parser.delegate = root
        return parser.parse() && root.name == "svg"
    }

    /// "<project> - <script> - <what>.<ext>" in Downloads, where your CTA files go, numbered rather than over an earlier one.
    static func file(project: String, script: String, what: String, ext: String, in folder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) -> URL {
        let clean = { (name: String) in name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-").trimmingCharacters(in: .whitespaces) }
        let stem = [clean(project), clean(script), clean(what)].filter { !$0.isEmpty }.joined(separator: " - ")
        var url = folder.appendingPathComponent(stem + "." + ext), number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem) \(number).\(ext)"); number += 1
        }
        return url
    }
}
