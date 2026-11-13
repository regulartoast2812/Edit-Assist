import Foundation

/// Sage's note view, free of the Mac (Foundation only) like `Study`: a recipe note's Markdown drawn as Obsidian draws it
/// in reading view, with your vault's own look (2026-11-06). The page copies Obsidian's structure (body.theme-dark or
/// theme-light, .markdown-preview-view.markdown-rendered, a .metadata-container for the properties) and its CSS
/// variables, then adds your vault's settings (.obsidian/appearance.json: light or dark, accent colour, font size, fonts),
/// your community theme (.obsidian/themes/<name>/theme.css) and your enabled snippets (.obsidian/snippets/<name>.css), so
/// a theme made for Obsidian dresses it the same way. Grown in Creative Assist, the Windows app (2026-11-07 and 08), and
/// brought back on 2026-11-09: Obsidian's own reading view structure, editing in place, Bases and canvases.
extension Study {
    // MARK: The vault's look

    struct Look: Equatable, Sendable {
        /// true dark, false light, nil the system's.
        var dark: Bool?
        var accent = ""
        var fontSize = 16.0
        var textFont = "", monospaceFont = ""
        /// Your theme's CSS, then your snippets'.
        var css = ""
        /// app.json's propertiesInDocument: "visible", "hidden" or "source" (the YAML as it is).
        var properties = "visible"
        /// app.json's showInlineTitle, the note's name as a title at the top.
        var inlineTitle = true
        /// app.json's readableLineLength.
        var readable = true
        /// appearance.json's interfaceFontFamily.
        var interfaceFont = ""
        /// Each property's type as the vault keeps it (.obsidian/types.json: "Created" → "date"); looked up case aside (`type(of:)`).
        var types: [String: String] = [:]
        /// A note opens for editing (app.json defaultViewMode "source", Obsidian's default) or for reading ("preview").
        var editByDefault = true
        /// app.json's spellcheck, and what Tab puts in (a tab, or tabSize spaces when useTab is off).
        var spellcheck = true
        var tab = "\t"
        /// (2026-11-08) The enabled community plugins with a styles.css (Vault Agent's draws its embeds).
        var plugins: [String] = []

        /// A property's type from types.json, its name's case aside.
        func type(of key: String) -> String? {
            types[key] ?? types.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
        }
    }

