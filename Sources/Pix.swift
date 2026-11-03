import SwiftUI

/// Pix, the CTA and image helper: a lavender blob with Bob Ross's big curly perm and a full beard up to his hair, holding a paintbrush upright
/// (a full Bob Ross did not fit with the other blobs, 2026-11-03). Working: he sweeps the brush and dabs of paint appear.
struct PixelPix: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 190 / 255, green: 170 / 255, blue: 240 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["...AAaAAAA......", ".AAaAAAAAaAA..P.", "AAAAAAaAAAAAA.R.", "AAaOOOOOOOAaA.R.",
                       "AAOOOOOOOOOAA.F.", "AaBOKOOOKOBAA.H.", ".ABOKOOOKOBA..H.", "..BBOOOOOBB...H.",
                       "..BBBBBBBBBOOOH.", "...BBBBBBB....H.", "....D...D.....H.", "................"]
    static let blink = ["...AAaAAAA......", ".AAaAAAAAaAA..P.", "AAAAAAaAAAAAA.R.", "AAaOOOOOOOAaA.R.",
                        "AAOOOOOOOOOAA.F.", "AaBOOOOOOOBAA.H.", ".ABOKOOOKOBA..H.", "..BBOOOOOBB...H.",
                        "..BBBBBBBBBOOOH.", "...BBBBBBB....H.", "....D...D.....H.", "................"]
    static let working: [[String]] = [
        ["...AAaAAAA......", ".AAaAAAAAaAA..PG", "AAAAAAaAAAAAA.R.", "AAaOOOOOOOAaA.R.",
         "AAOOOOOOOOOAA.F.", "AaBOKOOOKOBAA.H.", ".ABOKOOOKOBA..H.", "..BBOOOOOBB...H.",
         "..BBBBBBBBBOOOH.", "...BBBBBBB....H.", "....D...D.....H.", "................"],
        ["...AAaAAAA......", ".AAaAAAAAaAA...P", "AAAAAAaAAAAAA..R", "AAaOOOOOOOAaA..R",
         "AAOOOOOOOOOAA..F", "AaBOKOOOKOBAA..H", ".ABOKOOOKOBA...H", "..BBOOOOOBB....H",
         "..BBBBBBBBBOOOOH", "...BBBBBBB.....H", "....D...D......H", "................"],
        ["...AAaAAAA......", ".AAaAAAAAaAA..PG", "AAAAAAaAAAAAA.R.", "AAaOOOOOOOAaA.RY",
         "AAOOOOOOOOOAA.F.", "AaBOKOOOKOBAA.H.", ".ABOKOOOKOBA..H.", "..BBOOOOOBB...H.",
         "..BBBBBBBBBOOOH.", "...BBBBBBB....H.", "....D...D.....H.", "................"],
        ["...AAaAAAA......", ".AAaAAAAAaAA.P.G", "AAAAAAaAAAAAARL.", "AAaOOOOOOOAaAR.Y",
         "AAOOOOOOOOOAAF..", "AaBOKOOOKOBAAH..", ".ABOKOOOKOBA.H..", "..BBOOOOOBB..H..",
         "..BBBBBBBBBOOH..", "...BBBBBBB...H..", "....D...D....H..", "................"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["A": Color(red: 150 / 255, green: 95 / 255, blue: 55 / 255), "a": Color(red: 115 / 255, green: 70 / 255, blue: 40 / 255),
                                "O": Color(red: 190 / 255, green: 170 / 255, blue: 240 / 255), "K": Color(red: 30 / 255, green: 25 / 255, blue: 25 / 255),
                                "B": Color(red: 120 / 255, green: 75 / 255, blue: 45 / 255), "D": Color(red: 160 / 255, green: 140 / 255, blue: 210 / 255),
                                "P": Color(red: 90 / 255, green: 175 / 255, blue: 110 / 255), "R": Color(red: 45 / 255, green: 40 / 255, blue: 40 / 255),
                                "F": Color(red: 170 / 255, green: 170 / 255, blue: 175 / 255), "H": Color(red: 180 / 255, green: 130 / 255, blue: 70 / 255),
                                "G": Color(red: 90 / 255, green: 175 / 255, blue: 110 / 255), "Y": Color(red: 1, green: 214 / 255, blue: 80 / 255),
                                "L": Color(red: 110 / 255, green: 170 / 255, blue: 235 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Pix")
    }
}

/// Pix's page (2026-11-03): the CTA comes from each script's CTA line; it is laid out in your Illustrator CTA file, and
/// images are made with GPT Image. For now the page shows the CTA line found in this project's script.
struct PixPage: View {
    /// The project's script, with **bold** marks.
    let script: String
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelPix(pixel: 4, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your CTA and image helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Takes the **CTA** text from the CTA line of each script",
                             "Lays it out in your **Illustrator** CTA file",
                             "Makes images with **GPT Image**"], size: 11)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(md: L("CTA IN THIS SCRIPT")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Group {
                    if let line = Self.ctaLine(in: script) {
                        Text(Self.styled(line)).font(.system(size: 14))
                    } else {
                        Text(md: L("No script yet: paste one in the project first.")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                Text(md: L("For now, the script's last line is taken as its CTA.")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(md: L("Not connected yet: Pix is still being set up.")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// The CTA line: the last line of the script with any text in it, read as the highlight functions read it.
    static func ctaLine(in script: String) -> ScriptLine? {
        ((try? ScriptParser.parse(script)) ?? []).last { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The line with its bold phrases bold and in Pix's colour. Not through Markdown: a phrase saved with
    /// its trailing space ("**Sale: **UP") is not bold to Markdown, and the stars showed (2026-11-03).
    static func styled(_ line: ScriptLine) -> AttributedString {
        let chars = Array(line.text)
        var result = AttributedString(), at = 0
        for span in line.highlights.sorted(by: { $0.start < $1.start }) {
            let start = min(max(span.start, at), chars.count), end = min(max(span.end, start), chars.count)
            if start > at { result += AttributedString(String(chars[at ..< start])) }
            var bold = AttributedString(String(chars[start ..< end]))
            bold.font = .system(size: 14, weight: .bold)
            bold.foregroundColor = PixelPix.theme
            result += bold
            at = end
        }
        if at < chars.count { result += AttributedString(String(chars[at...])) }
        return result
    }
}
