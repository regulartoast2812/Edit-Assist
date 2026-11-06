import Foundation

/// Basil's note view, free of the Mac (Foundation only) like `Kitchen`: a recipe note's Markdown drawn as Obsidian draws it
/// in reading view, with your vault's own look (2026-11-06). The page copies Obsidian's structure (body.theme-dark or
/// theme-light, .markdown-preview-view.markdown-rendered, a .metadata-container for the properties) and its CSS
/// variables, then adds your vault's settings (.obsidian/appearance.json: light or dark, accent colour, font size, fonts),
/// your community theme (.obsidian/themes/<name>/theme.css) and your enabled snippets (.obsidian/snippets/<name>.css), so
/// a theme made for Obsidian dresses it the same way.
extension Kitchen {
    // MARK: The vault's look

    struct Look: Equatable {
        /// true dark, false light, nil the system's.
        var dark: Bool?
        var accent = ""
        var fontSize = 16.0
        var textFont = "", monospaceFont = ""
        /// Your theme's CSS, then your snippets'.
        var css = ""
    }

    /// The vault the folder is in: the nearest folder up holding `.obsidian`.
    static func vault(of folder: URL) -> URL? {
        var place = folder.standardizedFileURL
        for _ in 0 ..< 12 {
            if FileManager.default.fileExists(atPath: place.appendingPathComponent(".obsidian").path) { return place }
            let up = place.deletingLastPathComponent()
            if up.path == place.path { return nil }
            place = up
        }
        return nil
    }

    /// The vault's appearance as Obsidian keeps it; Obsidian's defaults where it keeps nothing.
    static func look(vault: URL) -> Look {
        let settings = vault.appendingPathComponent(".obsidian")
        let appearance = (try? Data(contentsOf: settings.appendingPathComponent("appearance.json"))).flatMap(json) ?? [:]
        var look = Look()
        switch appearance["theme"] as? String {
        case "obsidian": look.dark = true
        case "moonstone": look.dark = false
        default: look.dark = nil
        }
        look.accent = appearance["accentColor"] as? String ?? ""
        look.fontSize = (appearance["baseFontSize"] as? NSNumber)?.doubleValue ?? 16
        look.textFont = appearance["textFontFamily"] as? String ?? ""
        look.monospaceFont = appearance["monospaceFontFamily"] as? String ?? ""
        var css: [String] = []
        if let theme = appearance["cssTheme"] as? String, !theme.isEmpty,
           let text = try? String(contentsOf: settings.appendingPathComponent("themes/\(theme)/theme.css"), encoding: .utf8) { css.append(text) }
        for snippet in appearance["enabledCssSnippets"] as? [String] ?? [] {
            if let text = try? String(contentsOf: settings.appendingPathComponent("snippets/\(snippet).css"), encoding: .utf8) { css.append(text) }
        }
        look.css = css.joined(separator: "\n")
        return look
    }

    // MARK: The page

