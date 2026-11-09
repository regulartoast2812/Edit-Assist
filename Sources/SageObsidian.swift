import Foundation

/// Sage's note view in Obsidian's own look (2026-11-07, built first in Creative Assist and brought back on 2026-11-09).
/// Obsidian's own stylesheet (app.css), its fonts and its icons, read from the copy of Obsidian installed on this Mac, so a
/// note in Sage is dressed exactly as Obsidian dresses it, under your theme and snippets. Obsidian keeps them in an
/// Electron archive (Obsidian.app/Contents/Resources/obsidian.asar, and a newer one in ~/Library/Application
/// Support/obsidian when it has updated itself); Sage only reads it, copies what it needs into its own cache folder once
/// per Obsidian version, and falls back to its own look (baseCSS) when Obsidian isn't installed. Foundation only.
extension Study {
    /// The Obsidian archives on this Mac: the installed one and any it downloaded when it updated itself.
    static func obsidianArchives() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var found = [URL(fileURLWithPath: "/Applications/Obsidian.app/Contents/Resources/obsidian.asar"),
                     home.appendingPathComponent("Applications/Obsidian.app/Contents/Resources/obsidian.asar")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let updates = home.appendingPathComponent("Library/Application Support/obsidian")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: updates.path)) ?? [] where name.hasPrefix("obsidian-") && name.hasSuffix(".asar") {
            found.append(updates.appendingPathComponent(name))
        }
        return found
    }

    enum AsarError: Error { case notAnArchive }

    /// The files in an asar archive by their path ("public/fonts/x.woff2"): where each starts and its size.
    static func asarIndex(_ archive: FileHandle) throws -> [String: (offset: UInt64, size: Int)] {
        // An asar starts with two Chromium pickles: the header's size, then the header itself (a JSON tree of the files,
        // offsets counted from the end of the header).
        try archive.seek(toOffset: 0)
        guard let head = try archive.read(upToCount: 16), head.count == 16 else { throw AsarError.notAnArchive }
        func uint32(_ at: Int) -> UInt32 { head[head.startIndex + at ..< head.startIndex + at + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } }
        let headerSize = uint32(4)
        let jsonSize = Int(Int32(bitPattern: uint32(12)))
        guard jsonSize > 0, jsonSize <= 64_000_000, let json = try archive.read(upToCount: jsonSize), json.count == jsonSize else { throw AsarError.notAnArchive }
        let start = 8 + UInt64(headerSize)
        var files: [String: (offset: UInt64, size: Int)] = [:]
        func walk(_ folder: [String: Any], _ prefix: String) {
            for (name, node) in folder {
                guard let entry = node as? [String: Any] else { continue }
                if let inner = entry["files"] as? [String: Any] { walk(inner, prefix + name + "/"); continue }
                if (entry["unpacked"] as? NSNumber)?.boolValue == true { continue }
                if let offset = entry["offset"] as? String, let at = UInt64(offset), let size = (entry["size"] as? NSNumber)?.intValue {
                    files[prefix + name] = (start + at, size)
                }
            }
        }
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { throw AsarError.notAnArchive }
        if let top = root["files"] as? [String: Any] { walk(top, "") }
        return files
    }

    private static func asarFile(_ archive: FileHandle, _ entry: (offset: UInt64, size: Int)) throws -> Data {
        try archive.seek(toOffset: entry.offset)
        guard let data = try archive.read(upToCount: entry.size), data.count == entry.size else { throw AsarError.notAnArchive }
        return data
    }

    /// "1.10.2" after "1.9.0": versions compared number by number.
    static func newerVersion(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0 ..< max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// The folder holding Obsidian's app.css, its fonts (public/fonts) and icons.js, copied from the newest Obsidian on
    /// this Mac into `cache`; nil when there's no Obsidian. Copied once per version; a folder is used only once complete.
    static func obsidianStyle(cache: URL, archives: [URL] = obsidianArchives()) -> URL? {
        var newest: (version: String, path: URL)?
        for archive in archives {
            guard let file = try? FileHandle(forReadingFrom: archive) else { continue }
            defer { try? file.close() }
            guard let index = try? asarIndex(file), let package = index["package.json"], index["app.css"] != nil,
                  let data = try? asarFile(file, package), let version = json(data)?["version"] as? String,
                  version.split(separator: ".").allSatisfy({ Int($0) != nil }) else { continue }
            if newest == nil || newerVersion(version, than: newest!.version) { newest = (version, archive) }
        }
        guard let found = newest else { return nil }
        let size = ((try? FileManager.default.attributesOfItem(atPath: found.path.path))?[.size] as? NSNumber)?.intValue ?? 0
        let folder = cache.appendingPathComponent("\(found.version)-\(size)", isDirectory: true)
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.appendingPathComponent("done").path) { return folder }
        do {
            let making = cache.appendingPathComponent("\(folder.lastPathComponent).making-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? manager.removeItem(at: making)
            try manager.createDirectory(at: making.appendingPathComponent("public/fonts"), withIntermediateDirectories: true)
            let file = try FileHandle(forReadingFrom: found.path)
            defer { try? file.close() }
            let index = try asarIndex(file)
            try asarFile(file, index["app.css"]!).write(to: making.appendingPathComponent("app.css"))
            for (name, entry) in index where name.hasPrefix("public/fonts/") {
                let font = String(name.dropFirst("public/fonts/".count))
                guard !font.isEmpty, !font.contains("/") else { continue }
                try asarFile(file, entry).write(to: making.appendingPathComponent("public/fonts").appendingPathComponent(font))
            }
            let icons = try index["app.js"].map { obsidianIcons(String(decoding: try asarFile(file, $0), as: UTF8.self)) } ?? [:]
            let table = (try? JSONSerialization.data(withJSONObject: icons, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            try Data("window.sageIcons = \(table);".utf8).write(to: making.appendingPathComponent("icons.js"))
            try Data(found.path.path.utf8).write(to: making.appendingPathComponent("done"))
            try? manager.removeItem(at: folder)
            try manager.moveItem(at: making, to: folder)
            // Older copies (Obsidian updated since) are Sage's own, so they go.
            for old in (try? manager.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? [] where old.lastPathComponent != folder.lastPathComponent {
                try? manager.removeItem(at: old)
            }
            return folder
        } catch { return nil }
    }

    /// Obsidian's icons (Lucide's, as Obsidian ships them) by name, as the SVG's inner markup: app.js keeps them as a table
    /// of shapes ({"a-arrow-down":[[6,"M3 16 4 4 4-4"],…]}: 0 line, 1 circle, 2 polyline, 3 polygon, 4 ellipse, 5 rect,
    /// 6 path). Plus Obsidian's own fold triangle. An app.js this can't read gives just that one.
    static func obsidianIcons(_ appJs: String) -> [String: String] {
        var icons = ["right-triangle": "<path d=\"M3 8L12 17L21 8\"/>"]
        let text = Array(appJs.utf16)
        let marker = Array("\"a-arrow-down\":[[".utf16)
        guard let first = text.firstRange(of: marker)?.lowerBound,
              let open = text[..<first].lastIndex(of: UInt16(UInt8(ascii: "{"))) else { return icons }
        var depth = 0, end = -1, quoted = false, i = open
        while i < text.count && end < 0 {
            let c = text[i]
            if quoted {
                if c == UInt16(UInt8(ascii: "\\")) { i += 1 } else if c == UInt16(UInt8(ascii: "\"")) { quoted = false }
            } else if c == UInt16(UInt8(ascii: "\"")) { quoted = true }
            else if c == UInt16(UInt8(ascii: "{")) { depth += 1 }
            else if c == UInt16(UInt8(ascii: "}")) { depth -= 1; if depth == 0 { end = i } }
            i += 1
        }
        guard end >= 0, let slice = String(utf16CodeUnits: Array(text[open ... end]), count: end - open + 1) as String? else { return icons }
        // Plain JSON once its bare keys (info:[[…]]) are quoted and its short numbers (.5) have their 0.
        var json = substitute(#"(?<=[{,])([A-Za-z_$][\w$]*):"#, in: slice) { "\"\($0[1])\":" }
        json = substitute(#"(?<=[\[,])(-?)\.(?=\d)"#, in: json) { "\($0[1])0." }
        guard let table = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return icons }
        func number(_ value: Any?) -> String {
            if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
                let d = n.doubleValue
                return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
            }
            return escape(value as? String ?? "")
        }
        func on(_ shape: [Any], _ i: Int) -> Bool {
            guard shape.count > i, let n = shape[i] as? NSNumber else { return false }
            return n.doubleValue != 0
        }
        for (name, shapes) in table {
            guard let list = shapes as? [Any] else { continue }
            var svg = ""
            for case let shape as [Any] in list {
                guard let kind = (shape.first as? NSNumber)?.intValue else { continue }
                func a(_ i: Int) -> String { shape.count > i ? number(shape[i]) : "" }
                switch kind {
                case 0: svg += "<line x1=\"\(a(1))\" y1=\"\(a(2))\" x2=\"\(a(3))\" y2=\"\(a(4))\"/>"
                case 1: svg += "<circle cx=\"\(a(1))\" cy=\"\(a(2))\" r=\"\(a(3))\"\(on(shape, 4) ? " fill=\"currentColor\"" : "")/>"
                case 2: svg += "<polyline points=\"\(a(1))\"/>"
                case 3: svg += "<polygon points=\"\(a(1))\"/>"
                case 4: svg += "<ellipse cx=\"\(a(1))\" cy=\"\(a(2))\" rx=\"\(a(3))\" ry=\"\(a(4))\"/>"
                case 5:
                    let transform = shape.count > 7 ? (shape[7] as? String ?? "") : ""
                    svg += "<rect x=\"\(a(1))\" y=\"\(a(2))\" width=\"\(a(3))\" height=\"\(a(4))\"\(on(shape, 5) ? " rx=\"\(a(5))\"" : "")\(on(shape, 6) ? " ry=\"\(a(6))\"" : "")\(transform.isEmpty ? "" : " transform=\"\(escape(transform))\"")/>"
                case 6: svg += "<path d=\"\(a(1))\"\(on(shape, 2) ? " fill=\"currentColor\"" : "")/>"
                default: break
                }
            }
            if !svg.isEmpty { icons[name] = svg }
        }
        return icons
    }
}
