import AppKit
import SwiftUI

/// Bo, the Drive helper: a round blue fellow in a cap worn with its brim to the side, holding a long stick upright.
/// Working (checking or restarting Google Drive): he lifts the stick and taps it down with a spark.
struct PixelBo: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 110 / 255, green: 185 / 255, blue: 240 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    /// Something is wrong with Google Drive: Bo panics (`PanickedBo`) until it is fixed.
    var onFire = false
    static let rest = ["....CCCCC.......", "...CCCCCCC...S..", "..CCCCCCCCC..S..", "VVVVVVVVVVV..S..",
                       "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
                       "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F....S..", ".............S.."]
    static let blink = ["....CCCCC.......", "...CCCCCCC...S..", "..CCCCCCCCC..S..", "VVVVVVVVVVV..S..",
                        "..BBBBBBBBB..S..", "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
                        "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F....S..", ".............S.."]
    static let working: [[String]] = [
        ["....CCCCC....S..", "...CCCCCCC...S..", "..CCCCCCCCC..S..", "VVVVVVVVVVV..S..",
         "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
         "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F....S..", "................"],
        ["....CCCCC....S..", "...CCCCCCC...S..", "..CCCCCCCCC..S..", "VVVVVVVVVVV..S..",
         "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
         "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F....S..", "................"],
        ["....CCCCC.......", "...CCCCCCC...S..", "..CCCCCCCCC..S..", "VVVVVVVVVVV..S..",
         "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
         "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F...YSY.", "............YSY."],
        ["....CCCCC.......", "...CCCCCCC...S..", "..CCCCCCCCC..S..", "VVVVVVVVVVV..S..",
         "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
         "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F....S..", ".............S.."],
    ]
    var body: some View {
        if onFire { PanickedBo(pixel: pixel).accessibilityLabel("Bo, something is wrong with Google Drive") } else { calm }
    }

    var calm: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["C": Color(red: 40 / 255, green: 70 / 255, blue: 140 / 255), "V": Color(red: 25 / 255, green: 45 / 255, blue: 95 / 255),
                                "B": Color(red: 110 / 255, green: 185 / 255, blue: 240 / 255), "H": Color(red: 110 / 255, green: 185 / 255, blue: 240 / 255),
                                "K": Color(red: 20 / 255, green: 25 / 255, blue: 40 / 255), "S": Color(red: 150 / 255, green: 100 / 255, blue: 55 / 255),
                                "F": Color(red: 60 / 255, green: 90 / 255, blue: 150 / 255), "Y": Color(red: 1, green: 220 / 255, blue: 80 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Bo")
    }
}

/// Bo's icon in the sidebar, poking while he checks.
struct BoIcon: View {
    @ObservedObject var watcher: BoWatcher
    var pixel: CGFloat = 1.25
    var body: some View { PixelBo(pixel: pixel, busyUntil: watcher.busyUntil, onFire: watcher.onFire) }
}

