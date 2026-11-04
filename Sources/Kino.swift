import SwiftUI
import WebKit

/// Kino, the AI video helper: an orange blob in a red director's beret, holding a clapperboard. Working: the clapper
/// opens and snaps shut, and sparks of AI fly off it.
struct PixelKino: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 250 / 255, green: 160 / 255, blue: 70 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO.....",
                       ".OOOOOOOOOO.....", ".OOKOOOOKOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
                       ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"]
    static let blink = ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO.....",
                        ".OOOOOOOOOO.....", ".OOOOOOOOOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
                        ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"]
    static let working: [[String]] = [
        ["..RRRRRr....S...", ".RRRRRRR.......W", "..OOOOOOO.....B.", ".OOOOOOOOOO..W..",
         ".OOOOOOOOOO.B...", ".OOKOOOOKOOW....", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"],
        ["..RRRRRr....s...", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO...S.",
         ".OOOOOOOOOO.....", ".OOKOOOOKOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"],
        ["..RRRRRr........", ".RRRRRRR.......W", "..OOOOOOO.....B.", ".OOOOOOOOOO.sW..",
         ".OOOOOOOOOO.B...", ".OOOKOOOOKOW....", ".OOOKOOOOKOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D....S..", "................"],
        ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO...S...", ".OOOOOOOOOO.....",
         ".OOOOOOOOOO.....", ".OOOKOOOOKOWBWBW", ".OOOKOOOOKOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.....s.", "................"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["O": Color(red: 250 / 255, green: 160 / 255, blue: 70 / 255), "D": Color(red: 205 / 255, green: 131 / 255, blue: 57 / 255),
                                "R": Color(red: 215 / 255, green: 55 / 255, blue: 60 / 255), "r": Color(red: 160 / 255, green: 35 / 255, blue: 45 / 255),
                                "K": Color(red: 25 / 255, green: 25 / 255, blue: 28 / 255), "B": Color(red: 95 / 255, green: 95 / 255, blue: 108 / 255),
                                "W": Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255), "S": Color(red: 1, green: 230 / 255, blue: 120 / 255),
                                "s": Color(red: 150 / 255, green: 220 / 255, blue: 1)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Kino")
    }
}

/// Kino's page (2026-11-03): AI videos made with Kling and Higgsfield, from your media and prompts. The tab only, for now.
/// The research beside him (2026-11-04): how Kling and Higgsfield work, read in the app.
struct KinoPage: View {
    @State private var reading: KinoResearch?
    @State private var hovered: KinoResearch?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Side by side when the page is wide enough, the research under him otherwise.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { intro; Spacer(minLength: 0); research.frame(width: 320) }
                VStack(alignment: .leading, spacing: 18) { intro; research.frame(maxWidth: 420) }
            }
            Text(md: L("Not connected yet: Kino is still being set up.")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
        .sheet(item: $reading) { KinoResearchSheet(doc: $0) }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 16) {
            PixelKino(pixel: 4, previewOnHover: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(md: L("Your AI video helper")).font(.system(size: 13, weight: .semibold))
                Bullets(["Makes **AI videos** with **Kling** and **Higgsfield**",
                         "Connects your **media** (images, clips) to the **prompts**",
                         "Works to the look in **Don's** brief"], size: 11)
            }
        }
    }

    private var research: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(md: L("RESEARCH")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Text(L("As of %@", KinoResearch.asOf.formatted(date: .abbreviated, time: .omitted)))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.bottom, 2)
            ForEach(KinoResearch.allCases) { doc in
                Button { reading = doc } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: doc.icon).font(.system(size: 12)).foregroundStyle(PixelKino.theme).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L(doc.title)).font(.system(size: 12, weight: .semibold))
                            Text(L(doc.summary)).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).padding(.top, 3)
                    }
                    .padding(8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.white.opacity(hovered == doc ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 7))
                .onHover { inside in hovered = inside ? doc : (hovered == doc ? nil : hovered) }
            }
        }
        .padding(8).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// The research in docs/kino, which build.sh copies into the app's Resources/Kino: the map is a page (the same file
