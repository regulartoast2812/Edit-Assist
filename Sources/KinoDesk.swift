import AppKit
import AVFoundation
import Foundation
import Security

/// Kino's desk (2026-11-04, the media you put in since 2026-11-05). A batch starts empty: Kino reads only the files you
/// drop or add, never a folder by himself. A file named by shot code goes into its shot as it comes in (K1.1 and K1.2
/// into K1's one prompt, each under its own tag); any file can be dragged into any shot, and one picture can be in many
/// shots, under a tag of each (K2.3). Every file has a role in its shot (look, start frame, camera and motion, video to
/// edit…), and the roles, not a mode tab, decide which of the model's endpoints the shot goes to, so an edit is never sent
/// as a reference by chance (docs/kino/forge.md). Kept beside projects.json, one file per project (`kino/<project>.json`),
/// never in it; the Kling and Higgsfield keys live in the Keychain. Nothing is sent yet.
@MainActor
final class KinoDesk: ObservableObject {
    @Published private(set) var batch = KinoBatch()
    /// Video and sound lengths in seconds, by path.
    @Published private(set) var durations: [String: Double] = [:]
    /// Files of the batch no longer where they were put in (moved, renamed or deleted in Finder).
    @Published private(set) var missing: Set<String> = []
    @Published var selected: String?
    @Published private(set) var hasKling = KinoKeys.kling != nil
    @Published private(set) var hasHiggsfield = KinoKeys.higgsfield != nil
    private var project: UUID?

    /// The media you put in, in the order it came.
    var media: [KinoFile] {
        batch.media.compactMap { path in
            let url = URL(fileURLWithPath: path)
            return KinoKind(url).map { KinoFile(url: url, kind: $0, shot: nil, handle: url.deletingPathExtension().lastPathComponent) }
        }
    }
    var shots: [String] { batch.order }
    /// A shot's files, each under its tag in that shot.
    func files(in code: String) -> [KinoFile] {
        shot(code).inputs.compactMap { input in
            let url = URL(fileURLWithPath: input.path)
            return KinoKind(url).map { KinoFile(url: url, kind: $0, shot: code, handle: input.tag) }
        }
    }
    /// The shots a file is in.
    func shots(using path: String) -> [String] { batch.order.filter { shot($0).inputs.contains { $0.path == path } } }
    func shot(_ code: String) -> KinoShot { batch.shots[code] ?? KinoShot() }
    /// The shot's own settings, or the batch's when it has none.
    func settings(_ code: String) -> KinoSettings { shot(code).settings ?? batch.settings }
    func role(of file: KinoFile, in code: String) -> KinoRole { KinoRole.of(file, shot(code).roles) }
    func plan(_ code: String) -> KinoPlan {
        var plan = KinoRequest.plan(files: files(in: code), roles: shot(code).roles, prompt: shot(code).prompt, shared: batch.shared,
                                    settings: settings(code), durations: durations)
        for file in files(in: code) where missing.contains(file.id) { plan.problems.insert(L("@%@ is no longer on this Mac", file.handle), at: 0) }
        return plan
    }

    /// Why shots cannot run yet, said once: a missing key, something to fix, or sending, which is not built yet.
    func blocker(_ codes: [String]) -> String {
        let missing = missingKeys(codes)
        if missing.count > 1 { return L("Add your Higgsfield and Kling keys to run") }
        if let service = missing.first { return L("Add your %@ key to run", service.rawValue) }
        let broken = codes.filter { !plan($0).problems.isEmpty }.count
        if broken > 0 { return codes.count == 1 ? L("Fix what is marked first") : L("%@ shots to fix first", broken) }
        return L("Sending is built next, tested with your keys")
    }
    /// The services these shots go to whose key is not saved.
    func missingKeys(_ codes: [String]) -> [KinoModel.Service] {
        let services = Set(codes.map { KinoModel.named(settings($0).model).service })
        return [KinoModel.Service.higgsfield, .kling].filter { services.contains($0) && !($0 == .kling ? hasKling : hasHiggsfield) }
    }
    func missingKey(_ codes: [String]) -> Bool { !missingKeys(codes).isEmpty }

    /// The project's batch, when the page opens or the project changes.
    func open(project id: UUID) {
        if id != project {
            project = id
            batch = (try? JSONDecoder().decode(KinoBatch.self, from: Data(contentsOf: Self.file(id)))) ?? KinoBatch()
            selected = batch.order.first
        }
        refresh()
    }

    /// Which files are still there, then the lengths of the videos and sounds not read yet.
    func refresh() {
        missing = Set(batch.media.filter { !FileManager.default.fileExists(atPath: $0) })
        if selected.map(batch.order.contains) != true { selected = batch.order.first }
        Task {
            for file in media where file.kind != .image && durations[file.id] == nil && !missing.contains(file.id) {
                if let time = try? await AVURLAsset(url: file.url).load(.duration), time.isNumeric { durations[file.id] = time.seconds }
            }
        }
    }

