import AppKit
import SwiftUI

/// A small pixel-art picture: rows of characters, each a colour or "." for empty (the helpers' icons, like the running crab).
struct PixelSprite: View {
    let rows: [String]
    let colors: [Character: Color]
    var pixel: CGFloat = 2

    var body: some View {
        let width = CGFloat(rows.map(\.count).max() ?? 0), height = CGFloat(rows.count)
        Canvas { canvas, size in
            let left = ((size.width - width * pixel) / 2).rounded(), top = ((size.height - height * pixel) / 2).rounded()
            for (y, row) in rows.enumerated() {
                for (x, mark) in row.enumerated() {
                    guard let color = colors[mark] else { continue }
                    canvas.fill(Path(CGRect(x: left + CGFloat(x) * pixel, y: top + CGFloat(y) * pixel, width: pixel, height: pixel)), with: .color(color))
                }
            }
        }
        .frame(width: width * pixel, height: height * pixel)
    }
}

/// A helper's icon that moves while the helper works: its working frames in turn, a blink now and then while it rests, and
/// still with Reduce Motion on. Every frame is the same size, so nothing around it shifts.
struct AnimatedSprite: View {
    let rest: [String]
    var blink: [String]? = nil
    let working: [[String]]
    let colors: [Character: Color]
    var pixel: CGFloat = 2
    /// Working until this time.
    var busyUntil: Date?
    /// Plays the working frames while the pointer is over it (the page's big icon), to see them.
    var previewOnHover = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.16)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.16)
            let busy = hovering || busyUntil.map { context.date < $0 } == true
            PixelSprite(rows: reduceMotion ? rest : busy ? working[tick % working.count] : blink != nil && tick % 25 == 0 ? blink! : rest,
                        colors: colors, pixel: pixel)
        }
        .onHover { if previewOnHover { hovering = $0 } }
    }
}

