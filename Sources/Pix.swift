import SwiftUI

/// Pix, the CTA and image helper: a gold picture frame with arms and legs, a sunny landscape inside and eyes in its sky.
/// Working: arms up, a sparkle.
struct PixelPix: View {
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = [".GGGGGGGGGGGG...", ".GSSSSSSSSSSG...", ".GSSSSSSSYYSG...", ".GSKSSSKSYYSG...",
                       "AGSKSSSKSSSSGA..", ".GSSSSMSSSSSG...", ".GSSSMMMSSMSG...", ".GSSMMMMMMMMG...",
                       ".GMMMMMMMMMMG...", ".GGGGGGGGGGGG...", "...AA....AA.....", "................"]
    static let blink = [".GGGGGGGGGGGG...", ".GSSSSSSSSSSG...", ".GSSSSSSSYYSG...", ".GSSSSSSSYYSG...",
                        "AGSKSSSKSSSSGA..", ".GSSSSMSSSSSG...", ".GSSSMMMSSMSG...", ".GSSMMMMMMMMG...",
                        ".GMMMMMMMMMMG...", ".GGGGGGGGGGGG...", "...AA....AA.....", "................"]
    static let working: [[String]] = [
        [".GGGGGGGGGGGG.W.", ".GSSSSSSSSSSGWWW", "AGSSSSSSSYYSGAW.", "AGSKSSSKSYYSGA..",
         ".GSKSSSKSSSSG...", ".GSSSSMSSSSSG...", ".GSSSMMMSSMSG...", ".GSSMMMMMMMMG...",
         ".GMMMMMMMMMMG...", ".GGGGGGGGGGGG...", "...AA....AA.....", "................"],
        [".GGGGGGGGGGGG...", ".GSSSSSSSSSSG.W.", ".GSSSSSSSYYSG...", ".GSKSSSKSYYSG...",
         "AGSKSSSKSSSSGA..", ".GSSSSMSSSSSG...", ".GSSSMMMSSMSG...", ".GSSMMMMMMMMG...",
         ".GMMMMMMMMMMG...", ".GGGGGGGGGGGG...", "...AA....AA.....", "................"],
        [".GGGGGGGGGGGG...", ".GSSSSSSSSSSG.W.", "AGSSSSSSSYYSGA..", "AGSKSSSKSYYSGA..",
         ".GSKSSSKSSSSG...", ".GSSSSMSSSSSG...", ".GSSSMMMSSMSG...", ".GSSMMMMMMMMG...",
         ".GMMMMMMMMMMG...", ".GGGGGGGGGGGG...", "...AA....AA.....", "................"],
        [".GGGGGGGGGGGG.W.", ".GSSSSSSSSSSGWWW", ".GSSSSSSSYYSG.W.", ".GSKSSSKSYYSG...",
         "AGSKSSSKSSSSGA..", ".GSSSSMSSSSSG...", ".GSSSMMMSSMSG...", ".GSSMMMMMMMMG...",
         ".GMMMMMMMMMMG...", ".GGGGGGGGGGGG...", "...AA....AA.....", "................"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["G": Color(red: 214 / 255, green: 168 / 255, blue: 74 / 255), "S": Color(red: 140 / 255, green: 200 / 255, blue: 245 / 255),
                                "Y": Color(red: 1, green: 214 / 255, blue: 80 / 255), "K": Color(red: 25 / 255, green: 25 / 255, blue: 40 / 255),
                                "M": Color(red: 90 / 255, green: 175 / 255, blue: 110 / 255), "A": Color(red: 176 / 255, green: 128 / 255, blue: 52 / 255),
                                "W": .white],
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
                        // Read as Markdown directly: a CTA holds "%" ("70% OFF"), which a localised string key could take for a format.
                        Text((try? AttributedString(markdown: line)) ?? AttributedString(line)).font(.system(size: 14))
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

    /// The CTA line: the last line of the script with any text in it.
    static func ctaLine(in script: String) -> String? {
        script.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
    }
}