    /// Files you drop or add (a folder brings the media in it, three folders deep). Into `shot` when dropped on one;
    /// otherwise a file whose name has a shot code goes into that shot, made if new (K1.1 into K1). A bare number ("7")
    /// is not taken as a code here: too many files are named like that. Dropped on a shot's empty place, `role` is that
    /// place's role, for the files that can have it.
    func add(_ urls: [URL], into shot: String? = nil, as role: KinoRole? = nil) {
        var codes: [String] = []
        for url in urls.flatMap(Self.expand) {
            let path = url.standardizedFileURL.path
            if !batch.media.contains(path) { batch.media.append(path) }
            let name = url.deletingPathExtension().lastPathComponent
            let code = shot ?? KinoCode.parse(name).flatMap { $0.code.first?.isLetter == true || $0.code.contains(".") ? $0.shot : nil }
            if let code {
                let tag = put(path, into: code)
                if let role, let kind = KinoKind(url), KinoRole.choices(kind).contains(role) {
                    edit(code) { $0.roles[tag] = role == .usual(kind) ? nil : role }
                }
                codes.append(code)
            }
        }
        if let first = codes.first, shot == nil || selected == nil { selected = first }
        save()
        refresh()
    }

    /// Opens the file chooser and adds what you pick.
    func choose(into shot: String? = nil, as role: KinoRole? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = L("Add")
        panel.message = L("Pictures, videos and sounds for this batch. Files named K1, K1.1… go into their shot.")
        guard panel.runModal() == .OK else { return }
        add(panel.urls, into: shot, as: role)
    }

    /// A new shot after the last one with the same letters (K7 after K6; K1 when there is none), with these files.
    @discardableResult
    func newShot(with urls: [URL] = []) -> String {
        let letters = batch.order.last.map { String($0.prefix { $0.isLetter }) } ?? "K"
        let used = batch.order.compactMap { KinoCode.parse($0) }.filter { $0.shot.hasPrefix(letters) && $0.shot.dropFirst(letters.count).allSatisfy(\.isNumber) }
            .compactMap { Int($0.shot.dropFirst(letters.count)) }
        let code = letters + String((used.max() ?? 0) + 1)
        batch.order.append(code)
        selected = code
        if urls.isEmpty { save() } else { add(urls, into: code) }
        return code
    }

    func removeShot(_ code: String) {
        batch.order.removeAll { $0 == code }
        batch.shots[code] = nil
        if selected == code { selected = batch.order.first }
        save()
    }

    /// Takes a file out of one shot; it stays in the media.
    func takeOut(_ file: KinoFile, of code: String) {
        edit(code) { shot in
            shot.inputs.removeAll { $0.tag == file.handle }
            shot.roles[file.handle] = nil
        }
    }

    /// Takes a file out of the batch and every shot; the file itself is not touched.
    func remove(_ path: String) {
        batch.media.removeAll { $0 == path }
        for code in batch.order { edit(code) { shot in
            for input in shot.inputs where input.path == path { shot.roles[input.tag] = nil }
            shot.inputs.removeAll { $0.path == path }
        } }
        save()
        refresh()
    }

    /// The file into the shot under a tag of its own there: the code in its name when that is this shot's and free
    /// (K1.1), the code and its words when the code is taken (K9-ref), else the shot's next number (K2.3).
    @discardableResult
    private func put(_ path: String, into code: String) -> String {
        if !batch.order.contains(code) {
            batch.order.append(code)
            batch.order.sort(by: KinoCode.before)
        }
        if let had = shot(code).inputs.first(where: { $0.path == path }) { return had.tag }
        var made = code
        edit(code) { shot in
            let taken = Set(shot.inputs.map { $0.tag.lowercased() })
            let parsed = KinoCode.parse(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
            var tag: String?
            if let parsed, parsed.shot == code {
                if !taken.contains(parsed.code.lowercased()) { tag = parsed.code }
                else if !parsed.label.isEmpty, !taken.contains((parsed.code + "-" + KinoCode.slug(parsed.label)).lowercased()) {
                    tag = parsed.code + "-" + KinoCode.slug(parsed.label)
                }
            }
            if tag == nil, !taken.contains(code.lowercased()) { tag = code }
            if tag == nil {
                var number = 1
                while taken.contains("\(code).\(number)".lowercased()) { number += 1 }
                tag = "\(code).\(number)"
            }
            made = tag!
            shot.inputs.append(KinoInput(path: path, tag: made))
        }
        return made
    }

    func setPrompt(_ text: String, for code: String) { edit(code) { $0.prompt = text } }
    func setRole(_ role: KinoRole, of file: KinoFile, in code: String) {
        edit(code) { $0.roles[file.handle] = role == .usual(file.kind) ? nil : role }
    }
    /// A shot's own settings; the batch's again when they are the same.
    func setSettings(_ settings: KinoSettings?, for code: String) {
        edit(code) { $0.settings = settings == batch.settings ? nil : settings }
    }
    func setShared(_ text: String) { guard batch.shared != text else { return }; batch.shared = text; save() }
    func setBatchSettings(_ settings: KinoSettings) { guard batch.settings != settings else { return }; batch.settings = settings; save() }

    private func edit(_ code: String, _ change: (inout KinoShot) -> Void) {
        var shot = shot(code)
        change(&shot)
        guard shot != batch.shots[code] ?? KinoShot() else { return }
        batch.shots[code] = shot == KinoShot() ? nil : shot
        save()
    }

    private func save() {
        guard let project else { return }
        let file = Self.file(project)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(batch).write(to: file, options: .atomic)
    }

    func saveKling(_ key: String?) {
        KinoKeys.kling = key.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        hasKling = KinoKeys.kling != nil
    }
    /// Higgsfield's key is two parts, its ID and its secret, sent together as "id:secret".
    func saveHiggsfield(id: String, secret: String) {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines), secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        KinoKeys.higgsfield = id.isEmpty || secret.isEmpty ? nil : id + ":" + secret
        hasHiggsfield = KinoKeys.higgsfield != nil
    }
    func removeHiggsfield() { KinoKeys.higgsfield = nil; hasHiggsfield = false }

