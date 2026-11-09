import Foundation

/// Sage's vault browser (2026-11-07, built first in Creative Assist, the Windows app, and brought back on 2026-11-09):
/// your whole Obsidian vault as Obsidian's file explorer shows it, and how Obsidian resolves a [[link]] or an ![[embed]].
/// Foundation only, so the checks compile it as it is.
extension Study {
    /// Where the note view finds things (2026-11-09, the Mac's WKURLSchemeHandler; Windows maps made-up hosts): one
    /// scheme and one host, so pages, the vault and Obsidian's own files are one origin (fonts and pictures load freely).
    static let pageScheme = "sage"
    static let vaultBase = "sage://sage/vault/"
    static let obsidianBase = "sage://sage/obsidian/"
    static let pagesBase = "sage://sage/page/"

    /// A vault path's address in the note view ("Recipes/Pho bo.md" → sage://sage/vault/Recipes/Pho%20bo.md).
    static func vaultAddress(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;%")
        return vaultBase + path.components(separatedBy: "/").map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
    }

    /// A file or folder in the vault, by its path from the vault with '/' ("Quests/Custom tools/Edit Assist.md").
    struct VaultItem: Hashable, Sendable {
        var path: String
        var folder: Bool
        var modified: Date
        var created: Date

        init(path: String, folder: Bool, modified: Date = .distantPast, created: Date = .distantPast) {
            self.path = path; self.folder = folder; self.modified = modified; self.created = created
        }

        var name: String { path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path }
        var parent: String { path.lastIndex(of: "/").map { String(path[..<$0]) } ?? "" }
        /// The extension with its dot, lower case (".md"); "" for a folder or a name without one.
        var ext: String { folder ? "" : Study.extensionOf(name) }
        /// What the explorer shows: a note without ".md", any other file with its extension.
        var title: String { ext == ".md" ? String(name.dropLast(3)) : name }
    }

    /// ".png" for "a.PNG", "" for "a" or ".hidden" (as .NET's GetExtension: the last dot, not the first character).
    static func extensionOf(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex || name.count > 1 else { return "" }
        let ext = String(name[dot...])
        return ext == "." ? "" : ext.lowercased()
    }

