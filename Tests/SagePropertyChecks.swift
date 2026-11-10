import Foundation

/// Sage's Properties table, edited as in Obsidian (2026-11-10): one property's lines changed, the rest of the
/// frontmatter byte for byte, quotes kept, lists written as Obsidian writes them, nothing written over a frontmatter that
/// changed since the table was drawn, a type kept in types.json. Temp folders only, never your vault.
extension Checks {
    static func sageProperties(_ check: Checks.Check) throws {
        func written(_ result: Study.PropertyResult) -> String? { if case .written(let text) = result { return text }; return nil }
        let note = "---\nCategories:\n  - \"[[Recipes]]\"\ntags: [food, \"easy, quick\"]\nTitle: 'Pho'\ncount: 3\n# kept as it is\ndone: false\n---\n# Pho\nBody"
        let drawn = Study.frontmatter(of: note)
        func change(_ c: Study.PropertyChange, in text: String = note) -> String? { written(Study.changeProperty(text, drawn: Study.frontmatter(of: text), c)) }

        check(drawn == "Categories:\n  - \"[[Recipes]]\"\ntags: [food, \"easy, quick\"]\nTitle: 'Pho'\ncount: 3\n# kept as it is\ndone: false"
              && Study.frontmatter(of: "Body") == nil && Study.frontmatter(of: "---\n---\nBody") == "",
              "The frontmatter the table is drawn from: its lines, empty when it has none, nil when there is none")
        check(Study.propertySpans(["a: 1", "b:", "  - x", "- y", "# c", "d: |", "  one", "  two", "e: [x,", "  y]"]).map { "\($0.key) \($0.from)-\($0.to) \($0.complex)" }
              == ["a 0-0 false", "b 1-3 false", "d 5-7 true", "e 8-9 true"],
              "Each property's lines: its key, its list items (indented or not), and what's under it; a block or a list over lines is more than the table shows")

        // Values, written in their own lines only, keeping their quotes.
        check(change(.set(key: "Title", values: ["Phở bò"], list: false, plain: false)) == note.replacingOccurrences(of: "Title: 'Pho'", with: "Title: 'Phở bò'"),
              "A value typed in the table changes only its line, and keeps the single quotes it had")
        check(change(.set(key: "count", values: ["4.5"], list: false, plain: true)) == note.replacingOccurrences(of: "count: 3", with: "count: 4.5")
              && change(.set(key: "done", values: ["true"], list: false, plain: true)) == note.replacingOccurrences(of: "done: false", with: "done: true"),
              "A number and a tick are written as they are")
        let plainText = "---\nnote: old\n---\n"
        check(change(.set(key: "note", values: ["123"], list: false, plain: false), in: plainText) == "---\nnote: \"123\"\n---\n"
              && change(.set(key: "note", values: ["true"], list: false, plain: false), in: plainText) == "---\nnote: \"true\"\n---\n"
              && change(.set(key: "note", values: ["a: b"], list: false, plain: false), in: plainText) == "---\nnote: \"a: b\"\n---\n"
              && change(.set(key: "note", values: ["[[Pho]]"], list: false, plain: false), in: plainText) == "---\nnote: \"[[Pho]]\"\n---\n"
              && change(.set(key: "note", values: ["say \"hi\""], list: false, plain: false), in: plainText) == "---\nnote: say \"hi\"\n---\n"
              && change(.set(key: "note", values: ["#tag"], list: false, plain: false), in: plainText) == "---\nnote: \"#tag\"\n---\n"
              && change(.set(key: "note", values: ["plain words"], list: false, plain: false), in: plainText) == "---\nnote: plain words\n---\n"
              && change(.set(key: "note", values: [], list: false, plain: false), in: plainText) == "---\nnote:\n---\n",
              "Text is quoted only when YAML would read it as something else (a number, true, a key, a link, a comment); emptied, the key stays")
        check(Study.changeProperty(note, drawn: drawn, .set(key: "Title", values: ["Pho"], list: false, plain: false)) == .unchanged
              && Study.changeProperty(note, drawn: drawn, .set(key: "tags", values: ["food", "easy, quick"], list: true, plain: false)) == .unchanged,
              "A field left as it was writes nothing")
        let wikilink = "---\nsource: \"[[Old]]\"\n---\n"
        check(change(.set(key: "source", values: ["[[New|shown]]"], list: false, plain: false), in: wikilink) == "---\nsource: \"[[New|shown]]\"\n---\n",
              "A link keeps its [[ ]] and quotes when it's written")

        // Lists, as Obsidian writes them.
        check(change(.set(key: "Categories", values: ["[[Recipes]]", "Dinner"], list: true, plain: false))
              == note.replacingOccurrences(of: "  - \"[[Recipes]]\"\n", with: "  - \"[[Recipes]]\"\n  - \"Dinner\"\n"),
              "A pill added to a list whose items are quoted is quoted too; the others are kept as written")
        check(change(.set(key: "tags", values: ["food", "easy, quick", "soup"], list: true, plain: false))
              == note.replacingOccurrences(of: "tags: [food, \"easy, quick\"]", with: "tags:\n  - food\n  - \"easy, quick\"\n  - soup"),
              "A list written on one line is written as Obsidian writes lists (key:, then   - item), each old item as it was")
        check(change(.set(key: "tags", values: ["easy, quick"], list: true, plain: false)) == note.replacingOccurrences(of: "tags: [food, \"easy, quick\"]", with: "tags:\n  - \"easy, quick\"")
              && change(.set(key: "tags", values: [], list: true, plain: false)) == note.replacingOccurrences(of: "tags: [food, \"easy, quick\"]", with: "tags: []"),
              "A pill removed (×, or Backspace) takes its item away; the last one leaves an empty list")
        check(change(.set(key: "aliases", values: ["Pho", "1984"], list: true, plain: false), in: "---\naliases:\n- Pho\n---\n") == "---\naliases:\n- Pho\n- \"1984\"\n---\n",
              "A list keeps its own indent; a new item that YAML would read as a number is quoted")

        // Names.
        check(change(.rename(key: "Title", to: "Name")) == note.replacingOccurrences(of: "Title: 'Pho'", with: "Name: 'Pho'")
              && change(.rename(key: "Categories", to: "Kinds")) == note.replacingOccurrences(of: "Categories:", with: "Kinds:")
              && change(.rename(key: "count", to: "a: b")) == note.replacingOccurrences(of: "count: 3", with: "\"a: b\": 3"),
              "A property renamed keeps its value and items as written; a name YAML can't take bare is quoted")
        check(Study.changeProperty(note, drawn: drawn, .rename(key: "Title", to: "TAGS")) == .taken && Study.changeProperty(note, drawn: drawn, .rename(key: "Title", to: " ")) == .unchanged,
              "A rename to a name another property has (case aside) is refused; an empty name leaves it")

        // Removing and adding.
        check(change(.remove(key: "count")) == note.replacingOccurrences(of: "count: 3\n", with: "")
              && change(.remove(key: "Categories")) == note.replacingOccurrences(of: "Categories:\n  - \"[[Recipes]]\"\n", with: ""),
              "A property removed takes its lines (its list's too); the comment and the others stay")
        check(change(.remove(key: "a"), in: "---\na: 1\n---\n# Pho\nBody") == "# Pho\nBody",
              "Removing the last property takes the frontmatter away")
        check(change(.set(key: "rating", values: [], list: false, plain: false)) == note.replacingOccurrences(of: "done: false\n---", with: "done: false\nrating:\n---"),
              "A new property is added at the end of the frontmatter")
        check(written(Study.changeProperty("# Pho\nBody", drawn: nil, .set(key: "status", values: ["to try"], list: false, plain: false))) == "---\nstatus: to try\n---\n# Pho\nBody"
              && written(Study.changeProperty("", drawn: nil, .set(key: "k", values: [], list: false, plain: false))) == "---\nk:\n---\n",
              "A note without frontmatter gets one with its first property")

        // Never over a frontmatter that changed since the table was drawn.
        check(Study.changeProperty(note, drawn: "Title: 'Pho'", .set(key: "Title", values: ["X"], list: false, plain: false)) == .changed
              && Study.changeProperty(note, drawn: nil, .remove(key: "count")) == .changed
              && Study.changeProperty("---\na: 1\n---\n", drawn: nil, .set(key: "b", values: [], list: false, plain: false)) == .changed
              && Study.changeProperty("Body", drawn: "a: 1", .set(key: "b", values: [], list: false, plain: false)) == .changed,
              "Nothing is written when the frontmatter doesn't read as the table was drawn from it (changed in Obsidian, made or taken away)")

        // More than the table shows.
        let block = "---\nsummary: |\n  one\n  two\nTitle: Pho\n---\n"
        check(Study.changeProperty(block, drawn: Study.frontmatter(of: block), .set(key: "summary", values: ["x"], list: false, plain: false)) == .complex
              && change(.rename(key: "summary", to: "about"), in: block) == "---\nabout: |\n  one\n  two\nTitle: Pho\n---\n"
              && change(.remove(key: "summary"), in: block) == "---\nTitle: Pho\n---\n",
              "A value over several lines isn't set from the table (it's changed as YAML), but it can be renamed or removed whole")
        let drawnBlock = Study.properties(Study.split(block).header)
        check(drawnBlock.contains("data-property-key=\"summary\" data-property-type=\"text\" data-value=\"|\" data-sage-complex") && !drawnBlock.contains("contenteditable=\"plaintext-only\" class=\"metadata-input-longtext mod-truncate\" placeholder=\"Empty\">|<"),
              "Such a value is drawn as it is, not as a field")

        // Types: the value's shape follows, and types.json keeps it as Obsidian does.
        check(change(.retype(key: "Title", list: true)) == note.replacingOccurrences(of: "Title: 'Pho'", with: "Title:\n  - 'Pho'")
              && change(.retype(key: "Categories", list: false)) == note.replacingOccurrences(of: "Categories:\n  - \"[[Recipes]]\"", with: "Categories: \"[[Recipes]]\"")
              && Study.changeProperty(note, drawn: drawn, .retype(key: "tags", list: false)) == .unchanged
              && Study.changeProperty(note, drawn: drawn, .retype(key: "count", list: false)) == .unchanged,
              "A type changed to List makes a value a one-item list, back to a value a one-item list; a longer list is left whole")
        check(Study.typesJSON(nil, key: "Created", type: "date") == "{\n  \"types\": {\n    \"Created\": \"date\"\n  }\n}"
              && Study.typesJSON("{\"types\":{\"b\":\"text\",\"A\":\"number\",\"c/d\":\"checkbox\"}}", key: "a", type: "date")
                == "{\n  \"types\": {\n    \"b\": \"text\",\n    \"A\": \"date\",\n    \"c/d\": \"checkbox\"\n  }\n}"
              && Study.typesJSON("{\"types\":{\"b\":\"text\"}}", key: "Phở", type: "multitext") == "{\n  \"types\": {\n    \"b\": \"text\",\n    \"Phở\": \"multitext\"\n  }\n}"
              && Study.typesJSON("{not json", key: "a", type: "date") == nil,
              "types.json gets the type as Obsidian writes it: two-space JSON, entries in their order, a name matched case aside; a file that isn't JSON is left alone")
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("sage-properties-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: vault) }
        try Study.setPropertyType("Rating", to: "number", vault: vault)
        try Study.setPropertyType("rating", to: "text", vault: vault)
        check(Study.look(vault: vault).types == ["Rating": "text"], "A type changed in the table is kept in the vault's types.json, where Sage and Obsidian read it")

        // Written through the note's safe write: line endings, byte-order mark and the rest kept.
        let file = vault.appendingPathComponent("Pho.md"), keep = vault.appendingPathComponent("kept", isDirectory: true)
        try Data([0xEF, 0xBB, 0xBF] + Array("---\r\ntags:\r\n  - soup\r\nTitle: Pho\r\n---\r\nBody\r\n".utf8)).write(to: file)
        let was = try Study.readNote(file)
        if let text = written(Study.changeProperty(was.text, drawn: Study.frontmatter(of: was.text), .set(key: "tags", values: ["soup", "noodles"], list: true, plain: false))) {
            try Study.writeNote(file, text: text, was: was, keep: keep)
        }
        let after = try Data(contentsOf: file)
        check(after == Data([0xEF, 0xBB, 0xBF] + Array("---\r\ntags:\r\n  - soup\r\n  - noodles\r\nTitle: Pho\r\n---\r\nBody\r\n".utf8))
              && ((try? fm.contentsOfDirectory(atPath: keep.path)) ?? []).count == 1,
              "A property change is written as other edits are: the note copied first, its line endings and byte-order mark kept")

        // The table drawn for editing in place.
        let table = Study.properties("tags: [food]\nAuthor: \"[[Donald Miller]]\"\nCreated: 2026-04-29\nTitle: Pho\nlinks:\n  - \"[[A|B]]\"", types: ["Created": "date"])
        check(table.contains("<div class=\"multi-select-pill\" tabindex=\"0\" data-value=\"food\"><div class=\"multi-select-pill-content\"><span>food</span></div><div class=\"multi-select-pill-remove-button\" data-sage-icon=\"lucide-x\"></div></div>")
              && table.contains("data-value=\"[[A|B]]\"") && table.contains("<div class=\"multi-select-input\" contenteditable=\"plaintext-only\" tabindex=\"0\"></div>")
              && table.contains("<div contenteditable=\"plaintext-only\" class=\"metadata-input-longtext mod-truncate\" placeholder=\"Empty\">Pho</div>")
              && table.contains("type=\"date\" value=\"2026-04-29\">") && !table.contains("readonly")
              && table.contains("data-property-key=\"Author\" data-property-type=\"text\" data-value=\"[[Donald Miller]]\"") && table.contains("metadata-link-flair")
              && table.contains("class=\"metadata-add-button text-icon-button\""),
              "The table is drawn to be edited where it is: pills with × and room to type after them, text, dates, a link's pencil, Add property")
        check(Study.noteSizer("---\n---\nBody", look: Study.Look(), title: nil).contains("class=\"metadata-container\"")
              && !Study.noteSizer("Body", look: Study.Look(), title: nil).contains("metadata-container"),
              "An empty frontmatter shows its table (to add to), as Obsidian does; a note without one shows none")
        let page = Study.notePage(note, look: Study.Look(), dark: true)
        check(page.contains("window.sageProps = {\"front\":\"Categories:\\n") && page.contains("\"shown\":true") && page.contains("\"words\":{")
              && Study.notePage("Body", look: Study.Look(), dark: true).contains("window.sageProps = {\"front\":null")
              && Study.pageScript.contains("type = 'property'") && Study.pageScript.contains("e.key === ';'") && Study.pageScript.contains("propKeep"),
              "The page knows the frontmatter it was drawn from (in either view), and sends each property's change on its own")
    }
}
