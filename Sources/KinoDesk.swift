import AppKit
import AVFoundation
import Foundation
import Security

/// Kino's desk (2026-11-04). A batch is a folder of your media named by shot code: K1, K1.1 and K1.2 all go into shot
/// K1's one prompt, each under its own tag (@K1.1). Every file has a role in its shot (look, start frame, camera and
/// motion, video to edit…), and the roles, not a mode tab, decide which of the model's endpoints the shot goes to, so an
/// edit is never sent as a reference by chance (docs/kino/forge.md). Kept beside projects.json, one file per project
/// (`kino/<project>.json`), never in it; the Kling and Higgsfield keys live in the Keychain. Nothing is sent yet.
@MainActor
final class KinoDesk: ObservableObject {
    @Published private(set) var batch = KinoBatch()
    @Published private(set) var files: [KinoFile] = []
    /// Video and sound lengths in seconds, by path, read after the folder.
    @Published private(set) var durations: [String: Double] = [:]
    /// Takes already made, in the batch folder's Kino folder.
    @Published private(set) var outputs: [URL] = []
    @Published var selected: String?
    @Published private(set) var hasKling = KinoKeys.kling != nil
    @Published private(set) var hasHiggsfield = KinoKeys.higgsfield != nil
    private var project: UUID?

    var folder: URL? { batch.folder.map { URL(fileURLWithPath: $0, isDirectory: true) } }
    var outputFolder: URL? { folder?.appendingPathComponent("Kino", isDirectory: true) }
    var shots: [String] {
        var seen = Set<String>()
        return files.compactMap(\.shot).filter { seen.insert($0).inserted }.sorted(by: KinoCode.before)
    }
    /// Files whose names start with no shot code.
    var loose: [KinoFile] { files.filter { $0.shot == nil } }
    func files(in shot: String) -> [KinoFile] { files.filter { $0.shot == shot } }
    func shot(_ code: String) -> KinoShot { batch.shots[code] ?? KinoShot() }
    /// The shot's own settings, or the batch's when it has none.
    func settings(_ code: String) -> KinoSettings { shot(code).settings ?? batch.settings }
    func role(of file: KinoFile, in code: String) -> KinoRole { KinoRole.of(file, shot(code).roles) }
    func plan(_ code: String) -> KinoPlan {
        KinoRequest.plan(files: files(in: code), roles: shot(code).roles, prompt: shot(code).prompt, shared: batch.shared,
                         settings: settings(code), durations: durations)
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

    /// The project's batch, when the page opens or the project changes; the folder is read every time.
    func open(project id: UUID) {
        if id != project {
            project = id
            batch = (try? JSONDecoder().decode(KinoBatch.self, from: Data(contentsOf: Self.file(id)))) ?? KinoBatch()
            files = []; outputs = []; selected = nil
        }
        refresh()
    }

    @discardableResult
    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = folder; panel.prompt = L("Use this batch")
        panel.message = L("The folder with this batch's pictures and videos, named by shot: K1, K1.1, K2…")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        batch.folder = url.path
        selected = nil
        save()
        refresh()
        return true
    }

    /// Reads the folder off the main thread (macOS may ask before an app reads a folder like Downloads), then the
    /// lengths of the videos and sounds it has not read yet.
    func refresh() {
        guard let folder else { files = []; outputs = []; return }
        Task {
            let found = await Task.detached(priority: .utility) { KinoDesk.scan(folder) }.value
            guard self.folder == folder else { return }
            files = KinoCode.files(found.inputs)
            outputs = found.outputs
            if selected.map(shots.contains) != true { selected = shots.first }
            for file in files where file.kind != .image && durations[file.id] == nil {
                if let time = try? await AVURLAsset(url: file.url).load(.duration), time.isNumeric { durations[file.id] = time.seconds }
            }
        }
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

    /// The batch's media (three folders deep at most, without hidden files and packages), and the takes in its Kino folder.
    nonisolated static func scan(_ folder: URL) -> (inputs: [URL], outputs: [URL]) {
        let manager = FileManager.default
        let output = folder.appendingPathComponent("Kino", isDirectory: true).standardizedFileURL.path
        var inputs: [URL] = []
        if let walk = manager.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in walk {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if url.standardizedFileURL.path == output || walk.level >= 3 { walk.skipDescendants() }
                } else if KinoKind(url) != nil {
                    inputs.append(url)
                }
            }
        }
        let outputs = ((try? manager.contentsOfDirectory(at: URL(fileURLWithPath: output, isDirectory: true), includingPropertiesForKeys: nil,
                                                          options: .skipsHiddenFiles)) ?? [])
            .filter { KinoKind($0) == .video }.sorted { KinoCode.before($0.lastPathComponent, $1.lastPathComponent) }
        return (inputs, outputs)
    }
}

/// One project's batch: its folder, the words said in every shot (the product's facts, the look), the settings every
/// shot starts from, and what you changed per shot.
struct KinoBatch: Codable, Equatable {
    var folder: String?
    var shared = ""
    var settings = KinoSettings()
    var shots: [String: KinoShot] = [:]
}

struct KinoShot: Codable, Equatable {
    var prompt = ""
    /// Roles you changed, by tag; the others have the usual role for their kind.
    var roles: [String: KinoRole] = [:]
    /// nil: the batch's settings.
    var settings: KinoSettings?
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