/// Bo when something is wrong with Google Drive (2026-11-03, asked for): a fire burns behind him and he runs across,
/// out one side and back in from the other, wide-eyed and sweating, until it is fixed. Still, mid-frame, with Reduce
/// Motion on. Same size as Bo, so nothing around it moves.
struct PanickedBo: View {
    var pixel: CGFloat = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let fire: [[String]] = [
        ["................", "................", "................", "................", "................", "................",
         "................", "..Y.......Y.....", ".YOY....Y.OY..Y.", ".ORO.Y.YOYRO.YO.", "ORRROYOORRRROORO", "RRRRRRRRRRRRRRRR"],
        ["................", "................", "................", "................", "................", "...........Y....",
         "...........Y....", ".Y.....Y..YO....", "YOY...YOY.ORY.Y.", "ORO.YOROO.RRYOOY", "RRROORRRORRRORRO", "RRRRRRRRRRRRRRRR"],
        ["................", "................", "................", "................", "....Y...........", "................",
         "....Y...........", "...YO.......Y...", "..YOR.Y....YOY.Y", "Y.ORRYOY.Y.ORO.O", "OYRRRORROOYRRROR", "RRRRRRRRRRRRRRRR"],
    ]
    /// Running, facing left (his brim points the way he runs); flipped when he runs back.
    static let runA = ["....CCCCC..", "...CCCCCCC.", "..CCCCCCCCC", "VVVVVVVVVVV", "W.BBBBBBBBB", "..BKKBBKKBB", "..BKKBBKKBB", "H.BBBBKBBBB", "..BBBBBBBBB", "...BBBBBBB.", "...F.....F.", "..........."]
    static let runB = ["...........", "....CCCCC..", "...CCCCCCC.", "..CCCCCCCCC", "VVVVVVVVVVV", "..BBBBBBBBB", "W.BKKBBKKBH", "..BKKBBKKB.", "..BBBBKBBBB", "..BBBBBBBBB", "...BBBBBBB.", ".....FF...."]
    static let colors: [Character: Color] = [
        "R": Color(red: 225 / 255, green: 60 / 255, blue: 40 / 255), "O": Color(red: 250 / 255, green: 140 / 255, blue: 40 / 255),
        "Y": Color(red: 1, green: 215 / 255, blue: 80 / 255), "C": Color(red: 40 / 255, green: 70 / 255, blue: 140 / 255),
        "V": Color(red: 25 / 255, green: 45 / 255, blue: 95 / 255), "B": Color(red: 110 / 255, green: 185 / 255, blue: 240 / 255),
        "H": Color(red: 110 / 255, green: 185 / 255, blue: 240 / 255), "K": Color(red: 20 / 255, green: 25 / 255, blue: 40 / 255),
        "F": Color(red: 60 / 255, green: 90 / 255, blue: 150 / 255), "W": Color(red: 190 / 255, green: 230 / 255, blue: 1),
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            PixelSprite(rows: Self.frame(reduceMotion ? 12 : Int(context.date.timeIntervalSinceReferenceDate / 0.1)), colors: Self.colors, pixel: pixel)
        }
    }

    /// The picture at a tick: the fire flickers every other tick, his legs every tick; each pass he crosses the 16 columns
    /// one a tick, off-frame for a few ticks, then comes back the other way.
    static func frame(_ tick: Int) -> [String] {
        var grid = fire[(tick / 2) % fire.count].map { Array($0) }
        let width = grid[0].count, runner = runA[0].count, span = width + runner + 4
        let back = (tick / span) % 2 == 1, step = tick % span
        let left = back ? step - runner : width - 1 - step
        for (y, row) in (tick % 2 == 0 ? runA : runB).enumerated() {
            for (i, mark) in (back ? Array(row.reversed()) : Array(row)).enumerated() where mark != "." {
                let x = left + i
                if x >= 0, x < width { grid[y][x] = mark }
            }
        }
        return grid.map { String($0) }
    }
}

/// Bo's page: how Google Drive is doing, and what Bo has done about it.
struct BoPage: View {
    @ObservedObject var watcher: BoWatcher
    private let accent = PixelBo.theme
    /// Folders waiting for you to confirm moving them to the Trash.
    @State private var trashing: Trashing?
    struct Trashing: Identifiable {
        let title: String, what: String, urls: [URL]
        var id: String { title }
    }

