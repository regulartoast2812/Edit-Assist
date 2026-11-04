import SwiftUI

/// Don, the ads helper: a mint blob in a navy suit and red tie, his hair slicked back like an ad man's. Working: he looks
/// one way, then the other, and a light bulb lights up over his head.
struct PixelDon: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 150 / 255, green: 220 / 255, blue: 170 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = [".............", ".............", ".............", "....HHHHHHH..", "..HHhhhhHHHH.",
                       ".HHHHHHHHHHH.", ".OOOOOOOOOOO.", ".OOOOOOOOOOO.", ".OOOKOOOKOOO.", ".OOOKOOOKOOO.",
                       ".OOOOOOOOOOO.", ".SSSWTTWSSSS.", ".SSSSWTSSSSS.", "..SSSTTTSSS..", "...DD...DD..."]
    static let blink = [".............", ".............", ".............", "....HHHHHHH..", "..HHhhhhHHHH.",
                        ".HHHHHHHHHHH.", ".OOOOOOOOOOO.", ".OOOOOOOOOOO.", ".OOOOOOOOOOO.", ".OOOKOOOKOOO.",
                        ".OOOOOOOOOOO.", ".SSSWTTWSSSS.", ".SSSSWTSSSSS.", "..SSSTTTSSS..", "...DD...DD..."]
    static let working: [[String]] = [
        [".............", ".............", ".............", "....HHHHHHH..", "..HHhhhhHHHH.",
         ".HHHHHHHHHHH.", ".OOOOOOOOOOO.", ".OOOOOOOOOOO.", ".OOKOOOKOOOO.", ".OOKOOOKOOOO.",
         ".OOOOOOOOOOO.", ".SSSWTTWSSSS.", ".SSSSWTSSSSS.", "..SSSTTTSSS..", "...DD...DD..."],
        [".............", ".............", ".............", "....HHHHHHH..", "..HHhhhhHHHH.",
         ".HHHHHHHHHHH.", ".OOOOOOOOOOO.", ".OOOOOOOOOOO.", ".OOOOKOOOKOO.", ".OOOOKOOOKOO.",
         ".OOOOOOOOOOO.", ".SSSWTTWSSSS.", ".SSSSWTSSSSS.", "..SSSTTTSSS..", "...DD...DD..."],
        [".....YYY.....", ".....YYY.....", "......G......", "....HHHHHHH..", "..HHhhhhHHHH.",
         ".HHHHHHHHHHH.", ".OOOOOOOOOOO.", ".OOOOOOOOOOO.", ".OOOKOOOKOOO.", ".OOOKOOOKOOO.",
         ".OOOOOOOOOOO.", ".SSSWTTWSSSS.", ".SSSSWTSSSSS.", "..SSSTTTSSS..", "...DD...DD..."],
        ["...y.YYY.y...", "....yYYYy....", "......G......", "....HHHHHHH..", "..HHhhhhHHHH.",
         ".HHHHHHHHHHH.", ".OOOOOOOOOOO.", ".OOOOOOOOOOO.", ".OOOKOOOKOOO.", ".OOOKOOOKOOO.",
         ".OOOOOOOOOOO.", ".SSSWTTWSSSS.", ".SSSSWTSSSSS.", "..SSSTTTSSS..", "...DD...DD..."],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["O": Color(red: 150 / 255, green: 220 / 255, blue: 170 / 255), "D": Color(red: 110 / 255, green: 180 / 255, blue: 135 / 255),
                                "H": Color(red: 40 / 255, green: 32 / 255, blue: 30 / 255), "h": Color(red: 95 / 255, green: 85 / 255, blue: 80 / 255),
                                "K": Color(red: 25 / 255, green: 25 / 255, blue: 28 / 255), "S": Color(red: 45 / 255, green: 55 / 255, blue: 90 / 255),
                                "W": Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255), "T": Color(red: 215 / 255, green: 60 / 255, blue: 60 / 255),
                                "Y": Color(red: 1, green: 214 / 255, blue: 80 / 255), "y": Color(red: 1, green: 240 / 255, blue: 160 / 255),
                                "G": Color(red: 150 / 255, green: 150 / 255, blue: 155 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Don")
    }
}