/// as its web version), the notes on each service are Markdown.
enum KinoResearch: String, CaseIterable, Identifiable {
    case map, kling, higgsfield
    static let asOf = DateComponents(calendar: .current, year: 2026, month: 11, day: 4).date ?? .now
    var id: String { rawValue }
    var title: String {
        switch self {
        case .map: "Kling and Higgsfield side by side"
        case .kling: "Kling"
        case .higgsfield: "Higgsfield"
        }
    }
    var summary: String {
        switch self {
        case .map: "What a file can be in a shot, how each names it in the prompt, what each can make, a job's life"
        case .kling: "Models, modes, limits, prompt structure and the API"
        case .higgsfield: "Its models and tools, the API, and every endpoint's fields"
        }
    }
    var icon: String {
        switch self {
        case .map: "map"
        case .kling, .higgsfield: "doc.text"
        }
    }
    var file: String { self == .map ? "map.html" : rawValue + ".md" }
    var url: URL? { Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "Kino") }
    /// A link between the notes ("kling.md", "higgsfield.md#…"); README.md, the map in words, opens the map.
    init?(link: URL) {
        guard link.scheme == nil || link.scheme == "file" else { return nil }
        let name = (link.path as NSString).lastPathComponent
        if name == "README.md" || name == "map.html" { self = .map; return }
        guard name.hasSuffix(".md"), let doc = KinoResearch(rawValue: String(name.dropLast(3))) else { return nil }
        self = doc
    }
}

/// One research note, read in the app. Links between the notes open here; web links open in the browser.
struct KinoResearchSheet: View {
    @State var doc: KinoResearch
    @State private var blocks: [MarkdownBlock] = []
    @State private var missing = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                PixelKino(pixel: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(doc.title)).font(.system(size: 15, weight: .semibold))
                    Text("docs/kino/\(doc.file) · " + L("As of %@", KinoResearch.asOf.formatted(date: .abbreviated, time: .omitted)))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            Divider()
            if doc == .map, let url = doc.url {
                KinoMapView(url: url)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if missing {
                            Text(md: L("This note is not in this copy of the app. Build it again with **./build.sh**."))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in MarkdownBlockView(block: block) }
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 26).padding(.vertical, 20)
                    .frame(maxWidth: 980, alignment: .leading)
                }
                .id(doc)
            }
        }
        .frame(minWidth: 760, idealWidth: 1040, minHeight: 560, idealHeight: 800)
        .environment(\.openURL, OpenURLAction { url in
            if let other = KinoResearch(link: url) { doc = other; return .handled }
            return url.scheme == "https" || url.scheme == "http" ? .systemAction : .discarded
        })
        .task(id: doc) {
            let text = doc.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            missing = text == nil
            blocks = doc == .map ? [] : MarkdownBlock.parse(text ?? "")
        }
    }
}

/// The map (docs/kino/map.html), the page its web version is published from, so both look the same. Its diagrams are
/// drawn by the page itself; web links open in the browser.
struct KinoMapView: NSViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        if let page = try? String(contentsOf: url, encoding: .utf8) {
            view.loadHTMLString(Self.document(page), baseURL: url.deletingLastPathComponent())
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    /// The page is written as an artifact's body (the host adds the document around it); here the app does, and the
    /// sheet's own background shows through.
    static func document(_ page: String) -> String {
        "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<style>html,body{margin:0}body{background:transparent!important}</style></head><body>" + page + "</body></html>"
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let link = action.request.url, ["http", "https"].contains(link.scheme) else { return .allow }
            NSWorkspace.shared.open(link)
            return .cancel
        }
    }
}