    static let pictureTypes = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".avif"]
    /// The files Obsidian's explorer shows when "Detect all file extensions" is off.
    static let knownTypes = pictureTypes + [".md", ".canvas", ".base", ".pdf", ".mp3", ".wav", ".m4a", ".ogg", ".flac", ".webm", ".mp4", ".mov", ".mkv", ".ogv"]

    static func isPicture(_ path: String) -> Bool { pictureTypes.contains(extensionOf((path as NSString).lastPathComponent)) }

    /// Everything in the vault the explorer would show: folders and files, without hidden ones (a name starting with '.',
    /// like .obsidian and .trash). Other file types only when the vault shows them (app.json showUnsupportedFiles).
    static func vaultItems(_ vault: URL) -> [VaultItem] {
        let everything = appSetting(vault, "showUnsupportedFiles") as? Bool ?? false
        var items: [VaultItem] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey, .isPackageKey]
        func walk(_ folder: URL, _ prefix: String, _ depth: Int) {
            guard depth <= 30, let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)) else { return }
            for entry in entries {
                let name = entry.lastPathComponent
                if name.hasPrefix(".") { continue }
                let values = try? entry.resourceValues(forKeys: keys)
                let path = prefix + name
                let modified = values?.contentModificationDate ?? .distantPast, created = values?.creationDate ?? modified
                if values?.isDirectory == true && values?.isPackage != true {
                    items.append(VaultItem(path: path, folder: true, modified: modified, created: created))
                    walk(entry, path + "/", depth + 1)
                } else if values?.isSymbolicLink == true {
                    // A link is shown but not walked into, so a loop can't trap the scan.
                    var isFolder: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: entry.path, isDirectory: &isFolder)
                    if exists && isFolder.boolValue { items.append(VaultItem(path: path, folder: true, modified: modified, created: created)) }
                    else if exists && (everything || knownTypes.contains(extensionOf(name))) { items.append(VaultItem(path: path, folder: false, modified: modified, created: created)) }
                } else if everything || knownTypes.contains(extensionOf(name)) {
                    items.append(VaultItem(path: path, folder: false, modified: modified, created: created))
                }
            }
        }
        walk(vault.standardizedFileURL, "", 0)
        return items
    }

    /// The explorer's sort, as Obsidian keeps it in workspace.json (alphabetical when it keeps none).
    static func explorerOrder(_ vault: URL) -> String {
        func find(_ node: Any?) -> String? {
            if let object = node as? [String: Any] {
                if object["type"] as? String == "file-explorer", let state = object["state"] as? [String: Any], let order = state["sortOrder"] as? String { return order }
                for (_, child) in object { if let found = find(child) { return found } }
            } else if let array = node as? [Any] {
                for child in array { if let found = find(child) { return found } }
            }
            return nil
        }
        guard let data = try? Data(contentsOf: vault.appendingPathComponent(".obsidian/workspace.json")),
              let found = find(try? JSONSerialization.jsonObject(with: data)) else { return "alphabetical" }
        return ["alphabetical", "alphabeticalReverse", "byModifiedTime", "byModifiedTimeReverse", "byCreatedTime", "byCreatedTimeReverse"].contains(found) ? found : "alphabetical"
    }

    /// A setting from the vault's .obsidian/app.json (nil when it keeps none, as Obsidian's default applies).
    static func appSetting(_ vault: URL, _ name: String) -> Any? {
        guard let data = try? Data(contentsOf: vault.appendingPathComponent(".obsidian/app.json")) else { return nil }
        return json(data)?[name]
    }

    /// Names compared as Obsidian (and a person) does: case aside, numbers by value ("K2" before "K10"). Negative when
    /// `a` comes first.
    static func natural(_ a: String, _ b: String) -> Int {
        func runs(_ text: String) -> [String] {
            var parts: [String] = [], current = "", digits: Bool?
            for c in text {
                let isDigit = c.isASCII && c.isNumber
                if digits != nil && digits != isDigit { parts.append(current); current = "" }
                current.append(c); digits = isDigit
            }
            if !current.isEmpty { parts.append(current) }
            return parts
        }
        let x = runs(a), y = runs(b)
        for i in 0 ..< min(x.count, y.count) {
            let p = x[i], q = y[i]
            let c: Int
            if let first = p.first, let other = q.first, first.isASCII && first.isNumber, other.isASCII && other.isNumber {
                let pn = String(p.drop { $0 == "0" }), qn = String(q.drop { $0 == "0" })
                c = pn.count != qn.count ? (pn.count < qn.count ? -1 : 1) : (pn == qn ? 0 : (pn < qn ? -1 : 1))
            } else {
                switch p.compare(q, options: [.caseInsensitive], range: nil, locale: .current) {
                case .orderedAscending: c = -1
                case .orderedDescending: c = 1
                case .orderedSame: c = 0
                }
            }
            if c != 0 { return c }
        }
        return x.count == y.count ? 0 : (x.count < y.count ? -1 : 1)
    }

    /// What a folder holds, in the explorer's order: folders first, then files. Folders go by name (reversed only in
    /// reverse alphabetical); files by the vault's sort, newest first for the time sorts as Obsidian shows them.
    static func children(_ items: [VaultItem], folder: String, order: String) -> [VaultItem] {
        let here = items.filter { $0.parent == folder }
        let reverse = order == "alphabeticalReverse"
        let folders = here.filter(\.folder).sorted { reverse ? natural($1.name, $0.name) < 0 : natural($0.name, $1.name) < 0 }
        let files = here.filter { !$0.folder }.sorted(by: fileOrder(order))
        return folders + files
    }

    /// How files are ordered for one of Obsidian's six sorts.
    static func fileOrder(_ order: String) -> (VaultItem, VaultItem) -> Bool {
        switch order {
        case "alphabeticalReverse": return { natural($1.title, $0.title) < 0 }
        case "byModifiedTime": return { $0.modified > $1.modified }
        case "byModifiedTimeReverse": return { $0.modified < $1.modified }
        case "byCreatedTime": return { $0.created > $1.created }
        case "byCreatedTimeReverse": return { $0.created < $1.created }
        default: return { natural($0.title, $1.title) < 0 }
        }
    }

    static func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

    /// The file a [[link]] or ![[embed]] means, as Obsidian finds it: "#heading" and "|alias" aside; a bare name is a note
    /// ("Pho" is Pho.md) or a file with its extension, wherever it is, the one nearest the linking note first; a path
    /// ("Recipes/Pho") matches from the vault's top, then as the end of a path. Nil when nothing matches.
    static func resolve(_ link: String, in items: [VaultItem], from: String? = nil) -> VaultItem? {
        var target = String(link.split(separator: "|", omittingEmptySubsequences: false).first ?? "")
        target = String(target.split(separator: "#", omittingEmptySubsequences: false).first ?? "")
        target = target.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
        while target.hasPrefix("/") { target.removeFirst() }
        if target.isEmpty { return nil }
        target = target.removingPercentEncoding ?? target
        let files = items.filter { !$0.folder }
        let hasExtension = !extensionOf((target as NSString).lastPathComponent).isEmpty && !target.hasSuffix(".")
        let names = hasExtension ? [target, target + ".md"] : [target + ".md"]
        for name in names {
            if name.contains("/"), let exact = files.first(where: { same($0.path, name) }) { return exact }
            let bare = name.lastIndex(of: "/").map { String(name[name.index(after: $0)...]) } ?? name
            let suffix = "/" + name.lowercased()
            let matches = files.filter { same($0.name, bare) && (!name.contains("/") || $0.path.lowercased().hasSuffix(suffix)) }
            if matches.isEmpty { continue }
            let near = from.map { VaultItem(path: $0, folder: false).parent } ?? ""
            return matches.min { a, b in
                let an = same(a.parent, near), bn = same(b.parent, near)
                if an != bn { return an }
                let ad = a.path.filter { $0 == "/" }.count, bd = b.path.filter { $0 == "/" }.count
                if ad != bd { return ad < bd }
                return a.path.lowercased() < b.path.lowercased()
            }
        }
        return nil
    }

    /// A relative link in a note ("../Attachments/a.png", "Attachments/a%20b.png") made a vault path, or nil if it leaves the vault.
    static func relative(_ link: String, from: String?) -> String? {
        let path = (link.removingPercentEncoding ?? link).replacingOccurrences(of: "\\", with: "/")
        var parts: [String] = []
        if let from, !path.hasPrefix("/"), let slash = from.lastIndex(of: "/") { parts = from[..<slash].components(separatedBy: "/") }
        for part in path.drop(while: { $0 == "/" }).components(separatedBy: "/") {
            if part.isEmpty || part == "." { continue }
            if part == ".." { if parts.isEmpty { return nil }; parts.removeLast() } else { parts.append(part) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// Every match of the pattern replaced by what `with` makes of its groups (a group not matched is ""). Shared by the
    /// vault's files (Foundation's regular expressions, as .NET's Regex.Replace).
    static func substitute(_ pattern: String, in text: String, options: NSRegularExpression.Options = [], with: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        var result = "", last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text) else { continue }
            let groups = (0 ..< match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
            result += text[last ..< whole.lowerBound] + with(groups)
            last = whole.upperBound
        }
        return result + text[last...]
    }

    /// The groups of the first match ("" for a group not matched), or nil.
    static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0 ..< match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
    }

    static func matches(_ pattern: String, _ text: String, options: NSRegularExpression.Options = []) -> Bool { firstMatch(pattern, in: text, options: options) != nil }

    /// The note's pictures shown, as Obsidian shows them: an ![[embed]] or a ![](relative/path) that is a picture in the
    /// vault becomes the picture, its address made by `address` (the note view's own scheme for the vault). An embedded
    /// note or a missing file stays a link.
    static func withPictures(_ html: String, items: [VaultItem], from: String?, address: (String) -> String) -> String {
        func plain(_ text: String) -> String {
            text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
        }
        func quoted(_ text: String) -> String { escape(text).replacingOccurrences(of: "\"", with: "&quot;") }
        var page = substitute(#"<span class="internal-embed"(?: alt="([^"]*)")?><a class="internal-link" href="sage-note:([^"]*)">[^<]*</a></span>"#, in: html) { g in
            let link = plain(g[2])
            guard let found = resolve(link, in: items, from: from), isPicture(found.path) else { return g[0] }
            // ![[picture.png|300]] or |300x200: the size Obsidian gives it.
            let alt = plain(g[1])
            var sized = ""
            if let size = firstMatch(#"^\s*(\d+)(?:\s*x\s*(\d+))?\s*$"#, in: alt) {
                sized = " width=\"\(size[1])\"" + (size[2].isEmpty ? "" : " height=\"\(size[2])\"")
            }
            return "<span class=\"internal-embed media-embed image-embed is-loaded\" src=\"\(quoted(link))\" alt=\"\(quoted(alt))\"><img src=\"\(quoted(address(found.path)))\" alt=\"\(quoted(found.name))\"\(sized)></span>"
        }
        page = substitute(#"<img src="(?!https?:|data:)([^"]+)""#, in: page) { g in
            let link = plain(g[1])
            let path = relative(link, from: from)
            let found = path.flatMap { path in items.first { !$0.folder && same($0.path, path) } } ?? resolve(link, in: items, from: from)
            return found.map { "<img src=\"\(quoted(address($0.path)))\"" } ?? g[0]
        }
        return page
    }

    // MARK: Editing a note (2026-11-07): you edit it in the note view; Sage, the model, never writes over a file.

    /// A note's text with '\n' lines, and how the file keeps it (CRLF lines, a UTF-8 BOM), so it's written back the same way.
    struct NoteText: Equatable, Sendable {
        var text: String
        var crlf: Bool
        var bom: Bool
    }

    static func readNote(_ file: URL) throws -> NoteText {
        let bytes = try Data(contentsOf: file)
        let bom = bytes.starts(with: [0xEF, 0xBB, 0xBF])
        let text = String(decoding: bom ? bytes.dropFirst(3) : bytes[...], as: UTF8.self)
        return NoteText(text: text.replacingOccurrences(of: "\r\n", with: "\n"), crlf: text.contains("\r\n"), bom: bom)
    }

    /// The notes already copied this run, so each is kept once.
    private static let kept = Kept()
    private final class Kept: @unchecked Sendable {
        private var files: Set<String> = []
        private let lock = NSLock()
        func add(_ file: String) -> Bool { lock.lock(); defer { lock.unlock() }; return files.insert(file).inserted }
    }

    /// The note written as you changed it: the first time this run, the note as it was is copied into `keep` (copies older
    /// than 30 days go); then the new text goes into a hidden file beside it (Obsidian skips names starting with '.') that
    /// replaces the note in one step, keeping its created date, so Obsidian never reads half a note.
    static func writeNote(_ file: URL, text: String, was: NoteText, keep: URL?) throws {
        if let keep, kept.add(file.standardizedFileURL.path) {
            try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyy-MM-dd HHmmss"
            let copy = keep.appendingPathComponent("\(stamp.string(from: Date())) \(file.lastPathComponent)")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: file, to: copy)
            let month = Date().addingTimeInterval(-30 * 86_400)
            for old in (try? FileManager.default.contentsOfDirectory(at: keep, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                if let date = try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < month { try? FileManager.default.removeItem(at: old) }
            }
        }
        let body = was.crlf ? text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n") : text
        var data = Data(was.bom ? [0xEF, 0xBB, 0xBF] : [])
        data.append(Data(body.utf8))
        let created = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.creationDate] as? Date
        let temp = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).sage-\(ProcessInfo.processInfo.processIdentifier)")
        defer { try? FileManager.default.removeItem(at: temp) }
        try data.write(to: temp)
        // One step: the note is never half written (replaceItemAt swaps the files, keeping the note's own attributes).
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temp, backupItemName: nil, options: [])
        if let created { try? FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: file.path) }
    }
}