/// Don in the sidebar, at work while he reads a script.
struct DonIcon: View {
    @ObservedObject var don: DonReader
    var body: some View { PixelDon(pixel: 1.25, busyUntil: don.reading != nil ? .distantFuture : nil) }
}

/// Don's page: he reads the open script into a brief (the vibe, voice, music and graphic style the others work to, the
/// CTA, and the lines with no media that need AI video). Pix takes his jobs from it (2026-11-04).
struct DonPage: View {
    @ObservedObject var don: DonReader
    let project: Project
    private let accent = PixelDon.theme

    var body: some View {
        ThinScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelDon(pixel: 4, busyUntil: don.reading != nil ? .distantFuture : nil, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your ads expert")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Reads the project's **script** or **script sheet**",
                             "Recommends the **vibe**, **voice**, **music** and **graphic style**",
                             "Briefs the other helpers, so they all work to the same idea"], size: 11)
                }
            }
            section(L("THE BRIEF"), trailing: project.openScript.name) { brief }
            if let shots = don.brief?.videoShots, !shots.isEmpty {
                section(L("LINES THAT NEED AI VIDEO"), trailing: L("%@ with no media", shots.count)) {
                    ForEach(shots) { shot in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shot.line).font(.system(size: 12))
                            if !shot.idea.isEmpty { Text(shot.idea).font(.system(size: 10)).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(md: L("WHO HE BRIEFS")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    brief(L("Tala"), L("The voice and the music")) { PixelTala(pixel: 1.1) }
                    brief(L("Pix"), L("The CTA, queued by itself, and product schematics when lines need AI video")) { PixelPix(pixel: 1.25) }
                    brief(L("Kino"), L("The look of the AI videos")) { PixelKino(pixel: 1.25) }
                }
                .background(.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 9))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.automatic)
        .onAppear { don.load(script: project.openScript.id) }
        .onChange(of: project.openScript.id) { _, id in don.load(script: id) }
    }

    @ViewBuilder var brief: some View {
        let empty = DonBrief.lines(project.script).isEmpty
        if don.reading == project.openScript.id {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(md: L("Don is reading the script… (a minute or two)")).font(.system(size: 12))
            }
        } else if let brief = don.brief {
            if brief.outdated(by: project.script) {
                HStack(spacing: 10) {
                    status(false, L("The script changed since Don read it"))
                    readButton(L("Read again"))
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                row(L("Product"), brief.product)
                row(L("Vibe"), brief.vibe)
                row(L("Voice"), brief.voice)
                row(L("Music"), brief.music)
                row(L("Graphic style"), brief.graphicStyle)
                row(L("CTA"), brief.cta.isEmpty ? L("None in the script") : "“\(brief.cta)”")
                row(L("CTA look"), brief.ctaLook)
            }
            HStack(spacing: 10) {
                Text(L("Read %@", brief.read.formatted(date: .abbreviated, time: .shortened))).font(.system(size: 10)).foregroundStyle(.secondary)
                if !brief.outdated(by: project.script) { readButton(L("Read again")) }
            }
        } else if empty {
            Text(md: L("No script yet: paste one in the project first.")).font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            Text(md: L("Don hasn't read this script yet. He briefs the others from it, and Pix queues the CTA.")).font(.system(size: 12))
            readButton(L("Read the script"))
        }
        if let failure = don.failure { status(false, failure) }
    }

    func readButton(_ title: String) -> some View {
        Button(title) { don.read(script: project.openScript.id, text: project.script, project: project.name, name: project.openScript.name) }
            .controlSize(.small).disabled(don.reading != nil || DonBrief.lines(project.script).isEmpty)
    }

    @ViewBuilder func row(_ name: String, _ value: String) -> some View {
        if !value.isEmpty {
            GridRow(alignment: .firstTextBaseline) {
                Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(value).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func brief<Icon: View>(_ name: String, _ what: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 10) {
            icon().frame(width: 22)
            Text(name).font(.system(size: 12, weight: .medium))
            Text(what).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(md: title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    func status(_ good: Bool?, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: good == nil ? "info.circle" : good == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(good == nil ? Color.secondary : good == true ? accent : .orange)
            Text(md: text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