    nonisolated static func file(_ project: UUID) -> URL { Studio.folder.appendingPathComponent("kino/\(project.uuidString).json") }

    /// A dropped file as itself; a dropped folder as the media in it, three folders deep, without hidden files, in name order.
    nonisolated static func expand(_ url: URL) -> [URL] {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return KinoKind(url) == nil ? [] : [url] }
        var found: [URL] = []
        if let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let item as URL in walk {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if walk.level >= 3 { walk.skipDescendants() }
                } else if KinoKind(item) != nil {
                    found.append(item)
                }
            }
        }
        return found.sorted { KinoCode.before($0.lastPathComponent, $1.lastPathComponent) }
    }
}

/// The places in a shot for its model, in order: start frame, end frame, looks, videos, sounds. Each file sits where its
/// role puts it; a role the model still has room for gets one empty place (a box with a + on the page, where a dropped
/// file takes that role). Files in a role the model has no place for come next (their problem is said in the plan), left-out
/// files last. Room as each model takes it (docs/kino/README.md): Kling O3 4 pictures with its one video, 7 without;
/// Seedance 30 pictures, 10 videos, 10 sounds; Kling 4.0 10 pictures, 5 videos; Motion Control one person, one performance.
enum KinoSlot: Equatable {
    case file(KinoFile)
    case empty(KinoRole)

    static func all(model: String, files: [KinoFile], roles: [String: KinoRole]) -> [KinoSlot] {
        func of(_ role: KinoRole) -> [KinoFile] { files.filter { KinoRole.of($0, roles) == role } }
        let starts = of(.start), ends = of(.end), looks = of(.look), motions = of(.motion), edits = of(.edit), sounds = of(.sound)
        let pictures = starts.count + ends.count + looks.count, videos = motions.count + edits.count
        var room: [KinoRole: Bool]
        switch model {
        case "kling-motion":
            room = [.look: looks.isEmpty, .motion: motions.isEmpty]
        case "seedance-2.5":
            room = [.start: starts.isEmpty, .end: ends.isEmpty, .look: pictures < 30, .motion: videos < 10, .edit: edits.isEmpty && videos < 10,
                    .sound: sounds.count < 10]
        case "kling-4.0":
            room = [.start: starts.isEmpty, .end: ends.isEmpty, .look: looks.count < 10, .motion: videos < 5, .edit: edits.isEmpty && videos < 5]
        default:
            let most = videos == 0 ? 7 : 4
            room = [.start: starts.isEmpty && pictures < most, .end: ends.isEmpty && pictures < most, .look: pictures < most,
                    .motion: videos == 0, .edit: videos == 0]
        }
        var slots: [KinoSlot] = []
        let order: [KinoRole] = [.start, .end, .look, .motion, .edit, .sound]
        for role in order where room[role] != nil {
            slots += of(role).map { .file($0) }
            if room[role] == true { slots.append(.empty(role)) }
        }
        slots += order.filter { room[$0] == nil }.flatMap(of).map { .file($0) }
        return slots + of(.unused).map { .file($0) }
    }

    /// How many pictures, videos and sounds the model takes in a shot; a kind it does not take is left out.
    static func most(model: String, files: [KinoFile], roles: [String: KinoRole]) -> [KinoKind: Int] {
        let videos = files.filter { [.motion, .edit].contains(KinoRole.of($0, roles)) }.count
        switch model {
        case "kling-motion": return [.image: 1, .video: 1]
        case "seedance-2.5": return [.image: 30, .video: 10, .audio: 10]
        case "kling-4.0": return [.image: 12, .video: 5]
        default: return [.image: videos == 0 ? 7 : 4, .video: 1]
        }
    }

    /// The kind of file that goes in this place.
    var kind: KinoKind {
        switch self {
        case .file(let file): file.kind
        case .empty(let role): [.motion, .edit].contains(role) ? .video : role == .sound ? .audio : .image
        }
    }
}

/// One project's batch: the media you put in, the shots in order, the words said in every shot (the product's facts, the
/// look), the settings every shot starts from, and each shot's files, prompt and changes. Batches saved before
/// 2026-11-05 had a folder instead of media; they open empty.
struct KinoBatch: Codable, Equatable {
    var media: [String] = []
    var order: [String] = []
    var shared = ""
    var settings = KinoSettings()
    var shots: [String: KinoShot] = [:]
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        media = try values.decodeIfPresent([String].self, forKey: .media) ?? []
        order = try values.decodeIfPresent([String].self, forKey: .order) ?? []
        shared = try values.decodeIfPresent(String.self, forKey: .shared) ?? ""
        settings = try values.decodeIfPresent(KinoSettings.self, forKey: .settings) ?? KinoSettings()
        shots = try values.decodeIfPresent([String: KinoShot].self, forKey: .shots) ?? [:]
    }
}

