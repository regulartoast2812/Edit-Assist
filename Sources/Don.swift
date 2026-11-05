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
    @State private var link = ""

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
            section(L("SCRIPT SHEET"), trailing: don.sheet.map { [$0.title, $0.tab].filter { !$0.isEmpty }.joined(separator: " · ") }) { sheet }
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
        .onAppear { open() }
        .onChange(of: project.openScript.id) { _, _ in open() }
    }

    private func open() {
        don.load(script: project.openScript.id); don.load(project: project.id)
        link = don.sheet?.link ?? ""
    }

    /// The project's script sheet: its link, read with Claude's Google Sheets connector, and what Don found in it.
    @ViewBuilder var sheet: some View {
        let typed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        HStack(spacing: 8) {
            TextField(L("Paste the Google Sheets link"), text: $link).textFieldStyle(.roundedBorder).font(.system(size: 12))
                .onSubmit { if !typed.isEmpty { don.readSheet(typed, project: project.id) } }
            Button(don.sheet?.link == typed ? L("Read again") : L("Read")) { don.readSheet(typed, project: project.id) }
                .controlSize(.small).disabled(don.sheetReading || typed.isEmpty)
        }
        if don.sheetReading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(md: L("Don is reading the sheet…")).font(.system(size: 12))
            }
        } else if let sheet = don.sheet, let read = sheet.read {
            Text(L("%@ versions · read %@", sheet.versions.count, read.formatted(date: .abbreviated, time: .shortened)))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        } else {
            Text(md: L("Copy the link with the script's tab open. Don reads it with your Claude account's **Google Sheets** connector and changes nothing in it."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if let failure = don.sheetFailure { status(false, failure) }
    }

    /// Which script Don reads for the open one: the pasted script or one of the sheet's versions.
    @ViewBuilder var source: some View {
        if let sheet = don.sheet, !sheet.versions.isEmpty {
            Picker(L("Read from"), selection: Binding(get: { sheet.version(for: project.openScript)?.name ?? "" },
                                                      set: { don.pick($0.isEmpty ? nil : $0, script: project.openScript.id) })) {
                Text(L("The project's script")).tag("")
                ForEach(sheet.versions) { version in
                    Text(version.name + "  " + L("%@ lines, %@ with no media", version.lines.count, version.unfilmed)).tag(version.name)
                }
            }
            .pickerStyle(.menu).fixedSize().font(.system(size: 12)).disabled(don.reading != nil)
        }
    }

    @ViewBuilder var brief: some View {
        let empty = don.source(project).lines.isEmpty
        source
        if don.reading == project.openScript.id {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(md: L("Don is reading the script… (a minute or two)")).font(.system(size: 12))
            }
        } else if let brief = don.brief {
            if don.outdated(project) {
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
                let read = brief.read.formatted(date: .abbreviated, time: .shortened)
                Text(brief.sheet.map { L("Read from %@ in the sheet, %@", $0, read) } ?? L("Read %@", read)).font(.system(size: 10)).foregroundStyle(.secondary)
                if !don.outdated(project) { readButton(L("Read again")) }
            }
        } else if empty {
            Text(md: L("No script yet: paste one in the project, or read it from the script sheet above.")).font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            Text(md: L("Don hasn't read this script yet. He briefs the others from it, and Pix queues the CTA.")).font(.system(size: 12))
            readButton(L("Read the script"))
        }
        if let failure = don.failure { status(false, failure) }
    }

    func readButton(_ title: String) -> some View {
        Button(title) { don.read(project) }
            .controlSize(.small).disabled(don.reading != nil || don.source(project).lines.isEmpty)
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
