import Foundation

/// Sage's Bases, canvases and Vault Agent's file embeds.
extension Checks {
    static func sageBases(_ check: Checks.Check) throws {
        // Bases, canvases and Vault Agent's file embeds (2026-11-08): what Obsidian draws from more than one file. A temp vault, never yours.
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("sage-bases-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        func write(_ text: String, _ path: String) throws {
            let file = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        func read(_ path: String) -> String { (try? String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8)) ?? "" }
        let address = { (path: String) in "https://v/" + path }

        do {
            let root = Study.yaml("filters:\n  and:\n    - file.ext == \"md\"\nformulas:\n  Topic: if(file.folder == \"A\", \"Hub\", file.folder.replace(\"A/\", \"\"))\nviews:\n  - type: table\n    name: 📚 All\n    filters:\n      and:\n        - '!file.inFolder(\"B\")'\n    order:\n      - file.name\n      - formula.Topic\n    sort:\n      - property: file.name\n        direction: ASC\n  - type: cards\n    name: Cards\ntags: [a, \"b c\"]") as? Study.YamlMap
            let views = root?["views"] as? [Any?]
            let first = views?.first.flatMap { $0 as? Study.YamlMap }
            let filters = (first?["filters"] as? Study.YamlMap)?["and"] as? [Any?]
            let sort = (first?["sort"] as? [Any?])?.first.flatMap { $0 as? Study.YamlMap }
            let tags = (root?["tags"] as? [Any?])?.compactMap { $0 as? String }
            check(views?.count == 2 && first?["name"] as? String == "📚 All" && filters?.first as? String == "!file.inFolder(\"B\")"
                  && sort?["direction"] as? String == "ASC" && (root?["formulas"] as? Study.YamlMap)?["Topic"] as? String == "if(file.folder == \"A\", \"Hub\", file.folder.replace(\"A/\", \"\"))"
                  && tags == ["a", "b c"] && root?.keys == ["filters", "formulas", "views", "tags"],
                  "A base's YAML is read as Obsidian reads it: maps in order, lists of maps, quoted filters, [flow] lists")
        }

        try write("---\nCreated: 2026-01-02\n---\nSee [[Pho]]", "Lib/Hub.md")
        try write("---\nAuthor:\n  - \"[[Alex]]\"\nSource: https://x.y\nCreated: 2026-03-01\nCategories:\n  - \"[[Marketing]]\"\n---\nBody #deal", "Lib/Sales/Close.md")
        try write("---\nAuthor:\n  - \"[[Alex]]\"\nCreated: 2026-02-01\ntags: [quote]\n---\nBody", "Lib/Sales/Ask.md")
        do {
            let items = Study.vaultItems(vault)
            let html = Study.baseHTML("formulas:\n  Topic: if(file.folder == \"Lib\", \"Hub\", file.folder.replace(\"Lib/\", \"\"))\n  Type: if(file.hasTag(\"quote\"), \"Quote\", if(Source, \"Clipping\", \"Concept\"))\n"
                + "properties:\n  formula.Type:\n    displayName: Kind\nviews:\n  - type: table\n    name: All\n    filters:\n      and:\n        - file.inFolder(\"Lib\")\n    groupBy:\n      property: formula.Topic\n      direction: ASC\n"
                + "    order:\n      - file.name\n      - formula.Type\n      - Author\n    sort:\n      - property: Created\n        direction: DESC\n  - type: cards\n    name: Clips\n    filters:\n      and:\n        - file.inFolder(\"Lib\")\n        - formula.Type == \"Clipping\"\n        - Categories.contains(link(\"Marketing\"))\n"
                + "  - type: table\n    name: Linked\n    filters:\n      or:\n        - file.hasLink(\"Pho\")\n        - Author.contains(link(\"Alex\")) && !file.hasTag(\"quote\")\n    limit: 5",
                vault: vault, items: items, address: address, selfPath: "Lib/My.base")
            check(html.contains("data-sage-view-tab=\"0\" data-sage-count=\"3\"") && html.contains("data-sage-view-tab=\"1\" data-sage-count=\"1\"") && html.contains("data-sage-view-tab=\"2\" data-sage-count=\"2\"")
                  && !html.contains("sage-base-problem") && html.contains("Kind</th>")
                  && html.contains("<div class=\"bases-group-value sage-hued sage-hue-\(Study.hue("Sales"))\">Sales</div>") && html.contains("<div class=\"bases-group-value sage-hued sage-hue-\(Study.hue("Hub"))\">Hub</div>"),
                  "A base shows the notes its filters and formulas pick, in views with their counts, grouped in their names' colours")
            let sales = html.range(of: "\">Sales</div>").map { String(html[$0.lowerBound...]) } ?? ""
            let close = sales.range(of: ">Close</a>")?.lowerBound, ask = sales.range(of: ">Ask</a>")?.lowerBound
            check(close != nil && ask != nil && close! < ask! && sales.contains(">Quote<") && sales.contains("href=\"sage-note:Alex\" class=\"internal-link is-unresolved\">Alex</a>")
                  && html.contains("class=\"sage-base-card\" data-sage-href=\"sage-note:Lib/Sales/Close.md\""),
                  "A base sorts its rows, links its values (a missing note marked), and its cards open their note")
            check(Study.baseHTML("views:\n  - type: table\n    filters: file.name ==", vault: vault, items: items, address: address).contains("sage-base-problem"),
                  "A formula Sage can't read is said above the base, not dropped silently")
        }

        check(Study.categorical(["Hub", "Concept", "Concept", nil, "Clipping", "— Hub"]), "A base column of a few repeated words is drawn as chips")
        check(!Study.categorical(["[[Donald Miller]]", "[[Donald Miller]]", "Ann"]) && !Study.categorical(["2026-05-02", "2026-05-02", "2026-05-03"])
              && !Study.categorical(["a", "b", "c", "d"]) && !Study.categorical(["Hub", "Hub"]) && !Study.categorical([1.0, 1.0, 2.0])
              && !Study.categorical(["https://youtu.be/x", "https://youtu.be/x", "Hub"]),
              "Links, dates, numbers and many different values are not chips")
        do {
            let spread = Study.spreadHues(["Hub", "Concept", "Clipping", "Quote", "Course", "Master", "concept"])
            let again = Study.spreadHues(["Concept", "Hub", "Clipping", "Quote", "Master", "Course"])
            check(spread.count == 6 && Set(spread.values).count == 6 && spread["Concept"] == again["Concept"],
                  "A base column's chips each take a colour of their own, the same whatever order they come in")
        }

        do {
            let obsidian = "{\n\t\"nodes\":[\n\t\t{\"id\":\"a\",\"type\":\"text\",\"text\":\"Plan → act\",\"x\":0,\"y\":0,\"width\":250,\"height\":60},\n\t\t{\"id\":\"b\",\"type\":\"file\",\"file\":\"Lib/Hub.md\",\"x\":300,\"y\":0,\"width\":400,\"height\":400,\"color\":\"4\"}\n\t],\n\t\"edges\":[\n\t\t{\"id\":\"e\",\"fromNode\":\"a\",\"fromSide\":\"right\",\"toNode\":\"b\",\"toSide\":\"left\"}\n\t]\n}"
            try write(obsidian, "Lib/Edit.canvas")
            let file = vault.appendingPathComponent("Lib/Edit.canvas")
            let root = Study.OrderedJSON.parse(obsidian)!
            check(Study.canvasJSON(root, nodes: root["nodes"]?.array ?? [], edges: root["edges"]?.array ?? []) == obsidian, "A canvas untouched reads exactly as Obsidian wrote it")
            // What the page sends back: dictionaries, which keep no order of their own.
            var nodes = (try JSONSerialization.jsonObject(with: Data(obsidian.utf8)) as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            nodes[0]["text"] = "Plan → act → check"
            nodes[0]["x"] = 40
            let kept = vault.appendingPathComponent("kept")
            let hash = try Study.saveCanvas(file, nodes: nodes, edges: [], expected: Study.canvasHash(obsidian), keep: kept)
            let saved = read("Lib/Edit.canvas")
            check(hash != nil && saved.contains("\t\t{\"id\":\"a\",\"type\":\"text\",\"text\":\"Plan → act → check\",\"x\":40,") && saved.contains("\t\"edges\":[]") && hash == Study.canvasHash(saved)
                  && saved.contains("\"width\":400,\"height\":400,\"color\":\"4\"}") && ((try? FileManager.default.contentsOfDirectory(atPath: kept.path))?.count ?? 0) == 1,
                  "A canvas edited in Sage is written as Obsidian writes it (every field in its place), kept first as it was")
            let stale = try Study.saveCanvas(file, nodes: nodes, edges: [], expected: Study.canvasHash(obsidian), keep: nil)
            check(stale == nil && read("Lib/Edit.canvas") == saved,
                  "A canvas changed elsewhere since the page was drawn isn't written over")
            let html = Study.canvasHTML(saved, canvasPath: "Lib/Edit.canvas", height: "100%", vault: vault, items: Study.vaultItems(vault), address: address, standalone: true)
            check(html.contains("data-sage-canvas data-sage-editable") && html.contains("class=\"sage-canvas-data\"") && html.contains("\"hash\":\"\(hash ?? "-")\"") && html.contains("data-id=\"b\"")
                  && html.contains("\"notes\":{\"b\":{\"file\":\"Lib/Hub.md\",\"body\":") && !html.contains("Open full canvas"),
                  "A canvas opened on its own gets what it edits: its nodes, the version drawn, its notes' text")
            let hub = vault.appendingPathComponent("Lib/Hub.md")
            let note = read("Lib/Hub.md")
            let body = try Study.saveNoteBody(hub, original: "See [[Pho]]", text: "See [[Pho]] and [[Broth]]", keep: nil)
            let changed = try Study.saveNoteBody(hub, original: "See [[Pho]]", text: "x", keep: nil)
            check(body?.hasPrefix("---\nCreated: 2026-01-02\n---\nSee [[Pho]] and [[Broth]]") == true && changed == nil,
                  "A note's text edited on its canvas card is written only if it still reads as it did")
            try write(note, "Lib/Hub.md")
        }

        do {
            try write(#"{"nodes":[{"id":"a","type":"text","text":"**Plan**","x":0,"y":0,"width":200,"height":100,"color":"4"},{"id":"g","type":"group","label":"Loop","x":-20,"y":-20,"width":500,"height":200},{"id":"b","type":"file","file":"Lib/Hub.md","x":300,"y":0,"width":200,"height":100}],"edges":[{"id":"e","fromNode":"a","toNode":"b","label":"then"}]}"#, "Lib/Map.canvas")
            try write("name,spend\n\"Ad, one\",10\n\"Say \"\"hi\"\"\",20\n", "Lib/Ads.csv")
            try write("print('<hi>')", "Lib/tool.py")
            try write("views:\n  - type: table\n    name: Q", "Lib/Q.base")
            let items = Study.vaultItems(vault)
            let note = Study.markdown("```file-embed\nLib/Map.canvas\nheight: 700\n```\n\n```file-embed\n[[Ads.csv]]\n```\n\n```file-embed\nLib/tool.py\n```\n\n![[Q.base]]\n\n![[Hub]]\n\n```file-embed\nNope.csv\n```", sections: true)
            check(note.contains("<div class=\"block-language-file-embed\" data-sage-embed=\"Lib/Map.canvas\" data-sage-height=\"700\"></div>") && note.contains("data-sage-embed=\"Ads.csv\" data-sage-height=\"\""),
                  "A file-embed block leaves a slot for what it embeds")
            let drawn = Study.withVault(note, vault: vault, items: items, from: "Lib/Note.md", address: address)
            check(drawn.contains("<div class=\"va-canvas-embed\" data-sage-canvas style=\"height: 700px;\">") && drawn.contains("<strong>Plan</strong>") && drawn.contains("data-sage-preset=\"4\"")
                  && drawn.contains("va-canvas-group-label") && drawn.contains(">Loop<") && drawn.contains("class=\"va-canvas-edge\"") && drawn.contains(">then<") && drawn.contains("va-canvas-inline-title\">Hub<")
                  && drawn.contains("data-sage-href=\"sage-note:Lib/Map.canvas\""),
                  "Vault Agent's file-embed draws a canvas: groups, coloured cards, notes, arrows and their labels")
            check(drawn.contains("<table class=\"va-file-embed-table\"><thead><tr><th>name</th><th>spend</th></tr></thead><tbody><tr><td>Ad, one</td><td>10</td></tr><tr><td>Say \"hi\"</td><td>20</td></tr>"),
                  "A file-embed draws a CSV as a table (quoted fields and \"\" inside them), a file the explorer hides found on disk")
            check(drawn.contains("<code class=\"language-python is-loaded\">print('&lt;hi&gt;')</code>"), "A file-embed draws code in its language")
            check(drawn.contains("internal-embed bases-embed") && drawn.contains("data-sage-view-tab=\"0\"") && drawn.contains("markdown-embed inline-embed") && drawn.contains("See <a data-href=\"Pho\""),
                  "![[Q.base]] draws the base and ![[Hub]] the note's text where they are")
            check(drawn.contains("file-embed: can't find “Nope.csv”"), "A file-embed of a missing file says so")
        }

        check(Study.delimited("\u{FEFF}a\tb\r\n\"x\ny\"\t2\n\n", separator: "\t") == [["a", "b"], ["x\ny", "2"]], "A TSV's rows: a BOM dropped, a line break inside quotes kept, empty rows left out")
        var props = Study.YamlMap()
        props.set("Source", "https://youtu.be/x"); props.set("icon", "🎬")
        let kind = Study.noteKind(Study.BaseNote(item: Study.VaultItem(path: "a.md", folder: false), props: props, links: [], linkSet: [], tags: []))
        check(kind.kind == "video" && kind.icon == "🎬" && kind.color == nil
              && Study.fileKind(path: "q.md", text: "---\ncategories:\n  - \"[[Quotes]]\"\n---\n").kind == "quote",
              "A note's kind for its icon in the tree: a video or web clipping, a quote, a course; its own icon and colour")

        // Editing a base's table in place (2026-11-11): each cell is one property, written only if it still reads as shown.
        do {
            let note = "---\nStatus: Draft\ntags:\n  - a\n  - b\nviews: 12\n---\nBody"
            func edit(_ key: String, _ was: [String], _ values: [String], list: Bool = false, plain: Bool = false) -> Study.BaseCellResult {
                Study.changeCell(note, .init(path: "n.md", key: key, was: was, values: values, list: list, plain: plain))
            }
            check(Study.cellValues(["a", nil, "", "b"] as [Any?]) == ["a", "b"] && Study.cellValues("x") == ["x"] && Study.cellValues(nil) == [],
                  "A cell holds a list's items or one value; empty ones don't count")
            check(edit("status", ["Draft"], ["Done"]) == .written("---\nStatus: Done\ntags:\n  - a\n  - b\nviews: 12\n---\nBody"),
                  "A cell is written under the name the note already uses (case aside), only that line changed, the body kept")
            check(edit("Status", ["Old"], ["Done"]) == .changed, "A cell changed in the note since the table was drawn is never written over")
            if case .written(let text) = edit("tags", ["a", "b"], ["a", "c", " "], list: true) {
                check(text.contains("tags:\n  - a\n  - c\n") && !text.contains("  - b"), "A list cell writes its items as a list, blanks left out")
            } else { check(false, "A list cell writes its items as a list, blanks left out") }
            if case .written(let text) = edit("Owner", [], ["Mai"]) { check(text.contains("Owner: Mai") && text.hasSuffix("Body"), "An empty cell adds the property to the note") }
            else { check(false, "An empty cell adds the property to the note") }
            check(edit("Status", ["Draft"], ["Draft"]) == .unchanged, "A cell set to what it was writes nothing")
            check(Study.cellKind(key: "tags", type: nil, values: [], chips: false) == "list" && Study.cellKind(key: "x", type: "number", values: [], chips: false) == "number"
                  && Study.cellKind(key: "x", type: nil, values: ["true", "false"], chips: false) == "checkbox" && Study.cellKind(key: "x", type: nil, values: ["2026-01-02"], chips: false) == "date"
                  && Study.cellKind(key: "x", type: nil, values: ["Draft"], chips: true) == "select" && Study.cellKind(key: "x", type: nil, values: ["12", "3.5"], chips: false) == "number"
                  && Study.cellKind(key: "x", type: nil, values: ["hello"], chips: false) == "text",
                  "A column is edited by the vault's type for it, else by what its values look like")
            let items = Study.vaultItems(vault)
            let html = Study.baseHTML("views:\n  - type: table\n    name: All\n    filters:\n      and:\n        - file.inFolder(\"Lib\")\n    order:\n      - file.name\n      - Created\n      - Author\n",
                                      vault: vault, items: items, address: address, selfPath: "Lib/My.base")
            check(html.contains("data-sage-path=\"Lib/Hub.md\"") && html.contains("data-sage-kind=\"date\"") && html.contains("data-sage-key=\"Created\"")
                  && html.contains("data-sage-kind=\"list\"") && html.contains("data-sage-options="),
                  "A base's table marks each row's note and each property cell's kind, so the page can edit it")
            let base = "filters:\n  and:\n    - file.ext == \"md\"\nviews:\n  - type: table\n    name: A\n    order:\n      - file.name\n  # B next\n  - type: cards\n    name: B\n\n  - type: table\n    name: C\nformulas:\n  x: 1\n"
            check(Study.reorderViews(base, order: [2, 0, 1]) == "filters:\n  and:\n    - file.ext == \"md\"\nviews:\n  - type: table\n    name: C\n  - type: table\n    name: A\n    order:\n      - file.name\n  # B next\n  - type: cards\n    name: B\n\nformulas:\n  x: 1\n"
                  && Study.reorderViews(base, order: [0, 0, 1]) == nil && Study.reorderViews(base, order: [0, 1, 2]) == base,
                  "A base's views are reordered by moving only the views: list's items, each with its own lines; a wrong order writes nothing")
            let two = "views:\n  - type: table\n    name: All\n    order:\n      - file.name\n      - Status\n  - type: cards\n    name: Grid\n"
            check(Study.changeView(two, index: 0, .rename("My view: 1")) == two.replacingOccurrences(of: "name: All", with: "name: \"My view: 1\"")
                  && Study.changeView(two, index: 1, .layout("table")) == two.replacingOccurrences(of: "- type: cards", with: "- type: table")
                  && Study.changeView(two, index: 0, .sort(column: "note.Status", descending: true)) == two.replacingOccurrences(of: "      - Status\n", with: "      - Status\n    sort:\n      - property: Status\n        direction: DESC\n")
                  && Study.changeView(two, index: 0, .move(column: "note.Status", by: -1)) == two.replacingOccurrences(of: "      - file.name\n      - Status", with: "      - Status\n      - file.name")
                  && Study.changeView(two, index: 0, .hide(column: "file.name")) == two.replacingOccurrences(of: "      - file.name\n", with: "")
                  && Study.changeView(two, index: 0, .show(column: "note.Pillar")) == two.replacingOccurrences(of: "      - Status\n", with: "      - Status\n      - Pillar\n")
                  && Study.changeView(two, index: 0, .duplicate)?.contains("  - type: table\n    name: All copy\n    order:") == true
                  && Study.changeView(two, index: 1, .delete) == "views:\n  - type: table\n    name: All\n    order:\n      - file.name\n      - Status\n"
                  && Study.changeView(two, index: 1, .add("table"))?.hasSuffix("    name: Grid\n  - type: table\n    name: Table\n    order:\n      - file.name\n") == true
                  && Study.changeView("views:\n  - type: table\n    name: A\n", index: 0, .delete) == nil,
                  "A base view's menus change only that view's lines: name, layout, sort, columns moved, hidden and shown, a copy, a new view, removing one (never the last)")
            check(html.contains("data-sage-kind=\"name\" data-sage-was=\"[&quot;Hub&quot;]\""), "A note's name in a base's table can be edited (it renames the note, as its title does)")
            for (i, status) in ["Planned", "To film", "To film", "planned", "Planned"].enumerated() { try write("---\nStatus: \(status)\n---\n", "Show/E\(i).md") }
            try write("---\nStatus: Assessment\n---\n", "Other/X.md")
            let shows = Study.baseHTML("views:\n  - type: table\n    name: All\n    filters:\n      and:\n        - file.inFolder(\"Show\")\n    order:\n      - file.name\n      - Status\n",
                                       vault: vault, items: Study.vaultItems(vault), address: address, selfPath: "Show/S.base")
            let head = Study.firstMatch(#"data-sage-options="([^"]*)" data-sage-hues="([^"]*)""#, in: shows).map { $0[1] + "|" + $0[2] } ?? ""
            let chip = Study.firstMatch(#"sage-chip (sage-hue-\d)">To film"#, in: shows).map { $0[1] } ?? "?"
            check(head.contains("Planned") && head.contains("To film") && !head.contains("Assessment") && !head.contains("planned&quot;") && !head.contains("[[Planned]]")
                  && head.contains("&quot;To film&quot;:\(chip.dropFirst(9))"),
                  "A status column's menu holds this base's values only, one per name (case and [[ ]] aside), each in the colour its chips have: \(head)")
        }
    }
}