struct KinoShot: Codable, Equatable {
    /// Its files in the order they came, each under its tag in this shot.
    var inputs: [KinoInput] = []
    var prompt = ""
    /// Roles you changed, by tag; the others have the usual role for their kind.
    var roles: [String: KinoRole] = [:]
    /// nil: the batch's settings.
    var settings: KinoSettings?
    init(inputs: [KinoInput] = [], prompt: String = "", roles: [String: KinoRole] = [:], settings: KinoSettings? = nil) {
        self.inputs = inputs; self.prompt = prompt; self.roles = roles; self.settings = settings
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        inputs = try values.decodeIfPresent([KinoInput].self, forKey: .inputs) ?? []
        prompt = try values.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        roles = try values.decodeIfPresent([String: KinoRole].self, forKey: .roles) ?? [:]
        settings = try values.decodeIfPresent(KinoSettings.self, forKey: .settings)
    }
}

/// A file in a shot: where it is, and its tag there.
struct KinoInput: Codable, Equatable {
    var path: String
    var tag: String
}

struct KinoSettings: Codable, Equatable {
    var model = KinoModel.standard.id
    /// nil: the model's usual length.
    var seconds: Int?
    var aspect = "9:16"
    var quality = KinoModel.standard.defaultQuality
    var sound = false
    var takes = 1

    /// The same settings made to fit a model: the length within its range, its own aspect and quality when it lacks these.
    func fitted(to model: KinoModel) -> KinoSettings {
        var fitted = self
        fitted.model = model.id
        if let range = model.seconds, let seconds { fitted.seconds = min(max(seconds, range.lowerBound), range.upperBound) }
        if !model.aspects.isEmpty, !model.aspects.contains(aspect) { fitted.aspect = model.aspects[0] }
        if !model.qualities.isEmpty, !model.qualities.contains(where: { $0.id == quality }) {
            // The same picture size under another name (Kling's "pro" is 1080p) before the model's usual one.
            let title = KinoModel.all.lazy.flatMap(\.qualities).first { $0.id == quality }?.title
            fitted.quality = model.qualities.first { $0.title == title }?.id ?? model.defaultQuality
        }
        fitted.takes = min(max(takes, 1), 4)
        return fitted
    }
}

enum KinoKind: String, Codable {
    case image, video, audio
    init?(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "webp", "gif", "heic", "tif", "tiff": self = .image
        case "mp4", "mov", "m4v", "webm": self = .video
        case "wav", "mp3", "m4a", "aac", "aif", "aiff": self = .audio
        default: return nil
        }
    }
}

/// What a file does in its shot. Both services decide from the slot a file is sent in, then from the prompt
/// (docs/kino/README.md §2); unsaid, "the model will infer how to use it".
enum KinoRole: String, Codable, CaseIterable, Identifiable {
    case look, start, end, motion, edit, sound, unused
    var id: String { rawValue }
    var title: String {
        switch self {
        case .look: "Look"
        case .start: "Start frame"
        case .end: "End frame"
        case .motion: "Camera and motion"
        case .edit: "Video to edit"
        case .sound: "Sound"
        case .unused: "Left out"
        }
    }
    var detail: String {
        switch self {
        case .look: "Lends its look (the product, a person, a place, a style), not its exact picture"
        case .start: "The video opens on this exact picture"
        case .end: "The video ends on this exact picture"
        case .motion: "Its camera path and pacing are followed; its people, talking and place are not"
        case .edit: "Changed as the prompt says; everything else is kept"
        case .sound: "A sound or voice the video follows"
        case .unused: "Not sent"
        }
    }
    var icon: String {
        switch self {
        case .look: "eye"
        case .start: "backward.end.fill"
        case .end: "forward.end.fill"
        case .motion: "camera.fill"
        case .edit: "wand.and.stars"
        case .sound: "waveform"
        case .unused: "minus.circle"
        }
    }
    static func choices(_ kind: KinoKind) -> [KinoRole] {
        switch kind {
        case .image: [.look, .start, .end, .unused]
        case .video: [.motion, .edit, .unused]
        case .audio: [.sound, .unused]
        }
    }
    /// A video follows rather than edits unless you say so: an edit changes the clip itself.
    static func usual(_ kind: KinoKind) -> KinoRole {
        switch kind {
        case .image: .look
        case .video: .motion
        case .audio: .sound
        }
    }
    static func of(_ file: KinoFile, _ roles: [String: KinoRole]) -> KinoRole {
        let role = roles[file.handle] ?? usual(file.kind)
        return choices(file.kind).contains(role) ? role : usual(file.kind)
    }
}

