import SwiftUI

/// Bo, the Drive helper: a round blue fellow in a cap worn with its brim to the side, holding a long stick upright.
/// Working (checking or restarting Google Drive): he lifts the stick and taps it down with a spark.
struct PixelBo: View {
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["....CCCCC.......", "...CCCCCCC...S..", "VVVCCCCCCCC..S..", "...BBBBBBB...S..",
                       "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
                       "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F....S..", ".............S.."]
    static let blink = ["....CCCCC.......", "...CCCCCCC...S..", "VVVCCCCCCCC..S..", "...BBBBBBB...S..",
                        "..BBBBBBBBB..S..", "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
                        "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F....S..", ".............S.."]
    static let working: [[String]] = [
        ["....CCCCC....S..", "...CCCCCCC...S..", "VVVCCCCCCCC..S..", "...BBBBBBB...S..",
         "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
         "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F....S..", "................"],
        ["....CCCCC....S..", "...CCCCCCC...S..", "VVVCCCCCCCC..S..", "...BBBBBBB...S..",
         "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
         "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F....S..", "................"],
        ["....CCCCC.......", "...CCCCCCC...S..", "VVVCCCCCCCC..S..", "...BBBBBBB...S..",
         "..BBBBBBBBB..S..", "..BBKBBBKBB..S..", "..BBKBBBKBB..S..", "..BBBBBBBBBHHS..",
         "..BBBBBBBBB..S..", "...BBBBBBB...S..", "....F...F...YSY.", "............YSY."],
        ["....CCCCC.......", "...CCCCCCC...S..", "VVVCCCCCCCC..S..", "...BBBBBBB...S..",
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
    private let accent = Color(red: 0.43, green: 0.88, blue: 0.73)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelBo(pixel: 4, busyUntil: watcher.busyUntil, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your Drive helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Checks **Google Drive** every minute while you work",
                             "**Restarts** it by himself when a drive stops answering for 3 minutes",
                             "Opens it again if it is **not running**"], size: 11)
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
                    HStack(spacing: 12) {
                        Text(watcher.lastCheck.map { L("Checked %@", $0.formatted(.relative(presentation: .named))) } ?? L("First check in a few seconds"))
                        Text(L("%@ errors in Drive's log in the last 15 minutes (most are harmless)", watcher.logErrors))
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
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
            Spacer()
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