    /// The vault the folder is in: the nearest folder up holding `.obsidian`.
    static func vault(of folder: URL) -> URL? {
        var place = folder.standardizedFileURL
        for _ in 0 ..< 12 {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: place.appendingPathComponent(".obsidian").path, isDirectory: &isFolder), isFolder.boolValue { return place }
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
        look.interfaceFont = appearance["interfaceFontFamily"] as? String ?? ""
        var css: [String] = []
        if let theme = appearance["cssTheme"] as? String, !theme.isEmpty,
           let text = try? String(contentsOf: settings.appendingPathComponent("themes/\(theme)/theme.css"), encoding: .utf8) { css.append(text) }
        for snippet in appearance["enabledCssSnippets"] as? [String] ?? [] {
            if let text = try? String(contentsOf: settings.appendingPathComponent("snippets/\(snippet).css"), encoding: .utf8) { css.append(text) }
        }
        look.css = css.joined(separator: "\n")
        // (2026-11-08) Your enabled plugins that dress things (their styles.css), as Obsidian loads them.
        if let data = try? Data(contentsOf: settings.appendingPathComponent("community-plugins.json")),
           let enabled = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            look.plugins = enabled.compactMap { $0 as? String }.filter { id in
                !id.contains("/") && !id.contains("\\") && FileManager.default.fileExists(atPath: settings.appendingPathComponent("plugins/\(id)/styles.css").path)
            }
        }
        // (2026-11-07) The reading view's own settings from app.json, Obsidian's default where it keeps none.
        func flag(_ name: String) -> Bool { (appSetting(vault, name) as? NSNumber).map { $0.boolValue } ?? true }
        let properties = appSetting(vault, "propertiesInDocument") as? String
        look.properties = properties == "hidden" || properties == "source" ? properties! : "visible"
        look.inlineTitle = flag("showInlineTitle")
        look.readable = flag("readableLineLength")
        if let data = try? Data(contentsOf: settings.appendingPathComponent("types.json")), let kept = json(data)?["types"] as? [String: Any] {
            for (key, type) in kept { if let type = type as? String { look.types[key] = type } }
        }
        look.editByDefault = appSetting(vault, "defaultViewMode") as? String != "preview"
        look.spellcheck = flag("spellcheck")
        if flag("useTab") { look.tab = "\t" } else {
            let width = (appSetting(vault, "tabSize") as? NSNumber)?.intValue ?? 4
            look.tab = String(repeating: " ", count: (1 ... 8).contains(width) ? width : 4)
        }
        return look
    }

    // MARK: The page

    /// The note as a web page in Obsidian's reading view (kept for the topic notes' list; `notePage` is the whole of it).
    static func page(note text: String, look: Look, dark: Bool) -> String { notePage(text, look: look, dark: dark) }

    /// The note as a web page in Obsidian's reading view. Links: `sage-note:<name>` for a [[wikilink]], http(s) as
    /// written. (2026-11-07, from Creative Assist) With `app` (where Obsidian's own app.css, fonts and icons are served,
    /// obsidianStyle) the page is built as Obsidian builds its reading view (the same elements and classes, the workspace
    /// around it, your size, accent and fonts on the body as Obsidian sets them) and dressed by Obsidian's stylesheet, then
    /// your theme, then your snippets, so it looks as it does in Obsidian. Without it, Sage's own look (baseCSS) stands in
    /// for app.css.
    static func notePage(_ text: String, look: Look, dark: Bool, title: String? = nil, app: String? = nil, editing: Bool = false, vault: String? = nil) -> String {
        let header = split(text).header
        let values = header.isEmpty ? [:] : Study.header(of: "---\n" + header + "\n---\n")
        let shown = bodyStart(text) > 0 && look.properties != "hidden"
        let html = noteSizer(text, look: look, title: title)
        // The note's lines go with a page you can edit, so a block opens as the text it was drawn from.
        var lines = ""
        if editing {
            let all = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            lines = "<script>window.sageLines = \(scriptJSON(all)); window.sageEdit = {\"tab\":\(scriptJSON(look.tab)),\"spellcheck\":\(look.spellcheck)};</script>"
        }
        // (2026-11-10) What the Properties table was drawn from, so a change is written only over that, in either view.
        let front = frontmatter(of: text).map(scriptJSON) ?? "null"
        lines += "<script>window.sageProps = {\"front\":\(front),\"shown\":\(look.properties == "visible"),\"words\":\(scriptJSON(propertyWords))};</script>"
        // A note's cssclasses go on its view, as in Obsidian.
        let extra = values["cssclasses"] ?? values["cssclass"] ?? []
        let classes = extra.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: " ,")) }
            .filter { matches(#"^[\w-]+$"#, $0) }.map { " " + $0 }.joined()
        let view = "markdown-preview-view markdown-rendered node-insert-event" + (look.readable ? " is-readable-line-width" : "")
            + " allow-fold-headings allow-fold-lists show-indentation-guide" + (shown ? " show-properties" : "") + classes
        return shell("<div class=\"markdown-preview-sizer markdown-preview-section\">\(html)</div>", view: view, type: "markdown", look: look, dark: dark, app: app, vault: vault, editing: editing, before: lines)
    }

    /// (2026-11-08) A page that isn't a note, a Base's views or a canvas (Study.baseHTML, canvasHTML), in the same
    /// workspace and look as a note.
    static func filePage(_ inner: String, type: String, look: Look, dark: Bool, app: String? = nil, vault: String? = nil) -> String {
        shell("<div class=\"sage-file-view\">\(inner)</div>", view: "markdown-preview-view markdown-rendered node-insert-event sage-file-page", type: type,
              look: look, dark: dark, app: app, vault: vault, editing: false, before: "")
    }

    /// A value as JSON for a script (as .NET's JsonSerializer writes it: `<`, `>`, `&` and `'` escaped, so it can't end
    /// the script it's in).
    static func scriptJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]), let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]) else { return "null" }
        var text = String(decoding: data, as: UTF8.self)
        text = String(text.dropFirst().dropLast())
        return text.replacingOccurrences(of: "<", with: "\\u003C").replacingOccurrences(of: ">", with: "\\u003E")
            .replacingOccurrences(of: "&", with: "\\u0026").replacingOccurrences(of: "'", with: "\\u0027")
    }

    /// The page around what's shown: Obsidian's stylesheet (or Sage's stand-in), your enabled plugins' styles.css (served
    /// from the vault, as Obsidian loads them), your theme and snippets, the body as Obsidian sets it, and the workspace
    /// Obsidian puts around a view, so a theme's rules for it apply here too.
    private static func shell(_ content: String, view: String, type: String, look: Look, dark: Bool, app: String?, vault: String?, editing: Bool, before: String) -> String {
        let size = Int(look.fontSize)
        var style = "--font-text-size: \(size)px;" + accentStyle(look.accent)
        if !look.interfaceFont.isEmpty { style += " --font-interface-override: \(fontList(look.interfaceFont));" }
        if !look.textFont.isEmpty { style += " --font-text-override: \(fontList(look.textFont)); --font-print-override: \(fontList(look.textFont));" }
        if !look.monospaceFont.isEmpty { style += " --font-monospace-override: \(fontList(look.monospaceFont));" }
        // As Obsidian's body is on the Mac: mod-macos (themes pick their Mac fonts by it), frameless with its title bar
        // hidden (no room left for it), and no styled-scrollbars (Obsidian sets it everywhere but macOS).
        let bodyClass = "\(dark ? "theme-dark" : "theme-light") mod-macos is-frameless is-hidden-frameless obsidian-app is-focused\(look.inlineTitle ? " show-inline-title" : "")"
        let styles = app.map { "<link rel=\"stylesheet\" href=\"\(attribute($0))app.css\"><style>\(sageCSS)</style><script src=\"\(attribute($0))icons.js\"></script>" }
            ?? "<style>\(baseCSS)\n\(sageCSS)</style>"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        let plugins = vault.map { vault in look.plugins.map { id in
            "<link rel=\"stylesheet\" href=\"\(attribute(vault)).obsidian/plugins/\(id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)/styles.css\">"
        }.joined() } ?? ""
        return "<!doctype html><html style=\"font-size: calc(\(size)px * var(--preferred-text-scale, 1));\"><head><meta charset=\"utf-8\">\(styles)\(plugins)"
            + "<style>\(look.css)</style><style>\(afterTheme)</style></head>\n"
            + "<body class=\"\(bodyClass)\" style=\"\(attribute(style))\"\(editing ? " data-sage-edit" : "")>\(before)<div class=\"app-container\"><div class=\"horizontal-main-container\"><div class=\"workspace\">"
            + "<div class=\"workspace-split mod-vertical mod-root\"><div class=\"workspace-tabs mod-top mod-active\"><div class=\"workspace-tab-container\">"
            + "<div class=\"workspace-leaf mod-active\"><div class=\"workspace-leaf-content is-read-mode\" data-type=\"\(type)\" data-mode=\"preview\"><div class=\"view-content\">"
            + "<div class=\"markdown-reading-view\" style=\"width: 100%; height: 100%;\"><div class=\"\(view)\" tabindex=\"-1\" style=\"tab-size: 4;\">\n"
            + "\(content)</div></div>"
            + "</div></div></div></div></div></div></div></div></div><script>\(pageScript)</script></body></html>"
    }

    /// After your theme: Cupertino (and themes like it) puts "requires a newer Obsidian installer" over the page when the
    /// engine lacks `interpolate-size`, which Obsidian's Chromium has and the Mac's WebKit doesn't; the page is fine.
    /// And a picture opened full size (`pageScript`'s viewer).
    static let afterTheme = """
    .mod-root::before { content: none !important; display: none !important; }
    .markdown-preview-view img:not(.video-embed img), .canvas-node-content img { cursor: zoom-in; }
    #sage-viewer { position: fixed; inset: 0; z-index: 9999; background: rgba(0, 0, 0, .9); cursor: zoom-out; animation: sage-viewer-in .14s ease-out; }
    #sage-viewer .sv-stage { position: absolute; inset: 24px 72px 48px; display: flex; align-items: center; justify-content: center; }
    #sage-viewer.sv-single .sv-stage { inset: 24px 24px 48px; }
    #sage-viewer .sv-stage img, #sage-viewer .sv-stage video { max-width: 100%; max-height: 100%; object-fit: contain; border-radius: 6px; box-shadow: 0 10px 40px rgba(0,0,0,.6); }
    #sage-viewer .sv-stage video { cursor: default; background: #000; }
    #sage-viewer .sv-prev, #sage-viewer .sv-next { position: absolute; top: 50%; transform: translateY(-50%); width: 44px; height: 64px; border: 0; border-radius: 10px;
      background: rgba(255,255,255,.08); color: #fff; font-size: 34px; line-height: 1; cursor: pointer; }
    #sage-viewer .sv-prev { left: 14px; } #sage-viewer .sv-next { right: 14px; }
    #sage-viewer .sv-prev:hover:not(:disabled), #sage-viewer .sv-next:hover:not(:disabled) { background: rgba(255,255,255,.18); }
    #sage-viewer button:disabled { opacity: .2; cursor: default; }
    #sage-viewer.sv-single .sv-prev, #sage-viewer.sv-single .sv-next { display: none; }
    #sage-viewer .sv-bar { position: absolute; left: 0; right: 0; bottom: 14px; display: flex; gap: 12px; justify-content: center; align-items: baseline;
      color: rgba(255,255,255,.75); font-size: 13px; cursor: default; }
    #sage-viewer .sv-count { font-variant-numeric: tabular-nums; color: #fff; }
    @keyframes sage-viewer-in { from { opacity: 0; } }
    .video-embed.sage-playing .play { display: none; }
    body.reduce-motion #sage-viewer { animation: none; }
    """

    /// What the page's sizer holds, its header (inline title and properties) and the note's blocks, each with the lines it
    /// came from. Also sent on its own to a page you're editing, so it redraws in place after an edit.
    static func noteSizer(_ text: String, look: Look, title: String?) -> String {
        let header = split(text).header
        let start = bodyStart(text)
        let shown = start > 0 && look.properties != "hidden"
        var top = title != nil && look.inlineTitle ? "<div class=\"inline-title\" contenteditable=\"true\" spellcheck=\"false\" tabindex=\"-1\">\(escape(title!))</div>" : ""
        if shown && look.properties != "source" {
            top += properties(header, types: look.types).replacingOccurrences(of: "<div class=\"metadata-container\"",
                                                                              with: "<div data-sage-from=\"1\" data-sage-to=\"\(start - 2)\" class=\"metadata-container\"")
        }
        var html = "<div class=\"markdown-preview-pusher\" style=\"width: 1px; height: 0.1px; margin-bottom: 0px;\"></div>"
        if !top.isEmpty { html += "<div class=\"mod-header mod-ui\">\(top)</div>" }
        if shown && look.properties == "source" {
            html += "<div class=\"el-pre\" data-sage-from=\"0\" data-sage-to=\"\(start - 1)\"><pre class=\"frontmatter language-yaml\"><code class=\"language-yaml is-loaded\">---\n\(escape(header))\n---</code></pre></div>"
        }
        return html + markdown(split(text).body, sections: true, offset: start)
    }

    private static func trimmedST(_ text: String) -> String { text.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }
    private static func trimmedST(_ text: Substring) -> String { trimmedST(String(text)) }

    /// The line the note's body starts on, after its YAML header (0 when it has none).
    static func bodyStart(_ text: String) -> Int {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard trimmedST(lines[0]) == "---", let end = lines.indices.dropFirst().first(where: { trimmedST(lines[$0]) == "---" }) else { return 0 }
        return end + 1
    }

    /// (2026-11-07) The note with lines `from`...`to` (0-based, both included) replaced by `text`, only when they still read
    /// `original` (else nil: the note changed since the page was drawn). `from` = `to` + 1 inserts; at the end of a note, a
    /// new block is kept apart from the one before it by an empty line, as Markdown needs. With the lines the new text is
    /// on now (to = from - 1 when it was emptied).
    static func editLines(_ note: String, from: Int, to: Int, original: String, text: String) -> (text: String, from: Int, to: Int)? {
        var lines = note.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard from >= 0, to >= from - 1, to < lines.count, from <= lines.count else { return nil }
        guard lines[from ..< to + 1].joined(separator: "\n") == original.replacingOccurrences(of: "\r\n", with: "\n") else { return nil }
        var with = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if text.isEmpty { with = [] }
        let count = with.count
        // A new block: an empty line before it (unless the note is empty or ends with one).
        let spaced = to == from - 1 && count > 0 && from > 0 && !lines[from - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if spaced { with.insert("", at: 0) }
        lines.replaceSubrange(from ..< to + 1, with: with)
        let start = from + (spaced ? 1 : 0)
        return (lines.joined(separator: "\n"), start, start + count - 1)
    }

    /// A task's box ticked or cleared on its line ("- [ ] a" ↔ "- [x] a", also inside a callout); nil if it isn't a task.
    static func toggleTask(_ note: String, line: Int) -> String? {
        var lines = note.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard line >= 0, line < lines.count,
              let task = firstMatch(#"^(\s*(?:>\s*)*(?:[-*+]|\d+[.)])\s+\[)(.)(\])"#, in: lines[line]) else { return nil }
        lines[line] = task[1] + (task[2] == " " ? "x" : " ") + "]" + lines[line].dropFirst(task[0].count)
        return lines.joined(separator: "\n")
    }

    /// Your accent as Obsidian sets it, its hue, saturation and lightness on the body.
    static func accentStyle(_ accent: String) -> String {
        var hex = accent.trimmingCharacters(in: .whitespacesAndNewlines)
        while hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let rgb = Int(hex, radix: 16) else { return "" }
        let r = Double(rgb >> 16 & 255) / 255, g = Double(rgb >> 8 & 255) / 255, b = Double(rgb & 255) / 255
        let high = max(r, g, b), low = min(r, g, b), l = (high + low) / 2
        var h = 0.0, s = 0.0
        if high != low {
            let d = high - low
            s = l > 0.5 ? d / (2 - high - low) : d / (high + low)
            h = high == r ? (g - b) / d + (g < b ? 6 : 0) : high == g ? (b - r) / d + 2 : (r - g) / d + 4
            h *= 60
        }
        func whole(_ x: Double) -> Int { Int(x.rounded(.toNearestOrEven)) }
        return " --accent-h: \(whole(h)); --accent-s: \(whole(s * 100))%; --accent-l: \(whole(l * 100))%;"
    }

    /// A font setting ("Inter, Segoe UI") as a CSS list, each name quoted.
    private static func fontList(_ fonts: String) -> String {
        fonts.components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            .filter { !$0.isEmpty && !$0.contains("\"") && !$0.contains(";") && !$0.contains("}") }.map { "\"\($0)\"" }.joined(separator: ", ")
    }

    /// The YAML header and the body after it.
    static func split(_ text: String) -> (header: String, body: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard trimmedST(lines[0]) == "---", let end = lines.indices.dropFirst().first(where: { trimmedST(lines[$0]) == "---" }) else { return ("", text) }
        return (lines[1 ..< end].joined(separator: "\n"), lines[(end + 1)...].joined(separator: "\n"))
    }

    /// The header as Obsidian's Properties block: each key with its type's icon and its value as Obsidian shows that type
    /// (lists and tags as pills, a date as a date, a [[link]] as the link). Types from the vault (types.json), else guessed
    /// as Obsidian guesses them.
    static func properties(_ header: String, types: [String: String] = [:]) -> String {
        let values = Study.header(of: "---\n" + header + "\n---\n")
        var order: [String] = [], listed: Set<String> = [], last: String?
        for line in header.components(separatedBy: "\n") {
            let indented = line.hasPrefix(" ") || line.hasPrefix("-")
            if indented && line.drop(while: { $0.isWhitespace }).hasPrefix("- "), let last { listed.insert(last); continue }
            if indented || line.hasPrefix("#") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = trimmedST(line[..<colon])
            last = key
            let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.hasPrefix("[") && !rest.hasPrefix("[[") { listed.insert(key) }
            if !order.contains(key) { order.append(key) }
        }
        let typesLook = Look(types: types)
        let spans = propertySpans(header.components(separatedBy: "\n"))
        let rows = order.map { key -> String in
            let list = values[key] ?? []
            let type: String
            if let kept = typesLook.type(of: key) { type = kept } else {
                switch key.lowercased() {
                case "tags", "tag": type = "tags"
                case "aliases", "alias": type = "aliases"
                case "cssclasses", "cssclass": type = "multitext"
                case _ where listed.contains(key): type = "multitext"
                case _ where list.count == 1 && matches(#"^\d{4}-\d{2}-\d{2}$"#, list[0]): type = "date"
                case _ where list.count == 1 && matches(#"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}"#, list[0]): type = "datetime"
                case _ where list.count == 1 && (list[0] == "true" || list[0] == "false"): type = "checkbox"
                case _ where list.count == 1 && isNumber(list[0]): type = "number"
                default: type = "text"
                }
            }
            let icon = ["tags": "lucide-tags", "aliases": "lucide-forward", "multitext": "lucide-list", "date": "lucide-calendar", "datetime": "lucide-clock",
                        "number": "lucide-binary", "checkbox": "lucide-check-square"][type] ?? "lucide-text"
            let first = list.first ?? ""
            // (2026-11-10) Each value is edited where it is, as in Obsidian's Properties (pageScript's `props`), unless
            // it's more than the table shows (a block or map, or several values under a one-value type): that's YAML.
            let isList = ["tags", "aliases", "multitext"].contains(type)
            let locked = spans.first { $0.key == key }?.complex ?? false || (!isList && list.count > 1)
            let still = locked ? " readonly tabindex=\"-1\"" : ""
            let value: String
            switch type {
            case "tags", "aliases", "multitext":
                value = "<div class=\"multi-select-container\" tabindex=\"-1\">"
                    + list.map { item in
                        let shown = type == "tags" ? escape(String(item.drop { $0 == "#" })) : propertyValue(item)
                        return "<div class=\"multi-select-pill\" tabindex=\"0\" data-value=\"\(attribute(item))\"><div class=\"multi-select-pill-content\"><span>\(shown)</span></div>"
                            + (locked ? "" : "<div class=\"multi-select-pill-remove-button\" data-sage-icon=\"lucide-x\"></div>") + "</div>"
                    }.joined() + (locked ? "" : "<div class=\"multi-select-input\" contenteditable=\"plaintext-only\" tabindex=\"0\"></div>") + "</div>"
            case "date": value = "<input class=\"metadata-input metadata-input-text mod-date\" type=\"date\" value=\"\(attribute(first))\"\(still)>"
            case "datetime": value = "<input class=\"metadata-input metadata-input-text mod-datetime\" type=\"datetime-local\" value=\"\(attribute(String(first.prefix(16))))\"\(still)>"
            case "number": value = "<input class=\"metadata-input metadata-input-number\" type=\"number\" value=\"\(attribute(first))\"\(still)>"
            case "checkbox": value = "<input class=\"metadata-input-checkbox\" type=\"checkbox\"\(first == "true" ? " checked" : "")\(locked ? " disabled" : "")>"
            case _ where isLink(first) && !locked: value = "<div class=\"metadata-link\">\(propertyValue(first, kind: "metadata-link-inner "))<div class=\"metadata-link-flair\" data-sage-icon=\"lucide-pencil\"></div></div>"
            default: value = "<div\(locked ? "" : " contenteditable=\"plaintext-only\"") class=\"metadata-input-longtext mod-truncate\" placeholder=\"Empty\">\(escape(first))</div>"
            }
            return "<div class=\"metadata-property\" tabindex=\"0\" data-property-key=\"\(attribute(key))\" data-property-type=\"\(type)\"\(isList ? "" : " data-value=\"\(attribute(first))\"")\(locked ? " data-sage-complex" : "")>"
                + "<div class=\"metadata-property-key\"><span class=\"metadata-property-icon\" data-sage-icon=\"\(icon)\"></span>"
                + "<input class=\"metadata-property-key-input\" type=\"text\" value=\"\(attribute(key))\" autocapitalize=\"off\" spellcheck=\"false\"></div>"
                + "<div class=\"metadata-property-value\">\(value)</div></div>"
        }
        return "<div class=\"metadata-container\" tabindex=\"-1\" data-property-count=\"\(rows.count)\"><div class=\"metadata-properties-heading\" tabindex=\"0\">"
            + "<div class=\"collapse-indicator collapse-icon\" data-sage-icon=\"right-triangle\"></div><div class=\"metadata-properties-title\">Properties</div></div>"
            + "<div class=\"metadata-content\"><div class=\"metadata-properties\">\(rows.joined())</div>"
            + "<div class=\"metadata-add-button text-icon-button\" tabindex=\"0\"><span class=\"text-button-icon\" data-sage-icon=\"lucide-plus\"></span>"
            + "<span class=\"text-button-label\">\(escape(L("Add property")))</span></div></div></div>"
    }

    /// A number as .NET reads one (thousands commas allowed, spaces around).
    private static func isNumber(_ text: String) -> Bool {
        let plain = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        return !plain.isEmpty && Double(plain) != nil && plain.lowercased() != "nan" && !plain.lowercased().contains("inf")
    }

    private static func isLink(_ value: String) -> Bool {
        matches(#"^\[\[[^\]]+\]\]$"#, value.trimmingCharacters(in: .whitespacesAndNewlines)) || value.hasPrefix("http://") || value.hasPrefix("https://")
    }

    /// A property's value as Obsidian shows it, a "[[link]]" as the link (its alias, else its name).
    private static func propertyValue(_ value: String, kind: String = "") -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return "<a class=\"\(kind)external-link\" href=\"\(attribute(value))\" rel=\"noopener nofollow\">\(escape(value))</a>"
        }
        guard let link = firstMatch(#"^\[\[([^\]|]+)(?:\|([^\]]*))?\]\]$"#, in: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return escape(value) }
        let name = link[2].isEmpty ? link[1] : link[2]
        return "<a data-href=\"\(attribute(link[1]))\" href=\"sage-note:\(attribute(link[1]))\" class=\"\(kind)internal-link\">\(escape(name))</a>"
    }

    // MARK: Markdown (what recipe notes use: headings, lists, tasks, quotes and callouts, code, tables, links and embeds)

    /// (2026-11-07, from Creative Assist) The elements Obsidian's reading view makes, so its stylesheet and your theme
    /// dress them the same: with `sections` each top-level block in its own div.el-<tag> (el-p, el-h2, el-ul, el-div for a
    /// callout…), bullets as span.list-bullet in a ul.has-list-bullet, tasks with data-task, headings with data-heading,
    /// callouts with their type, metadata (|fw2) and fold (+/-) and a slot for their icon, code with its language and copy
    /// button. Each top-level block says which lines of the note it was drawn from (data-sage-from/to, counted from
    /// `offset`), and each list item its line (data-sage-line), so a block can be edited where it is (the note view).
    static func markdown(_ text: String, sections: Bool = false, offset: Int = 0) -> String {
        var html = "", paragraph: [String] = [], lists: [(ordered: Bool, indent: Int)] = [], list = "", listTag = "ul", quote: [String] = []
        var code: [String]?, language = "", table: [String] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // The line being read, the last line with something on it before it, and where each open block started.
        var last = -1, paragraphFrom = 0, listFrom = 0, quoteFrom = 0, tableFrom = 0, codeFrom = 0

        func emit(_ tag: String, _ block: String, _ from: Int) {
            html += sections ? "<div class=\"el-\(tag)\" data-sage-from=\"\(offset + from)\" data-sage-to=\"\(offset + max(from, last))\">\(block)</div>" : block
        }
        func closeParagraph() {
            guard !paragraph.isEmpty else { return }
            emit("p", "<p dir=\"auto\">" + paragraph.map(inline).joined(separator: "<br>") + "</p>", paragraphFrom)
            paragraph = []
        }
        func popList() {
            list += "</li>" + (lists[lists.count - 1].ordered ? "</ol>" : "</ul>")
            lists.removeLast()
            if !lists.isEmpty { return }
            emit(listTag, list, listFrom)
            list = ""
        }
        func closeLists(_ indent: Int = -1) { while let open = lists.last, open.indent > indent { popList() } }
        func closeQuote() {
            guard !quote.isEmpty else { return }
            if let callout = firstMatch(#"^\[!([^\]|]+)(?:\|([^\]]*))?\]([+-]?)\s*(.*)$"#, in: quote[0]) {
                let kind = callout[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let fold = callout[3]
                var title = callout[4].trimmingCharacters(in: .whitespacesAndNewlines)
                if title.isEmpty { title = capitalized(kind.replacingOccurrences(of: "-", with: " ")) }
                let shut = fold == "-" ? " is-collapsed" : ""
                let inner = markdown(quote.dropFirst().joined(separator: "\n"), sections: false, offset: offset + quoteFrom + 1)
                emit("div", "<div data-callout-metadata=\"\(attribute(callout[2]))\" data-callout-fold=\"\(fold)\" data-callout=\"\(attribute(kind))\" class=\"callout\(fold.isEmpty ? "" : " is-collapsible")\(shut)\">"
                    + "<div class=\"callout-title\" dir=\"auto\"><div class=\"callout-icon\"></div><div class=\"callout-title-inner\">\(inline(title))</div>"
                    + (fold.isEmpty ? "" : "<div class=\"callout-fold\(shut)\" data-sage-icon=\"lucide-chevron-down\"></div>") + "</div>"
                    + (inner.isEmpty ? "" : "<div class=\"callout-content\"\(fold == "-" ? " style=\"display: none;\"" : "")>\(inner)</div>") + "</div>", quoteFrom)
            } else {
                emit("blockquote", "<blockquote dir=\"auto\">\(markdown(quote.joined(separator: "\n"), sections: false, offset: offset + quoteFrom))</blockquote>", quoteFrom)
            }
            quote = []
        }
        func cells(_ row: String) -> [String] {
            let inner = trimmedST(row).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            var parts: [String] = [], current = "", previous: Character?
            for c in inner {
                if c == "|" && previous != "\\" { parts.append(current); current = "" } else { current.append(c) }
                previous = c
            }
            parts.append(current)
            return parts.map { trimmedST($0).replacingOccurrences(of: "\\|", with: "|") }
        }
        func closeTable() {
            if table.count < 2 || !matches(#"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#, table[1]) {
                if paragraph.isEmpty { paragraphFrom = tableFrom }
                paragraph += table
                table = []
                return
            }
            let aligns = cells(table[1]).map { c in c.hasPrefix(":") && c.hasSuffix(":") ? "center" : c.hasSuffix(":") ? "right" : c.hasPrefix(":") ? "left" : "" }
            func align(_ i: Int) -> String { i < aligns.count && !aligns[i].isEmpty ? " style=\"text-align: \(aligns[i]);\"" : "" }
            let heads = cells(table[0])
            var block = "<table><thead><tr>"
            for i in heads.indices { block += "<th dir=\"auto\"\(align(i))>\(inline(heads[i]))</th>" }
            block += "</tr></thead><tbody>"
            for row in table.dropFirst(2) {
                let found = cells(row)
                block += "<tr>"
                for i in heads.indices { block += "<td dir=\"auto\"\(align(i))>\(i < found.count ? inline(found[i]) : "")</td>" }
                block += "</tr>"
            }
            emit("table", block + "</tbody></table>", tableFrom)
            table = []
        }
        func closeCode() {
            let body = code ?? []
            if language == "file-embed" || language == "html-embed" {
                let kept = body.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                let first = substitute(#"^!?\[\[|\]\]$"#, in: kept.first ?? "") { _ in "" }
                let target = (first.components(separatedBy: "|").first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let height = firstMatch(#"^height:\s*(\d+)"#, in: kept.dropFirst().joined(separator: "\n"), options: [.caseInsensitive, .anchorsMatchLines])
                emit("pre", "<div class=\"block-language-file-embed\" data-sage-embed=\"\(attribute(target))\" data-sage-height=\"\(height?[1] ?? "")\"></div>", codeFrom)
                code = nil
                return
            }
            let kind = language.isEmpty ? "" : " class=\"language-\(attribute(language))\""
            emit("pre", "<pre\(kind)><code\(language.isEmpty ? "" : " class=\"language-\(attribute(language)) is-loaded\"")>\(escape(body.joined(separator: "\n")))</code>"
                + "<button class=\"copy-code-button\" data-sage-icon=\"lucide-copy\"></button></pre>", codeFrom)
            code = nil
        }
        func closeAll() { closeParagraph(); closeLists(); closeQuote(); closeTable() }

        for at in lines.indices {
            let line = lines[at]
            if at > 0 && code == nil && !trimmedST(lines[at - 1]).isEmpty { last = at - 1 }
            if code != nil {
                if trimmedST(line).hasPrefix("```") { last = at; closeCode() } else { code?.append(line) }
                continue
            }
            let trimmed = trimmedST(line)
            if trimmed.hasPrefix("```") {
                closeAll()
                code = []
                codeFrom = at
                language = (firstMatch(#"^[\w+#.-]*"#, in: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines))?[0] ?? "").lowercased()
                continue
            }
            if trimmed.hasPrefix(">") {
                closeParagraph(); closeLists(); closeTable()
                if quote.isEmpty { quoteFrom = at }
                let rest = trimmed.dropFirst()
                quote.append(String(rest.first == " " ? rest.dropFirst() : rest))
                continue
            }
            closeQuote()
            if trimmed.hasPrefix("|") { closeParagraph(); closeLists(); if table.isEmpty { tableFrom = at }; table.append(trimmed); continue }
            closeTable()
            if trimmed.isEmpty { closeParagraph(); closeLists(); continue }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { closeAll(); last = at; emit("hr", "<hr>", at); continue }
            if let level = heading(trimmed) {
                closeAll()
                last = at
                var words = trimmedST(trimmed.dropFirst(level))
                while words.hasSuffix("#") { words.removeLast() }
                while let end = words.last, end.isWhitespace { words.removeLast() }
                emit("h\(level)", "<h\(level) data-heading=\"\(attribute(words))\" dir=\"auto\">\(inline(words))</h\(level)>", at)
                continue
            }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            if let (ordered, rest) = item(trimmed) {
                closeParagraph()
                closeLists(indent)
                if let open = lists.last, open.indent == indent, open.ordered == ordered { list += "</li>" } else {
                    if let open = lists.last, open.indent == indent { popList() }
                    if lists.isEmpty { listTag = ordered ? "ol" : "ul"; listFrom = at }
                    list += ordered ? "<ol>" : "<ul class=\"has-list-bullet\">"
                    lists.append((ordered, indent))
                }
                let bullet = ordered ? "" : "<span class=\"list-bullet\"></span>"
                if let task = firstMatch(#"^\[(.)\] "#, in: rest) {
                    let mark = task[1], done = mark != " "
                    list += "<li data-task=\"\(done ? attribute(mark) : "")\" class=\"task-list-item\(done ? " is-checked" : "")\" dir=\"auto\" data-sage-line=\"\(offset + at)\">\(bullet)"
                        + "<input type=\"checkbox\" class=\"task-list-item-checkbox\"\(done ? " checked" : "")>\(inline(String(rest.dropFirst(task[0].count))))"
                } else {
                    list += "<li dir=\"auto\" data-sage-line=\"\(offset + at)\">\(bullet)\(inline(rest))"
                }
                continue
            }
            if !lists.isEmpty && indent > 0 { list += "<br>" + inline(trimmed); continue }
            closeLists()
            if paragraph.isEmpty { paragraphFrom = at }
            paragraph.append(trimmed)
        }
        last = code != nil ? lines.count - 1 : (lines.lastIndex { !trimmedST($0).isEmpty } ?? -1)
        if code != nil { closeCode() }
        closeAll()
        return html
    }

    private static func capitalized(_ word: String) -> String { word.isEmpty ? word : word.prefix(1).uppercased() + word.dropFirst() }

    private static func heading(_ line: String) -> Int? {
        let marks = line.prefix { $0 == "#" }.count
        return (1 ... 6).contains(marks) && line.dropFirst(marks).first == " " ? marks : nil
    }

    /// A list item's kind and text: "- a", "* a", "+ a", "1. a", "1) a".
    private static func item(_ line: String) -> (ordered: Bool, text: String)? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " { return (false, String(line.dropFirst(2))) }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, case let rest = line.dropFirst(digits.count), let mark = rest.first, ".)".contains(mark), rest.dropFirst().first == " " else { return nil }
        return (true, String(rest.dropFirst(2)))
    }

    /// Bold, italics, strikes, highlights, code, links, pictures, [[wikilinks]], embeds and #tags inside a line.
    static func inline(_ text: String) -> String {
        var codes: [String] = []
        // Code first, kept away from every other rule.
        var line = substitute(#"`([^`]+)`"#, in: text) { g in codes.append("<code>\(escape(g[1]))</code>"); return "\u{1}\(codes.count - 1)\u{2}" }
        line = escape(line)
        line = substitute(#"!\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#, in: line) { g in
            "<span class=\"internal-embed\"\(g[2].isEmpty ? "" : " alt=\"\(attribute(unescape(g[2])))\"")><a class=\"internal-link\" href=\"sage-note:\(attribute(unescape(g[1])))\">\(g[1])</a></span>"
        }
        line = substitute(#"\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#, in: line) { g in
            "<a data-href=\"\(attribute(unescape(g[1])))\" href=\"sage-note:\(attribute(unescape(g[1])))\" class=\"internal-link\">\(g[2].isEmpty ? g[1] : g[2])</a>"
        }
        line = substitute(#"!\[([^\]]*)\]\(([^)\s]+)\)"#, in: line) { g in
            let url = unescape(g[2])
            if let picture = thumbnail(of: url) {
                return "<a class=\"video-embed\" href=\"\(attribute(url))\"><img src=\"\(picture.absoluteString)\" alt=\"\"><span class=\"play\">▶</span></a>"
            }
            return "<img src=\"\(attribute(url))\" alt=\"\(g[1])\">"
        }
        line = substitute(#"\[([^\]]+)\]\(([^)\s]+)\)"#, in: line) { g in "<a rel=\"noopener nofollow\" class=\"external-link\" href=\"\(attribute(unescape(g[2])))\">\(g[1])</a>" }
        line = substitute(#"(^|[\s(])(https?://[^\s<]+)"#, in: line) { g in "\(g[1])<a rel=\"noopener nofollow\" class=\"external-link\" href=\"\(g[2])\">\(g[2])</a>" }
        line = substitute(#"\*\*([^*]+)\*\*"#, in: line) { "<strong>\($0[1])</strong>" }
        line = substitute(#"__([^_]+)__"#, in: line) { "<strong>\($0[1])</strong>" }
        line = substitute(#"(^|[^*])\*([^*\s][^*]*)\*"#, in: line) { "\($0[1])<em>\($0[2])</em>" }
        line = substitute(#"(^|[\s(])_([^_\s][^_]*)_"#, in: line) { "\($0[1])<em>\($0[2])</em>" }
        line = substitute(#"~~([^~]+)~~"#, in: line) { "<del>\($0[1])</del>" }
        line = substitute(#"==([^=]+)=="#, in: line) { "<mark>\($0[1])</mark>" }
        line = substitute(#"(^|\s)#([\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)"#, in: line) { "\($0[1])<a href=\"#\($0[2])\" class=\"tag\" rel=\"noopener nofollow\">#\($0[2])</a>" }
        return substitute("\u{1}(\\d+)\u{2}", in: line) { codes[Int($0[1]) ?? 0] }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }
    static func attribute(_ text: String) -> String { escape(text).replacingOccurrences(of: "\"", with: "&quot;") }
}

// MARK: The page's stylesheets and script, as Creative Assist has them (2026-11-09), with the Mac's keys and WKWebView's bridge.

extension Study {
    /// Obsidian's own reading-view look, in its CSS variables, so a theme's variables take over as in Obsidian. Sage's
    /// stand-in for app.css when Obsidian isn't installed.
    static let baseCSS = #"""
    body { --font-default: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Inter, "Apple Color Emoji", "Segoe UI Emoji", sans-serif;
      --font-monospace-default: ui-monospace, SFMono-Regular, "Cascadia Mono", "Roboto Mono", Menlo, Consolas, monospace;
      --font-text-theme: '??'; --font-monospace-theme: '??'; --font-text-override: '??'; --font-monospace-override: '??';
      --font-text: var(--font-text-override), var(--font-text-theme), var(--font-default); --font-monospace: var(--font-monospace-override), var(--font-monospace-theme), var(--font-monospace-default);
      --line-height-normal: 1.5; --file-line-width: 700px; --h1-size: 1.802em; --h2-size: 1.602em; --h3-size: 1.424em; --h4-size: 1.266em; --h5-size: 1.125em; --h6-size: 1em;
      --h1-weight: 700; --h2-weight: 600; --h3-weight: 600; --h4-weight: 600; --h5-weight: 600; --h6-weight: 600; --radius-s: 4px; --radius-m: 8px;
      --h1-color: inherit; --h2-color: inherit; --h3-color: inherit; --h4-color: inherit; --h5-color: inherit; --h6-color: inherit; --bold-color: inherit; --bold-weight: 600;
      --italic-color: inherit; --inline-title-color: var(--h1-color); --inline-title-size: var(--h1-size); --inline-title-weight: var(--h1-weight);
      --accent-h: 254; --accent-s: 80%; --accent-l: 68%; --color-accent: hsl(var(--accent-h), var(--accent-s), var(--accent-l));
      --code-white-space: pre-wrap; --link-color: var(--text-accent); --link-external-color: var(--text-accent); --callout-radius: var(--radius-s); --callout-padding: 12px 12px 12px 24px;
      --callout-border-width: 0px; --callout-border-opacity: .25; --callout-title-weight: 600; --callout-default: var(--color-blue-rgb); --callout-info: var(--color-blue-rgb);
      --callout-todo: var(--color-blue-rgb); --callout-tip: var(--color-cyan-rgb); --callout-important: var(--color-cyan-rgb); --callout-summary: var(--color-cyan-rgb);
      --callout-success: var(--color-green-rgb); --callout-question: var(--color-orange-rgb); --callout-warning: var(--color-orange-rgb); --callout-fail: var(--color-red-rgb);
      --callout-error: var(--color-red-rgb); --callout-bug: var(--color-red-rgb); --callout-example: var(--color-purple-rgb); --callout-quote: 158, 158, 158; }
    .theme-dark { --background-primary: #1e1e1e; --background-secondary: #262626; --background-modifier-border: #363636; --text-normal: #dadada; --text-muted: #b3b3b3;
      --text-faint: #666; --text-accent: var(--accent, var(--color-accent)); --interactive-accent: var(--accent, var(--color-accent)); --code-background: #2a2a2a; --tag-background: rgba(138,92,245,.15);
      --text-highlight-bg: rgba(255,208,0,.4); --blockquote-border-color: var(--interactive-accent); --scrollbar-thumb-bg: rgba(255,255,255,.1); --scrollbar-active-thumb-bg: rgba(255,255,255,.2);
      --color-red-rgb: 251, 70, 76; --color-orange-rgb: 233, 151, 63; --color-yellow-rgb: 224, 222, 113; --color-green-rgb: 68, 207, 110; --color-cyan-rgb: 83, 223, 221;
      --color-blue-rgb: 2, 122, 255; --color-purple-rgb: 168, 130, 255; --color-pink-rgb: 250, 153, 205; color-scheme: dark; }
    .theme-light { --background-primary: #ffffff; --background-secondary: #f6f6f6; --background-modifier-border: #e0e0e0; --text-normal: #222; --text-muted: #5c5c5c;
      --text-faint: #ababab; --text-accent: var(--accent, var(--color-accent)); --interactive-accent: var(--accent, var(--color-accent)); --code-background: #f5f5f5; --tag-background: rgba(138,92,245,.1);
      --text-highlight-bg: rgba(255,208,0,.4); --blockquote-border-color: var(--interactive-accent); --scrollbar-thumb-bg: rgba(0,0,0,.1); --scrollbar-active-thumb-bg: rgba(0,0,0,.2);
      --color-red-rgb: 233, 49, 71; --color-orange-rgb: 236, 117, 0; --color-yellow-rgb: 224, 172, 0; --color-green-rgb: 8, 185, 78; --color-cyan-rgb: 0, 191, 188;
      --color-blue-rgb: 8, 109, 221; --color-purple-rgb: 120, 82, 238; --color-pink-rgb: 213, 57, 132; color-scheme: light; }
    html, body { margin: 0; background: var(--background-primary); color: var(--text-normal); font-family: var(--font-text); font-size: var(--font-text-size); line-height: var(--line-height-normal); }
    ::-webkit-scrollbar { width: 12px; height: 12px; background: transparent; } ::-webkit-scrollbar-corner { background: transparent; }
    ::-webkit-scrollbar-thumb { background-color: var(--scrollbar-thumb-bg); border: 3px solid transparent; border-radius: 12px; background-clip: padding-box; }
    ::-webkit-scrollbar-thumb:hover, ::-webkit-scrollbar-thumb:active { background-color: var(--scrollbar-active-thumb-bg); }
    .markdown-preview-view { padding: 28px 36px 60px; }
    .is-readable-line-width .markdown-preview-sizer { max-width: var(--file-line-width); margin: 0 auto; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 1.2em 0 .5em; }
    h1 { font-size: var(--h1-size); font-weight: var(--h1-weight); color: var(--h1-color); } h2 { font-size: var(--h2-size); font-weight: var(--h2-weight); color: var(--h2-color); }
    h3 { font-size: var(--h3-size); font-weight: var(--h3-weight); color: var(--h3-color); } h4 { font-size: var(--h4-size); font-weight: var(--h4-weight); color: var(--h4-color); }
    h5 { font-size: var(--h5-size); font-weight: var(--h5-weight); color: var(--h5-color); } h6 { font-size: var(--h6-size); font-weight: var(--h6-weight); color: var(--h6-color); }
    strong { font-weight: var(--bold-weight); color: var(--bold-color); } em { color: var(--italic-color); }
    p { margin: .6em 0; } a { color: var(--link-color); text-decoration: none; } a:hover { text-decoration: underline; }
    a.external-link { background: none; color: var(--link-external-color); } a.internal-link { text-decoration: underline; text-decoration-color: color-mix(in srgb, var(--link-color) 40%, transparent); }
    ul, ol { padding-inline-start: 1.6em; margin: .4em 0; } li { margin: .15em 0; } li::marker { color: var(--text-faint); }
    .task-list-item { list-style: none; margin-inline-start: -1.4em; } .task-list-item-checkbox { margin-inline-end: .5em; accent-color: var(--interactive-accent); }
    .task-list-item.is-checked { color: var(--text-muted); text-decoration: line-through; }
    blockquote { margin: .8em 0; padding: .1em 1em; border-inline-start: 2px solid var(--blockquote-border-color); color: var(--text-muted); }
    .callout { --callout-color: var(--callout-default); margin: 1em 0; padding: var(--callout-padding); border-radius: var(--callout-radius);
      background-color: rgba(var(--callout-color), .1); border: var(--callout-border-width) solid rgba(var(--callout-color), var(--callout-border-opacity)); }
    .callout-title { font-weight: var(--callout-title-weight); color: rgb(var(--callout-color)); margin-bottom: .3em; } .callout-content > :first-child { margin-top: 0; }
    .callout:is([data-callout="info"],[data-callout="note"]) { --callout-color: var(--callout-info); } .callout[data-callout="todo"] { --callout-color: var(--callout-todo); }
    .callout:is([data-callout="tip"],[data-callout="hint"],[data-callout="important"]) { --callout-color: var(--callout-tip); }
    .callout:is([data-callout="abstract"],[data-callout="summary"],[data-callout="tldr"]) { --callout-color: var(--callout-summary); }
    .callout:is([data-callout="success"],[data-callout="check"],[data-callout="done"]) { --callout-color: var(--callout-success); }
    .callout:is([data-callout="question"],[data-callout="help"],[data-callout="faq"]) { --callout-color: var(--callout-question); }
    .callout:is([data-callout="warning"],[data-callout="caution"],[data-callout="attention"]) { --callout-color: var(--callout-warning); }
    .callout:is([data-callout="failure"],[data-callout="fail"],[data-callout="missing"]) { --callout-color: var(--callout-fail); }
    .callout:is([data-callout="danger"],[data-callout="error"]) { --callout-color: var(--callout-error); } .callout[data-callout="bug"] { --callout-color: var(--callout-bug); }
    .callout[data-callout="example"] { --callout-color: var(--callout-example); } .callout:is([data-callout="quote"],[data-callout="cite"]) { --callout-color: var(--callout-quote); }
    code { font-family: var(--font-monospace); font-size: .875em; background: var(--code-background); padding: .1em .3em; border-radius: var(--radius-s); }
    pre { background: var(--code-background); padding: 12px 14px; border-radius: var(--radius-s); overflow-x: auto; }
    pre code { background: none; padding: 0; white-space: var(--code-white-space); overflow-wrap: anywhere; }
    mark { background: var(--text-highlight-bg); color: inherit; } hr { border: none; border-top: 1px solid var(--background-modifier-border); margin: 1.6em 0; }
    table { border-collapse: collapse; margin: 1em 0; } th, td { border: 1px solid var(--background-modifier-border); padding: 4px 10px; } th { background: var(--background-secondary); }
    img { max-width: 100%; border-radius: var(--radius-s); }
    .inline-title[contenteditable] { cursor: text; outline: none; } .inline-title[contenteditable]:empty::before { content: 'Untitled'; color: var(--text-faint); }
    .inline-title { font-size: var(--inline-title-size, var(--h1-size)); font-weight: var(--inline-title-weight, 700); line-height: 1.2; margin: 0 0 .6em; color: var(--inline-title-color, var(--text-normal)); }
    pre.frontmatter { color: var(--text-muted); }
    a.tag { background: var(--tag-background); color: var(--text-accent); padding: .1em .55em; border-radius: 1em; font-size: .875em; }
    .metadata-container { margin: 0 0 1.4em; padding-bottom: .8em; border-bottom: 1px solid var(--background-modifier-border); font-size: .875em; }
    .metadata-properties-heading { color: var(--text-muted); font-weight: 600; margin-bottom: .4em; cursor: pointer; } .metadata-container.is-collapsed .metadata-content { display: none; }
    .metadata-property { display: flex; gap: 12px; padding: 3px 0; } .metadata-property-key { width: 130px; flex: none; color: var(--text-muted); display: flex; gap: 6px; align-items: center; }
    .metadata-property-key-input, .metadata-input { background: none; border: none; color: inherit; font: inherit; padding: 0; width: 100%; outline: none; }
    .metadata-property-value { color: var(--text-normal); overflow-wrap: anywhere; flex: 1; }
    .multi-select-pill { display: inline-block; background: var(--tag-background); color: var(--text-accent); padding: 0 .55em; border-radius: 1em; margin: 0 4px 2px 0; }
    .multi-select-container { display: flex; flex-wrap: wrap; align-items: center; min-height: 1.5em; cursor: text; }
    .multi-select-pill { display: inline-flex; align-items: center; gap: 3px; } .multi-select-pill-content { display: inline; }
    .multi-select-pill-remove-button { display: inline-flex; cursor: pointer; opacity: .6; } .multi-select-pill-remove-button:hover { opacity: 1; }
    .multi-select-pill-remove-button .svg-icon { width: 11px; height: 11px; } .multi-select-input { flex: 1; min-width: 3em; outline: none; }
    .metadata-input-longtext { outline: none; min-height: 1.4em; cursor: text; } .metadata-input-longtext:empty::before { content: attr(placeholder); color: var(--text-faint); }
    .metadata-property-icon { display: inline-flex; cursor: pointer; } .metadata-property-icon .svg-icon { width: 14px; height: 14px; }
    .metadata-add-button { display: inline-flex; align-items: center; gap: 6px; padding: 3px 0; color: var(--text-faint); cursor: pointer; } .metadata-add-button:hover { color: var(--text-muted); }
    .metadata-add-button .svg-icon { width: 14px; height: 14px; }
    .menu { background: var(--background-secondary); border: 1px solid var(--background-modifier-border); border-radius: 8px; padding: 4px; box-shadow: 0 6px 24px rgba(0,0,0,.35); font-size: 13px; color: var(--text-normal); }
    .menu-item { display: flex; align-items: center; gap: 8px; padding: 4px 10px; border-radius: 4px; cursor: pointer; } .menu-item:hover { background: var(--background-modifier-hover); }
    .menu-item.is-label { color: var(--text-muted); cursor: default; font-size: 12px; } .menu-item.is-label:hover { background: none; } .menu-item.is-warning { color: var(--text-error, #e5484d); }
    .menu-item-icon { display: inline-flex; } .menu-item-icon .svg-icon { width: 14px; height: 14px; } .menu-separator { height: 1px; margin: 4px 0; background: var(--background-modifier-border); }
    .list-bullet, .copy-code-button { display: none; } .callout.is-collapsible > .callout-title { cursor: pointer; }
    """#

    /// What Sage adds to either look: its card for a YouTube video (Obsidian plays it in place), and editing in place.
    static let sageCSS = #"""
    .video-embed { position: relative; display: block; max-width: 560px; aspect-ratio: 16 / 9; border-radius: var(--radius-m, 8px); overflow: hidden; margin: 1em 0; background: #000; }
    .video-embed img { width: 100%; height: 100%; object-fit: cover; border-radius: 0; opacity: .9; }
    .video-embed .play { position: absolute; inset: 0; margin: auto; width: 64px; height: 44px; border-radius: 12px; background: rgba(255,0,0,.88); color: #fff;
      display: flex; align-items: center; justify-content: center; font-size: 20px; }
    body[data-sage-edit] .markdown-preview-sizer [data-sage-from] { cursor: text; }
    body[data-sage-edit] .markdown-preview-sizer { padding-bottom: 35vh; }
    /* The Properties table, edited in place (2026-11-10): its YAML from the corner button, the icon's menu where it was pressed. */
    body[data-sage-edit] .metadata-container[data-sage-from] { position: relative; cursor: default; }
    .metadata-container .metadata-property-icon { cursor: pointer; } .metadata-container .metadata-add-button { cursor: pointer; }
    .metadata-property[data-sage-complex] .metadata-property-value { cursor: default; }
    .sage-menu { position: fixed; z-index: 10000; min-width: 170px; } .sage-menu .sage-menu-check { margin-left: auto; }
    .sage-editing { margin: var(--p-spacing, 1em) 0; }
    .sage-source { display: block; box-sizing: border-box; width: calc(100% + 16px); margin: 0 -8px; padding: 6px 8px; resize: none; overflow: hidden;
      border: none; outline: none; border-radius: var(--radius-s, 4px); background: var(--background-primary-alt, rgba(127,127,127,.08));
      box-shadow: 0 0 0 1px var(--background-modifier-border-focus, var(--interactive-accent, #7f6df2));
      color: var(--text-normal); font-family: var(--font-text); font-size: var(--font-text-size); line-height: var(--line-height-normal); tab-size: 4;
      caret-color: var(--caret-color, var(--text-normal)); }
    .sage-source[readonly] { opacity: .7; }
    /* Editing looks as Obsidian's Live Preview does (2026-11-09): no box around the block, the text staying exactly where
       it was, and only the line the caret is on lit (a box drawn round the block first clicked kept growing with Enter). */
    .sage-editing > .sage-live { margin: 0; padding: 0; background: none; box-shadow: none; border-radius: 0; }
    .sage-live .cm-line.cm-active { background: var(--sage-active-line, rgba(127, 127, 127, .07)); box-shadow: -8px 0 0 var(--sage-active-line, rgba(127, 127, 127, .07)), 8px 0 0 var(--sage-active-line, rgba(127, 127, 127, .07)); border-radius: 2px; }
    .sage-live, .sage-live .cm-editor, .sage-live .cm-scroller, .sage-live .cm-contentContainer { height: auto; margin: 0; padding: 0 !important; overflow: visible; background: none; border: none; }
    .sage-live { display: block; width: 100%; min-width: 0; }
    .sage-ghost { position: fixed; z-index: 30; pointer-events: none; white-space: pre; color: var(--text-faint); opacity: 0.8; }
    .sage-live .cm-editor, .sage-live .cm-scroller, .sage-live .cm-contentContainer, .sage-live .cm-content { display: block !important; width: 100% !important; min-width: 0; flex: none !important; position: static; }
    .sage-live .cm-content { outline: none; white-space: pre-wrap; overflow-wrap: anywhere; padding: 0 !important; min-height: 1.5em; max-width: none !important;
      font-family: var(--font-text); font-size: var(--font-text-size); line-height: var(--line-height-normal); tab-size: 4; caret-color: var(--caret-color, var(--text-normal)); color: var(--text-normal); }
    .sage-live .cm-content[contenteditable="false"] { opacity: .7; }
    .sage-live .cm-line { padding: 0 !important; }
    .sage-live .list-bullet { float: none; margin-inline-start: 0; display: inline-flex; }
    .sage-live .HyperMD-task-line .list-bullet { display: none; }
    .sage-live .cm-line:not(.cm-active) .cm-formatting:not(.cm-formatting-list):not(.cm-formatting-task):not(.sage-hr):not(.cm-formatting-code-block),
    .sage-live .cm-line:not(.cm-active) .sage-hide { display: none; }
    .sage-live .cm-formatting { color: var(--text-faint); }
    .sage-live .cm-strong { font-weight: var(--bold-weight, 600); color: var(--bold-color, inherit); }
    .sage-live .cm-em { font-style: italic; color: var(--italic-color, inherit); }
    .sage-live .cm-highlight { background-color: var(--text-highlight-bg); color: var(--text-normal); }
    .sage-live .cm-hmd-internal-link, .sage-live .cm-link { color: var(--link-color); }
    .sage-live .cm-url { color: var(--link-external-color); }
    .sage-live .cm-line:not(.cm-active) [data-sage-link] { cursor: pointer; }
    .sage-live .cm-hashtag { background-color: var(--tag-background); color: var(--tag-color, var(--text-accent)); }
    .sage-live .cm-hashtag-begin { border-radius: var(--tag-radius, 2em) 0 0 var(--tag-radius, 2em); padding-left: .55em; }
    .sage-live .cm-hashtag-end { border-radius: 0 var(--tag-radius, 2em) var(--tag-radius, 2em) 0; padding-right: .55em; }
    .sage-live .HyperMD-quote { position: relative; padding-inline-start: 1em !important; }
    .sage-live .cm-line:not(.cm-active) .sage-task { font-size: 0; display: inline-block; width: 15px; height: 15px; margin-inline-end: .5em; vertical-align: -2px; cursor: pointer;
      border: 1px solid var(--checkbox-border-color, var(--text-faint)); border-radius: var(--checkbox-radius, 4px); position: relative; }
    .sage-live .cm-line:not(.cm-active) .sage-task.is-checked { background: var(--checkbox-color, var(--interactive-accent)); border-color: var(--checkbox-color, var(--interactive-accent)); }
    .sage-live .cm-line:not(.cm-active) .sage-task.is-checked::after { content: ''; position: absolute; left: 4px; top: 1px; width: 4px; height: 8px; border: solid var(--checkbox-marker-color, #fff); border-width: 0 2px 2px 0; transform: rotate(45deg); }
    .sage-live .HyperMD-task-line:not([data-task=" "]) .cm-list-1, .sage-live .HyperMD-task-line:not([data-task=" "]) [class^="cm-list-"] { color: var(--checklist-done-color, var(--text-muted)); text-decoration: var(--checklist-done-decoration, line-through); }
    .sage-live .cm-line.hr:not(.cm-active) .sage-hr { display: block; font-size: 0; height: 0; margin: .9em 0; border-top: var(--hr-thickness, 1px) solid var(--hr-color, var(--background-modifier-border)); }
    .sage-notice { position: fixed; left: 50%; bottom: 18px; transform: translateX(-50%); max-width: 80%; padding: 8px 14px; border-radius: 8px; z-index: 10;
      background: var(--background-secondary, #333); color: var(--text-normal); box-shadow: 0 4px 18px rgba(0,0,0,.35); font-family: var(--font-interface, sans-serif); font-size: 13px; }
    .sage-file-page { padding: 20px 28px; } .sage-file-view { height: 100%; }
    .sage-base { margin: var(--p-spacing, 1em) 0; font-family: var(--font-interface, inherit); }
    .sage-file-view > .sage-base { margin: 0; }
    .sage-base .bases-header { height: auto; min-height: 0; padding: 0; border: none; } .sage-base .bases-toolbar { padding: 0 0 8px; flex-wrap: nowrap; gap: 6px; }
    .sage-base-tabs { display: flex; flex-wrap: nowrap; gap: 2px; min-width: 0; overflow-x: auto; scrollbar-width: none; }
    .sage-base-tabs::-webkit-scrollbar { display: none; } .sage-base-tab { flex: none; white-space: nowrap; }
    .sage-base-tab { display: inline-flex; align-items: center; gap: 6px; height: auto; user-select: none; padding: 4px 10px; border: none; border-radius: var(--radius-s, 4px); box-shadow: none;
      background: transparent; color: var(--text-muted); font: inherit; font-size: var(--font-ui-small, 13px); cursor: pointer; }
    .sage-base-tab:hover { background: var(--background-modifier-hover); color: var(--text-normal); }
    .sage-base-tab.is-active { background: var(--background-modifier-hover); color: var(--text-normal); font-weight: var(--font-semibold, 600); }
    .sage-base-tab .svg-icon { width: 14px; height: 14px; }
    .sage-base-add-view { flex: none; display: inline-flex; align-items: center; padding: 4px 6px; margin-left: 2px; color: var(--text-faint); border-radius: var(--radius-s, 4px); cursor: pointer; }
    .sage-base-add-view:hover { color: var(--text-normal); background: var(--background-modifier-hover); } .sage-base-add-view .svg-icon { width: 14px; height: 14px; }
    .sage-base-tab-name[contenteditable] { outline: none; cursor: text; box-shadow: 0 0 0 1px var(--interactive-accent); border-radius: 3px; padding: 0 3px; }
    .sage-file-view > [data-sage-base] .sage-base-table thead th { cursor: pointer; } .sage-base-table th[data-sage-sort] { color: var(--text-normal) !important; }
    .sage-view-menu { position: fixed; z-index: 60; min-width: 190px; animation: sage-menu-in 0.12s ease-out; } .sage-view-menu .menu-item.is-disabled { opacity: 0.4; pointer-events: none; }
    .sage-view-menu .menu-scroll { max-height: 60vh; overflow-y: auto; }
    @keyframes sage-menu-in { from { opacity: 0; transform: translateY(-4px) scale(0.98); } to { opacity: 1; transform: none; } }
    .sage-file-view > [data-sage-base] .sage-base-tab { cursor: grab; }
    .sage-base-tabs.is-sorting .sage-base-tab { cursor: grabbing; }
    .sage-base-tab.is-dragging { position: relative; z-index: 5; background: var(--background-secondary); color: var(--text-normal); box-shadow: 0 6px 18px rgba(0, 0, 0, 0.35), 0 0 0 1px var(--background-modifier-border-hover); scale: 1.04; transition: scale 0.15s ease, box-shadow 0.15s ease; }
    .sage-base-tab.is-settling { transition: transform 0.18s cubic-bezier(0.2, 0.8, 0.3, 1), scale 0.18s ease, box-shadow 0.18s ease; }
    .sage-base .bases-toolbar-result-count { margin-left: auto; flex: none; white-space: nowrap; font-size: var(--font-ui-smaller, 12px); color: var(--text-muted); }
    .sage-base .bases-view { padding: 0; overflow-x: auto; overflow-y: visible; }
    .sage-base-table { border-collapse: separate !important; border-spacing: 0 !important; border: none !important; border-radius: 0 !important; width: 100%; min-width: 100%; margin: 0 !important;
      font-size: var(--bases-table-font-size, var(--font-ui-small, 14px)); }
    .sage-base-table th, .sage-base-table td { border: none !important; border-bottom: 1px solid var(--background-modifier-border) !important; padding: 6px 10px !important;
      text-align: left; vertical-align: top; background: none !important; min-width: 7em; }
    .sage-base-table thead th { color: var(--text-muted) !important; font-weight: var(--font-medium, 500) !important; white-space: nowrap; }
    .sage-base-table tr:hover td { background: var(--background-modifier-hover) !important; }
    .sage-base-table .sage-base-group-row:hover td { background: none !important; }
    .sage-base-table .bases-table-header-icon { display: inline-flex; vertical-align: -2px; margin-right: 6px; } .sage-base-table .bases-table-header-icon .svg-icon { width: 14px; height: 14px; }
    .sage-base-table .sage-base-group-row td { padding: 16px 10px 6px !important; border-bottom: none !important; }
    .sage-base-table tbody.sage-collapsed tr.sage-base-row { display: none; }
    .sage-base .bases-group-heading { display: flex; align-items: center; gap: 8px; cursor: pointer; }
    .sage-base .bases-group-heading .collapse-icon .svg-icon { width: 14px; height: 14px; transition: transform .15s; }
    .sage-base .bases-group-count { color: var(--text-faint); font-size: var(--font-ui-smaller, 12px); }
    .sage-base-none { color: var(--text-faint); } .sage-base .sage-base-cell { overflow-wrap: break-word; }
    .sage-base-table td[data-sage-cell] { cursor: default; } .sage-base-table td[data-sage-kind] .sage-chip { cursor: pointer; }
    .sage-base-table td.sage-cell-picked { background: rgba(var(--interactive-accent-rgb, 124, 58, 237), 0.12) !important; }
    .sage-base-table td.sage-cell-focus { box-shadow: inset 0 0 0 2px var(--interactive-accent) !important; }
    .sage-base-table td.sage-cell-focus.is-idle { box-shadow: inset 0 0 0 2px var(--background-modifier-border-hover) !important; }
    .sage-base-table input[data-sage-tick] { cursor: pointer; }
    .sage-cell-catcher { position: fixed; left: -10000px; top: 0; width: 1px; height: 1px; opacity: 0; pointer-events: none; }
    .sage-cell-editor { position: fixed; z-index: 60; box-sizing: border-box; display: flex; flex-wrap: wrap; align-items: center; gap: 2px; padding: 5px 9px; max-width: 480px;
      background: var(--background-primary); border-radius: var(--radius-s, 4px); box-shadow: 0 0 0 2px var(--interactive-accent), var(--shadow-s, 0 2px 8px rgba(0,0,0,.25)); font-family: var(--font-interface, inherit); }
    .sage-cell-editor .sage-cell-field { flex: 1 1 80px; min-width: 80px; width: 100%; margin: 0; padding: 0; border: none !important; outline: none !important; box-shadow: none !important; background: transparent !important;
      color: var(--text-normal); font: inherit; font-size: var(--font-text-size, inherit); line-height: 1.5; resize: none; height: auto; }
    .sage-cell-editor input[type=date], .sage-cell-editor input[type=datetime-local] { color-scheme: light dark; }
    .sage-cell-editor.is-picker { display: block; padding: 0; max-width: 360px; overflow: hidden; background: var(--background-secondary, var(--background-primary));
      border: 1px solid var(--background-modifier-border); border-radius: var(--radius-m, 8px); box-shadow: var(--shadow-l, 0 8px 24px rgba(0,0,0,.35)); }
    .sage-cell-top { display: flex; flex-wrap: wrap; align-items: center; gap: 4px; padding: 7px 9px; background: var(--background-modifier-form-field, var(--background-primary)); border-bottom: 1px solid var(--background-modifier-border); }
    .sage-cell-top .sage-cell-field { font-size: var(--font-ui-small, 13px) !important; }
    .sage-cell-top .sage-cell-field::placeholder { color: var(--text-faint); }
    .sage-cell-pills { display: contents; }
    .sage-chip.sage-cell-pill { display: inline-flex; align-items: center; gap: 3px; padding-right: 4px; }
    .sage-cell-pill-x { display: inline-flex; cursor: pointer; opacity: .7; } .sage-cell-pill-x:hover { opacity: 1; } .sage-cell-pill-x .svg-icon { width: 11px; height: 11px; }
    .sage-cell-menu { max-height: 280px; overflow-y: auto; padding: 4px; font-family: var(--font-interface, inherit); font-size: var(--font-ui-small, 13px); }
    .sage-cell-hint { padding: 4px 8px 6px; color: var(--text-faint); font-size: var(--font-ui-smaller, 12px); }
    .sage-cell-option { display: flex; align-items: center; gap: 6px; min-height: 28px; padding: 3px 8px; border-radius: var(--radius-s, 4px); cursor: pointer; color: var(--text-normal); }
    .sage-cell-option .sage-chip { overflow: hidden; text-overflow: ellipsis; max-width: 100%; }
    .sage-cell-option.is-lit { background: var(--background-modifier-hover); }
    .sage-cell-create { color: var(--text-muted); } .sage-cell-tick { margin-left: auto; display: inline-flex; color: var(--text-muted); } .sage-cell-tick .svg-icon { width: 14px; height: 14px; }
    .sage-base-cards-group { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; margin: 8px 0 18px; }
    .sage-base-cards-group[hidden] { display: none; }
    .sage-base-card { display: flex; flex-direction: column; padding-bottom: 10px; overflow: hidden; cursor: pointer; user-select: none;
      background-color: var(--bases-cards-background, var(--background-primary-alt)); box-shadow: var(--bases-cards-shadow, 0 0 0 1px var(--background-modifier-border));
      border-radius: var(--bases-cards-radius, 8px); transition: box-shadow .15s, transform .15s; }
    .sage-base-card:hover { box-shadow: var(--bases-cards-shadow-hover, 0 0 0 1px var(--background-modifier-border-hover)); transform: translateY(-1px); }
    .sage-card-cover { flex: none; height: var(--sage-cover); background-color: var(--bases-cards-cover-background, var(--background-modifier-hover)); background-size: cover; background-position: center; }
    .sage-card-prop { padding: 3px 12px 0; min-width: 0; }
    .sage-card-prop.is-title { padding-top: 10px; padding-bottom: 2px; font-weight: var(--font-semibold, 600); --link-color: var(--text-normal); }
    .sage-card-label { font-size: var(--font-ui-smaller, 12px); color: var(--text-muted); }
    .sage-card-line { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: var(--font-ui-small, 13px); }
    .sage-card-prop.is-title .sage-card-line { white-space: normal; font-size: var(--font-ui-medium, 15px); line-height: 1.3; }
    .sage-base-problem { color: var(--text-error); font-size: 13px; margin: 0 0 8px; }
    .sage-file-page .sage-file-view > .va-canvas-embed { position: absolute; inset: 16px; height: auto !important; }
    .pdf-embed iframe.sage-pdf { width: 100%; height: 640px; border: none; border-radius: var(--radius-s, 4px); }
    .markdown-embed .markdown-embed-link { position: absolute; top: 6px; right: 6px; color: var(--text-faint); } .markdown-embed .markdown-embed-link .svg-icon { width: 16px; height: 16px; }
    body[data-sage-edit] .markdown-preview-sizer > [data-sage-from] { position: relative; }
    .sage-edit-block { position: absolute; top: 6px; right: 6px; z-index: 5; display: flex; padding: 5px; border-radius: var(--radius-s, 4px); opacity: 0; cursor: pointer;
      color: var(--text-muted); background: var(--background-primary); box-shadow: 0 0 0 1px var(--background-modifier-border); transition: opacity .15s; }
    [data-sage-from]:hover > .sage-edit-block { opacity: 1; }
    .va-canvas-embed[data-sage-canvas] { cursor: default; }
    .va-canvas-embed[data-sage-canvas]:not([data-sage-editable]) .va-canvas-node:not(.va-canvas-group) .va-canvas-node-content { cursor: auto; }
    .va-canvas-embed[data-sage-canvas].is-hand, .va-canvas-embed[data-sage-canvas].is-hand * { cursor: grab !important; }
    .va-canvas-embed[data-sage-canvas].is-dragging, .va-canvas-embed[data-sage-canvas].is-dragging * { cursor: grabbing !important; }
    .va-canvas-embed[data-sage-editable] .va-canvas-node:not(.va-canvas-group) { cursor: default; }
    .va-canvas-embed[data-sage-editable] .va-canvas-text .va-canvas-node-content, .va-canvas-embed[data-sage-editable] .sage-canvas-note-body { cursor: text; }
    .va-canvas-embed[data-sage-editable].is-moving, .va-canvas-embed[data-sage-editable].is-moving * { cursor: move !important; }
    .va-canvas-node.is-selected { box-shadow: 0 0 0 2px var(--interactive-accent), 0 6px 22px rgba(0,0,0,.28); }
    .va-canvas-node.is-editing { box-shadow: 0 0 0 2px var(--interactive-accent); }
    .va-canvas-node { transition: box-shadow .15s ease; }
    .sage-canvas-resize { position: absolute; right: 3px; bottom: 3px; width: 12px; height: 12px; border-radius: 3px; cursor: nwse-resize;
      background: var(--interactive-accent); opacity: .9; z-index: 2; }
    .sage-canvas-marquee { position: absolute; z-index: 5; pointer-events: none; border: 1px solid var(--interactive-accent);
      background: color-mix(in srgb, var(--interactive-accent) 12%, transparent); border-radius: 2px; }
    .va-canvas-node.is-editing .va-canvas-node-content { overflow: hidden; display: flex; flex-direction: column; }
    .sage-canvas-note-body:has(> .sage-canvas-source) { flex: 1; display: flex; flex-direction: column; min-height: 120px; }
    .sage-live.sage-canvas-source { flex: 1; min-height: 2.5em; overflow: auto !important; }
    .sage-live.sage-canvas-source .cm-content { min-height: 100%; } .sage-edit-block:hover { color: var(--text-normal); } .sage-edit-block .svg-icon { width: 16px; height: 16px; }
    /* (2026-11-08): a base keeps its views, its columns' names and the group you're in at the top as you scroll. */
    .sage-file-page:has(> .sage-file-view > .sage-base) { overflow: hidden !important; display: flex; flex-direction: column; padding: 8px 24px 0 !important; }
    .sage-file-page > .sage-file-view:has(> .sage-base) { display: flex; flex-direction: column; flex: 1 1 auto; min-height: 0; height: auto; }
    .sage-file-view > .sage-base { display: flex; flex-direction: column; flex: 1 1 auto; min-height: 0; }
    .sage-file-view > .sage-base > .bases-header, .sage-file-view > .sage-base > .sage-base-problem { flex: none; }
    .sage-file-view > .sage-base > .bases-view:not([hidden]) { flex: 1 1 auto; min-height: 0; overflow: auto; padding-bottom: 28px; }
    .sage-file-view > .sage-base > .bases-toolbar, .sage-file-view > .sage-base .bases-toolbar { padding-bottom: 4px; }
    .sage-file-view > .sage-base > .bases-header { padding-bottom: 2px; box-shadow: 0 1px 0 var(--background-modifier-border); margin-bottom: 0; }
    .sage-base .sage-base-table { overflow: visible !important; } .sage-base .sage-base-table th, .sage-base .sage-base-table td { border-radius: 0 !important; }
    .sage-base .sage-base-table thead th { position: sticky; top: 0; z-index: 3; background: var(--background-primary) !important; box-shadow: inset 0 -1px 0 var(--background-modifier-border); }
    .sage-base .sage-base-table .sage-base-group-row td { padding: 9px 10px 5px !important; }
    .sage-base .sage-base-table .sage-base-group-row td { position: sticky; top: calc(var(--sage-base-head, 33px) - 1px); z-index: 2; background: var(--background-primary) !important;
      box-shadow: 0 -10px 0 var(--background-primary), inset 0 -1px 0 var(--background-modifier-border); }
    .sage-base-table .sage-base-group-row:hover td { background: var(--background-primary) !important; }
    .sage-base .sage-base-cards > .bases-group-heading { position: sticky; top: 0; z-index: 2; background: var(--background-primary); padding: 10px 0 6px; }
    /* A name keeps one of Obsidian's colours everywhere (Study.Hue): a group, and a column of a few repeated values as chips. */
    .sage-hue-0 { --sage-hue: var(--color-red-rgb, 251, 70, 76); } .sage-hue-1 { --sage-hue: var(--color-orange-rgb, 233, 151, 63); }
    .sage-hue-2 { --sage-hue: var(--color-yellow-rgb, 224, 222, 113); } .sage-hue-3 { --sage-hue: var(--color-green-rgb, 68, 207, 110); }
    .sage-hue-4 { --sage-hue: var(--color-cyan-rgb, 83, 223, 221); } .sage-hue-5 { --sage-hue: var(--color-blue-rgb, 2, 122, 255); }
    .sage-hue-6 { --sage-hue: var(--color-purple-rgb, 168, 130, 255); } .sage-hue-7 { --sage-hue: var(--color-pink-rgb, 250, 153, 205); }
    .sage-chip { display: inline-block; padding: 0 8px; border-radius: 999px; font-size: var(--font-ui-smaller, 12px); line-height: 1.55; white-space: nowrap; vertical-align: top;
      color: rgb(var(--sage-hue)); background: rgba(var(--sage-hue), .14); }
    .sage-base .bases-group-value.sage-hued { color: rgb(var(--sage-hue)); font-weight: var(--font-semibold, 600); }
    .sage-base .bases-group-value.sage-hued .internal-link { color: inherit; }
    .sage-hue-dot { display: inline-block; flex: none; width: 8px; height: 8px; border-radius: 50%; background: rgb(var(--sage-hue)); box-shadow: 0 0 0 3px rgba(var(--sage-hue), .18); }
    /* (2026-11-08): in a long note, the headings you're under stay at the top; each takes you back to it. */
    .markdown-reading-view { position: relative; }
    .sage-where { position: absolute; top: 0; left: 0; right: 10px; z-index: 6; display: flex; align-items: center; gap: 2px; min-width: 0; padding: 5px 14px;
      font-family: var(--font-interface, inherit); font-size: var(--font-ui-small, 13px); color: var(--text-muted);
      background: color-mix(in srgb, var(--background-primary) 90%, transparent); backdrop-filter: blur(8px); box-shadow: 0 1px 0 var(--background-modifier-border);
      transform: translateY(-100%); opacity: 0; pointer-events: none; transition: transform .2s ease, opacity .2s ease; }
    .sage-where.is-shown { transform: none; opacity: 1; pointer-events: auto; }
    .sage-where button { all: unset; cursor: pointer; padding: 2px 7px; border-radius: var(--radius-s, 4px); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 2em; flex: 0 1 auto; }
    .sage-where button:hover { background: var(--background-modifier-hover); }
    .sage-where button[data-level="1"] { color: var(--h1-color, var(--text-normal)); } .sage-where button[data-level="2"] { color: var(--h2-color, var(--text-normal)); }
    .sage-where button[data-level="3"] { color: var(--h3-color, var(--text-normal)); } .sage-where button[data-level="4"] { color: var(--h4-color, var(--text-normal)); }
    .sage-where button[data-level="5"] { color: var(--h5-color, var(--text-normal)); } .sage-where button[data-level="6"] { color: var(--h6-color, var(--text-normal)); }
    .sage-where button:last-of-type { font-weight: var(--font-semibold, 600); } .sage-where .sage-where-sep { flex: none; opacity: .5; }
    @media (prefers-reduced-motion: reduce) { .sage-where { transition: none; } }
    """#

    /// (2026-11-07, from Creative Assist) The little Obsidian does by script in reading view, done by Sage's own script
    /// (nothing in a note runs): icons drawn from Obsidian's set (a callout's from its --callout-icon, so a theme's choice
    /// shows), callouts and the properties folding, code copied, a task ticked in the note. On a page you can edit
    /// (body[data-sage-edit]), a block you click becomes the Markdown it was drawn from, in place: Enter carries a list on,
    /// Tab indents, it's saved as you pause and again when you leave it (Esc, Cmd+Enter or a click elsewhere), and the note
    /// is redrawn. Below the last block starts a new one. Cmd+E switches between editing and reading, as in Obsidian. The
    /// page speaks to the app through window.webkit.messageHandlers.sage and hears it through window.sageReceive.
    static let pageScript = #"""
    (function () {
      // The media viewer (2026-11-09): a picture clicked (or a video double-clicked) opens full size, and ‹ › or the arrow
      // keys step through every picture and video in the note, in order. Home/End go to the first and last, Space plays or
      // pauses a video, Esc or a click outside closes. It hears the click before anything else (editing included);
      // pictures that are links and YouTube cards keep their own click.
      (function () {
        function media() {
          return Array.prototype.filter.call(document.querySelectorAll('.markdown-preview-view img, .canvas-node-content img, .media-embed video'), function (el) {
            return !el.closest('a, .video-embed, #sage-viewer') && (el.tagName !== 'IMG' || (el.naturalWidth || el.width) > 24);
          });
        }
        function source(el) { return el.currentSrc || el.src || ''; }
        function name(el) {
          var box = el.closest('.internal-embed');
          var raw = (box && box.getAttribute('src')) || el.getAttribute('alt') || decodeURIComponent(source(el).split('/').pop() || '');
          return raw.split('|')[0];
        }
        function open(start) {
          var list = media(), at = list.indexOf(start);
          if (at < 0) return;
          var viewer = document.createElement('div');
          viewer.id = 'sage-viewer';
          viewer.innerHTML = '<div class="sv-stage"></div><button class="sv-prev" aria-label="Previous">‹</button><button class="sv-next" aria-label="Next">›</button>'
            + '<div class="sv-bar"><span class="sv-count"></span><span class="sv-name"></span></div>';
          var stage = viewer.querySelector('.sv-stage');
          function show(i) {
            if (i < 0 || i >= list.length) return;
            var old = stage.querySelector('video'); if (old) old.pause();
            at = i;
            var el = list[i], shown;
            if (el.tagName === 'VIDEO') { shown = document.createElement('video'); shown.controls = true; shown.autoplay = true; shown.src = source(el); }
            else { shown = document.createElement('img'); shown.src = source(el); shown.alt = el.alt || ''; }
            stage.replaceChildren(shown);
            viewer.querySelector('.sv-count').textContent = list.length > 1 ? (i + 1) + ' / ' + list.length : '';
            viewer.querySelector('.sv-name').textContent = name(el);
            viewer.querySelector('.sv-prev').disabled = i === 0;
            viewer.querySelector('.sv-next').disabled = i === list.length - 1;
            viewer.classList.toggle('sv-single', list.length < 2);
            // The next and previous pictures are fetched ahead, so stepping doesn't wait.
            [i - 1, i + 1].forEach(function (j) { if (list[j] && list[j].tagName === 'IMG') { var p = new Image(); p.src = source(list[j]); } });
          }
          function close() { var v = stage.querySelector('video'); if (v) v.pause(); viewer.remove(); document.removeEventListener('keydown', key, true); }
          function key(k) {
            var handled = true;
            if (k.key === 'Escape') close();
            else if (k.key === 'ArrowLeft') show(at - 1);
            else if (k.key === 'ArrowRight') show(at + 1);
            else if (k.key === 'Home') show(0);
            else if (k.key === 'End') show(list.length - 1);
            else if (k.key === ' ' && stage.querySelector('video')) { var v = stage.querySelector('video'); if (v.paused) v.play(); else v.pause(); }
            else handled = false;
            if (handled) { k.preventDefault(); k.stopPropagation(); }
          }
          viewer.addEventListener('click', function (c) {
            c.stopPropagation();
            if (c.target.closest('.sv-prev')) { c.preventDefault(); show(at - 1); }
            else if (c.target.closest('.sv-next')) { c.preventDefault(); show(at + 1); }
            else if (!c.target.closest('video, .sv-bar')) { c.preventDefault(); close(); }
          }, true);
          document.addEventListener('keydown', key, true);
          document.body.appendChild(viewer);
          show(at);
        }
        document.addEventListener('click', function (e) {
          var img = e.target && e.target.closest ? e.target.closest('img') : null;
          if (!img || img.closest('a, .video-embed, .sage-viewer-skip, #sage-viewer') || !img.closest('.markdown-preview-view, .canvas-node-content')) return;
          e.preventDefault(); e.stopPropagation();
          open(img);
        }, true);
        document.addEventListener('dblclick', function (e) {
          var video = e.target && e.target.closest ? e.target.closest('.media-embed video') : null;
          if (!video || video.closest('#sage-viewer')) return;
          e.preventDefault(); e.stopPropagation(); video.pause();
          open(video);
        }, true);
      })();
      // YouTube cards play in place (2026-11-09): Sage lays YouTube's own player over each card in or near sight and is
      // told where the cards are as the note scrolls or redraws, so your first click lands on YouTube's play button.
      (function () {
        var queued = false, next = 0;
        function say(m) { try { webkit.messageHandlers.sage.postMessage(m); } catch (_) {} }
        function videoId(href) { var m = /(?:[?&]v=|youtu\.be\/|shorts\/|embed\/)([A-Za-z0-9_-]{11})/.exec(href || ''); return m ? m[1] : null; }
        var said = '';
        function report() {
          var cards = [], tall = window.innerHeight;
          document.querySelectorAll('.video-embed').forEach(function (card) {
            var id = videoId(card.getAttribute('href'));
            if (!id) return;
            var r = card.getBoundingClientRect();
            if (r.bottom < -200 || r.top > tall + 200 || r.width < 2) return;
            if (!card.dataset.sageCard) card.dataset.sageCard = id + ':' + (next++);
            card.classList.add('sage-playing');
            cards.push({ key: card.dataset.sageCard, id: id, x: r.left, y: r.top, w: r.width, h: r.height });
          });
          // Only when something moved: typing changes the page all the time without moving a card.
          var now = JSON.stringify(cards);
          if (now === said) return;
          said = now;
          say({ type: 'inline-cards', cards: cards });
        }
        // Nothing to do in a note without YouTube cards (once its last card has gone, Sage is told once).
        function soon() {
          if (queued || (!said.length || said === '[]') && !document.querySelector('.video-embed')) return;
          queued = true; requestAnimationFrame(function () { queued = false; report(); });
        }
        // A click that reaches the card (its player still loading) waits for the player instead of leaving the note.
        document.addEventListener('click', function (e) {
          var card = e.target && e.target.closest ? e.target.closest('.video-embed') : null;
          if (!card || e.metaKey || e.button !== 0 || !videoId(card.getAttribute('href'))) return;
          e.preventDefault(); e.stopPropagation(); soon();
        }, true);
        document.addEventListener('scroll', soon, true);
        window.addEventListener('resize', soon);
        window.addEventListener('load', soon);
        new MutationObserver(soon).observe(document.documentElement, { childList: true, subtree: true });
        soon();
      })();
      var icons = window.sageIcons || {};
      function svg(name) {
        name = (name || '').trim().replace(/^["']|["']$/g, '');
        var inner = icons[name.replace(/^lucide-/, '')] || icons[name];
        return inner ? '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="svg-icon ' + name + '">' + inner + '</svg>' : '';
      }
      // What a block shows that isn't text (a base, a canvas, an embedded note, a page) is used where it is; while
      // editing, its corner button opens the block's Markdown.
      // A video or sound plays where it is too (2026-11-09: pressing play turned it into its ![[…]] line).
      var embeds = '.va-canvas-embed, .sage-base, .markdown-embed, .va-file-embed-scroll, .va-file-embed-frame, .pdf-embed, .media-embed:not(.image-embed), video, audio';
      // The Properties table's own words, in your language (Study.propertyWords), and what it was drawn from.
      var props = window.sageProps || {}, words = props.words || {};
      function decorate(root) {
        if (document.body.hasAttribute('data-sage-edit'))
          root.querySelectorAll('[data-sage-from]').forEach(function (block) {
            // The properties are edited in their table; their YAML, as before, from the corner button.
            var yaml = block.classList.contains('metadata-container');
            if ((!yaml && !block.querySelector(embeds)) || block.querySelector(':scope > .sage-edit-block')) return;
            var button = document.createElement('div');
            button.className = 'sage-edit-block'; button.setAttribute('data-sage-icon', 'lucide-code-2'); button.title = yaml ? (words.yaml || 'Edit the properties as YAML') : 'Edit this block';
            block.appendChild(button);
          });
        root.querySelectorAll('[data-sage-icon]').forEach(function (e) { e.innerHTML = svg(e.getAttribute('data-sage-icon')); });
        root.querySelectorAll('.callout > .callout-title > .callout-icon').forEach(function (e) {
          e.innerHTML = svg(getComputedStyle(e.parentElement.parentElement).getPropertyValue('--callout-icon'));
        });
        root.querySelectorAll('[data-sage-canvas]').forEach(canvas);
      }

      var presets = ['red', 'orange', 'yellow', 'green', 'cyan', 'purple'];
      var fallback = ['233, 49, 71', '236, 117, 0', '224, 172, 0', '8, 185, 78', '0, 191, 188', '120, 82, 238'];
      function preset(i) {
        var css = getComputedStyle(document.body), names = ['--canvas-color-' + i, '--color-' + presets[i - 1] + '-rgb'];
        for (var k = 0; k < names.length; k++) {
          var value = css.getPropertyValue(names[k]).trim();
          if (/^\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}$/.test(value)) return value;
        }
        var probe = document.createElement('div');
        document.body.appendChild(probe);
        probe.style.color = 'var(--color-' + presets[i - 1] + ')';
        var got = getComputedStyle(probe).color;
        probe.remove();
        var m = got.match(/^rgba?\((\d+),\s*(\d+),\s*(\d+)/);
        return m && got !== css.color ? m[1] + ', ' + m[2] + ', ' + m[3] : fallback[i - 1];
      }
      // A canvas, inside a note (Vault Agent's file-embed, its canvas-embed.ts) or opened on its own. A click works with
      // what's under it (a link, a card); the middle button, or Space held, drags the view (the hand tool); Ctrl+wheel
      // zooms. Opened on its own (data-sage-editable) it's edited as in Obsidian: click a card's text to edit it there,
      // drag a card to move it (a group takes its cards), its corner to resize it, empty space to select several,
      // double-click empty space for a new card, Delete, Cmd+Z / Cmd+Y; the wheel pans. Saved into the .canvas file.
      var hand = false;
      document.addEventListener('keydown', function (e) {
        if (e.code === 'Space' && !e.target.closest('textarea, input, [contenteditable]')) {
          if (!hand) { hand = true; document.querySelectorAll('[data-sage-canvas]').forEach(function (b) { b.classList.add('is-hand'); }); }
          if (document.querySelector('[data-sage-canvas]:hover')) e.preventDefault();
        }
      });
      document.addEventListener('keyup', function (e) {
        if (e.code === 'Space') { hand = false; document.querySelectorAll('[data-sage-canvas]').forEach(function (b) { b.classList.remove('is-hand'); }); }
      });
      function canvas(box) {
        if (box.sageReady) return;
        box.sageReady = true;
        var world = box.querySelector('.va-canvas-world'), svgLayer = box.querySelector('svg.va-canvas-edges'), ns = 'http://www.w3.org/2000/svg';
        var editable = box.hasAttribute('data-sage-editable');
        var model = editable ? JSON.parse(box.querySelector('.sage-canvas-data').textContent) : null;
        svgLayer.style.overflow = 'visible';
        box.querySelectorAll('[data-sage-preset]').forEach(function (e) {
          var rgb = preset(+e.getAttribute('data-sage-preset'));
          if (e.getAttribute('data-sage-color-on') === 'edge') e.style.stroke = 'rgb(' + rgb + ')';
          else e.style.setProperty('--va-node-rgb', rgb);
        });
        var defs = document.createElementNS(ns, 'defs'), markers = {}, id = 'va-arrow-' + Math.random().toString(36).slice(2);
        svgLayer.insertBefore(defs, svgLayer.firstChild);
        function marker(color) {
          var key = color || 'default';
          if (markers[key]) return markers[key];
          var name = id + '-' + Object.keys(markers).length, m = document.createElementNS(ns, 'marker');
          [['id', name], ['viewBox', '0 0 10 10'], ['refX', '9'], ['refY', '5'], ['markerWidth', '6'], ['markerHeight', '6'], ['orient', 'auto-start-reverse']]
            .forEach(function (a) { m.setAttribute(a[0], a[1]); });
          var tip = document.createElementNS(ns, 'path');
          tip.setAttribute('d', 'M0,0 L10,5 L0,10 z'); tip.setAttribute('class', 'va-canvas-arrow');
          if (color) tip.style.fill = color;
          m.appendChild(tip); defs.appendChild(m);
          return markers[key] = name;
        }
        function arrowheads() {
          svgLayer.querySelectorAll('path.va-canvas-edge').forEach(function (p) {
            var color = p.style.stroke || null;
            if (p.hasAttribute('data-sage-arrow-end')) p.setAttribute('marker-end', 'url(#' + marker(color) + ')');
            if (p.hasAttribute('data-sage-arrow-start')) p.setAttribute('marker-start', 'url(#' + marker(color) + ')');
          });
        }
        var width = parseFloat(world.style.width), height = parseFloat(world.style.height), scale = 1, tx = 0, ty = 0;
        function apply() { world.style.transform = 'translate(' + tx + 'px, ' + ty + 'px) scale(' + scale + ')'; }
        // What Fit shows: the whole world inside a note; on its own, wherever the cards are now.
        function bounds() {
          if (!editable || !model.nodes.length) return { x: 0, y: 0, w: width, h: height };
          var l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
          model.nodes.forEach(function (n) { l = Math.min(l, n.x); t = Math.min(t, n.y); r = Math.max(r, n.x + n.width); b = Math.max(b, n.y + n.height); });
          return { x: l - model.minX - 40, y: t - model.minY - 40, w: r - l + 80, h: b - t + 80 };
        }
        function fit() {
          var w = box.clientWidth, h = box.clientHeight, area = bounds();
          if (!w || !h) return false;
          scale = Math.min(3, Math.min(w / area.w, h / area.h));
          tx = (w - area.w * scale) / 2 - area.x * scale; ty = (h - area.h * scale) / 2 - area.y * scale;
          apply();
          return true;
        }
        function zoomAt(factor, cx, cy) {
          var next = Math.min(3, Math.max(0.05, scale * factor));
          tx = cx - (cx - tx) * (next / scale); ty = cy - (cy - ty) * (next / scale); scale = next;
          apply();
        }
        box.sageFit = fit;
        box.sageZoom = function (factor) { touched = true; zoomAt(factor, box.clientWidth / 2, box.clientHeight / 2); };
        var fitted = false;
        // Fitted when it first has a size, and again as the view grows or shrinks, until you pan or zoom it yourself.
        var touched = false;
        new ResizeObserver(function () { if (!fitted || !touched) fitted = fit(); }).observe(box);
        box.addEventListener('wheel', function (e) {
          if (e.ctrlKey || e.metaKey) {
            e.preventDefault();
            var r = box.getBoundingClientRect();
            touched = true;
            zoomAt(Math.exp(-e.deltaY * 0.01), e.clientX - r.left, e.clientY - r.top);
          } else if (editable && !e.target.closest('.sage-canvas-source')) {
            // On its own the wheel moves around the canvas (Shift: sideways); inside a note it scrolls the note.
            e.preventDefault();
            touched = true;
            tx -= e.shiftKey ? e.deltaY : e.deltaX; ty -= e.shiftKey ? 0 : e.deltaY;
            apply();
          }
        }, { passive: false });
        function swallowClick() { box.addEventListener('click', function (c) { c.stopPropagation(); c.preventDefault(); }, { capture: true, once: true }); }

        // The hand tool: the middle button or Space+drag anywhere; inside a note, also a drag on empty space.
        var pan = null;
        box.addEventListener('mousedown', function (e) { if (e.button === 1) e.preventDefault(); });
        box.addEventListener('pointerdown', function (e) {
          if (e.target.closest('.va-canvas-toolbar')) return;
          var empty = !e.target.closest('.va-canvas-node:not(.va-canvas-group), .va-canvas-label, a, .va-canvas-edge-label');
          if (e.button === 1 || (e.button === 0 && hand) || (e.button === 0 && !editable && empty)) {
            e.preventDefault();
            pan = { x: e.clientX, y: e.clientY, moved: false, pointer: e.pointerId };
            try { box.setPointerCapture(e.pointerId); } catch (x) { }
            box.classList.add('is-dragging');
            return;
          }
          if (editable && e.button === 0) down(e);
        });
        box.addEventListener('pointermove', function (e) {
          if (pan) {
            var dx = e.clientX - pan.x, dy = e.clientY - pan.y;
            if (!pan.moved && Math.hypot(dx, dy) < 3) return;
            pan.moved = true;
            touched = true;
            tx += dx; ty += dy; pan.x = e.clientX; pan.y = e.clientY;
            apply();
            return;
          }
          if (editable) move(e);
        });
        function release(e) {
          if (pan) {
            try { box.releasePointerCapture(pan.pointer); } catch (x) { }
            box.classList.remove('is-dragging');
            if (pan.moved) swallowClick();
            pan = null;
            return;
          }
          if (editable) up(e);
        }
        box.addEventListener('pointerup', release);
        box.addEventListener('pointercancel', release);
        // The middle button's click (auxclick) after a pan doesn't open a link in a new tab.
        box.addEventListener('auxclick', function (e) { if (e.button === 1) { e.preventDefault(); e.stopPropagation(); } }, true);

        if (!editable) { arrowheads(); return; }

        // MARK: Editing a canvas
        var nodes = model.nodes, edges = model.edges, byId = {}, els = {}, labels = {}, gone = {};
        var selected = [], editing = null, act = null, undo = [], redo = [], saving = false, dirty = false, timer = 0;
        function index() { byId = {}; nodes.forEach(function (n) { byId[n.id] = n; }); }
        index();
        world.querySelectorAll('.va-canvas-node[data-id]').forEach(function (el) { els[el.getAttribute('data-id')] = el; });
        world.querySelectorAll('.va-canvas-label[data-for]').forEach(function (el) { labels[el.getAttribute('data-for')] = el; });
        function place(n) {
          var el = els[n.id], l = labels[n.id];
          if (el) { el.style.left = (n.x - model.minX) + 'px'; el.style.top = (n.y - model.minY) + 'px'; el.style.width = n.width + 'px'; el.style.height = n.height + 'px'; }
          if (l) { l.style.left = (n.x - model.minX) + 'px'; l.style.top = (n.y - model.minY) + 'px'; }
        }
        function anchor(n, s) {
          var x = n.x - model.minX, y = n.y - model.minY;
          return s === 'top' ? { x: x + n.width / 2, y: y, dx: 0, dy: -1 } : s === 'bottom' ? { x: x + n.width / 2, y: y + n.height, dx: 0, dy: 1 }
            : s === 'left' ? { x: x, y: y + n.height / 2, dx: -1, dy: 0 } : { x: x + n.width, y: y + n.height / 2, dx: 1, dy: 0 };
        }
        function colorOf(c) {
          if (!c) return null;
          if (/^[1-6]$/.test(c)) return 'rgb(' + preset(+c) + ')';
          var m = /^#?([0-9a-f]{6})$/i.exec(c);
          if (!m) return null;
          var v = parseInt(m[1], 16);
          return 'rgb(' + (v >> 16 & 255) + ', ' + (v >> 8 & 255) + ', ' + (v & 255) + ')';
        }
        // The arrows, drawn again whenever a card moves (the plugin's curve: out of one side, into the other).
        function drawEdges() {
          svgLayer.querySelectorAll('path.va-canvas-edge').forEach(function (p) { p.remove(); });
          world.querySelectorAll('.va-canvas-edge-label').forEach(function (l) { l.remove(); });
          edges.forEach(function (e) {
            var a = byId[e.fromNode], b = byId[e.toNode];
            if (!a || !b) return;
            var dx = b.x + b.width / 2 - (a.x + a.width / 2), dy = b.y + b.height / 2 - (a.y + a.height / 2);
            var guess = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? ['right', 'left'] : ['left', 'right']) : (dy > 0 ? ['bottom', 'top'] : ['top', 'bottom']);
            var p = anchor(a, e.fromSide || guess[0]), q = anchor(b, e.toSide || guess[1]);
            var off = Math.min(220, Math.max(40, Math.hypot(q.x - p.x, q.y - p.y) * 0.4));
            var c1 = { x: p.x + p.dx * off, y: p.y + p.dy * off }, c2 = { x: q.x + q.dx * off, y: q.y + q.dy * off };
            var path = document.createElementNS(ns, 'path'), color = colorOf(e.color);
            path.setAttribute('d', 'M ' + p.x + ' ' + p.y + ' C ' + c1.x + ' ' + c1.y + ', ' + c2.x + ' ' + c2.y + ', ' + q.x + ' ' + q.y);
            path.setAttribute('class', 'va-canvas-edge');
            if (color) path.style.stroke = color;
            if ((e.toEnd || 'arrow') === 'arrow') path.setAttribute('marker-end', 'url(#' + marker(color) + ')');
            if (e.fromEnd === 'arrow') path.setAttribute('marker-start', 'url(#' + marker(color) + ')');
            svgLayer.appendChild(path);
            if (e.label) {
              var label = document.createElement('div');
              label.className = 'va-canvas-edge-label'; label.textContent = e.label;
              label.style.left = (p.x + 3 * c1.x + 3 * c2.x + q.x) / 8 + 'px'; label.style.top = (p.y + 3 * c1.y + 3 * c2.y + q.y) / 8 + 'px';
              world.appendChild(label);
            }
          });
        }
        drawEdges();

        function select(ids) {
          selected.forEach(function (i) { if (els[i]) els[i].classList.remove('is-selected'); });
          selected = ids.filter(function (i) { return byId[i]; });
          selected.forEach(function (i) { if (els[i]) els[i].classList.add('is-selected'); });
          world.querySelectorAll('.sage-canvas-resize').forEach(function (h) { h.remove(); });
          if (selected.length === 1 && !editing && els[selected[0]]) {
            var handle = document.createElement('div');
            handle.className = 'sage-canvas-resize'; handle.title = 'Drag to resize';
            els[selected[0]].appendChild(handle);
          }
        }
        function at(e) {
          var r = box.getBoundingClientRect();
          return { x: (e.clientX - r.left - tx) / scale + model.minX, y: (e.clientY - r.top - ty) / scale + model.minY };
        }
        function snapshot() { return JSON.stringify({ nodes: nodes, edges: edges }); }
        // Saved a moment after you stop, one save at a time, each over the version the last one wrote.
        function save() {
          clearTimeout(timer);
          timer = setTimeout(function () {
            if (saving) { dirty = true; return; }
            saving = true; dirty = false;
            post({ type: 'canvas-save', nodes: nodes, edges: edges, base: model.hash });
          }, 300);
        }
        function commit(before) { undo.push(before); if (undo.length > 100) undo.shift(); redo = []; save(); }
        window.sageCanvasMessage = function (m) {
          if (m.type === 'canvas-saved') { model.hash = m.hash; saving = false; if (dirty) save(); }
          else if (m.type === 'rendered' && m.key.indexOf('card:') === 0) {
            var el = els[m.key.slice(5)], content = el && el.querySelector('.va-canvas-node-content');
            if (content && !(editing && editing.n.id === m.key.slice(5))) { content.innerHTML = m.html; decorate(content); }
          }
          else if (m.type === 'canvas-card') {
            var card = els[m.id], inner = card && card.querySelector('.va-canvas-node-content');
            if (model.notes[m.id]) model.notes[m.id].body = m.body;
            if (inner && !(editing && editing.n.id === m.id)) { inner.innerHTML = m.html; decorate(inner); }
          }
          else if (m.type === 'notice') saving = false;
        };
        function render(n) { post({ type: 'render', key: 'card:' + n.id, md: n.text || '' }); }

        // A card's text edited where you clicked, as in Obsidian; a note's card edits the note.
        function startEdit(n, x, y) {
          finishEdit();
          var el = els[n.id], content = el && el.querySelector('.va-canvas-node-content');
          if (!content) return;
          var note = n.type === 'file' ? model.notes[n.id] : null;
          var original = note ? note.body : (n.text || '');
          var caret = x == null ? null : caretFor(x, y, original);
          var holder = note ? (content.querySelector('.sage-canvas-note-body') || content) : content;
          var area = liveEditor(original, {
            key: function (e) {
              if (e.key === 'Escape' || (e.key === 'Enter' && e.metaKey)) { e.preventDefault(); area.blur(); return true; }
              return false;
            },
            blur: function () { if (editing && editing.area === area) finishEdit(); },
          });
          area.el.classList.add('sage-canvas-source');
          editing = { n: n, area: area, holder: holder, saved: holder.innerHTML, original: original, note: note };
          holder.innerHTML = '';
          holder.appendChild(area.el);
          el.classList.add('is-editing');
          select([n.id]);
          area.focus(caret == null ? original.length : caret);
        }
        function finishEdit() {
          if (!editing) return;
          var ed = editing;
          editing = null;
          if (els[ed.n.id]) els[ed.n.id].classList.remove('is-editing');
          var text = ed.area.value;
          if (text === ed.original) { ed.holder.innerHTML = ed.saved; select(selected.slice()); return; }
          ed.holder.textContent = text;
          if (ed.note) {
            post({ type: 'canvas-note', id: ed.n.id, file: ed.note.file, original: ed.original, text: text });
            ed.note.body = text;
          } else {
            var before = snapshot();
            ed.n.text = text;
            commit(before);
            render(ed.n);
          }
          select(selected.slice());
        }

        // What a drag moves: the selected cards, and the cards inside a selected group.
        function moving() {
          var list = selected.map(function (i) { return byId[i]; }).filter(Boolean);
          list.filter(function (g) { return g.type === 'group'; }).forEach(function (g) {
            nodes.forEach(function (n) {
              if (list.indexOf(n) < 0 && n.x >= g.x && n.y >= g.y && n.x + n.width <= g.x + g.width && n.y + n.height <= g.y + g.height) list.push(n);
            });
          });
          return list;
        }
        function down(e) {
          if (e.target.closest('.sage-canvas-source') || e.target.closest('a')) return;
          var p = at(e), handle = e.target.closest('.sage-canvas-resize'), el = e.target.closest('.va-canvas-node[data-id]');
          if (handle) {
            var r = byId[handle.parentElement.getAttribute('data-id')];
            act = { kind: 'resize', n: r, start: p, w: r.width, h: r.height, before: snapshot(), changed: false };
            try { box.setPointerCapture(e.pointerId); } catch (x) { }
            e.preventDefault();
            return;
          }
          if (el) {
            act = { kind: 'card', id: el.getAttribute('data-id'), start: p, x: e.clientX, y: e.clientY, moved: false, before: snapshot(), shift: e.shiftKey };
            return;
          }
          finishEdit();
          act = { kind: 'marquee', start: p, x: e.clientX, y: e.clientY, rect: null };
        }
        function move(e) {
          if (!act) return;
          var p = at(e);
          if (act.kind === 'resize') {
            act.n.width = Math.max(80, Math.round(act.w + p.x - act.start.x));
            act.n.height = Math.max(40, Math.round(act.h + p.y - act.start.y));
            act.changed = true;
            place(act.n);
            drawEdges();
            return;
          }
          if (act.kind === 'card') {
            if (!act.moved) {
              if (Math.hypot(e.clientX - act.x, e.clientY - act.y) < 4) return;
              // Dragging inside the card you're typing in selects text.
              if (editing && editing.n.id === act.id) { act = null; return; }
              act.moved = true;
              finishEdit();
              if (selected.indexOf(act.id) < 0) select(act.shift ? selected.concat([act.id]) : [act.id]);
              act.from = moving().map(function (n) { return { n: n, x: n.x, y: n.y }; });
              try { box.setPointerCapture(e.pointerId); } catch (x) { }
              box.classList.add('is-moving');
            }
            var dx = Math.round(p.x - act.start.x), dy = Math.round(p.y - act.start.y);
            act.from.forEach(function (o) { o.n.x = o.x + dx; o.n.y = o.y + dy; place(o.n); });
            drawEdges();
            return;
          }
          if (act.kind === 'marquee') {
            if (!act.rect) {
              if (Math.hypot(e.clientX - act.x, e.clientY - act.y) < 4) return;
              act.rect = document.createElement('div');
              act.rect.className = 'sage-canvas-marquee';
              world.appendChild(act.rect);
              try { box.setPointerCapture(e.pointerId); } catch (x) { }
            }
            var l = Math.min(p.x, act.start.x), t = Math.min(p.y, act.start.y), w = Math.abs(p.x - act.start.x), h = Math.abs(p.y - act.start.y);
            act.rect.style.left = (l - model.minX) + 'px'; act.rect.style.top = (t - model.minY) + 'px';
            act.rect.style.width = w + 'px'; act.rect.style.height = h + 'px';
            select(nodes.filter(function (n) { return n.x < l + w && n.x + n.width > l && n.y < t + h && n.y + n.height > t && (n.type !== 'group' || (n.x >= l && n.y >= t && n.x + n.width <= l + w && n.y + n.height <= t + h)); })
              .map(function (n) { return n.id; }));
          }
        }
        function up(e) {
          var a = act;
          act = null;
          if (!a) return;
          try { box.releasePointerCapture(e.pointerId); } catch (x) { }
          box.classList.remove('is-moving');
          if (a.kind === 'resize') { if (a.changed) commit(a.before); return; }
          if (a.kind === 'card') {
            if (a.moved) { commit(a.before); swallowClick(); return; }
            var n = byId[a.id];
            if (a.shift) { select(selected.indexOf(a.id) < 0 ? selected.concat([a.id]) : selected.filter(function (i) { return i !== a.id; })); return; }
            if (n && (n.type === 'text' || (n.type === 'file' && model.notes[n.id]))) { if (!(editing && editing.n === n)) startEdit(n, e.clientX, e.clientY); }
            else select([a.id]);
            return;
          }
          if (a.kind === 'marquee') { if (a.rect) { a.rect.remove(); swallowClick(); } else select([]); }
        }

        // A new card where you double-click empty space, ready to type in.
        function newId() { var s = ''; for (var i = 0; i < 16; i++) s += '0123456789abcdef'[Math.floor(Math.random() * 16)]; return s; }
        function cardFor(n) {
          var el = document.createElement('div');
          el.className = 'va-canvas-node va-canvas-text';
          el.setAttribute('data-id', n.id);
          var content = document.createElement('div');
          content.className = 'va-canvas-node-content markdown-rendered';
          el.appendChild(content);
          var first = world.querySelector('.va-canvas-edge-label, .va-canvas-label');
          world.insertBefore(el, first);
          els[n.id] = el;
          return el;
        }
        box.addEventListener('dblclick', function (e) {
          if (e.target.closest('.va-canvas-node:not(.va-canvas-group), .va-canvas-toolbar, a, .va-canvas-label') || hand) return;
          var p = at(e), before = snapshot();
          var n = { id: newId(), type: 'text', text: '', x: Math.round(p.x - 125), y: Math.round(p.y - 30), width: 250, height: 60 };
          nodes.push(n);
          index();
          cardFor(n);
          place(n);
          commit(before);
          startEdit(n, null, null);
        });

        // Undo and redo, and Delete, while the canvas (not a card's text) has the keyboard.
        function restore(state) {
          var s = JSON.parse(state), keep = {};
          s.nodes.forEach(function (n) { keep[n.id] = true; });
          nodes.forEach(function (n) {
            if (keep[n.id] || !els[n.id]) return;
            gone[n.id] = { el: els[n.id], label: labels[n.id] };
            els[n.id].remove(); if (labels[n.id]) labels[n.id].remove();
            delete els[n.id]; delete labels[n.id];
          });
          var texts = {};
          nodes.forEach(function (n) { texts[n.id] = n.text; });
          nodes = s.nodes; edges = s.edges;
          index();
          nodes.forEach(function (n) {
            if (!els[n.id]) {
              if (gone[n.id]) {
                world.insertBefore(gone[n.id].el, world.querySelector('.va-canvas-edge-label, .va-canvas-label'));
                els[n.id] = gone[n.id].el;
                if (gone[n.id].label) { world.appendChild(gone[n.id].label); labels[n.id] = gone[n.id].label; }
              } else cardFor(n);
              render(n);
            } else if (n.type === 'text' && texts[n.id] !== n.text) render(n);
            place(n);
          });
          drawEdges();
          select([]);
          save();
        }
        document.addEventListener('keydown', function (e) {
          if (e.target.closest('textarea, input, [contenteditable="true"]')) return;
          var key = (e.key || '').toLowerCase();
          if ((e.metaKey && key === 'z' && !e.shiftKey) && undo.length) { e.preventDefault(); finishEdit(); redo.push(snapshot()); restore(undo.pop()); }
          else if (e.metaKey && (key === 'y' || (key === 'z' && e.shiftKey)) && redo.length) { e.preventDefault(); undo.push(snapshot()); restore(redo.pop()); }
          else if (e.metaKey && key === 'a') { e.preventDefault(); select(nodes.map(function (n) { return n.id; })); }
          else if (key === 'escape') select([]);
          else if ((key === 'delete' || key === 'backspace') && selected.length) {
            e.preventDefault();
            var before = snapshot(), dead = {};
            selected.forEach(function (i) { dead[i] = true; });
            nodes.forEach(function (n) {
              if (!dead[n.id] || !els[n.id]) return;
              gone[n.id] = { el: els[n.id], label: labels[n.id] };
              els[n.id].remove(); if (labels[n.id]) labels[n.id].remove();
              delete els[n.id]; delete labels[n.id];
            });
            nodes = nodes.filter(function (n) { return !dead[n.id]; });
            edges = edges.filter(function (x) { return !dead[x.fromNode] && !dead[x.toNode]; });
            index();
            select([]);
            drawEdges();
            commit(before);
          }
        });
      }
      decorate(document);

      // The app hears the page through WKWebView's message handler, and speaks to it by calling window.sageReceive.
      var host = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sage;
      function post(message) { if (host) host.postMessage(message); }
      var editable = document.body.hasAttribute('data-sage-edit');
      var lines = window.sageLines || [];
      var settings = window.sageEdit || {};
      var open = null, timer = 0, waiting = false, queued = null;
      function sizer() { return document.querySelector('.markdown-preview-sizer'); }
      function notice(text) {
        var note = document.createElement('div'); note.className = 'sage-notice'; note.textContent = text;
        document.body.appendChild(note); setTimeout(function () { note.remove(); }, 5000);
      }

      // The block's text as it is now, when it differs from what the note has.
      // MARK: Live Preview (2026-11-08): editing that keeps the formatting, as Obsidian's editor does. The Markdown is the
      // text you typed, kept as it is; each line is drawn with Obsidian's own editor classes (HyperMD-header-3,
      // cm-formatting, list-bullet, cm-hmd-internal-link…) so app.css and your theme dress it as in Obsidian, and the
      // marks (###, **, [[ ]]) show only on the lines you're on. Every change goes through the text (typing, Enter,
      // deleting, pasting, undo), never the page's own editing, so the Markdown is exactly what you wrote.
      function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
      function attr(s) { return esc(s).replace(/"/g, '&quot;'); }
      function span(cls, s) { return '<span class="' + cls + '">' + esc(s) + '</span>'; }
      var F = 'cm-formatting ';
      var inlineRules = [
        { re: /(`+)([^`\n]+?)\1/, html: function (m) { var mark = span(F + 'cm-formatting-code cm-inline-code', m[1]); return mark + span('cm-inline-code', m[2]) + mark; } },
        { re: /(!?)\[\[([^\]\n|]+)(?:\|([^\]\n]*))?\]\]/, html: function (m) {
          var head = span(F + 'cm-formatting-link cm-formatting-link-start', m[1] + '[['), tail = span(F + 'cm-formatting-link cm-formatting-link-end', ']]'), to = attr(m[2]);
          if (m[3] != null)
            return head + '<span class="cm-hmd-internal-link cm-link-alias-target sage-hide" data-sage-link="' + to + '">' + esc(m[2]) + '</span>'
              + span(F + 'cm-link-alias-pipe', '|') + '<span class="cm-hmd-internal-link cm-link-alias" data-sage-link="' + to + '"><span class="cm-underline">' + esc(m[3]) + '</span></span>' + tail;
          return head + '<span class="cm-hmd-internal-link" data-sage-link="' + to + '"><span class="cm-underline">' + esc(m[2]) + '</span></span>' + tail;
        } },
        { re: /(!?)\[([^\]\n]*)\]\(([^)\s]*)\)/, html: function (m) {
          return span(F + 'cm-formatting-link cm-link', m[1] + '[') + '<span class="cm-link" data-sage-link="' + attr(m[3]) + '"><span class="cm-underline">' + inline(m[2]) + '</span></span>'
            + span(F + 'cm-formatting-link cm-link', ']') + span(F + 'cm-formatting-link-string cm-string cm-url', '(' + m[3] + ')');
        } },
        { re: /(\*\*|__)(?=\S)([^\n]*?\S)\1/, html: function (m) { var mark = span(F + 'cm-formatting-strong cm-strong', m[1]); return mark + '<span class="cm-strong">' + inline(m[2]) + '</span>' + mark; } },
        { re: /(^|[^\w*])([*_])(?=\S)([^\n*_]*?\S)\2(?![\w*])/, html: function (m) { var mark = span(F + 'cm-formatting-em cm-em', m[2]); return esc(m[1]) + mark + '<span class="cm-em">' + inline(m[3]) + '</span>' + mark; } },
        { re: /~~(?=\S)([^\n]*?\S)~~/, html: function (m) { var mark = span(F + 'cm-formatting-strikethrough cm-strikethrough', '~~'); return mark + '<span class="cm-strikethrough">' + inline(m[1]) + '</span>' + mark; } },
        { re: /==(?=\S)([^\n]*?\S)==/, html: function (m) { var mark = span(F + 'cm-formatting-highlight cm-highlight', '=='); return mark + '<span class="cm-highlight">' + inline(m[1]) + '</span>' + mark; } },
        { re: /(^|\s)#([\p{L}\p{N}_\/-]*[\p{L}_\/-][\p{L}\p{N}_\/-]*)/u, html: function (m) { return esc(m[1]) + span('cm-hashtag cm-hashtag-begin cm-meta', '#') + span('cm-hashtag cm-hashtag-end cm-meta', m[2]); } },
        { re: /https?:\/\/[^\s<>()\]]+/, html: function (m) { return '<span class="cm-url" data-sage-link="' + attr(m[0]) + '">' + esc(m[0]) + '</span>'; } },
      ];
      function inline(s) {
        var out = '';
        while (s.length) {
          var best = null;
          for (var i = 0; i < inlineRules.length; i++) {
            var m = inlineRules[i].re.exec(s);
            if (m && m[0].length && (!best || m.index < best.m.index)) best = { m: m, rule: inlineRules[i] };
          }
          if (!best) { out += esc(s); break; }
          out += esc(s.slice(0, best.m.index)) + best.rule.html(best.m);
          s = s.slice(best.m.index + best.m[0].length);
        }
        return out;
      }
      function line(cls, html, extra) { return '<div class="cm-line' + (cls ? ' ' + cls : '') + '"' + (extra || '') + '>' + (html || '<br>') + '</div>'; }
      function lineHtml(text, state) {
        var m;
        if (state.code) {
          if (/^\s*(```|~~~)/.test(text)) { state.code = false; return line('HyperMD-codeblock HyperMD-codeblock-bg HyperMD-codeblock-end HyperMD-codeblock-end-bg', span(F + 'cm-formatting-code-block cm-hmd-codeblock', text)); }
          return line('HyperMD-codeblock HyperMD-codeblock-bg', text.length ? span('cm-hmd-codeblock', text) : '');
        }
        if (/^\s*(```|~~~)/.test(text)) { state.code = true; return line('HyperMD-codeblock HyperMD-codeblock-bg HyperMD-codeblock-begin HyperMD-codeblock-begin-bg', span(F + 'cm-formatting-code-block cm-hmd-codeblock', text)); }
        if ((m = /^(#{1,6})(\s+)(.*)$/.exec(text))) {
          var n = m[1].length;
          return line('HyperMD-header HyperMD-header-' + n, span(F + 'cm-formatting-header cm-formatting-header-' + n + ' cm-header cm-header-' + n, m[1] + m[2]) + '<span class="cm-header cm-header-' + n + '">' + inline(m[3]) + '</span>');
        }
        if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(text)) return line('hr', span(F + 'cm-hr sage-hr', text));
        if ((m = /^((?:>\s?)+)(.*)$/.exec(text))) {
          var depth = (m[1].match(/>/g) || []).length;
          return line('HyperMD-quote HyperMD-quote-' + depth, span(F + 'cm-formatting-quote cm-formatting-quote-' + depth + ' cm-quote cm-quote-' + depth, m[1]) + '<span class="cm-quote cm-quote-' + depth + '">' + inline(m[2]) + '</span>');
        }
        if ((m = /^(\s*)([-*+]|\d+[.)])(\s+)(?:\[(.)\](\s))?(.*)$/.exec(text))) {
          var level = (m[1].match(/\t/g) || []).length + Math.floor(m[1].replace(/\t/g, '').length / 2) + 1, bulleted = /^[-*+]$/.test(m[2]);
          var html = (m[1] ? span('cm-hmd-list-indent cm-hmd-list-indent-' + (level - 1), m[1]) : '')
            + '<span class="cm-formatting cm-formatting-list cm-formatting-list-' + (bulleted ? 'ul' : 'ol') + ' cm-list-' + level + '">'
            + (bulleted ? '<span class="list-bullet">' + esc(m[2]) + '</span>' : esc(m[2])) + esc(m[3]) + '</span>';
          var task = m[4] != null;
          if (task) html += '<span class="cm-formatting cm-formatting-task sage-task' + (m[4] !== ' ' ? ' is-checked' : '') + '">' + esc('[' + m[4] + ']') + '</span>' + esc(m[5]);
          html += '<span class="cm-list-' + level + '">' + inline(m[6]) + '</span>';
          return line('HyperMD-list-line HyperMD-list-line-' + level + (task ? ' HyperMD-task-line' : ''), html, task ? ' data-task="' + attr(m[4]) + '"' : '');
        }
        return line('', inline(text));
      }

      // (2026-11-13, you asked) The word being typed finished in grey from the vault's words (the app's SageWords); Tab
      // takes it, Escape or moving away drops it. Asked of the app after each letter typed; the latest asking only.
      var completing = { id: 0, back: null };
      // (2026-11-13, you asked) Autocorrect (the app's SageSpell): when a word is ended the words before are put right
      // (typos; Vietnamese typed without marks given them), underlined a moment; Backspace straight after puts them back.
      var correcting = { id: 0, back: null };
      /// The editor: `hooks.input` after each change, `hooks.key` first look at a key (true: handled), `hooks.blur` on leaving.
      function liveEditor(start, hooks) {
        var text = start, history = [], future = [], lastKind = '', lastAt = 0, composing = false;
        var root = document.createElement('div');
        root.className = 'markdown-source-view cm-s-obsidian mod-cm6 is-live-preview sage-live';
        root.innerHTML = '<div class="cm-editor"><div class="cm-scroller"><div class="cm-contentContainer"><div class="cm-content" contenteditable="true" role="textbox" aria-multiline="true"></div></div></div></div>';
        var content = root.querySelector('.cm-content');
        content.spellcheck = settings.spellcheck !== false;
        content.setAttribute('autocorrect', 'off');
        function starts() { var s = [0]; for (var i = 0; i < text.length; i++) if (text.charCodeAt(i) === 10) s.push(i + 1); return s; }
        function draw() {
          var state = { code: false }, html = '';
          text.split('\n').forEach(function (l) { html += lineHtml(l, state); });
          content.innerHTML = html;
        }
        // A place in the text ↔ a place in the page (the marks are in the page on every line, shown or not).
        function point(index) {
          var s = starts(), n = 0;
          while (n + 1 < s.length && s[n + 1] <= index) n++;
          var lineEl = content.children[n], offset = Math.max(0, index - s[n]);
          if (!lineEl) return { node: content, offset: content.childNodes.length };
          var walker = document.createTreeWalker(lineEl, NodeFilter.SHOW_TEXT), node, last = null;
          while ((node = walker.nextNode())) {
            if (offset <= node.length) return { node: node, offset: offset };
            offset -= node.length;
            last = node;
          }
          return last ? { node: last, offset: last.length } : { node: lineEl, offset: 0 };
        }
        function index(node, offset) {
          if (!content.contains(node) && node !== content) return text.length;
          if (node === content) { var s0 = starts(); return offset >= content.children.length ? text.length : s0[offset]; }
          var lineEl = (node.nodeType === 1 ? node : node.parentElement).closest('.cm-line');
          if (!lineEl) return text.length;
          var n = Array.prototype.indexOf.call(content.children, lineEl), r = document.createRange();
          r.setStart(lineEl, 0);
          r.setEnd(node, offset);
          var s = starts(), length = (s[n + 1] != null ? s[n + 1] - 1 : text.length) - s[n];
          return s[n] + Math.min(r.toString().length, length);
        }
        function range() {
          var sel = getSelection();
          if (!sel.rangeCount || !content.contains(sel.anchorNode)) return { from: text.length, to: text.length };
          var a = index(sel.anchorNode, sel.anchorOffset), b = index(sel.focusNode, sel.focusOffset);
          return { from: Math.min(a, b), to: Math.max(a, b) };
        }
        function select(a, b) {
          var p = point(a), q = point(b == null ? a : b), sel = getSelection();
          sel.setBaseAndExtent(p.node, p.offset, q.node, q.offset);
          active();
        }
        // The lines the cursor or selection is on show their marks (cm-active), as in Obsidian.
        function active() {
          var sel = getSelection(), lo = -1, hi = -1;
          if (sel.rangeCount && content.contains(sel.anchorNode)) {
            var r = range(), s = starts();
            for (var i = 0; i < s.length; i++) { if (s[i] <= r.from) lo = i; if (s[i] <= r.to) hi = i; }
          }
          for (var k = 0; k < content.children.length; k++) content.children[k].classList.toggle('cm-active', k >= lo && k <= hi);
        }
        var ghost = null, ghostEl = null, ghostAt = -1, ghostTake = null;
        function unghost() { ghost = null; completing.back = null; if (ghostEl) { ghostEl.remove(); ghostEl = null; } }
        function askGhost() {
          unghost();
          var r = range();
          if (composing || r.from !== r.to || /[\p{L}\p{N}]/u.test(text.charAt(r.from))) return;
          var before = text.slice(Math.max(0, r.from - 200), r.from), was = text;
          if (!/\p{L}$/u.test(before) && !/\[\[[^\]\n]+$/.test(before)) return;
          completing.id++;
          completing.back = function (rest, take) {
            completing.back = null;
            var sel = getSelection();
            if (!rest || text !== was || !root.isConnected || !sel.rangeCount || range().from !== r.from) return;
            var caret = sel.getRangeAt(0).cloneRange(), box = caret.getClientRects()[0];
            if (!box) { var p = point(r.from), around = document.createRange(); around.setStart(p.node, Math.max(0, p.offset - 1)); around.setEnd(p.node, p.offset); var all = around.getClientRects(); box = all[all.length - 1]; if (box) box = { left: box.right, top: box.top, height: box.height }; }
            if (!box) return;
            var host = sel.anchorNode.nodeType === 1 ? sel.anchorNode : sel.anchorNode.parentElement, look = getComputedStyle(host);
            ghostEl = document.createElement('span');
            ghostEl.className = 'sage-ghost';
            ghostEl.textContent = rest;
            ghostEl.style.font = look.font;
            ghostEl.style.left = box.left + 'px';
            ghostEl.style.top = box.top + 'px';
            ghostEl.style.lineHeight = box.height + 'px';
            document.body.appendChild(ghostEl);
            ghost = rest; ghostAt = r.from; ghostTake = take;
          };
          post({ type: 'complete', id: completing.id, before: before, closed: text.slice(r.from, r.from + 2) === ']]' });
        }
        window.addEventListener('scroll', function () { if (ghost) unghost(); }, true);
        function onSelection() {
          if (!root.isConnected) { document.removeEventListener('selectionchange', onSelection); return; }
          active();
          if (ghost) { var g = range(); if (g.from !== g.to || g.from !== ghostAt) unghost(); }
        }
        document.addEventListener('selectionchange', onSelection);
        function change(from, to, insert, kind, caret) {
          var now = Date.now();
          if (!(kind === 'type' && lastKind === 'type' && now - lastAt < 1000)) { history.push({ text: text, at: range() }); if (history.length > 200) history.shift(); }
          future = [];
          lastKind = kind; lastAt = now;
          text = text.slice(0, from) + insert + text.slice(to);
          draw();
          var at = caret == null ? from + insert.length : caret;
          select(at, at);
          if (kind === 'type') askGhost(); else unghost();
          if (kind !== 'correct') lastFix = null;
          if (kind === 'type' && insert.length === 1 && ' .,;:!?)]}"\u201d'.indexOf(insert) >= 0) askFix(at);
          if (hooks.input) hooks.input();
        }
        var lastFix = null;
        function askFix(at) {
          var before = text.slice(Math.max(0, at - 300), at), base = at - before.length, was = text;
          correcting.id++;
          correcting.back = function (fix) {
            correcting.back = null;
            var r = range();
            if (!fix || text !== was || !root.isConnected || r.from !== at || r.to !== at) return;
            var from = base + fix.start, to = from + fix.old.length;
            if (text.slice(from, to) !== fix.old) return;
            var caret = at + fix.new.length - fix.old.length;
            change(from, to, fix.new, 'correct', caret);
            lastFix = { from: from, to: from + fix.new.length, old: fix.old, caret: caret, text: text };
            underline(from, from + fix.new.length);
          };
          post({ type: 'correct', id: correcting.id, before: before });
        }
        function underline(from, to) {
          var p = point(from), q = point(to), r = document.createRange();
          try { r.setStart(p.node, p.offset); r.setEnd(q.node, q.offset); } catch (e) { return; }
          var marks = Array.prototype.map.call(r.getClientRects(), function (box) {
            var m = document.createElement('div');
            m.style.cssText = 'position:fixed;pointer-events:none;z-index:30;height:2px;border-radius:1px;background:var(--interactive-accent);opacity:.7';
            m.style.left = box.left + 'px'; m.style.top = (box.bottom - 1) + 'px'; m.style.width = box.width + 'px';
            document.body.appendChild(m);
            return m;
          });
          function drop() { marks.forEach(function (m) { m.remove(); }); window.removeEventListener('scroll', drop, true); }
          window.addEventListener('scroll', drop, true);
          setTimeout(drop, 2000);
        }
        function travel(from, to) {
          if (!from.length) return;
          to.push({ text: text, at: range() });
          var state = from.pop();
          text = state.text;
          lastKind = '';
          draw();
          select(state.at.from, state.at.to);
          if (hooks.input) hooks.input();
        }
        // Enter carries a list or a quote on (numbered on, a task unticked); on an empty item it ends the list.
        function enter(r) {
          var first = text.lastIndexOf('\n', r.from - 1) + 1, before = text.slice(first, r.from);
          var item = before.match(/^(\s*(?:>\s?)*)([-*+]|\d+[.)])(\s+)(\[.\]\s+)?/);
          if (item) {
            if (before.length === item[0].length && r.from === r.to) { change(first, r.from, item[1], 'enter'); return; }
            var marker = item[2], number = marker.match(/^(\d+)([.)])$/);
            if (number) marker = (parseInt(number[1], 10) + 1) + number[2];
            change(r.from, r.to, '\n' + item[1] + marker + item[3] + (item[4] ? '[ ] ' : ''), 'enter');
            return;
          }
          var quote = before.match(/^(\s*(?:>\s?)+)/);
          change(r.from, r.to, '\n' + (quote && before.length > quote[0].length ? quote[1] : ''), 'enter');
        }
        function indent(back) {
          var r = range(), unit = settings.tab || '\t';
          if (!back && r.from === r.to) { change(r.from, r.to, unit, 'indent'); return; }
          var first = text.lastIndexOf('\n', r.from - 1) + 1, end = text.indexOf('\n', r.to);
          if (end < 0) end = text.length;
          var moved = text.slice(first, end).split('\n').map(function (l) {
            if (!back) return unit + l;
            if (l.charAt(0) === '\t') return l.slice(1);
            var spaces = l.match(/^ {1,4}/);
            return spaces ? l.slice(spaces[0].length) : l;
          }).join('\n');
          change(first, end, moved, 'indent', first + moved.length);
        }
        function wrap(mark) {
          var r = range();
          change(r.from, r.to, mark + text.slice(r.from, r.to) + mark, 'wrap', r.to + mark.length);
        }
        function targets(e) {
          var ranges = e.getTargetRanges ? e.getTargetRanges() : [];
          if (!ranges.length) return null;
          var a = index(ranges[0].startContainer, ranges[0].startOffset), b = index(ranges[0].endContainer, ranges[0].endOffset);
          return { from: Math.min(a, b), to: Math.max(a, b) };
        }
        content.addEventListener('beforeinput', function (e) {
          if (composing || e.inputType === 'insertCompositionText') return;
          e.preventDefault();
          var r = range(), t = targets(e), at;
          switch (e.inputType) {
            case 'insertText': change(r.from, r.to, e.data || '', 'type'); break;
            case 'insertReplacementText': { var with2 = (e.dataTransfer && e.dataTransfer.getData('text/plain')) || e.data || ''; var place = t || r; change(place.from, place.to, with2, 'replace'); break; }
            case 'insertParagraph': enter(r); break;
            case 'insertLineBreak': change(r.from, r.to, '\n', 'enter'); break;
            case 'insertFromPaste': case 'insertFromDrop': case 'insertFromYank':
              change(r.from, r.to, ((e.dataTransfer && e.dataTransfer.getData('text/plain')) || '').replace(/\r\n?/g, '\n'), 'paste'); break;
            case 'deleteByCut': case 'deleteByDrag': case 'deleteContent': if (r.from !== r.to) change(r.from, r.to, '', 'cut'); break;
            case 'deleteContentBackward':
              if (r.from !== r.to) change(r.from, r.to, '', 'delete');
              else if (t && t.from < t.to) change(t.from, t.to, '', 'delete');
              else if (r.from > 0) { at = r.from - 1; if (at > 0 && /[\uDC00-\uDFFF]/.test(text.charAt(at)) && /[\uD800-\uDBFF]/.test(text.charAt(at - 1))) at--; change(at, r.from, '', 'delete'); }
              break;
            case 'deleteContentForward':
              if (r.from !== r.to) change(r.from, r.to, '', 'delete');
              else if (t && t.from < t.to) change(t.from, t.to, '', 'delete');
              else if (r.to < text.length) { at = r.to + 1; if (/[\uD800-\uDBFF]/.test(text.charAt(r.to))) at++; change(r.to, at, '', 'delete'); }
              break;
            case 'deleteWordBackward': case 'deleteSoftLineBackward': case 'deleteHardLineBackward':
              if (r.from !== r.to) { change(r.from, r.to, '', 'delete'); break; }
              if (t && t.from < t.to) { change(t.from, t.to, '', 'delete'); break; }
              at = e.inputType === 'deleteWordBackward' ? r.from - text.slice(0, r.from).match(/(\s*[^\s]*|\s+)$/)[0].length : text.lastIndexOf('\n', r.from - 1) + 1;
              change(Math.min(at, r.from), r.from, '', 'delete');
              break;
            case 'deleteWordForward': case 'deleteSoftLineForward': case 'deleteHardLineForward':
              if (r.from !== r.to) { change(r.from, r.to, '', 'delete'); break; }
              if (t && t.from < t.to) { change(t.from, t.to, '', 'delete'); break; }
              at = e.inputType === 'deleteWordForward' ? r.to + text.slice(r.to).match(/^(\s*[^\s]*|\s+)/)[0].length : (text.indexOf('\n', r.to) < 0 ? text.length : text.indexOf('\n', r.to));
              change(r.to, Math.max(at, r.to), '', 'delete');
              break;
            case 'historyUndo': travel(history, future); break;
            case 'historyRedo': travel(future, history); break;
            case 'formatBold': wrap('**'); break;
            case 'formatItalic': wrap('*'); break;
          }
        });
        // Typing through an input method (Vietnamese Telex, say): the browser composes, then the line is read back.
        content.addEventListener('compositionstart', function () { composing = true; });
        content.addEventListener('compositionend', function () {
          composing = false;
          var sel = getSelection(), lineEl = sel.anchorNode && (sel.anchorNode.nodeType === 1 ? sel.anchorNode : sel.anchorNode.parentElement).closest('.cm-line');
          if (!lineEl || !content.contains(lineEl)) return;
          var n = Array.prototype.indexOf.call(content.children, lineEl), r = document.createRange();
          r.setStart(lineEl, 0); r.setEnd(sel.anchorNode, sel.anchorOffset);
          var caretInLine = r.toString().length, s = starts(), end = s[n + 1] != null ? s[n + 1] - 1 : text.length;
          history.push({ text: text, at: { from: s[n], to: s[n] } });
          future = [];
          text = text.slice(0, s[n]) + lineEl.textContent + text.slice(end);
          draw();
          select(s[n] + caretInLine);
          askGhost();
          if (hooks.input) hooks.input();
        });
        content.addEventListener('keydown', function (e) {
          if (ghost && !e.isComposing && e.key === 'Tab' && !e.shiftKey) {
            e.preventDefault(); e.stopPropagation();
            var take = ghostTake, r = range();
            unghost();
            // The whole word written as it should be (Mississippi's capital, a letter typed wrong).
            if (take && take.word) change(Math.max(0, r.from - take.replace), r.to, take.word, 'complete');
            return;
          }
          if (ghost && e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); unghost(); return; }
          if (ghost && e.key !== 'Shift') unghost();
          if (lastFix && e.key === 'Backspace' && !e.isComposing && !e.metaKey && !e.altKey && text === lastFix.text) {
            var b = range(), fixed = lastFix;
            if (b.from === fixed.caret && b.to === fixed.caret) {
              e.preventDefault(); e.stopPropagation();
              var put = text.slice(fixed.from, fixed.to);
              change(fixed.from, fixed.to, fixed.old, 'revert', fixed.caret + fixed.old.length - put.length);
              post({ type: 'keep-words', old: fixed.old, new: put });
              return;
            }
          }
          if (hooks.key && hooks.key(e)) return;
          if (e.defaultPrevented) return;
          var letter = (e.key || '').toLowerCase();
          if (e.metaKey && !e.shiftKey && letter === 'z') { e.preventDefault(); travel(history, future); }
          else if (e.metaKey && (letter === 'y' || (e.shiftKey && letter === 'z'))) { e.preventDefault(); travel(future, history); }
          else if (e.key === 'Tab') { e.preventDefault(); indent(e.shiftKey); }
          else if (e.metaKey && letter === 'b') { e.preventDefault(); wrap('**'); }
          else if (e.metaKey && letter === 'i') { e.preventDefault(); wrap('*'); }
        });
        content.addEventListener('copy', function (e) { var r = range(); if (r.from === r.to) return; e.preventDefault(); e.clipboardData.setData('text/plain', text.slice(r.from, r.to)); });
        content.addEventListener('cut', function (e) { var r = range(); if (r.from === r.to) return; e.preventDefault(); e.clipboardData.setData('text/plain', text.slice(r.from, r.to)); change(r.from, r.to, '', 'cut'); });
        // On a line you're not on, a link opens and a task's box ticks, as in Obsidian.
        content.addEventListener('mousedown', function (e) {
          var lineEl = e.target.closest('.cm-line');
          if (!lineEl || lineEl.classList.contains('cm-active') || e.button !== 0) return;
          var link = e.target.closest('[data-sage-link]');
          if (link) {
            e.preventDefault();
            var to = link.getAttribute('data-sage-link');
            post({ type: 'follow', href: /^https?:/.test(to) ? to : 'sage-note:' + to, newTab: e.metaKey });
            return;
          }
          var box = e.target.closest('.sage-task');
          if (box) {
            e.preventDefault();
            var r = document.createRange();
            r.setStart(lineEl, 0); r.setEnd(box, 0);
            var n = Array.prototype.indexOf.call(content.children, lineEl), at = starts()[n] + r.toString().length + 1;
            change(at, at + 1, text.charAt(at) === ' ' ? 'x' : ' ', 'tick', at + 1);
          }
        });
        content.addEventListener('blur', function () { unghost(); if (hooks.blur) hooks.blur(); });
        draw();
        var editor = {
          el: root,
          focus: function (at) { content.focus({ preventScroll: true }); select(at == null ? text.length : Math.min(at, text.length)); },
          blur: function () { content.blur(); },
        };
        Object.defineProperty(editor, 'value', { get: function () { return text; } });
        Object.defineProperty(editor, 'readOnly', { set: function (v) { content.contentEditable = v ? 'false' : 'true'; } });
        return editor;
      }

      function change(final) {
        if (!open) return null;
        clearTimeout(timer);
        var text = open.area.value;
        if (text === open.original) return null;
        var edit = { type: 'edit', from: open.from, to: open.to, original: open.original, text: text, live: !final };
        open.original = text;
        return edit;
      }
      function finish(flushing) {
        if (!open) return null;
        var edit = change(true), was = open;
        open = null;
        if (edit) { was.area.readOnly = true; waiting = true; if (!flushing) post(edit); }
        else if (was.saved) { waiting = true; post({ type: 'redraw' }); }
        else was.box.replaceWith(was.block);
        post({ type: 'editing', on: false });
        return edit;
      }
      // The app asks for what's still unsaved before it shows something else.
      window.sageFlush = function () {
        var edit = finish(true);
        if (edit) return JSON.stringify(edit);
        // A property being changed, or one still waiting to be sent.
        var op = prop ? propClose(true, true) : null;
        if (!op && propQueue.length && !propBusy) { op = propQueue.pop(); op.type = 'property'; op.drawn = front; }
        propQueue = [];
        return op ? JSON.stringify(op) : '';
      };

      function start(block, from, to, caret) {
        var original = lines.slice(from, to + 1).join('\n');
        var box = document.createElement('div');
        box.className = 'sage-editing';
        block.replaceWith(box);
        var editor = liveEditor(original, {
          input: function () {
            clearTimeout(timer);
            timer = setTimeout(function () {
              if (!open || open.area !== editor) return;
              var edit = change(false);
              if (edit) { open.saved = true; post(edit); }
            }, 1200);
          },
          key: key,
          blur: function () { if (open && open.area === editor) finish(false); },
        });
        box.appendChild(editor.el);
        open = { box: box, block: block, from: from, to: to, original: original, area: editor, saved: false };
        editor.focus(caret == null ? original.length : caret);
        post({ type: 'editing', on: true });
      }

      // Where in the Markdown the click was: the text just before it, found in the block's lines.
      function caretFor(x, y, original) {
        var range = document.caretRangeFromPoint && document.caretRangeFromPoint(x, y);
        if (!range || range.startContainer.nodeType !== 3) return null;
        var before = range.startContainer.textContent.slice(0, range.startOffset);
        for (var n = Math.min(before.length, 24); n >= 3; n--) {
          var piece = before.slice(before.length - n), i = original.indexOf(piece);
          if (i >= 0 && original.indexOf(piece, i + 1) < 0) return i + n;
        }
        return null;
      }
      function openAt(target, x, y) {
        var block = target.closest('[data-sage-from]');
        if (block) {
          var from = +block.getAttribute('data-sage-from'), to = +block.getAttribute('data-sage-to');
          start(block, from, to, caretFor(x, y, lines.slice(from, to + 1).join('\n')));
          return true;
        }
        // Below the last block: a new one at the end of the note.
        var place = sizer(), lastBlock = place && place.lastElementChild;
        if (place && target.closest('.markdown-preview-view') && !target.closest('.mod-header') && (!lastBlock || y > lastBlock.getBoundingClientRect().bottom)) {
          var fresh = document.createElement('div');
          place.appendChild(fresh);
          start(fresh, lines.length, lines.length - 1, 0);
          return true;
        }
        return false;
      }

      function key(event) {
        var letter = (event.key || '').toLowerCase();
        if (event.key === 'Escape' || (event.key === 'Enter' && event.metaKey)) { event.preventDefault(); if (open) open.area.blur(); return true; }
        if (event.metaKey && letter === 'e') { event.preventDefault(); if (open) open.area.blur(); post({ type: 'mode' }); return true; }
        if (event.metaKey && letter === 's') { event.preventDefault(); var edit = change(false); if (edit) { open.saved = true; post(edit); } return true; }
        return false;
      }
      document.addEventListener('keydown', function (event) {
        var key = (event.key || '').toLowerCase();
        if (event.metaKey && key === 'e' && !event.target.closest('.sage-editing')) { event.preventDefault(); post({ type: 'mode' }); return; }
        // The tabs' shortcuts, as in Obsidian on the Mac: Sage's, not the browser's (Cmd+W, Cmd+Shift+T, Cmd+O, Cmd+N,
        // Ctrl+Tab and Cmd+Shift+[ ] between tabs, Cmd+Alt+Left/Right and Cmd+[ ] back and forward).
        var bracket = event.code === 'BracketLeft' ? -1 : event.code === 'BracketRight' ? 1 : 0;
        var tab = event.metaKey && event.shiftKey && key === 't' ? 'reopen'
          : event.metaKey && !event.shiftKey && !event.altKey && key === 'o' ? 'switcher'
          : event.metaKey && !event.shiftKey && !event.altKey && key === 'n' ? 'new-note'
          : event.metaKey && !event.shiftKey && !event.altKey && key === 'w' ? 'close'
          : event.ctrlKey && key === 'tab' ? (event.shiftKey ? 'previous' : 'next')
          : event.metaKey && event.shiftKey && bracket ? (bracket < 0 ? 'previous' : 'next')
          : event.metaKey && event.altKey && key === 'arrowleft' ? 'back'
          : event.metaKey && event.altKey && key === 'arrowright' ? 'forward'
          : event.metaKey && !event.shiftKey && !event.altKey && bracket ? (bracket < 0 ? 'back' : 'forward') : null;
        if (tab) { event.preventDefault(); post({ type: 'key', key: tab }); }
      });
      // (2026-11-08): a link held with Cmd shows its note beside it (the app draws the preview).
      var previewing = null, overLink = null;
      function linkOf(el) { var a = el && el.closest && el.closest('a.internal-link, [data-sage-link]'); return a; }
      function hrefOf(a) {
        var to = a.getAttribute('data-sage-link');
        if (to) return /^https?:/.test(to) ? null : 'sage-note:' + to;
        var h = a.getAttribute('href') || '';
        return h.indexOf('sage-note:') === 0 ? h : null;
      }
      function ask(a) {
        var href = hrefOf(a);
        if (!href || previewing === a) return;
        previewing = a;
        var r = a.getBoundingClientRect();
        post({ type: 'preview', href: href, x: r.left, y: r.bottom });
      }
      function drop() { if (previewing) { previewing = null; post({ type: 'preview-end' }); } }
      document.addEventListener('mouseover', function (e) { overLink = linkOf(e.target); if (overLink && e.metaKey) ask(overLink); });
      document.addEventListener('mouseout', function (e) { if (linkOf(e.target) && !linkOf(e.relatedTarget)) { overLink = null; drop(); } });
      document.addEventListener('keydown', function (e) { if (e.key === 'Meta' && overLink) ask(overLink); });
      document.addEventListener('keyup', function (e) { if (e.key === 'Meta') drop(); });
      // The mouse's side buttons go back and forward in this tab, not in the page's own history.
      document.addEventListener('mouseup', function (event) {
        if (event.button !== 3 && event.button !== 4) return;
        event.preventDefault();
        post({ type: 'key', key: event.button === 3 ? 'back' : 'forward' });
      });
      // The middle button on a card or a canvas's Open opens it in a new tab (on a link the browser asks Sage for one).
      document.addEventListener('mousedown', function (event) { if (event.button === 1 && event.target.closest('a, [data-sage-href]')) event.preventDefault(); });
      document.addEventListener('auxclick', function (event) {
        if (event.button !== 1) return;
        var go = event.target.closest('[data-sage-href]');
        if (!go) return;
        event.preventDefault();
        post({ type: 'follow', href: go.getAttribute('data-sage-href'), newTab: true });
      });

      // MARK: Properties (2026-11-10, you asked): edited as in Obsidian's Properties table, in either view, never as
      // YAML. A value is changed where it is (text, a number, a date or time, a tick, a list's pills with × and the space
      // after them: Enter or a comma adds one, Backspace takes the last), a name by clicking it, the row's icon has the
      // type and Remove, and Add property (or Cmd+;) adds one. Enter or leaving a field saves, Esc puts it back. Each
      // change goes to Sage as one property's ('property'), written only over the frontmatter the table was drawn from
      // (`front`), one at a time; the note is redrawn around the field you're in.
      var front = props.front === undefined ? null : props.front;
      var prop = null, propQueue = [], propBusy = false, propBody = null, propFocus = null, propMenu = null;
      var propTypes = [['text', 'lucide-text'], ['multitext', 'lucide-list'], ['number', 'lucide-binary'], ['checkbox', 'lucide-check-square'], ['date', 'lucide-calendar'], ['datetime', 'lucide-clock']];
      function propRow(el) { return el && el.closest ? el.closest('.metadata-property') : null; }
      function propKey(row) { return row.getAttribute('data-property-key') || ''; }
      function setOp(key, values, list, plain) { return { op: 'set', key: key, values: values, list: list, plain: plain }; }
      function pillValues(row) {
        return Array.prototype.map.call(row.querySelectorAll('.multi-select-pill'), function (p) { return p.getAttribute('data-value') || ''; });
      }
      function propSend(op) {
        if (op.op === 'set') propQueue = propQueue.filter(function (q) { return !(q.op === 'set' && q.key === op.key); });
        propQueue.push(op);
        propPump();
      }
      function propPump() {
        if (propBusy || !propQueue.length) return;
        var op = propQueue.shift();
        op.type = 'property'; op.drawn = front;
        propBusy = true;
        post(op);
      }
      function propOpen(row, kind, field) {
        if (prop && prop.field === field) return;
        if (prop) propClose(true);
        prop = { row: row, kind: kind, field: field, key: propKey(row), fresh: !!row.sageFresh };
        prop.was = kind === 'text' ? field.textContent : kind === 'list' ? '' : field.value;
        prop.saved = kind === 'list' ? pillValues(row) : null;
        post({ type: 'editing', on: true });
      }
      // The field left: saved when it changed (`save`), else put back. With `flushing`, the change is handed back, not sent.
      function propClose(save, flushing) {
        if (!prop) return null;
        var p = prop, op = null;
        prop = null;
        if (p.kind === 'name') {
          var name = p.field.value.trim();
          if (p.fresh) {
            var same = null;
            document.querySelectorAll('.metadata-property').forEach(function (r) { if (r !== p.row && propKey(r).toLowerCase() === name.toLowerCase()) same = r; });
            var box = p.row.closest('.metadata-container');
            if (!save || !name || same) {
              p.row.remove();
              if (box && box.classList.contains('sage-new') && !box.querySelector('.metadata-property')) { var head = box.parentElement; box.remove(); if (head && !head.children.length) head.remove(); }
              if (same && save) { propFocus = propKey(same); setTimeout(propRefocus, 0); }
            } else {
              p.row.sageFresh = false;
              p.row.setAttribute('data-property-key', name);
              op = setOp(name, [], false, false);
              if (p.next) propFocus = name;
            }
          } else if (save && name && name !== p.key) {
            // Known by its new name at once, so a change to its value right after goes to it.
            op = { op: 'rename', key: p.key, to: name };
            p.row.setAttribute('data-property-key', name);
          } else p.field.value = p.key;
        } else if (p.kind === 'text') {
          var text = p.field.textContent.replace(/\s*\n\s*/g, ' ').trim();
          if (save && text !== p.was.trim()) op = setOp(p.key, text ? [text] : [], false, false);
          else p.field.textContent = p.was;
          p.field.classList.add('mod-truncate');
          if (!op && p.field.sageLink) p.field.replaceWith(p.field.sageLink);
        } else if (p.kind === 'value') {
          if (save && p.field.value !== p.was) op = setOp(p.key, p.field.value ? [p.field.value] : [], false, true);
          else p.field.value = p.was;
        } else if (p.kind === 'list') {
          var typed = p.field.textContent.trim();
          p.field.textContent = '';
          if (save && typed) addPill(p.row, typed);
          var now = pillValues(p.row);
          if (JSON.stringify(now) !== JSON.stringify(p.saved)) op = setOp(p.key, now, true, false);
        }
        post({ type: 'editing', on: false });
        if (op && flushing) { op.type = 'property'; op.drawn = front; return op; }
        if (op) propSend(op);
        setTimeout(propSettle, 300);
        return op;
      }
      // Left without saving (the note changed elsewhere): Sage redraws it as it is.
      function propDrop() {
        if (!prop) return;
        var field = prop.field;
        prop = null;
        post({ type: 'editing', on: false });
        field.blur();
      }
      // Once you've left the table, it's drawn as the note now has it (links as links, the new values in their places).
      function propSettle() {
        if (prop || propBusy || propQueue.length || !propBody) return;
        var message = propBody;
        propBody = null;
        applyBody(message);
      }
      // The note redrawn around the table you're in: everything but the header it sits in is replaced. False when the
      // page isn't laid out so (then the redraw waits until you leave the field).
      function propKeep(live, message) {
        var place = sizer(), head = live.closest('.mod-header');
        if (!place || !head || head.parentElement !== place) return true;
        var t = document.createElement('template');
        t.innerHTML = message.html;
        var fresh = t.content.querySelector('.metadata-container');
        if (fresh) ['data-sage-from', 'data-sage-to'].forEach(function (a) { if (fresh.hasAttribute(a)) live.setAttribute(a, fresh.getAttribute(a)); });
        var freshHead = fresh ? fresh.closest('.mod-header') : t.content.querySelector('.mod-header');
        Array.prototype.slice.call(place.children).forEach(function (c) { if (c !== head) c.remove(); });
        var before = true;
        Array.prototype.slice.call(t.content.childNodes).forEach(function (n) {
          if (n === freshHead) { before = false; return; }
          if (before) place.insertBefore(n, head); else place.appendChild(n);
        });
        lines = message.lines || lines;
        decorate(place);
        open = null;
        waiting = false;
        return true;
      }
      // After a new property's name, its value's field (as Obsidian moves on to it).
      function propRefocus() {
        if (!propFocus) return;
        var name = propFocus, row = null;
        propFocus = null;
        document.querySelectorAll('.metadata-property').forEach(function (r) { if (propKey(r) === name) row = r; });
        if (!row || row.hasAttribute('data-sage-complex')) return;
        var field = row.querySelector('.multi-select-input, .metadata-input-longtext[contenteditable], input.metadata-input:not([readonly])');
        if (field) field.focus();
      }
      function pillHtml(type, value) {
        var link = /^\[\[([^\]|]+)(?:\|([^\]]*))?\]\]$/.exec(value), shown = type === 'tags' ? value.replace(/^#+/, '') : link ? (link[2] || link[1]) : value;
        return '<div class="multi-select-pill-content"><span>' + esc(shown) + '</span></div><div class="multi-select-pill-remove-button">' + svg('lucide-x') + '</div>';
      }
      function addPill(row, value) {
        if (row.getAttribute('data-property-type') === 'tags') value = value.replace(/^#+/, '');
        value = value.trim();
        if (!value || pillValues(row).indexOf(value) >= 0) return false;
        var pill = document.createElement('div');
        pill.className = 'multi-select-pill'; pill.tabIndex = 0; pill.setAttribute('data-value', value);
        pill.innerHTML = pillHtml(row.getAttribute('data-property-type'), value);
        var input = row.querySelector('.multi-select-input');
        input.parentElement.insertBefore(pill, input);
        return true;
      }
      // A list changed while you're in it: saved at once, as Obsidian does with each pill.
      function listChanged(row) {
        var values = pillValues(row);
        if (prop && prop.row === row) prop.saved = values;
        propSend(setOp(propKey(row), values, true, false));
      }
      // A value shown as its link: the pencil (or the space beside it) edits it as text, its [[ ]] kept.
      function editLink(row) {
        var link = row.querySelector('.metadata-link');
        if (!link) return;
        var field = document.createElement('div');
        field.className = 'metadata-input-longtext'; field.setAttribute('placeholder', 'Empty'); field.setAttribute('contenteditable', 'plaintext-only');
        field.textContent = row.getAttribute('data-value') || '';
        field.sageLink = link;
        link.replaceWith(field);
        field.focus();
        var range = document.createRange(); range.selectNodeContents(field); range.collapse(false);
        var pick = getSelection(); pick.removeAllRanges(); pick.addRange(range);
      }
      // A new property's row (Add property, Cmd+;): its name first. A note without properties gets the table here; its
      // frontmatter is written with the first one.
      function propAdd() {
        var box = document.querySelector('.metadata-container');
        if (!box) {
          var place = sizer();
          if (!props.shown || !place) return;
          var head = place.querySelector(':scope > .mod-header');
          if (!head) {
            head = document.createElement('div'); head.className = 'mod-header mod-ui';
            var pusher = place.querySelector(':scope > .markdown-preview-pusher');
            place.insertBefore(head, pusher ? pusher.nextSibling : place.firstChild);
          }
          box = document.createElement('div');
          box.className = 'metadata-container sage-new';
          box.innerHTML = '<div class="metadata-properties-heading"><div class="collapse-indicator collapse-icon">' + svg('right-triangle') + '</div><div class="metadata-properties-title">Properties</div></div>'
            + '<div class="metadata-content"><div class="metadata-properties"></div></div>';
          head.appendChild(box);
        }
        box.classList.remove('is-collapsed');
        var row = document.createElement('div');
        row.className = 'metadata-property'; row.setAttribute('data-property-key', ''); row.setAttribute('data-property-type', 'text');
        row.sageFresh = true;
        row.innerHTML = '<div class="metadata-property-key"><span class="metadata-property-icon">' + svg('lucide-text') + '</span>'
          + '<input class="metadata-property-key-input" type="text" autocapitalize="off" spellcheck="false"></div>'
          + '<div class="metadata-property-value"><div class="metadata-input-longtext" placeholder="Empty"></div></div>';
        box.querySelector('.metadata-properties').appendChild(row);
        row.querySelector('input').focus();
      }
      function propMenuClose() { if (propMenu) { propMenu.remove(); propMenu = null; } }
      // The icon's menu: the property's type (as Obsidian's; tags, aliases and cssclasses keep theirs) and Remove.
      function propMenuOpen(icon) {
        propMenuClose();
        var row = propRow(icon), key = propKey(row), type = row.getAttribute('data-property-type');
        if (row.sageFresh) return;
        function item(action, iconName, title, extra, checked) {
          return '<div class="menu-item tappable' + (extra || '') + '" data-sage-action="' + attr(action) + '"><div class="menu-item-icon">' + svg(iconName) + '</div>'
            + '<div class="menu-item-title">' + esc(title || '') + '</div>' + (checked ? '<div class="menu-item-icon sage-menu-check">' + svg('lucide-check') + '</div>' : '') + '</div>';
        }
        var html = '';
        if (!/^(tags|aliases|cssclasses)$/i.test(key)) {
          html += '<div class="menu-group"><div class="menu-item is-label"><div class="menu-item-title">' + esc(words.type || 'Property type') + '</div></div>';
          propTypes.forEach(function (t) { html += item('type:' + t[0], t[1], words[t[0]], '', t[0] === type); });
          html += '</div><div class="menu-separator"></div>';
        }
        html += '<div class="menu-group">' + item('remove', 'lucide-trash-2', words.remove || 'Remove', ' is-warning') + '</div>';
        var menu = document.createElement('div');
        menu.className = 'menu sage-menu';
        menu.innerHTML = '<div class="menu-scroll">' + html + '</div>';
        var r = icon.getBoundingClientRect();
        menu.style.left = Math.max(4, r.left) + 'px'; menu.style.top = (r.bottom + 4) + 'px';
        document.body.appendChild(menu);
        var m = menu.getBoundingClientRect();
        if (m.bottom > window.innerHeight - 4) menu.style.top = Math.max(4, r.top - m.height - 4) + 'px';
        if (m.right > window.innerWidth - 4) menu.style.left = Math.max(4, window.innerWidth - m.width - 4) + 'px';
        menu.addEventListener('mousedown', function (e) { e.preventDefault(); });
        menu.addEventListener('click', function (e) {
          e.preventDefault(); e.stopPropagation();
          var choice = e.target.closest('[data-sage-action]');
          if (!choice) return;
          var action = choice.getAttribute('data-sage-action');
          propMenuClose();
          if (action === 'remove') { row.remove(); propSend({ op: 'remove', key: key }); }
          else if (action.indexOf('type:') === 0 && action.slice(5) !== type) propSend({ op: 'type', key: key, to: action.slice(5) });
        });
        propMenu = menu;
      }
      document.addEventListener('mousedown', function (e) { if (propMenu && !propMenu.contains(e.target)) propMenuClose(); }, true);
      document.addEventListener('scroll', function () { propMenuClose(); }, true);
      function propClick(event, target) {
        var heading = target.closest('.metadata-properties-heading');
        if (heading) { heading.parentElement.classList.toggle('is-collapsed'); return; }
        if (target.closest('.metadata-add-button')) { event.preventDefault(); propAdd(); return; }
        var row = propRow(target);
        if (!row) return;
        var icon = target.closest('.metadata-property-icon');
        if (icon) { event.preventDefault(); if (propMenu && propMenu.sageIcon === icon) propMenuClose(); else { propMenuOpen(icon); if (propMenu) propMenu.sageIcon = icon; } return; }
        var x = target.closest('.multi-select-pill-remove-button');
        if (x) { event.preventDefault(); x.closest('.multi-select-pill').remove(); listChanged(row); return; }
        if (!target.closest('.metadata-property-value')) return;
        // More than the table shows: its YAML, while editing.
        if (row.hasAttribute('data-sage-complex')) {
          var block = row.closest('[data-sage-from]');
          if (editable && block && !waiting && !open) start(block, +block.getAttribute('data-sage-from'), +block.getAttribute('data-sage-to'), null);
          return;
        }
        if (row.querySelector('.metadata-link')) { editLink(row); return; }
        if (target.closest('input, [contenteditable], .multi-select-pill')) return;
        // The space beside a value: its field, the caret at the end.
        var field = row.querySelector('.multi-select-input, .metadata-input-longtext[contenteditable], input.metadata-input:not([readonly])');
        if (!field) return;
        field.focus();
        if (field.isContentEditable) { var range = document.createRange(); range.selectNodeContents(field); range.collapse(false); var pick = getSelection(); pick.removeAllRanges(); pick.addRange(range); }
      }
      document.addEventListener('focusin', function (e) {
        var t = e.target, row = propRow(t);
        if (!row || !t.closest('.metadata-container')) return;
        if (t.matches('.metadata-property-key-input')) propOpen(row, 'name', t);
        else if (t.matches('.multi-select-input')) propOpen(row, 'list', t);
        else if (t.matches('.metadata-input-longtext[contenteditable]')) { t.classList.remove('mod-truncate'); propOpen(row, 'text', t); }
        else if (t.matches('input.metadata-input:not([readonly])')) propOpen(row, 'value', t);
      });
      document.addEventListener('focusout', function (e) { if (prop && e.target === prop.field) propClose(true); });
      document.addEventListener('change', function (e) {
        var box = e.target.closest && e.target.closest('.metadata-input-checkbox');
        var row = propRow(box);
        if (box && row && !box.disabled) propSend(setOp(propKey(row), [box.checked ? 'true' : 'false'], false, true));
      });
      document.addEventListener('keydown', function (e) {
        if (e.metaKey && !e.shiftKey && !e.altKey && e.key === ';') { e.preventDefault(); if (prop) prop.field.blur(); propAdd(); return; }
        if (propMenu && e.key === 'Escape') { e.preventDefault(); propMenuClose(); return; }
        if (!prop || e.target !== prop.field || e.isComposing) return;
        var p = prop;
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); propClose(false); p.field.blur(); return; }
        if (p.kind === 'list') {
          var typed = p.field.textContent.trim();
          if (e.key === 'Enter' || (e.key === ',' && !e.metaKey && !e.ctrlKey)) {
            e.preventDefault();
            if (typed) { p.field.textContent = ''; if (addPill(p.row, typed)) listChanged(p.row); }
            else if (e.key === 'Enter') p.field.blur();
          } else if (e.key === 'Backspace' && !p.field.textContent.length) {
            var pills = p.row.querySelectorAll('.multi-select-pill');
            if (pills.length) { e.preventDefault(); pills[pills.length - 1].remove(); listChanged(p.row); }
          }
        } else if (e.key === 'Enter') { e.preventDefault(); p.next = true; p.field.blur(); }
      });
      function applyBody(message) {
        var place = sizer();
        place.innerHTML = message.html;
        lines = message.lines || lines;
        decorate(place);
        open = null;
        waiting = false;
        if (queued && editable) { var q = queued; queued = null; var at = document.elementFromPoint(q.x, q.y); if (at) openAt(at, q.x, q.y); }
        propRefocus();
      }
      window.sageReceive = function (message) {
        if (message.type === 'complete') { if (completing.back && message.id === completing.id) completing.back(message.text || '', { word: message.word || '', replace: message.replace || 0 }); return; }
        if (message.type === 'correct') { if (correcting.back && message.id === correcting.id) correcting.back(message.fix || null); return; }
        if (message.type === 'body') {
          if ('front' in message) front = message.front;
          propBusy = false;
          // While you're in a property's field, the note is redrawn around its table, which stays as you have it.
          var live = prop && prop.row.isConnected ? prop.row.closest('.metadata-container') : null;
          if (live && propKeep(live, message)) propBody = message;
          else { propBody = null; applyBody(message); }
          propPump();
        }
        else if (message.type === 'placed') {
          lines = message.lines || lines;
          if (open) { open.from = message.from; open.to = message.to; }
        }
        else if (message.type === 'notice') {
          waiting = false;
          // A property change that couldn't be written: the field is left (nothing more sent), the table redrawn as the note has it.
          if (message.property) { propQueue = []; propBusy = false; propDrop(); }
          notice(message.text);
          if (window.sageCanvasMessage) window.sageCanvasMessage(message);
        }
        else if (window.sageCanvasMessage) window.sageCanvasMessage(message);
      };

      document.addEventListener('click', function (event) {
        var target = event.target;
        if (target.closest('.sage-editing')) return;
        if (target.matches('.task-list-item-checkbox')) {
          event.preventDefault();
          var item = target.closest('[data-sage-line]');
          if (item && !waiting) { waiting = true; post({ type: 'task', line: +item.getAttribute('data-sage-line') }); }
          return;
        }
        var copy = target.closest('.copy-code-button');
        if (copy) {
          event.preventDefault();
          var range = document.createRange(); range.selectNodeContents(copy.parentElement.querySelector('code'));
          var pick = getSelection(); pick.removeAllRanges(); pick.addRange(range); document.execCommand('copy'); pick.removeAllRanges();
          copy.innerHTML = svg('lucide-check'); setTimeout(function () { copy.innerHTML = svg('lucide-copy'); }, 1500);
          return;
        }
        var editBlock = target.closest('.sage-edit-block');
        if (editBlock) {
          event.preventDefault();
          if (!waiting && !open) {
            var block = editBlock.parentElement, from = +block.getAttribute('data-sage-from'), to = +block.getAttribute('data-sage-to');
            editBlock.remove();
            start(block, from, to, 0);
          }
          return;
        }
        // The properties, edited in their table (a link in a value still opens its note).
        if (target.closest('.metadata-container')) { if (!target.closest('a')) propClick(event, target); return; }
        if (target.closest('a')) return;
        // A base: its views, its groups folding, a card opening its note.
        var tab = target.closest('[data-sage-view-tab]');
        if (tab) {
          var base = tab.closest('[data-sage-base]'), shown = tab.getAttribute('data-sage-view-tab'), count = +tab.getAttribute('data-sage-count');
          base.querySelectorAll('[data-sage-view-tab]').forEach(function (t) { t.classList.toggle('is-active', t === tab); });
          base.querySelectorAll('[data-sage-view]').forEach(function (v) { v.hidden = v.getAttribute('data-sage-view') !== shown; });
          base.querySelector('.bases-toolbar-result-count').textContent = count + (count === 1 ? ' result' : ' results');
          baseHeads();
          return;
        }
        var group = target.closest('.sage-base .bases-group-heading');
        if (group) {
          var shut = !group.classList.contains('is-collapsed'), body = group.closest('tbody');
          group.classList.toggle('is-collapsed', shut);
          var chevron = group.querySelector('.collapse-icon'); if (chevron) chevron.classList.toggle('is-collapsed', shut);
          if (body) body.classList.toggle('sage-collapsed', shut);
          else if (group.nextElementSibling) group.nextElementSibling.hidden = shut;
          // A group folded from where it was pinned at the top: what follows it comes up under the columns' names.
          var groupView = group.closest('.bases-view'), groupBox = body || group;
          if (groupView && groupView.scrollHeight > groupView.clientHeight) {
            var groupHead = groupView.querySelector('thead');
            var d = groupBox.getBoundingClientRect().top - groupView.getBoundingClientRect().top - (groupHead ? groupHead.offsetHeight : 0);
            if (d < 0) groupView.scrollTop += d;
          }
          return;
        }
        var zoom = target.closest('[data-sage-zoom]');
        if (zoom) { zoom.closest('[data-sage-canvas]').sageZoom(+zoom.getAttribute('data-sage-zoom')); return; }
        var fitButton = target.closest('[data-sage-fit]');
        if (fitButton) { fitButton.closest('[data-sage-canvas]').sageFit(); return; }
        var go = target.closest('[data-sage-href]');
        if (go) { event.preventDefault(); post({ type: 'follow', href: go.getAttribute('data-sage-href'), newTab: event.metaKey }); return; }
        if (target.closest(embeds)) return;
        var title = target.closest('.callout.is-collapsible > .callout-title');
        if (title) {
          var callout = title.parentElement, shut = !callout.classList.contains('is-collapsed');
          callout.classList.toggle('is-collapsed', shut);
          var fold = title.querySelector('.callout-fold'); if (fold) fold.classList.toggle('is-collapsed', shut);
          var content = callout.querySelector(':scope > .callout-content'); if (content) content.style.display = shut ? 'none' : '';
          return;
        }
        var heading = target.closest('.metadata-properties-heading');
        if (heading) { heading.parentElement.classList.toggle('is-collapsed'); return; }
        if (!editable || String(getSelection()).length > 0) return;
        // A click while the last edit is being saved opens where it was once the note is redrawn.
        if (waiting) { queued = { x: event.clientX, y: event.clientY }; return; }
        openAt(target, event.clientX, event.clientY);
      });
      // (2026-11-08): a base's group headings stay under its columns' names (how tall they are, per view).
      function baseHeads() {
        document.querySelectorAll('[data-sage-base] .bases-view:not([hidden])').forEach(function (view) {
          var head = view.querySelector(':scope > table > thead');
          if (head) view.style.setProperty('--sage-base-head', head.offsetHeight + 'px');
        });
      }
      baseHeads();
      addEventListener('load', baseHeads);
      addEventListener('resize', baseHeads);
      if (document.fonts && document.fonts.ready) document.fonts.ready.then(baseHeads);
      // (2026-11-08): in a long note, the headings above where you are stay in a bar at the top (each in its
      // theme's colour); one pressed is brought back into view. It slides away near the top of the note.
      (function () {
        var scroller = document.querySelector('.markdown-reading-view > .markdown-preview-view');
        if (!scroller || scroller.classList.contains('sage-file-page')) return;
        var bar = document.createElement('div');
        bar.className = 'sage-where';
        bar.setAttribute('role', 'navigation');
        bar.setAttribute('aria-label', 'Headings you are under');
        scroller.parentElement.appendChild(bar);
        var shownKey = '', frame = 0;
        function headings() {
          return Array.prototype.filter.call(scroller.querySelectorAll('.markdown-preview-sizer h1, .markdown-preview-sizer h2, .markdown-preview-sizer h3, .markdown-preview-sizer h4, .markdown-preview-sizer h5, .markdown-preview-sizer h6'),
            function (h) { return !h.closest('.markdown-embed, .callout, .sage-base, .va-canvas-embed, .sage-live') && h.offsetParent !== null; });
        }
        function update() {
          frame = 0;
          var top = scroller.getBoundingClientRect().top + (bar.classList.contains('is-shown') ? bar.offsetHeight : 0) + 4;
          var all = headings(), chain = [];
          for (var i = 0; i < all.length; i++) {
            if (all[i].getBoundingClientRect().top > top) break;
            var level = +all[i].tagName[1];
            while (chain.length && +chain[chain.length - 1].tagName[1] >= level) chain.pop();
            chain.push(all[i]);
          }
          var show = chain.length > 0 && scroller.scrollTop > 60;
          bar.classList.toggle('is-shown', show);
          var key = chain.map(function (h) { return h.textContent; }).join('\u0001');
          if (!show || key === shownKey) return;
          shownKey = key;
          var sizer = scroller.querySelector('.markdown-preview-sizer');
          if (sizer) bar.style.paddingLeft = Math.max(14, sizer.getBoundingClientRect().left - scroller.parentElement.getBoundingClientRect().left - 7) + 'px';
          bar.textContent = '';
          chain.forEach(function (h, i) {
            if (i > 0) { var sep = document.createElement('span'); sep.className = 'sage-where-sep'; sep.textContent = '›'; bar.appendChild(sep); }
            var b = document.createElement('button');
            b.textContent = h.textContent.replace(/\s+/g, ' ').trim();
            b.title = b.textContent;
            b.setAttribute('data-level', h.tagName[1]);
            b.addEventListener('click', function () {
              var to = h.getBoundingClientRect().top - scroller.getBoundingClientRect().top - bar.offsetHeight - 6;
              scroller.scrollTo({ top: scroller.scrollTop + to, behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
            });
            bar.appendChild(b);
          });
        }
        scroller.addEventListener('scroll', function () { if (!frame) frame = requestAnimationFrame(update); }, { passive: true });
        new MutationObserver(function (records) {
          if (records.every(function (r) { return bar.contains(r.target); })) return;
          shownKey = '';
          if (!frame) frame = requestAnimationFrame(update);
        }).observe(scroller, { childList: true, subtree: true });
      })();
      // (2026-11-11, you asked) The title at the top is the file's name, edited in place as in Obsidian: Enter or a click
      // away renames the note (links to it follow), Esc puts it back; one line, plain text.
      (function () {
        var shownName = null;
        function title() { return document.querySelector('.inline-title[contenteditable]'); }
        function cleaned(el) { return (el.innerText || '').replace(/[\r\n]+/g, ' ').replace(/\u00a0/g, ' ').trim(); }
        function back() { var el = title(); if (el && shownName !== null) el.textContent = shownName; }
        document.addEventListener('focusin', function (e) {
          if (e.target.matches && e.target.matches('.inline-title[contenteditable]')) shownName = cleaned(e.target);
        });
        document.addEventListener('focusout', function (e) {
          if (!(e.target.matches && e.target.matches('.inline-title[contenteditable]')) || shownName === null) return;
          var name = cleaned(e.target), was = shownName;
          shownName = null;
          if (!name) { e.target.textContent = was; return; }
          e.target.textContent = name;
          if (name !== was) { shownName = was; post({ type: 'rename-note', name: name, was: was }); }
        });
        document.addEventListener('keydown', function (e) {
          var el = e.target.matches && e.target.matches('.inline-title[contenteditable]') ? e.target : null;
          if (!el || e.isComposing) return;
          if (e.key === 'Enter' || e.key === 'Escape' || (e.key === 'Tab' && !e.shiftKey)) {
            e.preventDefault(); e.stopPropagation();
            if (e.key === 'Escape') el.textContent = shownName;
            el.blur();
            return;
          }
          e.stopPropagation();
        }, true);
        document.addEventListener('paste', function (e) {
          if (!(e.target.closest && e.target.closest('.inline-title[contenteditable]'))) return;
          e.preventDefault();
          document.execCommand('insertText', false, (e.clipboardData.getData('text/plain') || '').replace(/[\r\n]+/g, ' '));
        }, true);
        var before = window.sageReceive;
        window.sageReceive = function (message) {
          if (message.type === 'title-back') { back(); shownName = null; return; }
          if (before) before(message);
        };
      })();
      // (2026-11-11, you asked) A base's table edited in place, as a spreadsheet: a click picks a cell (Shift or a drag picks
      // more), a second click, a double-click, Enter or typing edits it (text, number, date, a menu of the values the vault
      // uses, a list's pills); a chip opens its menu at once, a tick toggles. Cmd+C, X and V copy, cut and paste
      // (tab-separated, as spreadsheets do, so a range pastes from Numbers, Sheets or Excel), Delete clears, Cmd+Z undoes
      // and Cmd+Shift+Z redoes. Each cell is one property of one note, written by Sage (`baseCells`) only if the note still
      // reads as the cell showed it. Formula and file columns are read only.
      (function () {
        var pick = null, editor = null, drag = null, undo = [], redo = [], sent = [];
        var catcher = document.createElement('textarea');
        catcher.className = 'sage-cell-catcher'; catcher.setAttribute('aria-hidden', 'true'); catcher.tabIndex = -1;
        document.body.appendChild(catcher);
        var plainKinds = { number: 1, checkbox: 1, date: 1, datetime: 1 };

        function rowsOf(table) { return Array.prototype.filter.call(table.querySelectorAll('tr.sage-base-row'), function (tr) { return tr.offsetParent !== null; }); }
        function posOf(td) { var table = td.closest('table'); return { table: table, r: rowsOf(table).indexOf(td.parentElement), c: td.cellIndex }; }
        function cellAt(table, r, c) { var tr = rowsOf(table)[r]; return tr ? tr.cells[c] || null : null; }
        function box() {
          if (!pick) return null;
          return { r0: Math.min(pick.a.r, pick.f.r), r1: Math.max(pick.a.r, pick.f.r), c0: Math.min(pick.a.c, pick.f.c), c1: Math.max(pick.a.c, pick.f.c) };
        }
        function picked() {
          var b = box(), out = [];
          if (!b) return out;
          var list = rowsOf(pick.table);
          for (var r = b.r0; r <= b.r1; r++) { var line = []; for (var c = b.c0; c <= b.c1; c++) line.push(list[r] ? list[r].cells[c] : null); out.push(line); }
          return out;
        }
        function was(td) { try { return JSON.parse(td.getAttribute('data-sage-was') || '[]'); } catch (e) { return []; } }
        function textOf(td) {
          if (!td) return '';
          if (td.hasAttribute('data-sage-kind')) return was(td).join(', ');
          return (td.innerText || '').replace(/[\t\r\n]+/g, ' ').trim();
        }
        function tsv() { return picked().map(function (line) { return line.map(textOf).join('\t'); }).join('\n'); }
        function prime() {
          if (editor) return;
          catcher.value = tsv() || ' ';
          if (document.activeElement !== catcher) catcher.focus({ preventScroll: true });
          catcher.select();
        }
        function paint() {
          document.querySelectorAll('.sage-cell-picked, .sage-cell-focus').forEach(function (e) { e.classList.remove('sage-cell-picked', 'sage-cell-focus'); });
          if (!pick || !pick.table.isConnected) { pick = null; return; }
          picked().forEach(function (line) { line.forEach(function (td) { if (td) td.classList.add('sage-cell-picked'); }); });
          var f = cellAt(pick.table, pick.f.r, pick.f.c);
          if (f) {
            f.classList.add('sage-cell-focus');
            var view = f.closest('.bases-view'), fr = f.getBoundingClientRect();
            if (view) {
              var vr = view.getBoundingClientRect(), head = view.querySelector('thead'), top = vr.top + (head ? head.offsetHeight : 0);
              if (fr.left < vr.left) view.scrollLeft -= vr.left - fr.left; else if (fr.right > vr.right) view.scrollLeft += fr.right - vr.right;
              if (fr.top < top) view.scrollTop -= top - fr.top; else if (fr.bottom > vr.bottom) view.scrollTop += fr.bottom - vr.bottom;
            }
            f.scrollIntoView({ block: 'nearest', inline: 'nearest' });
          }
          prime();
        }
        function unpick() { pick = null; paint(); if (document.activeElement === catcher) catcher.blur(); }
        function move(dr, dc, extend) {
          if (!pick) return;
          var list = rowsOf(pick.table), cols = list.length ? list[0].cells.length : 0;
          var r = Math.max(0, Math.min(list.length - 1, pick.f.r + dr)), c = Math.max(0, Math.min(cols - 1, pick.f.c + dc));
          pick.f = { r: r, c: c };
          if (!extend) pick.a = { r: r, c: c };
          paint();
        }

        // What a typed or pasted value becomes in a cell of each kind (null: it can't go there).
        function pad(n) { return (n < 10 ? '0' : '') + n; }
        function asValues(kind, text) {
          text = (text || '').replace(/ /g, ' ').trim();
          if (!text) return [];
          if (kind === 'list') {
            var items = [], depth = 0, at = '';
            for (var i = 0; i < text.length; i++) {
              var ch = text[i];
              if (ch === '[') depth++; else if (ch === ']') depth = Math.max(0, depth - 1);
              if (ch === ',' && depth === 0) { items.push(at); at = ''; } else at += ch;
            }
            items.push(at);
            return items.map(function (s) { return s.trim(); }).filter(Boolean);
          }
          if (kind === 'checkbox') return [/^(true|yes|y|1|x|✓|✔|on|checked)$/i.test(text) ? 'true' : 'false'];
          if (kind === 'number') { var n = text.replace(/[, _]/g, ''); return isFinite(+n) && n !== '' ? [n] : null; }
          if (kind === 'date' || kind === 'datetime') {
            var m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?/.exec(text), d = m ? null : new Date(text);
            if (!m && (!d || isNaN(d))) return null;
            var day = m ? m[1] + '-' + m[2] + '-' + m[3] : d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
            if (kind === 'date') return [day];
            return [day + 'T' + (m ? (m[4] || '00') + ':' + (m[5] || '00') : pad(d.getHours()) + ':' + pad(d.getMinutes()))];
          }
          return [text.replace(/[\r\n\t]+/g, ' ')];
        }
        // A link's name as shown ([[Notes/Active|on]] → on, [[Active]] → Active); other text as it is.
        function shown(v) {
          var m = /^\[\[([^\]]*)\]\]$/.exec(String(v).trim());
          if (!m) return String(v);
          var inner = m[1], bar = inner.indexOf('|');
          if (bar >= 0) return inner.slice(bar + 1);
          inner = inner.split('#')[0];
          return inner.slice(inner.lastIndexOf('/') + 1);
        }
        function same(a, b) { return a.length === b.length && a.every(function (x, i) { return x === b[i]; }); }
        function editFor(td, values) {
          var kind = td && td.getAttribute('data-sage-kind');
          if (!kind || kind === 'name' || !values) return null;
          var old = was(td);
          if (same(old, values)) return null;
          return { path: td.parentElement.getAttribute('data-sage-path'), key: td.getAttribute('data-sage-key'), was: old, values: values, list: kind === 'list', plain: !!plainKinds[kind] };
        }
        function send(edits, kind) {
          edits = edits.filter(Boolean);
          if (!edits.length) return;
          sent.push(kind || 'do');
          post({ type: 'base-cell', edits: edits });
        }
        function inverse(e) { return { path: e.path, key: e.key, was: (e.values || []).map(function (v) { return String(v).trim(); }).filter(Boolean), values: e.was, list: e.list, plain: e.plain }; }
        function readOnly() { notice('Formulas and file details come from the base and the files; change those in the note or the base itself.'); }

        // Clearing, pasting and toggling: every picked cell that can be edited.
        function clear() {
          var edits = [], skipped = 0;
          picked().forEach(function (line) { line.forEach(function (td) { if (!td) return; if (td.hasAttribute('data-sage-kind') && td.getAttribute('data-sage-kind') !== 'name') edits.push(editFor(td, [])); else skipped++; }); });
          send(edits);
          if (skipped && !edits.filter(Boolean).length) readOnly();
        }
        function paste(text) {
          if (!pick) return;
          var lines = text.replace(/\r\n?/g, '\n').split('\n');
          if (lines.length > 1 && lines[lines.length - 1] === '') lines.pop();
          var grid = lines.map(function (l) { return l.split('\t'); });
          var b = box(), edits = [], bad = 0, skipped = 0;
          var single = grid.length === 1 && grid[0].length === 1;
          var r1 = single ? b.r1 : b.r0 + grid.length - 1, c1 = single ? b.c1 : b.c0 + grid[0].length - 1;
          for (var r = b.r0; r <= r1; r++) for (var c = b.c0; c <= c1; c++) {
            var td = cellAt(pick.table, r, c), text = single ? grid[0][0] : (grid[r - b.r0] || [])[c - b.c0];
            if (!td || text === undefined) continue;
            var kind = td.getAttribute('data-sage-kind');
            if (!kind || kind === 'name') { skipped++; continue; }
            var values = asValues(kind, text);
            if (!values) { bad++; continue; }
            edits.push(editFor(td, values));
          }
          send(edits);
          if (!single) { var list = rowsOf(pick.table); pick.a = { r: b.r0, c: b.c0 }; pick.f = { r: Math.min(r1, list.length - 1), c: Math.min(c1, list[0].cells.length - 1) }; paint(); }
          if (bad) notice(bad + (bad === 1 ? ' value didn’t fit its column (a number or a date), so it was left out.' : ' values didn’t fit their columns (numbers or dates), so they were left out.'));
          else if (skipped && !edits.filter(Boolean).length) readOnly();
        }
        function toggle(td) {
          var on = was(td)[0] === 'true';
          send([editFor(td, [on ? 'false' : 'true'])]);
        }
        function step(back) {
          var from = back ? undo : redo;
          if (!from.length) return;
          send(from.pop(), back ? 'undo' : 'redo');
        }

        // The editor: laid over the cell (fixed, so the view's scrolling never clips its menu), moved as the page scrolls.
        function optionsOf(td) {
          var th = td.closest('table').querySelector('thead tr').cells[td.cellIndex];
          try { return JSON.parse(th.getAttribute('data-sage-options') || '[]'); } catch (e) { return []; }
        }
        function edit(td, typed) {
          var kind = td.getAttribute('data-sage-kind'), naming = kind === 'name';
          if (!kind) { readOnly(); return; }
          if (kind === 'checkbox') { toggle(td); return; }
          if (naming) kind = 'text';
          if (editor) editor.close(true);
          var old = was(td), shell = document.createElement('div'), field, picker = kind === 'select' || kind === 'list';
          var pills = old.slice(), menu = null, lit = 0, pillBox = null;
          var th = td.closest('table').querySelector('thead tr').cells[td.cellIndex], hues = {};
          try { hues = JSON.parse(th.getAttribute('data-sage-hues') || '{}'); } catch (e) {}
          function hueOf(v) {
            for (var k in hues) if (shown(k).toLowerCase() === shown(v).toLowerCase()) return hues[k];
            var h = 0; for (var i = 0; i < v.length; i++) h = (h * 31 + v.charCodeAt(i)) >>> 0; return h % 8;
          }
          function chip(v) { var c = document.createElement('span'); c.className = 'sage-chip sage-hue-' + hueOf(v); c.textContent = shown(v); return c; }
          shell.className = 'sage-cell-editor' + (picker ? ' is-picker' : '');
          if (kind === 'date' || kind === 'datetime') {
            field = document.createElement('input');
            field.type = kind === 'date' ? 'date' : 'datetime-local';
            field.value = old[0] ? (kind === 'date' ? old[0].slice(0, 10) : old[0].replace(' ', 'T').slice(0, 16)) : '';
          } else if (picker) {
            // As Notion's status and multi-select: the value(s) as pills on top, a search under them, every option below.
            field = document.createElement('input'); field.type = 'text';
            field.placeholder = pills.length && kind === 'select' ? 'Search for another option…' : 'Search for an option…';
            field.value = typed !== undefined ? typed : '';
          } else {
            field = document.createElement(kind === 'text' ? 'textarea' : 'input');
            if (kind !== 'text') field.type = 'text';
            if (kind === 'number') field.inputMode = 'decimal';
            field.value = typed !== undefined ? typed : old.join(', ');
            if (kind === 'text') field.rows = 1;
          }
          field.className = 'sage-cell-field';
          field.spellcheck = kind === 'text';
          if (picker) {
            var top = document.createElement('div'); top.className = 'sage-cell-top';
            pillBox = document.createElement('div'); pillBox.className = 'sage-cell-pills';
            top.appendChild(pillBox); top.appendChild(field); shell.appendChild(top);
            menu = document.createElement('div'); menu.className = 'sage-cell-menu'; shell.appendChild(menu);
          } else shell.appendChild(field);
          document.body.appendChild(shell);
          post({ type: 'editing', on: true });

          function drawPills() {
            if (!pillBox) return;
            pillBox.textContent = '';
            pills.forEach(function (v, i) {
              var p = chip(v); p.classList.add('sage-cell-pill');
              var x = document.createElement('span'); x.className = 'sage-cell-pill-x'; x.innerHTML = svg('lucide-x'); x.title = 'Remove';
              x.addEventListener('mousedown', function (e) { e.preventDefault(); e.stopPropagation(); pills.splice(i, 1); drawPills(); drawMenu(); place(); field.focus(); });
              p.appendChild(x); pillBox.appendChild(p);
            });
          }
          function choices() {
            if (!picker) return null;
            var typedNow = field.value.trim(), q = typedNow.toLowerCase(), all = optionsOf(td);
            var key = function (v) { return shown(v).toLowerCase(); }, has = function (set, v) { return set.some(function (o) { return key(o) === key(v); }); };
            pills.forEach(function (v) { if (!has(all, v)) all = [v].concat(all); });
            var list = all.filter(function (o) { return (!q || key(o).indexOf(q) >= 0) && (kind !== 'list' || !has(pills, o)); }).slice(0, 100)
              .map(function (o) { return { value: o }; });
            if (q && !all.some(function (o) { return key(o) === q; })) list.push({ value: typedNow, fresh: true });
            return list;
          }
          function drawMenu() {
            var list = choices();
            if (!list) return;
            lit = Math.max(0, Math.min(lit, list.length - 1));
            menu.textContent = '';
            var hint = document.createElement('div'); hint.className = 'sage-cell-hint';
            hint.textContent = list.length ? (kind === 'list' ? 'Select options or create one' : 'Select an option or create one') : 'No options yet: type one';
            menu.appendChild(hint);
            list.forEach(function (o, i) {
              var row = document.createElement('div');
              var current = kind === 'select' && pills[0] && shown(pills[0]).toLowerCase() === shown(o.value).toLowerCase();
              row.className = 'sage-cell-option' + (i === lit ? ' is-lit' : '') + (current ? ' is-current' : '');
              if (o.fresh) { var w = document.createElement('span'); w.className = 'sage-cell-create'; w.textContent = 'Create'; row.appendChild(w); }
              row.appendChild(chip(o.value));
              if (current) { var tick = document.createElement('span'); tick.className = 'sage-cell-tick'; tick.innerHTML = svg('lucide-check'); row.appendChild(tick); }
              row.addEventListener('mousedown', function (e) { e.preventDefault(); e.stopPropagation(); choose(o); });
              row.addEventListener('mousemove', function () { if (lit !== i) { lit = i; menu.querySelectorAll('.sage-cell-option').forEach(function (r, j) { r.classList.toggle('is-lit', j === i); }); } });
              menu.appendChild(row);
            });
            var l = menu.querySelector('.is-lit'); if (l) l.scrollIntoView({ block: 'nearest' });
          }
          function choose(o) {
            if (kind === 'select') { pills = o.value ? [o.value] : []; close(true); return; }
            if (o.value && !pills.some(function (p) { return shown(p).toLowerCase() === shown(o.value).toLowerCase(); })) pills.push(o.value);
            field.value = ''; lit = 0; drawPills(); drawMenu(); place(); field.focus();
          }
          function place() {
            if (!td.isConnected) { close(false); return; }
            var r = td.getBoundingClientRect();
            shell.style.minWidth = Math.max(r.width, picker ? 260 : 160) + 'px';
            if (!picker) shell.style.minHeight = r.height + 'px';
            if (field.tagName === 'TEXTAREA') { field.style.height = 'auto'; field.style.height = Math.min(field.scrollHeight, 240) + 'px'; }
            var left = Math.max(4, Math.min(r.left, innerWidth - shell.offsetWidth - 8)), topAt = r.top;
            if (topAt + shell.offsetHeight > innerHeight - 8) topAt = Math.max(4, innerHeight - 8 - shell.offsetHeight);
            shell.style.left = left + 'px'; shell.style.top = topAt + 'px';
          }
          function valuesNow() {
            if (kind === 'select') return pills.slice(0, 1);
            if (kind === 'list') return pills.slice();
            return asValues(kind, field.value);
          }
          function pending() { var v = valuesNow(); return v && !naming ? editFor(td, v) : null; }
          function close(save, then) {
            if (!editor || editor.shell !== shell) return;
            var change = save ? pending() : null;
            // A note's name: renamed by Sage as the tree renames it (links follow; Undo is in Sage's list of changes).
            var renamed = save && naming ? field.value.replace(/\s+/g, ' ').trim() : '';
            if (renamed && renamed !== old[0]) post({ type: 'base-rename', path: td.parentElement.getAttribute('data-sage-path'), name: renamed, was: old[0] });
            if (save && !valuesNow()) notice(kind === 'number' ? 'That isn’t a number, so it wasn’t saved.' : 'That isn’t a date, so it wasn’t saved.');
            editor = null;
            removeEventListener('scroll', place, true); removeEventListener('resize', place);
            shell.remove();
            post({ type: 'editing', on: false });
            if (change) send([change]);
            if (then) then(); else paint();
          }
          field.addEventListener('input', function () { lit = 0; drawMenu(); place(); });
          field.addEventListener('keydown', function (e) {
            if (e.isComposing) return;
            e.stopPropagation();
            var list = picker ? choices() : [];
            if (e.key === 'Escape') { e.preventDefault(); close(picker); return; }
            if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && list.length) {
              e.preventDefault(); lit = (lit + (e.key === 'ArrowDown' ? 1 : list.length - 1)) % list.length; drawMenu(); return;
            }
            if (e.key === 'Tab') { e.preventDefault(); close(true, function () { move(0, e.shiftKey ? -1 : 1); }); return; }
            if (picker) {
              if (e.key === 'Enter') {
                e.preventDefault();
                if (list[lit] && (field.value.trim() || kind === 'select')) choose(list[lit]);
                else close(true, function () { move(1, 0); });
                return;
              }
              if (kind === 'list' && e.key === ',' && field.value.trim()) { e.preventDefault(); choose({ value: field.value.trim() }); return; }
              if (e.key === 'Backspace' && !field.value && pills.length) { e.preventDefault(); pills.pop(); drawPills(); drawMenu(); place(); }
              return;
            }
            if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); close(true, function () { move(1, 0); }); }
          });
          editor = { shell: shell, close: close, pending: pending, has: function (el) { return shell.contains(el); } };
          if (kind === 'select' && pills[0] && typed === undefined) { var at = choices().findIndex(function (o) { return shown(o.value).toLowerCase() === shown(pills[0]).toLowerCase(); }); lit = Math.max(0, at); }
          drawPills(); drawMenu();
          addEventListener('scroll', place, true); addEventListener('resize', place);
          place();
          field.focus({ preventScroll: true });
          if (!picker && field.setSelectionRange && field.type !== 'date' && field.type !== 'datetime-local') { var end = field.value.length; field.setSelectionRange(typed !== undefined ? end : 0, end); }
        }

        // Picking with the mouse; links in a cell still open their note, a tick still toggles.
        function tdOf(target) {
          var td = target.closest && target.closest('.sage-base-table td[data-sage-cell]');
          return td && td.closest('.bases-view') ? td : null;
        }
        document.addEventListener('mousedown', function (e) {
          if (e.button !== 0) return;
          if (editor && editor.has(e.target)) return;
          if (editor) editor.close(true, function () {});
          var td = tdOf(e.target);
          if (!td) { if (pick) unpick(); return; }
          if (e.target.closest('a, [data-sage-tick]')) { pick = { table: td.closest('table'), a: posOf(td), f: posOf(td) }; paint(); return; }
          e.preventDefault();
          var at = posOf(td), focusBefore = pick && pick.table === at.table && pick.a.r === pick.f.r && pick.a.c === pick.f.c && pick.f.r === at.r && pick.f.c === at.c;
          if (e.shiftKey && pick && pick.table === at.table) pick.f = { r: at.r, c: at.c };
          else pick = { table: at.table, a: { r: at.r, c: at.c }, f: { r: at.r, c: at.c } };
          drag = { td: td, again: focusBefore && !e.shiftKey, moved: false };
          paint();
          var chip = e.target.closest('.sage-chip');
          if (chip && td.getAttribute('data-sage-kind') === 'select' && !e.shiftKey) { drag = null; edit(td); }
        }, true);
        document.addEventListener('mousemove', function (e) {
          if (!drag || !pick || !(e.buttons & 1)) return;
          var td = tdOf(e.target);
          if (!td || td === drag.td && !drag.moved || td.closest('table') !== pick.table) return;
          drag.moved = true;
          var at = posOf(td);
          if (at.r !== pick.f.r || at.c !== pick.f.c) { pick.f = { r: at.r, c: at.c }; paint(); }
        });
        document.addEventListener('mouseup', function (e) {
          var d = drag; drag = null;
          if (d && d.again && !d.moved && tdOf(e.target) === d.td) edit(d.td);
        });
        document.addEventListener('dblclick', function (e) {
          var td = tdOf(e.target);
          if (!td || e.target.closest('a, [data-sage-tick]') || (editor && editor.has(e.target))) return;
          e.preventDefault();
          if (!editor) edit(td);
        }, true);
        document.addEventListener('click', function (e) {
          var tick = e.target.closest && e.target.closest('.sage-base-table input[data-sage-tick]');
          if (!tick) return;
          e.preventDefault(); e.stopPropagation();
          var td = tick.closest('td');
          if (td) toggle(td);
        }, true);

        // Keys, while cells are picked (the hidden box holds the focus, so Cmd+C and Cmd+V reach the page).
        catcher.addEventListener('keydown', function (e) {
          if (!pick || e.isComposing) return;
          var key = e.key, meta = e.metaKey || e.ctrlKey;
          if (meta && key.toLowerCase() === 'z') { e.preventDefault(); e.stopPropagation(); step(!e.shiftKey); return; }
          if (meta && key.toLowerCase() === 'a') {
            e.preventDefault(); e.stopPropagation();
            var list = rowsOf(pick.table); pick.a = { r: 0, c: 0 }; pick.f = { r: list.length - 1, c: list.length ? list[0].cells.length - 1 : 0 }; paint(); return;
          }
          if (meta) return;
          var moves = { ArrowUp: [-1, 0], ArrowDown: [1, 0], ArrowLeft: [0, -1], ArrowRight: [0, 1] };
          if (moves[key]) { e.preventDefault(); e.stopPropagation(); move(moves[key][0], moves[key][1], e.shiftKey); return; }
          var f = cellAt(pick.table, pick.f.r, pick.f.c);
          if (key === 'Tab') { e.preventDefault(); e.stopPropagation(); move(0, e.shiftKey ? -1 : 1); return; }
          if (key === 'Escape') { e.preventDefault(); e.stopPropagation(); unpick(); return; }
          if (key === 'Enter' || key === 'F2') { e.preventDefault(); e.stopPropagation(); if (f) edit(f); return; }
          if (key === 'Backspace' || key === 'Delete') { e.preventDefault(); e.stopPropagation(); clear(); return; }
          if (key === ' ' && f && f.getAttribute('data-sage-kind') === 'checkbox') { e.preventDefault(); e.stopPropagation(); toggle(f); return; }
          if (key.length === 1 && !e.altKey && f) {
            var kind = f.getAttribute('data-sage-kind');
            e.preventDefault(); e.stopPropagation();
            if (!kind) { readOnly(); return; }
            if (kind === 'text' || kind === 'name' || kind === 'number' || kind === 'select' || kind === 'list') { pick.a = { r: pick.f.r, c: pick.f.c }; paint(); edit(f, key); }
            else edit(f);
          }
        });
        catcher.addEventListener('copy', function (e) { if (!pick) return; e.preventDefault(); e.clipboardData.setData('text/plain', tsv()); });
        catcher.addEventListener('cut', function (e) { if (!pick) return; e.preventDefault(); e.clipboardData.setData('text/plain', tsv()); clear(); });
        catcher.addEventListener('paste', function (e) { if (!pick) return; e.preventDefault(); paste(e.clipboardData.getData('text/plain') || ''); });
        catcher.addEventListener('blur', function () { setTimeout(function () { if (!editor && document.activeElement !== catcher && pick) { document.querySelectorAll('.sage-cell-focus').forEach(function (c) { c.classList.add('is-idle'); }); } }, 0); });
        catcher.addEventListener('focus', function () { document.querySelectorAll('.sage-cell-focus.is-idle').forEach(function (c) { c.classList.remove('is-idle'); }); });

        // What Sage says back: which changes were written (they can be undone), and the base drawn again, which keeps the
        // view, the folded groups, where it was scrolled and the cells picked.
        // The base's view tabs dragged into a new order (2026-11-12, you asked), the others sliding aside as it passes, the
        // tab settling into its place; then the file's views: list is rewritten to match ('base-views').
        var tabDrag = null, tabDragged = false;
        document.addEventListener('mousedown', function (e) {
          var tab = e.button === 0 && e.target.closest && e.target.closest('.sage-file-view > [data-sage-base] .sage-base-tab');
          if (!tab || e.target.closest('[contenteditable]')) return;
          tabDrag = { tab: tab, row: tab.parentElement, x: e.clientX, home: tab.offsetLeft, on: false, before: Array.prototype.map.call(tab.parentElement.children, function (t) { return t.getAttribute('data-sage-view-tab'); }).join() };
        }, true);
        document.addEventListener('mousemove', function (e) {
          var d = tabDrag;
          if (!d) return;
          if (!(e.buttons & 1)) { tabDrop(); return; }
          if (!d.on) {
            if (Math.abs(e.clientX - d.x) < 5) return;
            d.on = true; d.tab.classList.remove('is-settling'); d.tab.classList.add('is-dragging'); d.row.classList.add('is-sorting');
          }
          e.preventDefault();
          var tabs = Array.prototype.slice.call(d.row.children), mid = e.clientX, target = null, after = false, at = tabs.indexOf(d.tab);
          function centre(t) { var r = t.getBoundingClientRect(); return r.left + r.width / 2; }
          for (var i = at + 1; i < tabs.length; i++) if (mid > centre(tabs[i])) { target = tabs[i]; after = true; }
          if (!target) for (var j = at - 1; j >= 0; j--) if (mid < centre(tabs[j])) { target = tabs[j]; after = false; }
          if (target) {
            var rects = new Map(tabs.map(function (t) { return [t, t.getBoundingClientRect().left]; }));
            d.row.insertBefore(d.tab, after ? target.nextSibling : target);
            tabs.forEach(function (t) {
              if (t === d.tab) return;
              var shift = rects.get(t) - t.getBoundingClientRect().left;
              if (!shift) return;
              t.style.transition = 'none'; t.style.transform = 'translateX(' + shift + 'px)';
              requestAnimationFrame(function () { t.style.transition = 'transform 0.2s cubic-bezier(0.2, 0.8, 0.3, 1)'; t.style.transform = ''; });
            });
          }
          d.tab.style.transform = 'translateX(' + (e.clientX - d.x - (d.tab.offsetLeft - d.home)) + 'px)';
        }, true);
        document.addEventListener('mouseup', function () { tabDrop(); }, true);
        function tabDrop() {
          var d = tabDrag; tabDrag = null;
          if (!d || !d.on) return;
          tabDragged = true; setTimeout(function () { tabDragged = false; }, 0);
          d.row.classList.remove('is-sorting');
          d.tab.classList.add('is-settling'); d.tab.classList.remove('is-dragging'); d.tab.style.transform = '';
          setTimeout(function () { d.tab.classList.remove('is-settling'); }, 220);
          var tabs = Array.prototype.slice.call(d.row.children), order = tabs.map(function (t) { return +t.getAttribute('data-sage-view-tab'); });
          if (order.join() === d.before) return;
          // Each tab and its view numbered by their new places, so a redraw finds the view you're on.
          var base = d.row.closest('[data-sage-base]'), views = Array.prototype.slice.call(base.querySelectorAll('[data-sage-view]'));
          tabs.forEach(function (t, i) {
            views.forEach(function (v) { if (v.getAttribute('data-sage-view') === String(order[i]) && !v.hasAttribute('data-sage-renumbered')) { v.setAttribute('data-sage-view', i); v.setAttribute('data-sage-renumbered', ''); } });
            t.setAttribute('data-sage-view-tab', i);
          });
          views.forEach(function (v) { v.removeAttribute('data-sage-renumbered'); });
          post({ type: 'base-views', order: order });
        }
        window.addEventListener('click', function (e) { if (tabDragged && e.target.closest && e.target.closest('.sage-base-tab')) { e.preventDefault(); e.stopPropagation(); } }, true);

        // A view's menus (2026-11-12, you asked, as Obsidian's): right-click a tab for Rename, Layout, Properties,
        // Duplicate and Delete, + for a new view; click or right-click a column's header to sort it, move it or hide it.
        // Each is one change to the .base file ('base-view'), then the base is drawn again.
        var viewMenu = null;
        function viewMenuClose() { if (viewMenu) { viewMenu.remove(); viewMenu = null; } }
        function ownBase(el) { return el && el.closest && el.closest('.sage-file-view > [data-sage-base]'); }
        function h(t) { return String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
        function openMenu(x, y, entries) {
          viewMenuClose();
          var html = '';
          entries.forEach(function (e, i) {
            if (e === '-') { html += '<div class="menu-separator"></div>'; return; }
            if (e.label) { html += '<div class="menu-item is-label"><div class="menu-item-title">' + h(e.label) + '</div></div>'; return; }
            html += '<div class="menu-item tappable' + (e.warn ? ' is-warning' : '') + (e.off ? ' is-disabled' : '') + '" data-sage-entry="' + i + '"><div class="menu-item-icon">' + svg(e.icon || '') + '</div>'
              + '<div class="menu-item-title">' + h(e.title) + '</div>' + (e.checked ? '<div class="menu-item-icon sage-menu-check">' + svg('lucide-check') + '</div>' : '') + '</div>';
          });
          var menu = document.createElement('div');
          menu.className = 'menu sage-menu sage-view-menu';
          menu.innerHTML = '<div class="menu-scroll">' + html + '</div>';
          menu.style.left = x + 'px'; menu.style.top = y + 'px';
          document.body.appendChild(menu);
          var m = menu.getBoundingClientRect();
          if (m.bottom > window.innerHeight - 4) menu.style.top = Math.max(4, window.innerHeight - m.height - 4) + 'px';
          if (m.right > window.innerWidth - 4) menu.style.left = Math.max(4, window.innerWidth - m.width - 4) + 'px';
          menu.addEventListener('mousedown', function (e) { e.preventDefault(); e.stopPropagation(); });
          menu.addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            var item = e.target.closest('[data-sage-entry]');
            if (!item) return;
            var entry = entries[+item.getAttribute('data-sage-entry')];
            viewMenuClose();
            if (entry && entry.run) entry.run();
          });
          viewMenu = menu;
        }
        document.addEventListener('mousedown', function (e) { if (viewMenu && !viewMenu.contains(e.target)) viewMenuClose(); }, true);
        document.addEventListener('scroll', function (e) { if (viewMenu && !viewMenu.contains(e.target)) viewMenuClose(); }, true);
        document.addEventListener('keydown', function (e) { if (viewMenu && e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); viewMenuClose(); } }, true);
        function viewSend(index, op, value, column) { post({ type: 'base-view', index: +index, op: op, value: value || '', column: column || '' }); }
        function renameView(tab) {
          var name = tab.querySelector('.sage-base-tab-name');
          if (!name) return;
          var old = name.textContent, done = false;
          name.setAttribute('contenteditable', 'plaintext-only'); name.setAttribute('spellcheck', 'false');
          name.focus();
          var range = document.createRange(); range.selectNodeContents(name);
          var sel = getSelection(); sel.removeAllRanges(); sel.addRange(range);
          function finish(save) {
            if (done) return; done = true;
            name.removeAttribute('contenteditable');
            var fresh = name.textContent.replace(/\s+/g, ' ').trim();
            if (save && fresh && fresh !== old) viewSend(tab.getAttribute('data-sage-view-tab'), 'rename', fresh);
            else name.textContent = old;
          }
          name.addEventListener('keydown', function (e) {
            e.stopPropagation();
            if (e.key === 'Enter') { e.preventDefault(); finish(true); name.blur(); }
            else if (e.key === 'Escape') { e.preventDefault(); finish(false); name.blur(); }
          });
          name.addEventListener('blur', function () { finish(true); }, { once: true });
        }
        function propertiesMenu(base, index, x, y) {
          var view = base.querySelector('[data-sage-view="' + index + '"]'), shown = [], all = [];
          try { shown = JSON.parse(view.getAttribute('data-sage-cols') || '[]'); all = JSON.parse(base.getAttribute('data-sage-props') || '[]'); } catch (e) {}
          shown.forEach(function (id) { if (!all.some(function (p) { return p[0].toLowerCase() === id.toLowerCase(); })) all.unshift([id, id.replace(/^note\./, '')]); });
          var entries = [{ label: 'Properties shown' }];
          all.forEach(function (p) {
            var on = shown.some(function (id) { return id.toLowerCase() === p[0].toLowerCase(); });
            entries.push({ icon: p[0].indexOf('formula.') === 0 ? 'lucide-function-square' : p[0].indexOf('file.') === 0 ? 'lucide-file' : 'lucide-text', title: p[1], checked: on,
              off: on && shown.length === 1, run: function () { viewSend(index, on ? 'hide' : 'show', '', p[0]); } });
          });
          openMenu(x, y, entries);
        }
        document.addEventListener('contextmenu', function (e) {
          var tab = e.target.closest && e.target.closest('.sage-base-tab'), base = ownBase(tab);
          if (tab && base) {
            e.preventDefault(); e.stopPropagation();
            var index = tab.getAttribute('data-sage-view-tab'), type = tab.getAttribute('data-sage-type') || 'table', count = base.querySelectorAll('.sage-base-tab').length;
            openMenu(e.clientX, e.clientY, [
              { icon: 'lucide-pencil', title: 'Rename', run: function () { renameView(tab); } },
              { icon: 'lucide-list', title: 'Properties…', run: function () { propertiesMenu(base, index, e.clientX, e.clientY); } },
              '-', { label: 'Layout' },
              { icon: 'lucide-table', title: 'Table', checked: type === 'table', run: function () { if (type !== 'table') viewSend(index, 'layout', 'table'); } },
              { icon: 'lucide-layout-grid', title: 'Cards', checked: type === 'cards', run: function () { if (type !== 'cards') viewSend(index, 'layout', 'cards'); } },
              '-',
              { icon: 'lucide-copy', title: 'Duplicate', run: function () { viewSend(index, 'duplicate'); } },
              { icon: 'lucide-trash-2', title: 'Delete view', warn: true, off: count < 2, run: function () { viewSend(index, 'delete'); } }
            ]);
            return;
          }
          var th = e.target.closest && e.target.closest('.sage-base-table thead th[data-sage-col]');
          if (th && ownBase(th)) { e.preventDefault(); e.stopPropagation(); columnMenu(th, e.clientX, e.clientY); }
        }, true);
        function columnMenu(th, x, y) {
          var view = th.closest('[data-sage-view]'), index = view.getAttribute('data-sage-view'), column = th.getAttribute('data-sage-col'), sort = th.getAttribute('data-sage-sort');
          var heads = Array.prototype.slice.call(th.parentElement.children), at = heads.indexOf(th);
          openMenu(x, y, [
            { icon: 'lucide-arrow-up-narrow-wide', title: 'Sort A → Z', checked: sort === 'asc', run: function () { viewSend(index, 'sort', 'asc', column); } },
            { icon: 'lucide-arrow-down-wide-narrow', title: 'Sort Z → A', checked: sort === 'desc', run: function () { viewSend(index, 'sort', 'desc', column); } },
            { icon: 'lucide-x', title: 'Remove sort', off: !sort, run: function () { viewSend(index, 'sort', '', column); } },
            '-',
            { icon: 'lucide-arrow-left', title: 'Move left', off: at <= 0, run: function () { viewSend(index, 'left', '', column); } },
            { icon: 'lucide-arrow-right', title: 'Move right', off: at >= heads.length - 1, run: function () { viewSend(index, 'right', '', column); } },
            '-',
            { icon: 'lucide-list', title: 'Properties…', run: function () { propertiesMenu(ownBase(th), index, x, y); } },
            { icon: 'lucide-eye-off', title: 'Hide property', off: heads.length < 2, run: function () { viewSend(index, 'hide', '', column); } }
          ]);
        }
        document.addEventListener('click', function (e) {
          var add = e.target.closest && e.target.closest('[data-sage-add-view]');
          var th = !add && e.target.closest && e.target.closest('.sage-base-table thead th[data-sage-col]');
          if (add && ownBase(add)) {
            e.preventDefault(); e.stopPropagation();
            var base = ownBase(add), last = base.querySelectorAll('.sage-base-tab').length - 1, r = add.getBoundingClientRect();
            openMenu(r.left, r.bottom + 4, [{ label: 'New view' },
              { icon: 'lucide-table', title: 'Table', run: function () { viewSend(last, 'add', 'table'); } },
              { icon: 'lucide-layout-grid', title: 'Cards', run: function () { viewSend(last, 'add', 'cards'); } }]);
          } else if (th && ownBase(th) && !(viewMenu)) {
            e.preventDefault(); e.stopPropagation();
            var b = th.getBoundingClientRect();
            columnMenu(th, b.left, b.bottom + 2);
          }
        }, true);

        function swapBase(html, view) {
          var base = document.querySelector('.sage-file-view > [data-sage-base]');
          if (!base) return;
          var tab = base.querySelector('.sage-base-tab.is-active'), shown = view >= 0 ? String(view) : tab ? tab.getAttribute('data-sage-view-tab') : '0';
          var scrolls = Array.prototype.map.call(base.querySelectorAll('[data-sage-view]'), function (v) { return [v.scrollTop, v.scrollLeft]; });
          var folded = Array.prototype.map.call(base.querySelectorAll('.bases-group-heading.is-collapsed'), function (h) { return h.closest('[data-sage-view]').getAttribute('data-sage-view') + '|' + h.textContent; });
          var keep = null;
          if (pick && base.contains(pick.table)) {
            var list = rowsOf(pick.table), at = function (p) { return { path: list[p.r] && list[p.r].getAttribute('data-sage-path'), c: p.c }; };
            keep = { a: at(pick.a), f: at(pick.f) };
          }
          var holder = document.createElement('div'); holder.innerHTML = html;
          decorate(holder);
          var fresh = holder.querySelector('[data-sage-base]');
          if (!fresh) return;
          base.replaceWith(fresh);
          var t = fresh.querySelector('[data-sage-view-tab="' + shown + '"]');
          if (t) {
            fresh.querySelectorAll('[data-sage-view-tab]').forEach(function (x) { x.classList.toggle('is-active', x === t); });
            fresh.querySelectorAll('[data-sage-view]').forEach(function (v) { v.hidden = v.getAttribute('data-sage-view') !== shown; });
            var count = +t.getAttribute('data-sage-count'); fresh.querySelector('.bases-toolbar-result-count').textContent = count + (count === 1 ? ' result' : ' results');
          }
          fresh.querySelectorAll('.bases-group-heading').forEach(function (h) {
            if (folded.indexOf(h.closest('[data-sage-view]').getAttribute('data-sage-view') + '|' + h.textContent) < 0) return;
            h.classList.add('is-collapsed');
            var chevron = h.querySelector('.collapse-icon'); if (chevron) chevron.classList.add('is-collapsed');
            var body = h.closest('tbody'); if (body) body.classList.add('sage-collapsed'); else if (h.nextElementSibling) h.nextElementSibling.hidden = true;
          });
          fresh.querySelectorAll('[data-sage-view]').forEach(function (v, i) { if (scrolls[i]) { v.scrollTop = scrolls[i][0]; v.scrollLeft = scrolls[i][1]; } });
          baseHeads();
          if (keep) {
            var view = fresh.querySelector('[data-sage-view="' + shown + '"]'), table = view && view.querySelector('table');
            var rows = table ? rowsOf(table) : [], find = function (k) { var r = rows.findIndex(function (tr) { return tr.getAttribute('data-sage-path') === k.path; }); return r < 0 ? null : { r: r, c: k.c }; };
            var a = find(keep.a), f = find(keep.f);
            pick = table && a && f ? { table: table, a: a, f: f } : null;
            if (!editor) paint();
          }
        }
        var before = window.sageReceive;
        window.sageReceive = function (message) {
          if (message.type === 'base-saved') {
            var kind = sent.shift() || 'do', done = (message.done || []).map(inverse);
            if (done.length) { if (kind === 'undo') redo.push(done); else { undo.push(done); if (undo.length > 100) undo.shift(); if (kind === 'do') redo = []; } }
            return;
          }
          if (message.type === 'base-html') { swapBase(message.html, message.view == null ? -1 : message.view); return; }
          if (before) before(message);
        };
        var flushBefore = window.sageFlush;
        window.sageFlush = function () {
          if (editor) {
            var change = editor.pending();
            var e = editor; editor = null; e.shell.remove();
            if (change) return JSON.stringify({ type: 'base-cell', edits: [change] });
          }
          return flushBefore ? flushBefore() : '';
        };
      })();
    })();
    """#
}