    var body: some View {
        ThinScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelBo(pixel: 4, busyUntil: watcher.busyUntil, previewOnHover: true, onFire: watcher.onFire)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your Drive helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Checks **Google Drive** every minute while you work",
                             "**Restarts** it by himself when a drive stops answering for 3 minutes",
                             "Opens it again if it is **not running**",
                             "Restarts macOS's **File Provider** when Finder stops showing Drive's changes",
                             "Keeps track of Drive's **cache** and says when to **clear** it",
                             "Watches this **Mac's disk** and what you could **archive** to Drive"], size: 11)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(md: L("GOOGLE DRIVE")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    status(watcher.running, L(watcher.running ? "Google Drive is running" : "Google Drive is not running"))
                    ForEach(watcher.drives) { drive in
                        status(drive.answered, drive.answered == nil ? L("%@: checking…", drive.account)
                               : drive.answered == true ? L("%@: answering (%@ ms)", drive.account, drive.milliseconds ?? 0)
                               : L("%@: not answering", drive.account))
                    }
                    if watcher.drives.isEmpty { status(false, L("No Google Drive found in this Mac's CloudStorage")) }
                    // Whether Finder is taking what Drive brings down: when not, new folders never show up.
                    if watcher.running {
                        let worst = watcher.finderLag.max { $0.value < $1.value }
                        if let worst, worst.value >= BoWatcher.finderStuckAfter {
                            status(false, L("Finder has not taken %@'s changes for %@", watcher.accountName(worst.key), L(BoWatcher.duration(worst.value))))
                        } else {
                            status(true, L("Finder is taking Drive's changes"))
                        }
                        // Finder's own copy broken: what Drive has and Finder does not show.
                        if let gap = watcher.finderMissing.first {
                            HStack(spacing: 10) {
                                status(false, L("Finder is missing %@ items Google Drive has", watcher.finderMissing.reduce(0) { $0 + $1.gap }))
                                Button(L("How to fix")) {
                                    watcher.reconnect = .init(account: gap.account, email: gap.email, missing: watcher.finderMissing.filter { $0.account == gap.account })
                                }.controlSize(.small)
                            }
                        } else if watcher.storage != nil {
                            status(true, L("Finder shows everything Google Drive has"))
                        }
                    }
                    if let until = watcher.holdUntil {
                        status(nil, L("Leaving Google Drive alone while it rebuilds, until %@", until.formatted(date: .omitted, time: .shortened)))
                    }
                    Text(watcher.lastCheck.map { L("Checked %@", $0.formatted(.relative(presentation: .named))) } ?? L("First check in a few seconds"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            recommendations
            thisMac
            cache
            errorKinds
            VStack(alignment: .leading, spacing: 8) {
                Text(md: L("WHAT BO DID")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                if watcher.events.isEmpty {
                    Text(md: L("Nothing yet: Google Drive has been fine.")).font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ForEach(watcher.events) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(event.time.formatted(date: .omitted, time: .shortened)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            Text(event.text).font(.system(size: 11))
                        }
                    }
                }
            }
            Text(md: L("Script sheets come next: Bo will read your script sheet after you sign in with Google."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.automatic)
        .confirmationDialog(trashing?.title ?? "", isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }), presenting: trashing) { item in
            Button(L("Move to Trash"), role: .destructive) { watcher.trash(item.urls, what: item.what); trashing = nil }
        } message: { _ in Text(md: L("You can put them back from the Trash until you empty it.")) }
    }

    func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(md: L(title)).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }

    /// What Bo recommends clearing, and how; or that nothing needs it.
    var recommendations: some View {
        section("BO RECOMMENDS") {
            if watcher.storage == nil {
                Text(md: L("Measuring Drive's cache…")).font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
            } else if watcher.advice.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                    Text(md: L("Nothing to clear now: Drive's cache and logs are a healthy size.")).font(.system(size: 12))
                }.padding(12)
            } else {
                ForEach(Array(watcher.advice.enumerated()), id: \.element.id) { index, advice in
                    if index > 0 { Divider().opacity(0.4) }
                    adviceRow(advice).padding(12)
                }
            }
        }
    }

    @ViewBuilder func adviceRow(_ advice: BoWatcher.Advice) -> some View {
        let support = BoWatcher.support
        switch advice {
        case .clearCache(let account, let reason):
            tip(L("Clear Drive's cache for %@", account.name),
                {
                    switch reason {
                    case .big: return L("It is **%@**, more than the 2 GB Bo keeps it under. A fresh cache makes Drive lighter and quicker to start.", Self.bytes(account.bytes))
                    case .stuck(let times): return L("Bo had to restart Google Drive **%@ times** in the last day. A fresh cache usually stops it getting stuck.", times)
                    case .lowSpace: return L("Your Mac is short of room and this cache is **%@**.", Self.bytes(account.bytes))
                    }
                }(),
                steps: ["Check that Drive says **all files are up to date** (nothing still uploading)",
                        "In Google Drive: **Settings → Preferences → ⚙ → Disconnect account**",
                        "Sign in again: Drive builds a fresh cache and your files come back"],
                note: L("Google's way: never delete Drive's folders by hand, files not yet uploaded live there.")) {
                Button(L("Open Google Drive")) { watcher.openGoogleDrive() }.buttonStyle(.borderedProminent).tint(accent)
            }
        case .unuploaded(let files, let bytes):
            tip(L("%@ files Drive could not upload", files),
                L("Drive set them aside (**%@**). Drag any you still need into My Drive to upload them, then delete the rest.", Self.bytes(bytes))) {
                Button(L("Show the files")) { NSWorkspace.shared.open(support.appendingPathComponent("lost_and_found")) }
                if let drive = watcher.archiveDrive { Button(L("Open My Drive")) { NSWorkspace.shared.open(drive) } }
            }
        case .oldLogs(let bytes, let files):
            tip(L("Drive's old logs take %@", Self.bytes(bytes)),
                L("**%@ log files**, only of use to Google's support. Quit Google Drive, then delete all but **drive_fs.txt**.", files)) {
                Button(L("Show the logs")) { NSWorkspace.shared.open(support.appendingPathComponent("Logs")) }
            }
        case .archive(let projects, let bytes):
            tip(L("Archive %@ projects to Google Drive to free %@", projects, Self.bytes(bytes)),
                L("They have not been touched for a month or more (marked below). Drag them into your Drive, then right-click each and choose **Remove Download** once it has uploaded: it stays in Drive and frees this Mac."),
                note: L("Your work Drive has no storage limit of its own; the Gmail one has a 15 GB limit.")) {
                Button(L("Show the projects")) {
                    NSWorkspace.shared.activateFileViewerSelecting(BoWatcher.idleProjects(watcher.mac?.folders ?? []).map(\.url))
                }.buttonStyle(.borderedProminent).tint(accent)
                if let drive = watcher.archiveDrive {
                    Button(L("Open %@", drive.deletingLastPathComponent().lastPathComponent.replacingOccurrences(of: "GoogleDrive-", with: ""))) { NSWorkspace.shared.open(drive) }
                }
            }
        case .dragCopies(let bytes, let newest):
            let parts = watcher.mac?.folders.first { $0.kind == .dragCopies }?.parts ?? []
            tip(L("%@ of copies left by dragging files into apps", Self.bytes(bytes)),
                L("macOS copies files you drag into some apps and does not clear them (newest from %@). Check you still have the originals, then delete them.",
                  newest.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "?")) {
                Button(L("Show them")) { NSWorkspace.shared.activateFileViewerSelecting(parts) }
                Button(L("Move to Trash…")) {
                    trashing = Trashing(title: L("Move %@ of drag copies to the Trash?", Self.bytes(bytes)), what: "the drag copies", urls: parts)
                }.disabled(parts.isEmpty)
            }
        case .mediaCache(let bytes):
            let parts = watcher.mac?.folders.first { $0.kind == .mediaCache }?.parts ?? []
            tip(L("Premiere's media cache takes %@", Self.bytes(bytes)),
                L("Premiere rebuilds it when needed: your projects open a little slower the first time after.")) {
                Button(L("Show it")) { NSWorkspace.shared.activateFileViewerSelecting(parts) }
                Button(L("Move to Trash…")) {
                    trashing = Trashing(title: L("Move Premiere's %@ media cache to the Trash?", Self.bytes(bytes)), what: "Premiere's media cache", urls: parts)
                }.disabled(parts.isEmpty || watcher.premiereOpen)
                if watcher.premiereOpen { Text(md: L("Quit Premiere first")).font(.system(size: 10)).foregroundStyle(.orange) }
            }
        case .lowSpace(let free):
            tip(L("Your Mac has %@ free", Self.bytes(free)),
                L("Drive needs room for the files you open. Free up space, or turn files you don't need offline back to online-only.")) {
                Button(L("Open Storage settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    /// A recommendation: what and why, the steps when there are any, and buttons that do it or open where it is done.
    func tip<Actions: View>(_ title: String, _ detail: String, steps: [String] = [], note: String? = nil, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill").foregroundStyle(.orange).font(.system(size: 13))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(md: detail).font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).").font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
                        Text(md: L(step)).font(.system(size: 11))
                    }
                }
                if let note { Text(md: note).font(.system(size: 10)).foregroundStyle(.secondary) }
                HStack(spacing: 8) { actions() }.controlSize(.small).padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    /// This Mac's disk, every minute; its biggest folders, every three hours; each Google account's Drive space.
    var thisMac: some View {
        section("THIS MAC", trailing: watcher.mac?.measured.map { L("Folders measured %@", $0.formatted(.relative(presentation: .named))) }) {
            if let mac = watcher.mac {
                let used = mac.total - mac.free, low = mac.free < BoWatcher.lowSpace
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(low ? Color.orange : accent).frame(width: geometry.size.width * CGFloat(used) / CGFloat(max(mac.total, 1)))
                        }
                    }.frame(height: 8)
                    HStack {
                        Text(L("%@ used", Self.bytes(used))).font(.system(size: 11))
                        Spacer()
                        Text(L("%@ free of %@", Self.bytes(mac.free), Self.bytes(mac.total))).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(low ? .orange : .primary)
                    }
                }.padding(12)
                if !watcher.quotas.isEmpty {
                    Divider().opacity(0.4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(md: L("GOOGLE DRIVE SPACE")).font(.system(size: 8, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
                        ForEach(watcher.quotas) { quota in
                            HStack(spacing: 10) {
                                Image(systemName: "cloud").frame(width: 18).foregroundStyle(.secondary)
                                Text(quota.email).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text(quota.text).font(.system(size: 12, design: .monospaced))
                                Text(quota.seen.formatted(.relative(presentation: .named))).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        Text(md: L("As Google Drive's settings last showed it; open them to refresh.")).font(.system(size: 9)).foregroundStyle(.secondary)
                    }.padding(12)
                }
                Divider().opacity(0.4)
                if mac.measured == nil {
                    Text(md: L("Measuring the biggest folders…")).font(.system(size: 11)).foregroundStyle(.secondary).padding(12)
                } else {
                    let idle = Set(BoWatcher.idleProjects(mac.folders).map(\.url))
                    ForEach(mac.folders.prefix(10)) { folder in folderRow(folder, idle: idle.contains(folder.url)) }
                }
            } else {
                Text(md: L("Measuring…")).font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
            }
        }
    }

    func folderRow(_ folder: BoWatcher.Folder, idle: Bool) -> some View {
        let icon = switch folder.kind { case .project: "film.stack"; case .folder: "folder"; case .mediaCache: "film"; case .dragCopies: "doc.on.doc" }
        let tag: String? = idle ? L("Archive?") : folder.kind == .dragCopies ? L("Leftover copies") : folder.kind == .mediaCache ? L("Premiere cache") : nil
        return HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(idle ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(folder.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    if let tag {
                        Text(tag).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background((idle ? Color.orange : accent).opacity(0.18), in: Capsule()).foregroundStyle(idle ? .orange : accent)
                    }
                }
                if let used = folder.lastUsed {
                    Text(L("Last changed %@", used.formatted(.relative(presentation: .named)))).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(Self.bytes(folder.bytes)).font(.system(size: 12, design: .monospaced))
            Button { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) } label: { Image(systemName: "folder") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Show in Finder"))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    /// What Drive keeps on this Mac, measured every 15 minutes.
    var cache: some View {
        section("CACHE", trailing: watcher.cacheGrowth.map { growth in
            growth.since.timeIntervalSinceNow > -86_400 ? L("Tracking since today")
                : L("%@%@ since %@", growth.bytes >= 0 ? "+" : "−", Self.bytes(abs(growth.bytes)), growth.since.formatted(.dateTime.day().month()))
        }) {
            if let storage = watcher.storage {
                ForEach(storage.accounts) { account in
                    sizeRow("internaldrive", account.name, Self.bytes(account.bytes), warn: account.bytes > BoWatcher.cacheLimit)
                }
                sizeRow("doc.text", L("Old logs (%@ files)", storage.logFiles), Self.bytes(storage.logBytes), warn: storage.logBytes > BoWatcher.logLimit)
                sizeRow("tray.full", L("Not uploaded (%@ files)", storage.unuploadedFiles), Self.bytes(storage.unuploadedBytes), warn: storage.unuploadedFiles > 0)
                if let free = storage.free { sizeRow("externaldrive", L("Free on this Mac"), Self.bytes(free), warn: free < BoWatcher.lowSpace) }
            } else {
                Text(md: L("Measuring…")).font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
            }
        }
    }

    func sizeRow(_ icon: String, _ name: String, _ size: String, warn: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(warn ? .orange : .secondary)
            Text(name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(size).font(.system(size: 12, design: .monospaced)).foregroundStyle(warn ? .orange : .primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    /// Drive's log errors of the last day by kind, each with its count; the newest line shows on hover.
    var errorKinds: some View {
        section("ERRORS IN DRIVE'S LOG", trailing: L("last 24 hours")) {
            ForEach(watcher.errors) { count in
                let info = Self.info(count.kind)
                HStack(spacing: 10) {
                    Image(systemName: info.icon).frame(width: 18)
                        .foregroundStyle(count.day == 0 ? Color.secondary : count.kind == .noise ? Color.secondary : count.hour > 0 ? .orange : accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(md: L(info.name)).font(.system(size: 12, weight: .medium))
                        Text(md: L(info.about)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(count.day)").font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(count.day == 0 || count.kind == .noise ? .secondary : .primary)
                        Text(count.hour > 0 ? L("%@ in the last hour", count.hour) : count.last.map { $0.formatted(.relative(presentation: .named)) } ?? " ")
                            .font(.system(size: 9)).foregroundStyle(count.hour > 0 && count.kind != .noise ? .orange : .secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .opacity(count.kind == .noise ? 0.7 : 1)
                .help(count.example.isEmpty ? L("None in the last 24 hours") : count.example)
            }
        }
    }

    static func info(_ kind: BoWatcher.ErrorKind) -> (icon: String, name: String, about: String) {
        switch kind {
        case .connection: ("wifi.exclamationmark", "Connection", "The internet dropped or was too slow for Drive")
        case .server: ("server.rack", "Google's servers", "Google was busy (too many requests) or failing")
        case .access: ("lock", "Access", "Sign-in, permissions, or shared drives Drive can't open")
        case .sync: ("arrow.triangle.2.circlepath", "Uploads and sync", "Files that failed to upload, conflicts, storage full")
        case .mac: ("desktopcomputer", "macOS and Finder", "The link between Drive and Finder (File Provider)")
        case .crash: ("bolt.trianglebadge.exclamationmark", "Crashes", "Google Drive closed unexpectedly")
        case .noise: ("ellipsis.circle", "Background noise", "Drive's own housekeeping: harmless")
        }
    }

    func status(_ good: Bool?, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: good == nil ? "circle.dotted" : good == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(good == nil ? Color.secondary : good == true ? accent : .orange)
            Text(text).font(.system(size: 12))
        }
    }
}

/// Bo's dialog when Finder's copy of an account is broken: what is missing, and Google's way to rebuild it. Never over
/// a run; "Not now" asks again in six hours.
struct BoReconnectDialog: ViewModifier {
    @ObservedObject var watcher: BoWatcher
    var busy: Bool
    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { busy ? nil : watcher.reconnect },
                                 set: { if $0 == nil, !busy, watcher.reconnect != nil { watcher.reconnectLater() } })) { reconnect in
                BoReconnectSheet(reconnect: reconnect, watcher: watcher)
            }
            .onChange(of: watcher.reconnect) { _, new in if new != nil { NSApp.requestUserAttention(.informationalRequest) } }
            .sheet(item: Binding(get: { busy ? nil : watcher.disconnectStuck.map(StuckDisconnect.init) },
                                 set: { if $0 == nil, !busy, watcher.disconnectStuck != nil { watcher.disconnectWait() } })) { stuck in
                BoStuckDisconnectSheet(since: stuck.since, watcher: watcher)
            }
            .onChange(of: watcher.disconnectStuck) { _, new in if new != nil { NSApp.requestUserAttention(.informationalRequest) } }
    }
}

struct BoReconnectSheet: View {
    let reconnect: BoWatcher.Reconnect
    @ObservedObject var watcher: BoWatcher
    private let accent = PixelBo.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                PixelBo(pixel: 3, busyUntil: .distantFuture, onFire: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(md: L("Finder is missing folders from your Google Drive")).font(.system(size: 15, weight: .semibold))
                    Text(reconnect.email ?? reconnect.account).font(.system(size: 12)).foregroundStyle(accent)
                }
            }
            Text(md: L("Google Drive has them, but Finder's copy of this account is broken, so they never show up. Restarting does not mend it: the account needs rebuilding."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !reconnect.missing.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(reconnect.missing.prefix(5)) { gap in
                    HStack {
                        Text(gap.drive).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text(L("Finder shows %@ of %@", gap.inFinder, gap.inDrive)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.orange)
                    }
                }
            }
            .padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(["Check Google Drive says **all files are up to date** (nothing still uploading)",
                               "In Google Drive: **⚙ → Preferences → ⚙**, then **Disconnect account** for this account",
                               "**Add account** and sign in with it again: Drive builds a fresh copy"].enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).").font(.system(size: 12, design: .monospaced)).foregroundStyle(accent)
                        Text(md: L(step)).font(.system(size: 12))
                    }
                }
            }
            Text(md: L("Bo leaves Google Drive alone for 3 hours while it rebuilds. Turning off a VPN such as Cloudflare WARP makes it quicker."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("Not now")) { watcher.reconnectLater() }
                Button(L("Open Google Drive")) { watcher.reconnecting() }.buttonStyle(.borderedProminent).tint(accent)
            }
        }
        .padding(22).frame(width: 470)
    }
}

struct StuckDisconnect: Identifiable {
    let since: Date
    var id: Date { since }
}

/// Bo's dialog when Drive's disconnect has not moved for 10 minutes: restart Drive and try again.
struct BoStuckDisconnectSheet: View {
    let since: Date
    @ObservedObject var watcher: BoWatcher
    private let accent = PixelBo.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                PixelBo(pixel: 3, busyUntil: .distantFuture, onFire: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(md: L("Google Drive's disconnect seems stuck")).font(.system(size: 15, weight: .semibold))
                    Text(L("“Preparing to disconnect account” since %@, and nothing has changed", since.formatted(date: .omitted, time: .shortened)))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(["Click **Cancel** in Google Drive's window if you can",
                               "**Restart Google Drive** below: Bo quits it (forced if it will not) and opens it again",
                               "Try **Disconnect account** again, with a VPN such as Cloudflare WARP turned off"].enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).").font(.system(size: 12, design: .monospaced)).foregroundStyle(accent)
                        Text(md: L(step)).font(.system(size: 12))
                    }
                }
            }
            Text(md: L("Nothing is lost: files still uploading stay on this Mac until Drive is back."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L("Wait longer")) { watcher.disconnectWait() }
                Button(L("Restart Google Drive")) { watcher.restartForDisconnect() }.buttonStyle(.borderedProminent).tint(accent)
            }
        }
        .padding(22).frame(width: 470)
    }
}