    /// The note as a web page in Obsidian's reading view. Links: `basil-note:<name>` for a [[wikilink]], http(s) as written.
    static func page(note text: String, look: Look, dark: Bool) -> String {
        let (header, body) = split(text)
        var html = ""
        if !header.isEmpty { html += properties(header) }
        html += markdown(body)
        let accent = look.accent.isEmpty ? "" : "--accent: \(look.accent); --interactive-accent: \(look.accent); --text-accent: \(look.accent); --color-accent: \(look.accent);"
        let fonts = (look.textFont.isEmpty ? "" : "--font-text-override: \(look.textFont);") + (look.monospaceFont.isEmpty ? "" : "--font-monospace-override: \(look.monospaceFont);")
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>\(baseCSS)
        body { --font-text-size: \(Int(look.fontSize))px; \(accent) \(fonts) }
        </style><style>\(look.css)</style></head>
        <body class="\(dark ? "theme-dark" : "theme-light") is-readable-line-width"><div class="markdown-reading-view"><div class="markdown-preview-view markdown-rendered">
        <div class="markdown-preview-sizer markdown-preview-section">\(html)</div></div></div></body></html>
        """
    }

    /// The YAML header and the body after it.
    static func split(_ text: String) -> (header: String, body: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return ("", text) }
        return (lines[1 ..< end].joined(separator: "\n"), lines[(end + 1)...].joined(separator: "\n"))
    }

    /// The header as Obsidian's Properties block: each key with its value, lists as pills, links clickable.
    static func properties(_ header: String) -> String {
        let values = Kitchen.header(of: "---\n" + header + "\n---\n")
        var order: [String] = []
        for line in header.components(separatedBy: "\n") where !line.hasPrefix(" ") && !line.hasPrefix("-") {
            if let colon = line.firstIndex(of: ":") { let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces); if !order.contains(key) { order.append(key) } }
        }
        let rows = order.compactMap { key -> String? in
            let list = values[key] ?? []
            let value: String
            if key == "tags" || list.count > 1 {
                value = list.map { "<span class=\"multi-select-pill\">\(escape(key == "tags" ? "#" + $0 : $0))</span>" }.joined()
            } else if let one = list.first, one.hasPrefix("http") {
                value = "<a class=\"external-link\" href=\"\(attribute(one))\">\(escape(one))</a>"
            } else {
                value = escape(list.first ?? "")
            }
            return "<div class=\"metadata-property\"><div class=\"metadata-property-key\">\(escape(key))</div><div class=\"metadata-property-value\">\(value)</div></div>"
        }
        return "<div class=\"metadata-container\"><div class=\"metadata-properties-heading\">Properties</div><div class=\"metadata-content\">\(rows.joined())</div></div>"
    }

    // MARK: Markdown (what recipe notes use: headings, lists, tasks, quotes and callouts, code, tables, links and embeds)

    static func markdown(_ text: String) -> String {
        var html = "", paragraph: [String] = [], lists: [(ordered: Bool, indent: Int)] = [], quote: [String] = []
        var code: [String]?, table: [String] = []
        let lines = text.components(separatedBy: "\n")

        func closeParagraph() { if !paragraph.isEmpty { html += "<p>" + paragraph.map(inline).joined(separator: "<br>") + "</p>"; paragraph = [] } }
        func closeLists(to indent: Int = -1) {
            while let last = lists.last, last.indent > indent { html += "</li>" + (last.ordered ? "</ol>" : "</ul>"); lists.removeLast() }
        }
        func closeQuote() {
            guard !quote.isEmpty else { return }
            if let first = quote.first, first.hasPrefix("[!"), let end = first.firstIndex(of: "]") {
                let kind = first[first.index(first.startIndex, offsetBy: 2) ..< end].lowercased().filter { $0.isLetter }
                let title = first[first.index(after: end)...].trimmingCharacters(in: CharacterSet(charactersIn: "+- "))
                html += "<div class=\"callout\" data-callout=\"\(kind)\"><div class=\"callout-title\"><div class=\"callout-title-inner\">\(inline(title.isEmpty ? kind.capitalized : title))</div></div>"
                    + "<div class=\"callout-content\">\(markdown(quote.dropFirst().joined(separator: "\n")))</div></div>"
            } else {
                html += "<blockquote>\(markdown(quote.joined(separator: "\n")))</blockquote>"
            }
            quote = []
        }
        func closeTable() {
            guard table.count >= 2 else { paragraph += table; table = []; return }
            let cells = { (row: String) in row.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
            html += "<table><thead><tr>" + cells(table[0]).map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>"
            for row in table.dropFirst(2) { html += "<tr>" + cells(row).map { "<td>\(inline($0))</td>" }.joined() + "</tr>" }
            html += "</tbody></table>"; table = []
        }
        func closeAll() { closeParagraph(); closeLists(); closeQuote(); closeTable() }

        for line in lines {
            if var block = code {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { html += "<pre><code>\(escape(block.joined(separator: "\n")))</code></pre>"; code = nil }
                else { block.append(line); code = block }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { closeAll(); code = []; continue }
            if trimmed.hasPrefix(">") { closeParagraph(); closeLists(); closeTable(); quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)); continue }
            closeQuote()
            if trimmed.hasPrefix("|") { closeParagraph(); closeLists(); table.append(trimmed); continue }
            closeTable()
            if trimmed.isEmpty { closeParagraph(); closeLists(); continue }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { closeAll(); html += "<hr>"; continue }
            if let level = heading(trimmed) {
                closeAll()
                html += "<h\(level)>\(inline(String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)))</h\(level)>"
                continue
            }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            if let (ordered, rest) = item(trimmed) {
                closeParagraph()
                closeLists(to: indent)
                if let last = lists.last, last.indent == indent, last.ordered == ordered { html += "</li>" }
                else {
                    if let last = lists.last, last.indent == indent { html += "</li>" + (last.ordered ? "</ol>" : "</ul>"); lists.removeLast() }
                    html += ordered ? "<ol>" : "<ul>"; lists.append((ordered, indent))
                }
                if rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
                    let done = !rest.hasPrefix("[ ]")
                    html += "<li class=\"task-list-item\(done ? " is-checked" : "")\" data-task=\"\(done ? "x" : " ")\"><input type=\"checkbox\" class=\"task-list-item-checkbox\" disabled\(done ? " checked" : "")>\(inline(String(rest.dropFirst(4))))"
                } else {
                    html += "<li>\(inline(rest))"
                }
                continue
            }
            if !lists.isEmpty && indent > 0 { html += "<br>" + inline(trimmed); continue }
            closeLists()
            paragraph.append(trimmed)
        }
        if let block = code { html += "<pre><code>\(escape(block.joined(separator: "\n")))</code></pre>" }
        closeAll()
        return html
    }

    private static func heading(_ line: String) -> Int? {
        let marks = line.prefix { $0 == "#" }.count
        return (1 ... 6).contains(marks) && line.dropFirst(marks).first == " " ? marks : nil
    }

    /// A list item's kind and text: "- a", "* a", "+ a", "1. a", "1) a".
    private static func item(_ line: String) -> (ordered: Bool, text: String)? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " { return (false, String(line.dropFirst(2))) }
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, case let rest = line.dropFirst(digits.count), let mark = rest.first, ".)".contains(mark), rest.dropFirst().first == " " else { return nil }
        return (true, String(rest.dropFirst(2)))
    }

    /// Bold, italics, strikes, highlights, code, links, pictures, [[wikilinks]], embeds and #tags inside a line.
    static func inline(_ text: String) -> String {
        var codes: [String] = []
        // Code first, kept away from every other rule.
        var line = replacing(#"`([^`]+)`"#, in: text) { groups in codes.append("<code>\(escape(groups[1]))</code>"); return "\u{1}\(codes.count - 1)\u{2}" }
        line = escape(line)
        line = replacing(#"!\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#, in: line) { groups in
            "<span class=\"internal-embed\"><a class=\"internal-link\" href=\"basil-note:\(attribute(unescape(groups[1])))\">\(groups[1])</a></span>"
        }
        line = replacing(#"\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#, in: line) { groups in
            "<a class=\"internal-link\" href=\"basil-note:\(attribute(unescape(groups[1])))\">\(groups[2].isEmpty ? groups[1] : groups[2])</a>"
        }
        line = replacing(#"!\[([^\]]*)\]\(([^)\s]+)\)"#, in: line) { groups in
            let url = unescape(groups[2])
            if let picture = thumbnail(of: url) {
                return "<a class=\"video-embed\" href=\"\(attribute(url))\"><img src=\"\(picture.absoluteString)\" alt=\"\"><span class=\"play\">▶</span></a>"
            }
            return "<img src=\"\(attribute(url))\" alt=\"\(groups[1])\">"
        }
        line = replacing(#"\[([^\]]+)\]\(([^)\s]+)\)"#, in: line) { groups in "<a class=\"external-link\" href=\"\(attribute(unescape(groups[2])))\">\(groups[1])</a>" }
        line = replacing(#"(^|[\s(])(https?://[^\s<]+)"#, in: line) { groups in "\(groups[1])<a class=\"external-link\" href=\"\(groups[2])\">\(groups[2])</a>" }
        line = replacing(#"\*\*([^*]+)\*\*"#, in: line) { "<strong>\($0[1])</strong>" }
        line = replacing(#"__([^_]+)__"#, in: line) { "<strong>\($0[1])</strong>" }
        line = replacing(#"(^|[^*])\*([^*\s][^*]*)\*"#, in: line) { "\($0[1])<em>\($0[2])</em>" }
        line = replacing(#"(^|[\s(])_([^_\s][^_]*)_"#, in: line) { "\($0[1])<em>\($0[2])</em>" }
        line = replacing(#"~~([^~]+)~~"#, in: line) { "<del>\($0[1])</del>" }
        line = replacing(#"==([^=]+)=="#, in: line) { "<mark>\($0[1])</mark>" }
        line = replacing(#"(^|\s)#([\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)"#, in: line) { "\($0[1])<a class=\"tag\" href=\"#\($0[2])\">#\($0[2])</a>" }
        return replacing("\u{1}(\\d+)\u{2}", in: line) { codes[Int($0[1]) ?? 0] }
    }

    /// Every match of the pattern replaced by what `with` makes of its groups (a group not matched is "").
    private static func replacing(_ pattern: String, in text: String, with: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = "", last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text) else { continue }
            let groups = (0 ..< match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
            result += text[last ..< whole.lowerBound] + with(groups)
            last = whole.upperBound
        }
        return result + text[last...]
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }
    private static func attribute(_ text: String) -> String { escape(text).replacingOccurrences(of: "\"", with: "&quot;") }

    /// Obsidian's own reading-view look, in its CSS variables, so a theme's variables take over as in Obsidian.
    static let baseCSS = """
    body { --font-text-theme: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, sans-serif; --font-monospace-theme: ui-monospace, Menlo, Consolas, monospace;
      --font-text: var(--font-text-override, var(--font-text-theme)); --font-monospace: var(--font-monospace-override, var(--font-monospace-theme));
      --line-height-normal: 1.5; --file-line-width: 700px; --h1-size: 1.802em; --h2-size: 1.602em; --h3-size: 1.424em; --h4-size: 1.266em; --h5-size: 1.125em; --h6-size: 1em;
      --h1-weight: 700; --h2-weight: 600; --h3-weight: 600; --h4-weight: 600; --radius-s: 4px; --radius-m: 8px; }
    body.theme-dark { --background-primary: #1e1e1e; --background-secondary: #262626; --background-modifier-border: #363636; --text-normal: #dadada; --text-muted: #b3b3b3;
      --text-faint: #666; --text-accent: var(--accent, #a68af9); --interactive-accent: var(--accent, #8a5cf5); --code-background: #2a2a2a; --tag-background: rgba(138,92,245,.15);
      --text-highlight-bg: rgba(255,208,0,.4); --blockquote-border-color: var(--interactive-accent); color-scheme: dark; }
    body.theme-light { --background-primary: #ffffff; --background-secondary: #f6f6f6; --background-modifier-border: #e0e0e0; --text-normal: #222; --text-muted: #5c5c5c;
      --text-faint: #ababab; --text-accent: var(--accent, #8a5cf5); --interactive-accent: var(--accent, #8a5cf5); --code-background: #f5f5f5; --tag-background: rgba(138,92,245,.1);
      --text-highlight-bg: rgba(255,208,0,.4); --blockquote-border-color: var(--interactive-accent); color-scheme: light; }
    html, body { margin: 0; background: var(--background-primary); color: var(--text-normal); font-family: var(--font-text); font-size: var(--font-text-size); line-height: var(--line-height-normal); }
    .markdown-preview-view { padding: 28px 36px 60px; }
    .is-readable-line-width .markdown-preview-sizer { max-width: var(--file-line-width); margin: 0 auto; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 1.2em 0 .5em; color: var(--text-normal); }
    h1 { font-size: var(--h1-size); font-weight: var(--h1-weight); } h2 { font-size: var(--h2-size); font-weight: var(--h2-weight); }
    h3 { font-size: var(--h3-size); font-weight: var(--h3-weight); } h4 { font-size: var(--h4-size); font-weight: var(--h4-weight); }
    h5 { font-size: var(--h5-size); } h6 { font-size: var(--h6-size); }
    p { margin: .6em 0; } a { color: var(--text-accent); text-decoration: none; } a:hover { text-decoration: underline; }
    a.external-link { background: none; } a.internal-link { text-decoration: underline; text-decoration-color: color-mix(in srgb, var(--text-accent) 40%, transparent); }
    ul, ol { padding-inline-start: 1.6em; margin: .4em 0; } li { margin: .15em 0; } li::marker { color: var(--text-faint); }
    .task-list-item { list-style: none; margin-inline-start: -1.4em; } .task-list-item-checkbox { margin-inline-end: .5em; accent-color: var(--interactive-accent); }
    .task-list-item.is-checked { color: var(--text-muted); text-decoration: line-through; }
    blockquote { margin: .8em 0; padding: .1em 1em; border-inline-start: 2px solid var(--blockquote-border-color); color: var(--text-muted); }
    .callout { margin: 1em 0; padding: 12px 14px; border-radius: var(--radius-s); background: color-mix(in srgb, var(--interactive-accent) 10%, transparent); }
    .callout-title { font-weight: 600; color: var(--text-accent); margin-bottom: .3em; }
    code { font-family: var(--font-monospace); font-size: .875em; background: var(--code-background); padding: .1em .3em; border-radius: var(--radius-s); }
    pre { background: var(--code-background); padding: 12px 14px; border-radius: var(--radius-s); overflow-x: auto; } pre code { background: none; padding: 0; }
    mark { background: var(--text-highlight-bg); color: inherit; } hr { border: none; border-top: 1px solid var(--background-modifier-border); margin: 1.6em 0; }
    table { border-collapse: collapse; margin: 1em 0; } th, td { border: 1px solid var(--background-modifier-border); padding: 4px 10px; } th { background: var(--background-secondary); }
    img { max-width: 100%; border-radius: var(--radius-s); }
    a.tag { background: var(--tag-background); color: var(--text-accent); padding: .1em .55em; border-radius: 1em; font-size: .875em; }
    .video-embed { position: relative; display: block; max-width: 560px; aspect-ratio: 16 / 9; border-radius: var(--radius-m); overflow: hidden; margin: 1em 0; background: #000; }
    .video-embed img { width: 100%; height: 100%; object-fit: cover; border-radius: 0; opacity: .9; }
    .video-embed .play { position: absolute; inset: 0; margin: auto; width: 64px; height: 44px; border-radius: 12px; background: rgba(255,0,0,.88); color: #fff;
      display: flex; align-items: center; justify-content: center; font-size: 20px; }
    .metadata-container { margin: 0 0 1.4em; padding-bottom: .8em; border-bottom: 1px solid var(--background-modifier-border); font-size: .875em; }
    .metadata-properties-heading { color: var(--text-muted); font-weight: 600; margin-bottom: .4em; }
    .metadata-property { display: flex; gap: 12px; padding: 3px 0; } .metadata-property-key { width: 110px; flex: none; color: var(--text-muted); }
    .metadata-property-value { color: var(--text-normal); overflow-wrap: anywhere; }
    .multi-select-pill { display: inline-block; background: var(--tag-background); color: var(--text-accent); padding: 0 .55em; border-radius: 1em; margin: 0 4px 2px 0; }
    """
}