struct KinoFile: Identifiable, Equatable {
    let url: URL
    let kind: KinoKind
    /// The shot it belongs to ("K1"), from the start of its name; nil when its name starts with no shot code.
    let shot: String?
    /// Its tag in the prompt, one file each in the batch: "K1.1"; "K9-ref" when another file has the code K9.
    let handle: String
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Shot codes in file names, as the team names them (2026-11-04): K1, K1.1, K1.2… are shot K1's files; words after
/// the code ("K3 improve", "K9 ref") are a label, not another shot. Up to three digits a part, so a date or a camera
/// number ("20260911_…", "IMG_1234") is not read as a shot.
enum KinoCode {
    private static let pattern = try! NSRegularExpression(pattern: #"^\s*([A-Za-z]{0,3})(\d{1,3})((?:\.\d{1,3})*)(?![\d.])[\s_-]*(.*)$"#)

    static func parse(_ name: String) -> (shot: String, code: String, label: String)? {
        guard let match = pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { return nil }
        func part(_ index: Int) -> String { Range(match.range(at: index), in: name).map { String(name[$0]) } ?? "" }
        let shot = part(1).uppercased() + String(Int(part(2)) ?? 0)
        return (shot, shot + part(3), part(4).trimmingCharacters(in: .whitespaces))
    }

    /// K2 before K10, K1 before K1.1 before K1.2.
    static func before(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }

    /// The batch's files with their shots and tags. A code two files share goes to the one without words after it;
    /// the other is told apart by its words ("K9 ref" → K9-ref) or its kind (K1-video), so a tag names one file.
    static func files(_ urls: [URL]) -> [KinoFile] {
        let named = urls.compactMap { url -> (url: URL, kind: KinoKind, code: (shot: String, code: String, label: String)?)? in
            KinoKind(url).map { (url, $0, parse(url.deletingPathExtension().lastPathComponent)) }
        }.sorted { a, b in
            let one = a.code?.code ?? a.url.lastPathComponent, two = b.code?.code ?? b.url.lastPathComponent
            if one != two { return before(one, two) }
            if (a.code?.label.isEmpty ?? true) != (b.code?.label.isEmpty ?? true) { return a.code?.label.isEmpty ?? true }
            // A picture keeps the plain code before a video or a sound of the same code.
            let kinds: [KinoKind] = [.image, .video, .audio]
            if a.kind != b.kind { return kinds.firstIndex(of: a.kind)! < kinds.firstIndex(of: b.kind)! }
            return before(a.url.lastPathComponent, b.url.lastPathComponent)
        }
        var taken = Set<String>(), found: [KinoFile] = []
        for item in named {
            let base = item.code?.code ?? slug(item.url.deletingPathExtension().lastPathComponent)
            var handle = base
            if taken.contains(handle.lowercased()) {
                let words = slug(item.code?.label ?? "")
                handle = base + "-" + (words.isEmpty ? item.kind.rawValue : words)
                let stem = handle
                var number = 2
                while taken.contains(handle.lowercased()) { handle = "\(stem)-\(number)"; number += 1 }
            }
            taken.insert(handle.lowercased())
            found.append(KinoFile(url: item.url, kind: item.kind, shot: item.code?.shot, handle: handle))
        }
        return found.sorted { before($0.handle, $1.handle) }
    }

    static func slug(_ text: String) -> String {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return String(words.joined(separator: "-").prefix(20))
    }
}

/// The @tags in a prompt.
enum KinoPrompt {
    private static let pattern = try! NSRegularExpression(pattern: #"@([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)"#)

    static func tags(in text: String) -> [(range: Range<String.Index>, handle: String)] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text), let name = Range(match.range(at: 1), in: text) else { return nil }
            return (whole, String(text[name]))
        }
    }

    /// The text with each tag `name` knows written its way; the others are kept as typed.
    static func replacing(_ text: String, _ name: (String) -> String?) -> String {
        var result = text
        for tag in tags(in: text).reversed() {
            if let written = name(tag.handle) { result.replaceSubrange(tag.range, with: written) }
        }
        return result
    }
}

/// The models Kino offers, with the limits their documentation gives (docs/kino, as of 2026-11-04).
struct KinoModel: Identifiable, Equatable {
    enum Service: String { case kling = "Kling", higgsfield = "Higgsfield" }
    struct Option: Equatable { let id: String; let title: String }
    let id: String
    let name: String
    let service: Service
    let note: String
    /// nil: the length comes from the video.
    let seconds: ClosedRange<Int>?
    let defaultSeconds: Int
    /// Empty: the picture follows the inputs.
    let aspects: [String]
    let qualities: [Option]
    let defaultQuality: String
    /// Whether sound can be turned on or off; nil when the model decides (Kling 4.0 always makes it).
    let sound: Bool?
    let promptLimit: Int?

