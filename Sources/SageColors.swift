import AppKit
import SwiftUI

/// Colour and keeping your place in Sage's tree (2026-11-08 in Creative Assist; the user asked for "more colors" and for
/// what you're looking in to stay in sight; brought to the Mac 2026-11-09). Each folder has a colour (yours, else Notebook
/// Navigator's, else one its name always gets, the same as in a base's groups), its icon and its line drawn in it; a
/// file's icon says what it is (an emoji it starts with, a clipping of a video or a page, a quote, a course, a canvas, a
/// base, a PDF, a picture) and is otherwise its folder's colour.
enum SageColors {
    /// A colour as its red, green and blue (0–255).
    struct RGB: Equatable { var r: Double, g: Double, b: Double, a: Double = 255
        var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a / 255) }
        func opacity(_ alpha: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255, opacity: alpha) }
    }

    /// Eight soft colours for the tree, in Study.hue's order (red … pink), muted to sit on the app's warm dark panel
    /// beside its accent: the user found Obsidian's full-strength ones on every folder and note too loud (2026-11-08).
    static let hues: [RGB] = [
        RGB(r: 0xD6, g: 0x8C, b: 0x86), RGB(r: 0xD4, g: 0xA2, b: 0x6A), RGB(r: 0xC9, g: 0xB9, b: 0x78), RGB(r: 0x92, g: 0xB8, b: 0x8A),
        RGB(r: 0x7D, g: 0xB5, b: 0xAE), RGB(r: 0x86, g: 0xA6, b: 0xD0), RGB(r: 0xA9, g: 0x9C, b: 0xD4), RGB(r: 0xC5, g: 0x95, b: 0xB6),
    ]
    static let hueNames = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"]

    /// A colour light enough to read on the dark panel (Notebook Navigator's can be very dark).
    static func readable(_ c: RGB) -> RGB {
        var c = c
        func lum(_ x: RGB) -> Double { (0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b) / 255 }
        var i = 0
        while i < 8 && lum(c) < 0.42 {
            c = RGB(r: (c.r + (255 - c.r) * 0.2).rounded(.down), g: (c.g + (255 - c.g) * 0.2).rounded(.down), b: (c.b + (255 - c.b) * 0.2).rounded(.down), a: c.a)
            i += 1
        }
        return c
    }

    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: (a.r + (b.r - a.r) * t).rounded(.down), g: (a.g + (b.g - a.g) * t).rounded(.down), b: (a.b + (b.b - a.b) * t).rounded(.down))
    }

    /// #rrggbb or #rrggbbaa (as CSS writes it); a faint tint either way.
    static func parse(_ hex: String) -> RGB? {
        var hex = hex.trimmingCharacters(in: .whitespaces)
        while hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let v = UInt32(hex, radix: 16) else { return nil }
        if hex.count == 6 { return RGB(r: Double(v >> 16 & 255), g: Double(v >> 8 & 255), b: Double(v & 255), a: 40) }
        return RGB(r: Double(v >> 24 & 255), g: Double(v >> 16 & 255), b: Double(v >> 8 & 255), a: Double(max(24, min(90, Int(v & 255)))))
    }

    /// Animations as the Mac sets them (System Settings → Accessibility → Display → Reduce motion).
    static var motion: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// What the tree knows about a vault's look beyond its files: Notebook Navigator's folder icons (emoji) and background
/// colours (its data.json, when you use it), each note's kind (from its properties, for its icon), and the folders'
/// colours worked out once per reading of the vault.
@MainActor final class SageTreeLook: ObservableObject {
    private(set) var folderIcons: [String: String] = [:]
    /// Notebook Navigator's faint row tints, and its colours made opaque (its background colours are faint: their colour is what's kept).
    private(set) var tints: [String: SageColors.RGB] = [:]
    private var nnHues: [String: SageColors.RGB] = [:]
    @Published private(set) var kinds: [String: (kind: String?, icon: String?, color: String?)] = [:]
    /// The notes' aliases, for the quick switcher.
    @Published private(set) var aliases: [String: [String]] = [:]
    private var hues: [String: SageColors.RGB?] = [:]
    private var readFor = -1
    /// The tree's rows as last worked out (SageExplorer.cachedRows).
    var rowCache: (key: String, rows: [SageExplorer.Row])?
    private var yours: [String: String] = [:]

    /// Read again when the vault was (its version changed); the notes' kinds off the main thread.
    func read(_ vault: SageVaultDesk) {
        let colors = vault.settings.folderColors
        if colors != yours { yours = colors; hues = [:] }
        guard readFor != vault.version, let root = vault.vault else { return }
        readFor = vault.version
        hues = [:]; folderIcons = [:]; tints = [:]; nnHues = [:]
        if let data = try? Data(contentsOf: root.appendingPathComponent(".obsidian/plugins/notebook-navigator/data.json")), let json = Study.json(data) {
            for (folder, icon) in json["folderIcons"] as? [String: Any] ?? [:] {
                if let text = icon as? String, text.hasPrefix("emoji:") { folderIcons[folder.lowercased()] = String(text.dropFirst(6)) }
            }
            for key in ["folderBackgroundColors", "folderColors"] {
                for (folder, value) in json[key] as? [String: Any] ?? [:] where tints[folder.lowercased()] == nil {
                    guard let hex = value as? String, let color = SageColors.parse(hex) else { continue }
                    tints[folder.lowercased()] = color
                    nnHues[folder.lowercased()] = SageColors.mix(SageColors.readable(SageColors.RGB(r: color.r, g: color.g, b: color.b)), SageColors.RGB(r: 0x9A, g: 0x98, b: 0x90), 0.3)
                }
            }
        }
        let items = vault.items, version = vault.version
        Task {
            let (kinds, aliases) = await Task.detached { () -> ([String: (kind: String?, icon: String?, color: String?)], [String: [String]]) in
                let finder = Study.LinkFinder(items)
                var kinds: [String: (kind: String?, icon: String?, color: String?)] = [:], aliases: [String: [String]] = [:]
                for note in Study.baseNotes(vault: root, items: items, finder: finder) where note.item.ext == ".md" {
                    let kind = Study.noteKind(note)
                    if (kind.kind ?? kind.icon ?? kind.color) != nil { kinds[note.item.path.lowercased()] = kind }
                    if let value = note.prop("aliases") {
                        let names = ((value as? [Any?]) ?? [value]).compactMap { $0.map { "\($0)" } }.filter { !$0.isEmpty }
                        if !names.isEmpty { aliases[note.item.path.lowercased()] = names }
                    }
                }
                return (kinds, aliases)
            }.value
            guard self.readFor == version else { return }
            self.kinds = kinds; self.aliases = aliases
        }
    }

