import AppKit
import Foundation

/// Changing the vault from Sage's tree (2026-11-08 in Creative Assist, the user's request: "build everything and I'll
/// review them"; brought to the Mac 2026-11-09): move, rename, new note or folder, duplicate, delete, copy files in. Links
/// follow a move or rename as Obsidian's "update internal links" does; every change can be undone, each step only if
/// nothing changed it since. Nothing is moved over something already there.
extension SageVaultDesk {
    /// Whether the vault keeps links right when files move (app.json alwaysUpdateLinks; on unless it says off).
    var updatesLinks: Bool { vault.flatMap { Study.appSetting($0, "alwaysUpdateLinks") as? Bool } ?? true }

    private func refuse(_ why: String) { say(why) }

    private func done(_ change: FileChange) {
        changes.append(change)
        if changes.count > 30 { changes.removeFirst() }
        say(change.said, undo: true)
        reload()
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: full(path).path) }
    private func isFolder(_ path: String) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: full(path).path, isDirectory: &folder) && folder.boolValue
    }

    /// A path's name as the tree shows it: a note without ".md".
    static func name(_ path: String) -> String {
        let last = (path as NSString).lastPathComponent
        return last.lowercased().hasSuffix(".md") ? String(last.dropLast(3)) : last
    }

    private static func joined(_ folder: String, _ name: String) -> String { folder.isEmpty ? name : folder + "/" + name }

    /// Files and folders moved into a folder ("" is the vault), and every link to them rewritten (when the vault updates
    /// links, as yours does). Nothing is moved over something already there, nor a folder into itself.
    @discardableResult func move(_ paths: [String], into folder: String, said: String? = nil) -> Bool {
        let tops = paths.filter { p in !paths.contains { q in q != p && p.lowercased().hasPrefix(q.lowercased() + "/") } }
        var moves: [String: String] = [:]
        for path in tops { moves[path] = Self.joined(folder, (path as NSString).lastPathComponent) }
        let place = folder.isEmpty ? L("the vault") : "“\(Self.name(folder))”"
        return apply(moves, said: said ?? (paths.count == 1 ? L("Moved “%@” to %@", Self.name(paths[0]), place) : L("Moved %@ items to %@", "\(paths.count)", place)))
    }

    /// A file or folder renamed (a note keeps its .md), links following.
    @discardableResult func rename(_ path: String, to name: String) -> Bool {
        var name = name.trimmingCharacters(in: .whitespaces)
        let item = item(path)
        let ext = item.map { $0.folder ? "" : $0.ext } ?? ""
        if ext == ".md" && name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        if let rule = Study.nameRule(name) { refuse(rule.value.map { L(rule.text, $0) } ?? L(rule.text)); return false }
        let parent = Study.VaultItem(path: path, folder: false).parent
        let keepsExtension = ext == ".md" || (!ext.isEmpty && !name.lowercased().hasSuffix(ext))
        let to = Self.joined(parent, name + (keepsExtension ? ext : ""))
        if to == path { return true }
        return apply([path: to], said: L("Renamed “%@” to “%@”", Self.name(path), Self.name(to)))
    }

    /// A file or folder moved in place: rename(2) for a change of case only (macOS' disk keeps "a.md" and "A.md" as one).
    private func relocate(_ from: String, _ to: String) throws {
        let source = full(from), target = full(to)
        if Study.same(from, to) {
            guard Darwin.rename(source.path, target.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } else {
            try FileManager.default.moveItem(at: source, to: target)
        }
    }

    private func apply(_ moves: [String: String], said: String) -> Bool {
        var moves = moves
        for (from, to) in moves {
            if from == to { moves[from] = nil; continue }
            if to.lowercased().hasPrefix(from.lowercased() + "/") { refuse(L("“%@” can't go inside itself.", Self.name(from))); return false }
            // A different case of the same name is a rename the Mac allows in place.
            if !Study.same(from, to) && exists(to) { refuse(L("There's already a “%@” there.", Self.name(to))); return false }
            if !exists(from) { refuse(L("“%@” isn't there any more.", Self.name(from))); return false }
        }
        guard !moves.isEmpty else { return false }
        var change = FileChange(said: said)
        do {
            let edits = updatesLinks ? Study.relink(items, moves: moves) { try? Study.readNote(self.full($0)).text } : []
            for (from, to) in moves {
                try FileManager.default.createDirectory(at: full(to).deletingLastPathComponent(), withIntermediateDirectories: true)
                try relocate(from, to)
                change.moves.append((from, to))
            }
            for (note, text) in edits {
                let path = Study.movedPath(note, moves), file = full(path)
                let was = try Study.readNote(file)
                try Study.writeNote(file, text: text, was: was, keep: editsKept)
                change.edits.append((path, was.text, text))
            }
            if !edits.isEmpty { change.said += " · " + (edits.count == 1 ? L("1 note's links updated") : L("%@ notes' links updated", "\(edits.count)")) }
        } catch {
            // What moved goes back, so a half-done move doesn't leave links pointing nowhere.
            for (from, to) in change.moves.reversed() { try? relocate(to, from) }
            refuse(L("Couldn't move it: %@", error.localizedDescription))
            return false
        }
        repath(moves)
        done(change)
        return true
    }

    /// A new note in a folder (from a template when one is given), opened, its path given back to rename it.
    @discardableResult func newNote(in folder: String, template: String? = nil) -> String? {
        guard let vault else { return nil }
        let name = Study.freeName(taken: { self.exists(Self.joined(folder, $0)) }, stem: "Untitled", extension: ".md")
        let path = Self.joined(folder, name)
        var text = ""
        if let template {
            let settings = (try? Data(contentsOf: vault.appendingPathComponent(".obsidian/templates.json"))).flatMap(Study.json) ?? [:]
            let date = (settings["dateFormat"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "YYYY-MM-DD"
            let time = (settings["timeFormat"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "HH:mm"
            text = Study.applyTemplate((try? String(contentsOf: full(template), encoding: .utf8)) ?? "", title: "Untitled", now: Date(), dateFormat: date, timeFormat: time)
        }
        guard make(path, text: text, folder: false) else { return nil }
        var change = FileChange(said: L("Made “%@”", Self.name(path)))
        change.made.append((path, text))
        show(path: path)
        done(change)
        return path
    }

    /// The vault's templates folder (Templates' core plugin settings, templates.json), when it has one.
    var templatesFolder: String? {
        guard let vault, let data = try? Data(contentsOf: vault.appendingPathComponent(".obsidian/templates.json")),
              let folder = Study.json(data)?["folder"] as? String, !folder.isEmpty else { return nil }
        return folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Where app.json puts new notes (newFileLocation "folder" with newFileFolderPath, "current" beside the open note,
    /// else the vault's top).
    var newNoteFolder: String {
        guard let vault else { return "" }
        switch Study.appSetting(vault, "newFileLocation") as? String {
        case "folder": return ((Study.appSetting(vault, "newFileFolderPath") as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        case "current": return note.flatMap(inVault).map { Study.VaultItem(path: $0, folder: false).parent } ?? ""
        default: return ""
        }
    }

    @discardableResult func newFolder(in parent: String) -> String? {
        let path = Self.joined(parent, Study.freeName(taken: { self.exists(Self.joined(parent, $0)) }, stem: "Untitled", extension: ""))
        guard make(path, text: nil, folder: true) else { return nil }
        if !parent.isEmpty { setOpen(parent, true) }
        var change = FileChange(said: L("Made the folder “%@”", Self.name(path)))
        change.made.append((path, ""))
        done(change)
        return path
    }

    /// A copy beside it ("Pho 1.md").
    @discardableResult func duplicate(_ path: String) -> String? {
        let parent = Study.VaultItem(path: path, folder: false).parent
        let last = (path as NSString).lastPathComponent
        let ext = (last as NSString).pathExtension.isEmpty ? "" : "." + (last as NSString).pathExtension
        let stem = ext.isEmpty ? last : String(last.dropLast(ext.count))
        let to = Self.joined(parent, Study.freeName(taken: { self.exists(Self.joined(parent, $0)) }, stem: stem, extension: ext))
        if isFolder(path) { refuse(L("Folders can't be copied here yet.")); return nil }
        do { try FileManager.default.copyItem(at: full(path), to: full(to)) } catch { refuse(L("Couldn't copy it: %@", error.localizedDescription)); return nil }
        var change = FileChange(said: L("Copied “%@”", Self.name(path)))
        change.made.append((to, (try? String(contentsOf: full(to), encoding: .utf8)) ?? ""))
        done(change)
        return to
    }

    /// Files from outside (dropped from Finder) copied into a folder of the vault.
    func copyIn(_ files: [URL], into folder: String) {
        var change = FileChange()
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            let ext = file.pathExtension.isEmpty ? "" : "." + file.pathExtension
            let to = Self.joined(folder, Study.freeName(taken: { self.exists(Self.joined(folder, $0)) }, stem: file.deletingPathExtension().lastPathComponent, extension: ext))
            do { try FileManager.default.copyItem(at: file, to: full(to)); change.made.append((to, "")) } catch { refuse(L("Couldn't copy it in: %@", error.localizedDescription)) }
        }
        guard !change.made.isEmpty else { return }
        change.said = change.made.count == 1 ? L("Copied “%@” in", Self.name(change.made[0].path)) : L("Copied %@ files in", "\(change.made.count)")
        done(change)
    }

    private func make(_ path: String, text: String?, folder: Bool) -> Bool {
        do {
            if folder { try FileManager.default.createDirectory(at: full(path), withIntermediateDirectories: true) } else {
                try FileManager.default.createDirectory(at: full(path).deletingLastPathComponent(), withIntermediateDirectories: true)
                // Never over a file that appeared meanwhile.
                try Data((text ?? "").utf8).write(to: full(path), options: .withoutOverwriting)
            }
            return true
        } catch { refuse(L("Couldn't make it: %@", error.localizedDescription)); return false }
    }

    /// Files and folders deleted as your vault deletes them (app.json "trashOption": "local" is the vault's .trash folder,
    /// else the Mac's Trash), each copied first into Sage's folder so Undo can bring it back. Tabs showing them go back.
    func delete(_ paths: [String]) {
        guard let vault else { return }
        let trash = Study.appSetting(vault, "trashOption") as? String ?? "system"
        var change = FileChange(said: paths.count == 1 ? L("Deleted “%@”", Self.name(paths[0])) : L("Deleted %@ items", "\(paths.count)"))
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyy-MM-dd HHmmss"
        let keep = editsKept.appendingPathComponent("deleted/\(stamp.string(from: Date()))", isDirectory: true)
        for path in paths where !paths.contains(where: { q in q != path && path.lowercased().hasPrefix(q.lowercased() + "/") }) {
            let file = full(path)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                let kept = keep.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: file, to: kept)
                if trash == "local" {
                    let bin = vault.appendingPathComponent(".trash", isDirectory: true)
                    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
                    let folder = isFolder(path), ext = folder || file.pathExtension.isEmpty ? "" : "." + file.pathExtension
                    let name = Study.freeName(taken: { FileManager.default.fileExists(atPath: bin.appendingPathComponent($0).path) },
                                              stem: folder ? file.lastPathComponent : file.deletingPathExtension().lastPathComponent, extension: ext)
                    try FileManager.default.moveItem(at: file, to: bin.appendingPathComponent(name))
                } else {
                    try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                }
                change.deleted.append((path, kept))
            } catch { refuse(L("Couldn't delete “%@”: %@", Self.name(path), error.localizedDescription)) }
        }
        guard !change.deleted.isEmpty else { return }
        let gone = change.deleted.map { $0.path.lowercased() }
        leaveGone { p in gone.contains { p.lowercased() == $0 || p.lowercased().hasPrefix($0 + "/") } }
        done(change)
    }

    /// The last change undone: moves go back and the links edited for them are put back (each only if nothing changed it
    /// since), deleted files come back from their copy, files made go (only if still as they were made).
    @discardableResult func undo() -> Bool {
        guard let change = changes.popLast() else { return false }
        var back: [String: String] = [:], skipped = 0
        do {
            for edit in change.edits {
                let file = full(edit.file)
                guard FileManager.default.fileExists(atPath: file.path) else { skipped += 1; continue }
                let now = try Study.readNote(file)
                guard now.text == edit.after else { skipped += 1; continue }
                try Study.writeNote(file, text: edit.before, was: now, keep: editsKept)
            }
            for (from, to) in change.moves.reversed() {
                if !exists(to) || (exists(from) && !Study.same(from, to)) { skipped += 1; continue }
                try relocate(to, from)
                back[to] = from
            }
            for (path, kept) in change.deleted {
                if exists(path) { skipped += 1; continue }
                try FileManager.default.createDirectory(at: full(path).deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: kept.path) { try FileManager.default.copyItem(at: kept, to: full(path)) } else { skipped += 1 }
            }
            for (path, text) in change.made {
                let file = full(path)
                if isFolder(path) {
                    if ((try? FileManager.default.contentsOfDirectory(atPath: file.path)) ?? ["?"]).isEmpty { try FileManager.default.removeItem(at: file) } else { skipped += 1 }
                } else if FileManager.default.fileExists(atPath: file.path), ((try? String(contentsOf: file, encoding: .utf8)) ?? "") == text {
                    try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                } else { skipped += 1 }
            }
        } catch { refuse(L("Couldn't undo all of it: %@", error.localizedDescription)) }
        if !back.isEmpty { repath(back) }
        if !change.made.isEmpty {
            let made = change.made.map { $0.path.lowercased() }
            leaveGone { p in !self.exists(p) && made.contains { p.lowercased() == $0 || p.lowercased().hasPrefix($0 + "/") } }
        }
        say(L("Undone: %@", change.said) + (skipped > 0 ? " " + L("(%@ left as they are now: they changed since)", "\(skipped)") : ""))
        reload()
        return true
    }
}