    static let all: [KinoModel] = [
        KinoModel(id: "kling-o3", name: "Kling O3 (3.0 Omni)", service: .higgsfield,
                  note: "Up to 7 pictures, or 4 with one video to edit or follow · 3–15 s", seconds: 3...15, defaultSeconds: 5,
                  aspects: ["9:16", "16:9", "1:1"],
                  qualities: [Option(id: "std", title: "720p"), Option(id: "pro", title: "1080p"), Option(id: "4k", title: "4K")],
                  defaultQuality: "pro", sound: true, promptLimit: 2500),
        KinoModel(id: "seedance-2.5", name: "Seedance 2.5", service: .higgsfield,
                  note: "Up to 30 pictures, 10 videos and 10 sounds · 4–30 s", seconds: 4...30, defaultSeconds: 5,
                  aspects: ["9:16", "16:9", "1:1", "3:4", "4:3", "21:9"],
                  qualities: [Option(id: "480p", title: "480p"), Option(id: "720p", title: "720p"), Option(id: "1080p", title: "1080p")],
                  defaultQuality: "1080p", sound: true, promptLimit: nil),
        KinoModel(id: "kling-motion", name: "Kling 3.0 Motion Control", service: .higgsfield,
                  note: "One picture of the person and one video of the performance (3–30 s), copied move for move",
                  seconds: nil, defaultSeconds: 0, aspects: [], qualities: [], defaultQuality: "", sound: nil, promptLimit: 2500),
        KinoModel(id: "kling-4.0", name: "Kling 4.0 Omni", service: .kling,
                  note: "Up to 10 pictures and 5 videos (30 s in all) · 3–30 s · always makes sound", seconds: 3...30, defaultSeconds: 10,
                  aspects: ["9:16", "16:9", "1:1", "21:9", "adaptive"],
                  qualities: [Option(id: "720p", title: "720p"), Option(id: "1080p", title: "1080p")],
                  defaultQuality: "1080p", sound: nil, promptLimit: 26_000),
    ]
    static let standard = all[0]
    static func named(_ id: String) -> KinoModel { all.first { $0.id == id } ?? standard }
}

/// What Kino would send for a shot: the endpoint its roles lead to, each file's slot, the prompt as the service reads it
/// (with a line saying each file's role, the words for every shot, and the tags written the service's way), and what
/// stops it or what Kino changes, said before anything is spent.
struct KinoPlan: Equatable {
    struct Input: Equatable {
        let handle: String
        let slot: String
        /// How the prompt names it to the service.
        let tag: String
    }
    var endpoint = ""
    var inputs: [Input] = []
    var problems: [String] = []
    var notes: [String] = []
    var prompt = ""
    /// nil: the length follows the video.
    var seconds: Int?
}