/// A Markdown file as blocks, as much as the research notes use: headings, paragraphs, lists, tables, code, rules.
/// Bold, code and links inside a block are left to AttributedString.
enum MarkdownBlock {
    struct Item { var indent: Int; var marker: String; var text: String }
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([Item])
    case table(header: [String], rows: [[String]])
    case code(language: String, text: String)
    case rule

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = [], paragraph: [String] = [], items: [Item] = [], table: [[String]] = []
        var code: (language: String, lines: [String])?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !items.isEmpty { blocks.append(.list(items)); items = [] }
            if !table.isEmpty { blocks.append(.table(header: table[0], rows: Array(table.dropFirst()))); table = [] }
        }
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var open = code {
                if trimmed.hasPrefix("```") { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))); code = nil }
                else { open.lines.append(line); code = open }
                continue
            }
            let indent = line.prefix { $0 == " " }.count
            if trimmed.hasPrefix("```") { flush(); code = (String(trimmed.dropFirst(3)), []); continue }
            if trimmed.isEmpty { flush(); continue }
            if trimmed.hasPrefix("|") {
                if table.isEmpty { flush() }
                let row = cells(trimmed)
                if !row.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { table.append(row) }
                continue
            }
            if !table.isEmpty { flush() }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flush(); blocks.append(.heading(level: hashes, text: String(trimmed.dropFirst(hashes + 1)))); continue
            }
            if trimmed == "---" || trimmed == "***" { flush(); blocks.append(.rule); continue }
            if let item = listItem(trimmed, indent: indent) {
                if !paragraph.isEmpty { flush() }
                items.append(item); continue
            }
            if !items.isEmpty, indent > 0 { items[items.count - 1].text += " " + trimmed; continue }
            if !items.isEmpty { flush() }
            paragraph.append(trimmed)
        }
        if let open = code { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// "| a | b \| c |" → ["a", "b | c"].
    private static func cells(_ row: String) -> [String] {
        var inner = row.replacingOccurrences(of: "\\|", with: "\u{1}")
        if inner.hasPrefix("|") { inner.removeFirst() }
        if inner.hasSuffix("|") { inner.removeLast() }
        return inner.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{1}", with: "|")
        }
    }

    private static func listItem(_ trimmed: String, indent: Int) -> Item? {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return Item(indent: min(3, indent / 2), marker: "•", text: String(trimmed.dropFirst(2)))
        }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, trimmed.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return Item(indent: min(3, indent / 2), marker: digits + ".", text: String(trimmed.dropFirst(digits.count + 2)))
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text)).font(.system(size: [1: 20, 2: 16, 3: 13.5][level] ?? 12.5, weight: .semibold))
                .padding(.top, level <= 2 ? 14 : 6).fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(inline(text)).font(.system(size: 12)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.marker).font(.system(size: 12)).foregroundStyle(PixelKino.theme)
                        Text(inline(item.text)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * 16)
                }
            }
        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows)
        case .code(let language, let text):
            if language == "mermaid" {
                Label(L("A diagram: drawn in the web version of the map. The tables carry the same facts."), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView(.horizontal) {
                    Text(text).font(.system(size: 11, design: .monospaced)).padding(10)
                }
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }
}

/// A table whose columns are as wide as their longest cell, up to 300 points, wrapping beyond; wide tables scroll sideways.
struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]
    private let widths: [CGFloat]
    init(header: [String], rows: [[String]]) {
        self.header = header; self.rows = rows
        widths = header.indices.map { column in
            let longest = ([header] + rows).map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0
            return min(300, max(50, CGFloat(longest) * 6))
        }
    }
    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        cell(header[column], column).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            cell(row.indices.contains(column) ? row[column] : "", column).font(.system(size: 11))
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
    private func cell(_ text: String, _ column: Int) -> some View {
        Text(inline(text)).frame(width: widths[column], alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}

/// Bold, italics, code and links inside one block of Markdown; the text as it is when it does not parse.
private func inline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
