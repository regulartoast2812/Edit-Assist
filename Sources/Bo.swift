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
    var body: some View { PixelBo(pixel: pixel, busyUntil: watcher.busyUntil) }
}

/// Bo's page: how Google Drive is doing, and what Bo has done about it.
struct BoPage: View {
    @ObservedObject var watcher: BoWatcher
    private let accent = PixelBo.theme

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelBo(pixel: 4, busyUntil: watcher.busyUntil, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your Drive helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Checks **Google Drive** every minute while you work",
                             "**Restarts** it by himself when a drive stops answering for 3 minutes",
                             "Opens it again if it is **not running**",
                             "Keeps track of Drive's **cache** and says when to **clear** it"], size: 11)
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
                    Text(watcher.lastCheck.map { L("Checked %@", $0.formatted(.relative(presentation: .named))) } ?? L("First check in a few seconds"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            recommendations
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
                note: L("Google's way: never delete Drive's folders by hand, files not yet uploaded live there."))
        case .unuploaded(let files, let bytes):
            tip(L("%@ files Drive could not upload", files),
                L("Drive set them aside (**%@**). Check whether you still need them, upload any you do, then delete the rest.", Self.bytes(bytes)),
                folder: support.appendingPathComponent("lost_and_found"))
        case .oldLogs(let bytes, let files):
            tip(L("Drive's old logs take %@", Self.bytes(bytes)),
                L("**%@ log files**, only of use to Google's support. Quit Google Drive, then delete all but **drive_fs.txt**.", files),
                folder: support.appendingPathComponent("Logs"))
        case .lowSpace(let free):
            tip(L("Your Mac has %@ free", Self.bytes(free)),
                L("Drive needs room for the files you open. Free up space, or turn files you don't need offline back to online-only."))
        }
    }

    func tip(_ title: String, _ detail: String, steps: [String] = [], note: String? = nil, folder: URL? = nil) -> some View {
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
                if let folder { Button(L("Show in Finder")) { NSWorkspace.shared.open(folder) }.controlSize(.small) }
            }
            Spacer(minLength: 0)
        }
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