enum KinoRequest {
    static func plan(files: [KinoFile], roles: [String: KinoRole], prompt: String, shared: String, settings: KinoSettings,
                     durations: [String: Double]) -> KinoPlan {
        let model = KinoModel.named(settings.model)
        let settings = settings.fitted(to: model)
        var plan = KinoPlan()
        let used = files.filter { KinoRole.of($0, roles) != .unused }
        func with(_ role: KinoRole) -> [KinoFile] { used.filter { KinoRole.of($0, roles) == role } }
        let looks = with(.look), starts = with(.start), ends = with(.end), motions = with(.motion), edits = with(.edit), sounds = with(.sound)
        func names(_ list: [KinoFile]) -> String { list.map(\.handle).joined(separator: ", ") }
        func length(_ file: KinoFile) -> Double? { durations[file.id] }
        func seconds(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
        func checkLength(_ list: [KinoFile], _ range: ClosedRange<Double>, _ said: String) {
            for file in list {
                if let time = length(file), !range.contains(time) { plan.problems.append(L("%@ is %@ s; %@", file.handle, seconds(time), L(said))) }
            }
        }
        if starts.count > 1 { plan.problems.append(L("One start frame a shot: %@", names(starts))) }
        if ends.count > 1 { plan.problems.append(L("One end frame a shot: %@", names(ends))) }
        if edits.count > 1 { plan.problems.append(L("One video to edit at a time: %@", names(edits))) }

        /// The slot and the prompt's name for each file sent, in order.
        var sent: [(file: KinoFile, role: KinoRole, slot: String, tag: String)] = []
        func send(_ list: [KinoFile], as role: KinoRole, slot: String, tag: (Int) -> String) {
            for (index, file) in list.enumerated() { sent.append((file, role, slot, tag(index))) }
        }
        /// Higgsfield's models are told by order, in words ("image 2"); Kling's new API by the id given to each file.
        var images = 0, videos = 0, audios = 0
        func image(_ list: [KinoFile], as role: KinoRole) {
            send(list, as: role, slot: "image_urls") { _ in images += 1; return "image \(images)" }
        }
        func video(_ list: [KinoFile], as role: KinoRole) {
            send(list, as: role, slot: "video_urls") { _ in videos += 1; return "video \(videos)" }
        }
        func audio(_ list: [KinoFile]) { send(list, as: .sound, slot: "audio_urls") { _ in audios += 1; return "audio \(audios)" } }
        func asLooks(_ frames: [KinoFile], _ why: String) {
            if !frames.isEmpty { plan.notes.append(L("%@ goes as a look: %@", names(frames), L(why))) }
        }
        var needsPrompt = true
        var exclusions = ""

        switch model.id {
        case "kling-4.0":
            plan.endpoint = "Kling · /omni-video/kling-4.0"
            let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            send(starts, as: .start, slot: "first_frame") { _ in "@start" }
            send(ends, as: .end, slot: "last_frame") { _ in "@end" }
            send(looks, as: .look, slot: "refer_image") { "@ref" + String(letters[min($0, 25)]) }
            send(motions, as: .motion, slot: "feature_video") { "@motion" + String(letters[min($0, 25)]) }
            send(edits, as: .edit, slot: "base_video") { _ in "@edit" }
            if looks.count > 10 { plan.problems.append(L("Kling 4.0 takes up to 10 pictures; this shot has %@", looks.count)) }
            let clips = motions + edits
            if clips.count > 5 { plan.problems.append(L("Kling 4.0 takes up to 5 videos; this shot has %@", clips.count)) }
            checkLength(clips, 3...30, "Kling 4.0 takes videos of 3 to 30 s")
            let total = clips.compactMap(length).reduce(0, +)
            if total > 30 { plan.problems.append(L("The videos are %@ s in all; Kling 4.0 takes 30 s", seconds(total))) }
            if !sounds.isEmpty { plan.notes.append(L("Kling takes voices from its own library, not sound files: %@ left out", names(sounds))) }
            if !files.isEmpty { plan.notes.append(L("Kling takes files only as links: how Kino puts them online is still to be decided")) }
            plan.seconds = edits.isEmpty ? settings.seconds ?? model.defaultSeconds : nil
            exclusions = "No subtitles, no background music."
        case "kling-o3":
            if !sounds.isEmpty { plan.notes.append(L("Kling O3 takes no sound files: %@ left out", names(sounds))) }
            if !edits.isEmpty, !motions.isEmpty { plan.problems.append(L("Kling O3 takes one video, to edit or to follow, not both")) }
            if motions.count > 1 { plan.problems.append(L("Kling O3 follows one video at a time: %@", names(motions))) }
            if let clip = edits.first ?? motions.first {
                let editing = !edits.isEmpty
                plan.endpoint = "Higgsfield · kling-video/o3/" + (editing ? "video-edit" : "video-reference")
                let frames = starts + ends
                asLooks(frames, "Kling O3 takes no start or end frame with a video")
                image(looks + frames, as: .look)
                video([clip], as: editing ? .edit : .motion)
                if looks.count + frames.count > 4 {
                    plan.problems.append(L("With a video, Kling O3 takes up to 4 pictures; this shot has %@", looks.count + frames.count))
                }
                if editing {
                    checkLength([clip], 3...15.5, "Kling O3 edits videos of 3 to 15.5 s")
                    if settings.sound { plan.notes.append(L("Kling makes no sound while editing a video: sound is off")) }
                } else {
                    let wanted = settings.seconds ?? model.defaultSeconds
                    plan.seconds = min(wanted, 10)
                    if wanted > 10 { plan.notes.append(L("Kling O3 makes up to 10 s when it follows a video: %@ s", 10)) }
                    if settings.sound { plan.notes.append(L("Kling makes no sound when it follows a video: sound is off")) }
                }
            } else {
                plan.endpoint = "Higgsfield · kling-video/o3/" + (looks.isEmpty && !starts.isEmpty ? "first-last-frame" : "image-reference")
                send(starts.prefix(1).map { $0 }, as: .start, slot: "first_frame_url") { _ in "the start frame" }
                send(ends.prefix(1).map { $0 }, as: .end, slot: "last_frame_url") { _ in "the end frame" }
                image(looks, as: .look)
                if looks.count + starts.count + ends.count > 7 {
                    plan.problems.append(L("Kling O3 takes up to 7 pictures; this shot has %@", looks.count + starts.count + ends.count))
                }
                if !ends.isEmpty, starts.isEmpty { plan.problems.append(L("Kling needs a start frame to go with an end frame")) }
                plan.seconds = settings.seconds ?? model.defaultSeconds
            }
            exclusions = "No subtitles, no background music."
        case "seedance-2.5":
            if let source = edits.first {
                plan.endpoint = "Higgsfield · bytedance/seedance-2.5/video-edit"
                let frames = starts + ends
                asLooks(frames, "Seedance takes no start or end frame when it edits")
                send([source], as: .edit, slot: "video_url") { _ in "the source video" }
                image(looks + frames, as: .look)
                video(motions, as: .motion)
                audio(sounds)
                if motions.count > 9 { plan.problems.append(L("Besides the video to edit, Seedance takes up to 9 videos; this shot has %@", motions.count)) }
                let total = ([source] + motions).compactMap(length).reduce(0, +)
                if total > 30 { plan.notes.append(L("The videos are %@ s in all: Higgsfield trims them to 30 s", seconds(total))) }
            } else if !starts.isEmpty, looks.isEmpty, motions.isEmpty, sounds.isEmpty {
                plan.endpoint = "Higgsfield · bytedance/seedance-2.5/image-to-video"
                send(starts.prefix(1).map { $0 }, as: .start, slot: "image_url") { _ in "the start frame" }
                send(ends.prefix(1).map { $0 }, as: .end, slot: "end_image_url") { _ in "the end frame" }
                plan.notes.append(L("The picture's shape follows %@", starts[0].handle))
                plan.seconds = settings.seconds ?? model.defaultSeconds
                needsPrompt = false
            } else if !used.isEmpty {
                plan.endpoint = "Higgsfield · bytedance/seedance-2.5/reference-to-video"
                let frames = starts + ends
                asLooks(frames, "Seedance's reference mode has no start or end frame")
                image(looks + frames, as: .look)
                video(motions, as: .motion)
                audio(sounds)
                let total = motions.compactMap(length).reduce(0, +)
                if total > 30 { plan.notes.append(L("The videos are %@ s in all: Higgsfield trims them to 30 s", seconds(total))) }
                plan.seconds = settings.seconds ?? model.defaultSeconds
            } else {
                plan.endpoint = "Higgsfield · bytedance/seedance-2.5/text-to-video"
                plan.seconds = settings.seconds ?? model.defaultSeconds
            }
            if images > 30 { plan.problems.append(L("Seedance takes up to 30 pictures; this shot has %@", images)) }
            if videos > 10 { plan.problems.append(L("Seedance takes up to 10 videos; this shot has %@", videos)) }
            if audios > 10 { plan.problems.append(L("Seedance takes up to 10 sounds; this shot has %@", audios)) }
            if sent.count > 50 { plan.problems.append(L("Seedance takes up to 50 files in all; this shot has %@", sent.count)) }
        default: // Motion Control
            plan.endpoint = "Higgsfield · kling-video/v3/motion-control"
            let pictures = looks + starts + ends
            send(pictures.prefix(1).map { $0 }, as: .look, slot: "image_url") { _ in "the person" }
            send(motions.prefix(1).map { $0 }, as: .motion, slot: "video_url") { _ in "the performance" }
            if !edits.isEmpty { plan.problems.append(L("Motion Control copies a performance and edits nothing: make %@ Camera and motion", names(edits))) }
            if pictures.count != 1 { plan.problems.append(L("Motion Control takes one picture of the person; this shot has %@", pictures.count)) }
            if motions.count != 1 { plan.problems.append(L("Motion Control takes one video of the performance; this shot has %@", motions.count)) }
            checkLength(motions, 3...30, "Motion Control takes performances of 3 to 30 s")
            if !sounds.isEmpty { plan.notes.append(L("Motion Control takes no sound files: %@ left out", names(sounds))) }
            if !motions.isEmpty { plan.notes.append(L("The performance's own sound is not kept")) }
            needsPrompt = false
        }
        if plan.seconds == nil, let clip = edits.first ?? (model.seconds == nil ? motions.first : nil) {
            plan.notes.append(length(clip).map { L("The length follows %@: %@ s", clip.handle, seconds($0)) } ?? L("The length follows %@", clip.handle))
        }
        plan.inputs = sent.map { KinoPlan.Input(handle: $0.file.handle, slot: $0.slot, tag: $0.tag) }

        // The prompt as the service reads it: each file's role first, then the words for every shot, then yours.
        var tags: [String: String] = [:]
        for item in sent { tags[item.file.handle.lowercased()] = item.tag }
        let known = Set(files.map { $0.handle.lowercased() })
        for tag in KinoPrompt.tags(in: shared + "\n" + prompt) where tags[tag.handle.lowercased()] == nil {
            let problem = known.contains(tag.handle.lowercased()) ? L("@%@ is named in the prompt but not sent", tag.handle)
                                                                    : L("@%@ is not a file in this shot", tag.handle)
            if !plan.problems.contains(problem) { plan.problems.append(problem) }
        }
        let lines = sent.map { line($0.role, $0.tag, motionControl: model.id == "kling-motion") }
        let written = [shared, prompt].map { KinoPrompt.replacing($0, { tags[$0.lowercased()] }).trimmingCharacters(in: .whitespacesAndNewlines) }
        if needsPrompt, written.allSatisfy(\.isEmpty) { plan.problems.append(L("Write what happens in the shot")) }
        plan.prompt = ([lines.joined(separator: "\n")] + written + [exclusions]).filter { !$0.isEmpty }.joined(separator: "\n\n")
        if let limit = model.promptLimit, plan.prompt.count > limit {
            plan.problems.append(L("The prompt is %@ characters; %@ reads %@", plan.prompt.count.formatted(), model.name, limit.formatted()))
        }
        return plan
    }

    /// The line that tells the model what a file is for. A reference video lends its camera and pacing only, so the
    /// talking in most reference clips is not copied (forge.md, job 4).
    static func line(_ role: KinoRole, _ tag: String, motionControl: Bool = false) -> String {
        let text: String
        switch role {
        case .look: text = motionControl ? "\(tag) is the person who performs." : "\(tag) is a look reference: keep the appearance of what it shows."
        case .start: text = "\(tag) is the first frame: the video opens on it."
        case .end: text = "\(tag) is the last frame: the video ends on it."
        case .motion: text = motionControl ? "\(tag) is the performance to copy." : "Follow only the camera path and pacing of \(tag); do not carry over its people, speech or setting."
        case .edit: text = "Edit \(tag): change only what is asked below and keep everything else unchanged."
        case .sound: text = "\(tag) is the sound the video follows."
        case .unused: text = ""
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// The Kling and Higgsfield keys, in the login Keychain; nil removes one.
enum KinoKeys {
    static var kling: String? {
        get { read("Edit Assist Kling") }
        set { write(newValue, "Edit Assist Kling") }
    }
    /// "id:secret", as Higgsfield's Authorization header takes it.
    static var higgsfield: String? {
        get { read("Edit Assist Higgsfield") }
        set { write(newValue, "Edit Assist Higgsfield") }
    }
    private static func read(_ service: String) -> String? {
        var result: AnyObject?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "api-key", kSecReturnData as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func write(_ value: String?, _ service: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "api-key"]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
