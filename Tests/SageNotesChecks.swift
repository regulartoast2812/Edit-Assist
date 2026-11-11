import Foundation

/// Sage's note view: the page drawn as Obsidian draws it, Obsidian's own look, editing a note's lines.
extension Checks {
    static func sageNotes(_ check: Checks.Check) throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("sage-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        // The page as Obsidian's reading view builds it (2026-11-07, from Creative Assist).
        let md = Study.markdown("## Steps\n\n1. Brown **chicken**\n2. Add `soy`\n   - nested *one*\n\n- [x] done\n- [ ] todo\n\n> [!tip] Swap\n> Use ==thighs==\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nSee [[Pho|my pho]] and #soup <b>")
        check(md.contains("<h2 data-heading=\"Steps\" dir=\"auto\">Steps</h2>") && md.contains("<ol><li dir=\"auto\" data-sage-line=\"2\">Brown <strong>chicken</strong>") && md.contains("<code>soy</code>")
              && md.contains("<ul class=\"has-list-bullet\"><li dir=\"auto\" data-sage-line=\"4\"><span class=\"list-bullet\"></span>nested <em>one</em>")
              && md.contains("task-list-item is-checked") && md.contains("data-callout=\"tip\"") && md.contains("<mark>thighs</mark>") && md.contains("<td dir=\"auto\">2</td>")
              && md.contains("href=\"sage-note:Pho\" class=\"internal-link\">my pho</a>") && md.contains("href=\"#soup\" class=\"tag\"") && md.contains("&lt;b&gt;") && !md.contains("<b>"),
              "Sage's note view draws Markdown with the elements Obsidian's reading view makes")
        let note = "---\ntags: [filipino-food]\n---\n## Steps\n\n![](https://www.youtube.com/watch?v=wwapBsT0oc8)"
        let page = Study.notePage(note, look: Study.Look(dark: true, accent: "#ff8800", fontSize: 18, css: ".theme-dark{--x:1}"), dark: true)
        check(page.contains("theme-dark") && page.contains("metadata-container") && page.contains("<span>filipino-food</span>") && page.contains("--accent-h: 32; --accent-s: 100%; --accent-l: 50%;")
              && page.contains("--font-text-size: 18px") && page.contains(".theme-dark{--x:1}") && page.contains("class=\"video-embed\"") && page.contains("data-heading=\"Steps\""),
              "A note's page has its properties, the video, your accent (as Obsidian's hue, saturation and lightness), size and theme")
        check(page.contains(".mod-root::before { content: none !important") && page.contains("#sage-viewer") && Study.pageScript.contains("sage-viewer") && Study.pageScript.contains("'ArrowRight'") && page.contains(".sv-next"),
              "A theme's \"newer Obsidian installer\" notice is hidden (WebKit lacks interpolate-size), and pictures open full size")
        check(Study.byteRange("bytes=0-1023").map { $0.lowerBound == 0 && $0.upperBound == 1023 } == true && Study.byteRange("bytes=500-").map { $0.lowerBound == 500 && $0.upperBound == nil } == true
              && Study.byteRange("bytes=0-1,5-9") == nil && Study.byteRange("items=0-1") == nil,
              "A video in a note is served the bytes it asks for")
        let unresolved = Study.withVault(#"<p><a data-href="Nope" href="sage-note:Nope" class="internal-link">Nope</a> <a data-href="Pho" href="sage-note:Pho" class="internal-link">Pho</a></p>"#,
                                         vault: URL(fileURLWithPath: "/tmp"), items: [Study.VaultItem(path: "Soups/Pho.md", folder: false)], from: nil, address: Study.vaultAddress)
        check(unresolved.contains(#"class="is-unresolved internal-link">Nope"#) && unresolved.contains(#"class="internal-link">Pho"#),
              "A link to a note that doesn't exist yet is drawn dimmed, as in Obsidian; one that does is left as it is")
        check(Study.pageScript.contains("'inline-cards'") && Study.playerPage.contains("autoplay') === '0'") && page.contains(".video-embed.sage-playing .play"),
              "YouTube cards play in place: the page says where the cards in sight are as it scrolls, and their players wait for a click")
        check(page.contains("mod-macos") && !page.contains("mod-windows") && !page.contains("styled-scrollbars") && page.contains("is-hidden-frameless"),
              "The page's body is as Obsidian's on the Mac: mod-macos, no styled scrollbars, no room for a title bar")
        check(Study.accentStyle("#38f") == " --accent-h: 215; --accent-s: 100%; --accent-l: 60%;" && Study.accentStyle("red") == "" && Study.accentStyle("") == "",
              "Your accent is given as Obsidian gives it, a short hex too")

        // The vault's reading settings (app.json, types.json, plugins).
        let obsidian = vault.appendingPathComponent(".obsidian")
        try Data(#"{"propertiesInDocument":"hidden","showInlineTitle":false,"defaultViewMode":"preview","useTab":false,"tabSize":2,"spellcheck":false}"#.utf8).write(to: obsidian.appendingPathComponent("app.json"))
        try Data(#"{"types":{"Created":"date"}}"#.utf8).write(to: obsidian.appendingPathComponent("types.json"))
        try Data(#"["vault-agent","missing","../escape"]"#.utf8).write(to: obsidian.appendingPathComponent("community-plugins.json"))
        try FileManager.default.createDirectory(at: obsidian.appendingPathComponent("plugins/vault-agent"), withIntermediateDirectories: true)
        try Data("/* va */".utf8).write(to: obsidian.appendingPathComponent("plugins/vault-agent/styles.css"))
        let reading = Study.look(vault: vault)
        check(reading.properties == "hidden" && !reading.inlineTitle && reading.readable && !reading.editByDefault && !reading.spellcheck && reading.tab == "  "
              && reading.type(of: "created") == "date" && reading.plugins == ["vault-agent"],
              "Sage reads the vault's reading settings: properties, inline title, line width, view mode, tabs, spellcheck, property types, plugins")
        let bare = Study.notePage("---\nstatus: read\n---\nBody", look: reading, dark: true, title: "Pho")
        check(!bare.contains("class=\"metadata-container\"") && !bare.contains("class=\"inline-title\"")
              && Study.notePage("Body", look: Study.Look(), dark: true, title: "Pho").contains("<div class=\"inline-title\" contenteditable=\"true\" spellcheck=\"false\" tabindex=\"-1\">Pho</div>"),
              "The note view follows the vault's reading settings: properties hidden, no inline title")
        let plugged = Study.notePage("Body", look: reading, dark: true, vault: Study.vaultBase)
        check(plugged.contains("href=\"\(Study.vaultBase).obsidian/plugins/vault-agent/styles.css\""), "Your enabled plugins' styles load from the vault, as in Obsidian")

        let built = Study.markdown("Intro\n\n> [!multi-column|fw2]- Two\n> body\n\n- [x] done\n\n```js\nlet a\n```\n\n| a | b |\n|:-:|--:|\n| 1 | 2 |", sections: true)
        check(built.hasPrefix("<div class=\"el-p\" data-sage-from=\"0\" data-sage-to=\"0\"><p dir=\"auto\">Intro</p></div>")
              && built.contains("<div class=\"el-div\" data-sage-from=\"2\" data-sage-to=\"3\"><div data-callout-metadata=\"fw2\" data-callout-fold=\"-\" data-callout=\"multi-column\" class=\"callout is-collapsible is-collapsed\">")
              && built.contains("<div class=\"callout-icon\"></div><div class=\"callout-title-inner\">Two</div><div class=\"callout-fold is-collapsed\"") && built.contains("<div class=\"callout-content\" style=\"display: none;\"><p dir=\"auto\">body</p>")
              && built.contains("<div class=\"el-ul\" data-sage-from=\"5\" data-sage-to=\"5\"><ul class=\"has-list-bullet\"><li data-task=\"x\" class=\"task-list-item is-checked\" dir=\"auto\" data-sage-line=\"5\"><span class=\"list-bullet\"></span><input type=\"checkbox\"")
              && built.contains("<div class=\"el-pre\" data-sage-from=\"7\" data-sage-to=\"9\"><pre class=\"language-js\"><code class=\"language-js is-loaded\">let a</code>")
              && built.contains("<div class=\"el-table\" data-sage-from=\"11\" data-sage-to=\"13\">") && built.contains("<th dir=\"auto\" style=\"text-align: center;\">a</th>")
              && built.contains("<td dir=\"auto\" style=\"text-align: right;\">2</td>"),
              "A note is built as Obsidian's reading view builds it, so its stylesheet and your theme dress it the same")
        let typed = Study.properties("Created: 2026-04-29\nAuthor:\n  - \"[[Donald Miller]]\"\nSource: \"https://x.y/z\"\ntags: [food]\nTitle: Pho", types: ["Created": "date"])
        check(typed.contains("data-property-type=\"date\"") && typed.contains("type=\"date\" value=\"2026-04-29\"") && typed.contains("data-property-type=\"multitext\"")
              && typed.contains("<a data-href=\"Donald Miller\" href=\"sage-note:Donald Miller\" class=\"internal-link\">Donald Miller</a>") && typed.contains("class=\"metadata-link-inner external-link\"")
              && typed.contains("data-property-type=\"tags\"") && typed.contains(" class=\"metadata-input-longtext mod-truncate\" placeholder=\"Empty\">Pho</div>"),
              "Properties show as Obsidian shows each type: dates, lists, links, tags, text")
        let linked = Study.properties("Categories:\n  - \"[[Games]]\"\n  - \"[[Ghost Online|GO]]\"")
        check(linked.contains("href=\"sage-note:Games\" class=\"internal-link\">Games</a>") && linked.contains(">GO</a>")
              && !linked.replacingOccurrences(of: #"data-value="[^"]*""#, with: "", options: .regularExpression).contains("[["),
              "A [[link]] in a note's properties shows as the link, as Obsidian shows it")
        let styled = Study.notePage("---\ncssclasses: wide\n---\nBody", look: Study.Look(), dark: true, title: "Pho", app: "sage://sage/obsidian/")
        check(styled.contains("<link rel=\"stylesheet\" href=\"sage://sage/obsidian/app.css\">") && styled.contains("src=\"sage://sage/obsidian/icons.js\"") && !styled.contains("--font-default:")
              && styled.contains("show-properties wide\"") && styled.contains("class=\"workspace-leaf-content is-read-mode\" data-type=\"markdown\"")
              && Study.notePage("Body", look: Study.Look(), dark: true).contains("--font-default:"),
              "With Obsidian's own stylesheet the page loads it, its icons, and a note's cssclasses; without, Sage's stand-in")
        let source = Study.notePage("---\na: 1\n---\nBody", look: Study.Look(properties: "source"), dark: true)
        check(source.contains("<pre class=\"frontmatter language-yaml\">") && !source.contains("class=\"metadata-container\""), "Properties can show as their YAML (source), as Obsidian can")
        let file = Study.filePage("<div class=\"x\"></div>", type: "bases", look: Study.Look(), dark: false)
        check(file.contains("theme-light") && file.contains("data-type=\"bases\"") && file.contains("<div class=\"sage-file-view\"><div class=\"x\"></div></div>"),
              "A base or a canvas sits in the same workspace and look as a note")

        // Editing a note in Sage (2026-11-07): you change the lines a block came from; Sage, the model, never writes over a note.
        let sizer = Study.noteSizer("---\ntags: [a]\nTitle: Pho\n---\n# Pho\n\nBroth\nstill broth\n\n- [ ] star anise\n  - [x] toast it\n> [!tip]\n> - [ ] skim", look: Study.Look(), title: "Pho")
        check(Study.bodyStart("---\na: 1\n---\nx") == 3 && Study.bodyStart("x") == 0 && sizer.contains("data-sage-from=\"1\" data-sage-to=\"2\" class=\"metadata-container\"")
              && sizer.contains("<div class=\"el-h1\" data-sage-from=\"4\" data-sage-to=\"4\">") && sizer.contains("<div class=\"el-p\" data-sage-from=\"6\" data-sage-to=\"7\">")
              && sizer.contains("<div class=\"el-ul\" data-sage-from=\"9\" data-sage-to=\"10\">") && sizer.contains("data-sage-line=\"10\"")
              && sizer.contains("<div class=\"el-div\" data-sage-from=\"11\" data-sage-to=\"12\">") && sizer.contains("data-sage-line=\"12\""),
              "Each part of a note knows the lines it came from, after its properties too, so it can be edited where it is")
        let editable = Study.notePage("Body", look: Study.Look(spellcheck: false, tab: "  "), dark: true, title: "Pho", editing: true)
        check(editable.contains(" data-sage-edit>") && editable.contains("window.sageLines = [\"Body\"]") && editable.contains("window.sageEdit = {\"tab\":\"  \",\"spellcheck\":false}")
              && !Study.notePage("Body", look: Study.Look(), dark: true).contains("data-sage-edit>")
              && Study.notePage("</script>", look: Study.Look(), dark: true, editing: true).contains("window.sageLines = [\"\\u003C/script\\u003E\"]"),
              "A page you can edit carries the note's lines and your tab and spellcheck settings, safely inside its script")
        let lines = "# Pho\n\nBroth\n\n- a\n- b"
        func same(_ a: (text: String, from: Int, to: Int)?, _ b: (String, Int, Int)) -> Bool { a.map { $0.text == b.0 && $0.from == b.1 && $0.to == b.2 } ?? false }
        check(same(Study.editLines(lines, from: 2, to: 2, original: "Broth", text: "Rich broth\nwith bones"), ("# Pho\n\nRich broth\nwith bones\n\n- a\n- b", 2, 3))
              && Study.editLines(lines, from: 2, to: 2, original: "Soup", text: "x") == nil && Study.editLines(lines, from: 9, to: 9, original: "", text: "x") == nil
              && same(Study.editLines(lines, from: 4, to: 5, original: "- a\n- b", text: ""), ("# Pho\n\nBroth\n", 4, 3))
              && same(Study.editLines(lines, from: 6, to: 5, original: "", text: "New"), ("# Pho\n\nBroth\n\n- a\n- b\n\nNew", 7, 7))
              && Study.editLines("a", from: 3, to: 2, original: "", text: "x") == nil && same(Study.editLines("", from: 0, to: 0, original: "", text: "First"), ("First", 0, 0)),
              "An edit changes only its own lines, and only when they still read as they did")
        check(Study.toggleTask("- [ ] a\n> - [x] b\n1. [ ] c", line: 0) == "- [x] a\n> - [x] b\n1. [ ] c" && Study.toggleTask("- [ ] a\n> - [x] b", line: 1) == "- [ ] a\n> - [ ] b"
              && Study.toggleTask("- [ ] a\n1. [ ] c", line: 1) == "- [ ] a\n1. [x] c" && Study.toggleTask("plain", line: 0) == nil && Study.toggleTask("- [ ] a", line: 3) == nil,
              "A task's box is ticked or cleared on its own line, in a callout too")
        do {
            let folder = vault.appendingPathComponent("Edits"), keep = vault.appendingPathComponent("kept")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("Pho.md")
            try Data([0xEF, 0xBB, 0xBF] + Array("# Pho\r\n\r\nBroth".utf8)).write(to: file)
            let created = Date(timeIntervalSince1970: 1_704_164_645)
            try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: file.path)
            let was = try Study.readNote(file)
            try Study.writeNote(file, text: "# Pho\n\nRich broth", was: was, keep: keep)
            try Study.writeNote(file, text: "# Pho\n\nRicher broth", was: try Study.readNote(file), keep: keep)
            let bytes = try Data(contentsOf: file)
            let date = (try FileManager.default.attributesOfItem(atPath: file.path))[.creationDate] as? Date
            let kept = try FileManager.default.contentsOfDirectory(at: keep, includingPropertiesForKeys: nil)
            let keptText = kept.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            check(was.text == "# Pho\n\nBroth" && was.crlf && was.bom && bytes.starts(with: [0xEF, 0xBB, 0xBF]) && String(decoding: bytes.dropFirst(3), as: UTF8.self) == "# Pho\r\n\r\nRicher broth"
                  && date.map { abs($0.timeIntervalSince(created)) < 1 } == true && ((try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.count ?? 0) == 1
                  && kept.count == 1 && kept[0].lastPathComponent.hasSuffix(" Pho.md") && keptText.hasSuffix("Broth") && !keptText.contains("Rich"),
                  "A note you edit is written back as it was kept (CRLF, BOM, created date) in one step, the note as it was kept first")
        }

        // Obsidian's own stylesheet, fonts and icons (2026-11-07): read from its archive, never changed.
        do {
            let json = Array(#"{"files":{"package.json":{"size":3,"offset":"0"},"public":{"files":{"fonts":{"files":{"a.woff2":{"size":2,"offset":"3"}}}}},"x":{"size":1,"offset":"5","unpacked":true}}}"#.utf8)
            let pad = (4 - json.count % 4) % 4
            var data = Data()
            for n in [4, 8 + json.count + pad, 4 + json.count + pad, json.count] { withUnsafeBytes(of: UInt32(n).littleEndian) { data.append(contentsOf: $0) } }
            data.append(contentsOf: json); data.append(contentsOf: [UInt8](repeating: 0, count: pad)); data.append(contentsOf: Array("abcde".utf8))
            let archive = vault.appendingPathComponent("test.asar")
            try data.write(to: archive)
            let handle = try FileHandle(forReadingFrom: archive)
            let index = try Study.asarIndex(handle)
            try handle.close()
            let start = UInt64(16 + json.count + pad)
            check(index.count == 2 && index["package.json"]?.offset == start && index["package.json"]?.size == 3 && index["public/fonts/a.woff2"]?.offset == start + 3
                  && index["public/fonts/a.woff2"]?.size == 2,
                  "Obsidian's archive is read as Electron packs it: each file's place and size, unpacked ones left out")
            let icons = Study.obsidianIcons(#"x;var yb={"a-arrow-down":[[6,"M3 16 4 4 4-4"]],info:[[1,12,12,10],[6,"M12 16v-4"]],clipboard:[[5,8,2,8,4,1,1]],dot:[[1,1,2,3,1]],small:[[1,16,13,.5],[1,2,2,-.5]]};var LR={}"#)
            check(icons["info"] == "<circle cx=\"12\" cy=\"12\" r=\"10\"/><path d=\"M12 16v-4\"/>" && icons["clipboard"] == "<rect x=\"8\" y=\"2\" width=\"8\" height=\"4\" rx=\"1\" ry=\"1\"/>"
                  && icons["dot"]?.contains("fill=\"currentColor\"") == true && icons["small"] == "<circle cx=\"16\" cy=\"13\" r=\"0.5\"/><circle cx=\"2\" cy=\"2\" r=\"-0.5\"/>"
                  && icons["a-arrow-down"] != nil && icons["right-triangle"] != nil && Study.obsidianIcons("nothing").count == 1,
                  "Obsidian's icons are read from its app.js as Obsidian keeps them")
            check(Study.newerVersion("1.10.2", than: "1.9.0") && !Study.newerVersion("1.9.0", than: "1.10.2") && !Study.newerVersion("1.9", than: "1.9.0"),
                  "The newest Obsidian is found by its version, number by number")
            // A whole archive copied into Sage's cache once: app.css, the fonts and the icons.
            let full = Array(#"{"files":{"package.json":{"size":19,"offset":"0"},"app.css":{"size":4,"offset":"19"},"public":{"files":{"fonts":{"files":{"f.woff2":{"size":2,"offset":"23"}}}}}}}"#.utf8)
            let gap = (4 - full.count % 4) % 4
            var asar = Data()
            for n in [4, 8 + full.count + gap, 4 + full.count + gap, full.count] { withUnsafeBytes(of: UInt32(n).littleEndian) { asar.append(contentsOf: $0) } }
            asar.append(contentsOf: full); asar.append(contentsOf: [UInt8](repeating: 0, count: gap)); asar.append(contentsOf: Array(#"{"version":"1.9.0"}a{}bff"#.utf8))
            let made = vault.appendingPathComponent("obsidian.asar")
            try asar.write(to: made)
            let cache = vault.appendingPathComponent("cache")
            let style = Study.obsidianStyle(cache: cache, archives: [made])
            check(style.map { (try? String(contentsOf: $0.appendingPathComponent("app.css"), encoding: .utf8)) == "a{}b"
                && FileManager.default.fileExists(atPath: $0.appendingPathComponent("public/fonts/f.woff2").path)
                && ((try? String(contentsOf: $0.appendingPathComponent("icons.js"), encoding: .utf8))?.hasPrefix("window.sageIcons = {") ?? false) } == true
                  && Study.obsidianStyle(cache: cache, archives: [made]) == style && Study.obsidianStyle(cache: cache, archives: []) == nil,
                  "Obsidian's stylesheet, fonts and icons are copied into Sage's cache once per version")
        }
    }
}