    func folderIcon(_ path: String) -> String? { folderIcons[path.lowercased()] }
    func tint(_ path: String) -> Color? { tints[path.lowercased()]?.color }

    private func explicitHue(_ path: String, _ vault: SageVaultDesk) -> (set: Bool, color: SageColors.RGB?) {
        if let name = vault.folderColor(path) { return (true, SageColors.hueNames.firstIndex(of: name).map { SageColors.hues[$0] }) }
        if let nn = nnHues[path.lowercased()] { return (true, nn) }
        return (false, nil)
    }

    /// A folder's colour: the one you gave it, else Notebook Navigator's, else the one given to a folder it's in (passed
    /// down, as Notebook Navigator does), else its top folder's: each part of the vault is one calm colour, not a new one
    /// at every level. Nil when you chose none.
    func folderHue(_ path: String, _ vault: SageVaultDesk) -> SageColors.RGB? {
        if path.isEmpty { return nil }
        if let known = hues[path.lowercased()] { return known }
        var hue: SageColors.RGB?
        let own = explicitHue(path, vault)
        if own.set { hue = own.color } else {
            var inherited = false
            var p = Study.VaultItem(path: path, folder: true).parent
            while !p.isEmpty {
                let up = explicitHue(p, vault)
                if up.set { hue = up.color; inherited = true; break }
                p = Study.VaultItem(path: p, folder: true).parent
            }
            if !inherited { hue = SageColors.hues[Study.hue(path.components(separatedBy: "/")[0])] }
        }
        hues[path.lowercased()] = hue
        return hue
    }

    func hueColor(_ path: String, _ vault: SageVaultDesk, _ alpha: Double = 1) -> Color {
        folderHue(path, vault).map { $0.opacity(alpha) } ?? Color.secondary
    }

    /// A file's icon: its leading emoji, its own icon (an emoji in its "icon" property), what it is, or its folder's colour.
    enum Icon { case emoji(String), symbol(String, Color) }

    func fileIcon(_ item: Study.VaultItem, _ vault: SageVaultDesk) -> Icon {
        let kind = kinds[item.path.lowercased()]
        if let lead = Study.leadingEmoji(item.title) { return .emoji(lead.emoji) }
        if let own = kind?.icon, Study.leadingEmoji(own + " x") != nil { return .emoji(own) }
        let folderHue = self.folderHue(item.parent, vault)
        var hue: SageColors.RGB?
        if let color = kind?.color {
            if let named = SageColors.hueNames.firstIndex(of: color.lowercased()) { hue = SageColors.hues[named] }
            else if let parsed = SageColors.parse(color) { hue = SageColors.readable(SageColors.RGB(r: parsed.r, g: parsed.g, b: parsed.b)) }
        }
        let h = SageColors.hues
        func tone(_ c: SageColors.RGB?) -> Color { c?.color ?? Color.secondary }
        switch item.ext {
        case ".md":
            switch kind?.kind {
            case "video": return .symbol("play.rectangle", tone(hue ?? h[0]))
            case "web": return .symbol("globe", tone(hue ?? h[4]))
            case "quote": return .symbol("quote.opening", tone(hue ?? h[2]))
            case "course": return .symbol("graduationcap", tone(hue ?? h[6]))
            default: break
            }
            // A folder's own note (named as its folder): its hub.
            if !item.parent.isEmpty, Study.same(item.title, (item.parent as NSString).lastPathComponent) { return .symbol("square.grid.2x2", tone(hue ?? folderHue)) }
            return .symbol("doc.text", tone(hue))
        case ".canvas": return .symbol("rectangle.3.group", tone(h[6]))
        case ".base": return .symbol("tablecells", tone(h[5]))
        case ".pdf": return .symbol("doc.richtext", tone(h[0]))
        case _ where Study.pictureTypes.contains(item.ext): return .symbol("photo", tone(h[3]))
        case ".mp3", ".wav", ".m4a", ".ogg", ".flac": return .symbol("waveform", tone(h[1]))
        case ".mp4", ".mov", ".webm", ".mkv", ".ogv": return .symbol("film", tone(h[7]))
        default: return .symbol("doc", Color.secondary)
        }
    }

    /// A name shown without the emoji its icon already shows.
    static func shown(_ title: String) -> String { Study.leadingEmoji(title)?.name ?? title }
}

/// A file's or folder's icon as the tree draws it.
struct SageIconView: View {
    let icon: SageTreeLook.Icon
    var size: CGFloat = 11.5
    var body: some View {
        switch icon {
        case .emoji(let emoji): Text(emoji).font(.system(size: size - 0.5)).frame(width: 15)
        case .symbol(let name, let color): Image(systemName: name).font(.system(size: size)).foregroundStyle(color).frame(width: 15)
        }
    }
}