/// Amir, the file helper: a folder with a handlebar mustache. Working (a file just arrived): the mustache flicks up and
/// down, the eyes look left and right, the lid lifts.
struct PixelAmir: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 240 / 255, green: 190 / 255, blue: 82 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["..TTTTT.........", ".TTTTTTT........", ".FFFFFFFFFFFFFF.", ".FFFFFFFFFFFFFF.",
                       ".FFFFKFFFFKFFFF.", ".FFFFKFFFFKFFFF.", ".FFFFFFFFFFFFFF.", ".FMFFFFFFFFFFMF.",
                       ".FMMMMMFFMMMMMF.", ".FFFMMMMMMMMFFF.", ".FFFFFFFFFFFFFF.", ".DDDDDDDDDDDDDD."]
    static let blink = ["..TTTTT.........", ".TTTTTTT........", ".FFFFFFFFFFFFFF.", ".FFFFFFFFFFFFFF.",
                        ".FFFFFFFFFFFFFF.", ".FFFFKFFFFKFFFF.", ".FFFFFFFFFFFFFF.", ".FMFFFFFFFFFFMF.",
                        ".FMMMMMFFMMMMMF.", ".FFFMMMMMMMMFFF.", ".FFFFFFFFFFFFFF.", ".DDDDDDDDDDDDDD."]
    static let working: [[String]] = [
        ["..TTTTT.........", ".TTTTTTT........", ".FFFFFFFFFFFFFF.", ".FFFFFFFFFFFFFF.",
         ".FFFKFFFFKFFFFF.", ".FFFKFFFFKFFFFF.", ".FFFFFFFFFFFFFF.", ".FMFFFFFFFFFFMF.",
         ".FMMMMMFFMMMMMF.", ".FFFMMMMMMMMFFF.", ".FFFFFFFFFFFFFF.", ".DDDDDDDDDDDDDD."],
        ["...TTTTT........", ".TTTTTTTT.......", ".FFFFFFFFFFFFFF.", ".FFFFFFFFFFFFFF.",
         ".FFFFKFFFFKFFFF.", ".FFFFKFFFFKFFFF.", ".FFFFFFFFFFFFFF.", ".FFFFFFFFFFFFFF.",
         ".FMMMMMFFMMMMMF.", ".MFFMMMMMMMMFFM.", ".FFFFFFFFFFFFFF.", ".DDDDDDDDDDDDDD."],
        ["..TTTTT.........", ".TTTTTTT........", ".FFFFFFFFFFFFFF.", ".FFFFFFFFFFFFFF.",
         ".FFFFFKFFFFKFFF.", ".FFFFFKFFFFKFFF.", ".FFFFFFFFFFFFFF.", ".FMFFFFFFFFFFMF.",
         ".FMMMMMFFMMMMMF.", ".FFFMMMMMMMMFFF.", ".FFFFFFFFFFFFFF.", ".DDDDDDDDDDDDDD."],
        ["...TTTTT........", ".TTTTTTTT.......", ".FFFFFFFFFFFFFF.", ".FFFFFFFFFFFFFF.",
         ".FFFFKFFFFKFFFF.", ".FFFFKFFFFKFFFF.", ".FFFFFFFFFFFFFF.", ".FFFFFFFFFFFFFF.",
         ".FMMMMMFFMMMMMF.", ".MFFMMMMMMMMFFM.", ".FFFFFFFFFFFFFF.", ".DDDDDDDDDDDDDD."],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["T": Color(red: 214 / 255, green: 150 / 255, blue: 60 / 255), "F": Color(red: 240 / 255, green: 190 / 255, blue: 82 / 255),
                                "D": Color(red: 200 / 255, green: 140 / 255, blue: 55 / 255), "K": Color(red: 20 / 255, green: 14 / 255, blue: 10 / 255),
                                "M": Color(red: 36 / 255, green: 22 / 255, blue: 14 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Amir")
    }
}

/// Amir's icon in the sidebar, moving when a file arrives.
struct AmirIcon: View {
    @ObservedObject var watcher: AmirWatcher
    var pixel: CGFloat = 1.25
    var body: some View { PixelAmir(pixel: pixel, busyUntil: watcher.lastArrival.map { $0.addingTimeInterval(4) }) }
}

/// Amir's page: the folder watched and the files found in it.
struct AmirPage: View {
    @ObservedObject var watcher: AmirWatcher
    private let accent = PixelAmir.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelAmir(pixel: 4, busyUntil: watcher.lastArrival.map { $0.addingTimeInterval(4) }, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your file helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Watches a folder while you work", "Suggests a **name** and the **right folder** for each new file",
                             "**Unzips** downloads and sorts what is inside", "**Always asks** before moving anything"], size: 11)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(md: L("WATCHING")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: watcher.folder.path)).resizable().frame(width: 22, height: 22)
                    Text((watcher.folder.path as NSString).abbreviatingWithTildeInPath).font(.system(size: 12, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button { NSWorkspace.shared.open(watcher.folder) } label: { Image(systemName: "folder") }.help(L("Show in Finder"))
                    Button(L("Change…")) { watcher.choose() }
                }
                .padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(md: L("DETECTED FILES")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    let fresh = watcher.items.filter(\.new).count
                    Text(fresh > 0 ? L("%@ files · %@ new", watcher.items.count, fresh) : L("%@ files", watcher.items.count))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(fresh > 0 ? accent : .secondary)
                }
                if watcher.unreadable {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(md: L("macOS has not let Edit Assist read this folder.")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                        Text(md: L("Turn on **Edit Assist** under **Files and Folders** in Privacy & Security, then come back here."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack {
                            Button(L("Open System Settings")) { watcher.openFolderSettings() }
                            Button(L("Try again")) { watcher.refresh() }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                } else if watcher.items.isEmpty {
                    Text(md: L("Nothing in this folder yet.")).font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ThinScrollView {
                        LazyVStack(spacing: 2) { ForEach(watcher.items) { row($0) } }
                    }
                    .background(.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            Text(md: L("Amir only lists files for now; nothing is renamed or moved yet."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    func row(_ item: AmirWatcher.Item) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 20, height: 20)
            Text(item.url.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            if item.new {
                Text(md: L("New")).font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(accent.opacity(0.22), in: Capsule()).foregroundStyle(accent)
            }
            Spacer(minLength: 8)
            Text(item.isFolder ? L("Folder") : item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            Text(item.added == .distantPast ? "" : item.added.formatted(.relative(presentation: .named)))
                .font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(item.new ? accent.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contextMenu { Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } }
    }
}
