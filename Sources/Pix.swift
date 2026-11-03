import SwiftUI

/// Pix, the CTA and image helper, after Bob Ross: a big curly perm, a beard, a light blue shirt and a paintbrush held up.
/// Working: he sweeps the brush and dabs of paint appear beside it.
struct PixelPix: View {
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["..AAAaAAAA......", ".AAaAAAAaAA.....", "AaAAAAAAAAaA.P..", "AAASSSSSSAAA.R..",
                       "AaASKSSKSAAA.R..", "AAASSSSSSAaA.F..", "aAABSSSSBAAA.H..", ".AABBBBBBAa..H..",
                       "...BBBBBB....H..", "..CCCCCCCCCSSH..", ".CCCCCCCCCC..H..", ".CCCCCCCCCC....."]
    static let blink = ["..AAAaAAAA......", ".AAaAAAAaAA.....", "AaAAAAAAAAaA.P..", "AAASSSSSSAAA.R..",
                        "AaASSSSSSAAA.R..", "AAASSSSSSAaA.F..", "aAABSSSSBAAA.H..", ".AABBBBBBAa..H..",
                        "...BBBBBB....H..", "..CCCCCCCCCSSH..", ".CCCCCCCCCC..H..", ".CCCCCCCCCC....."]
    static let working: [[String]] = [
        ["..AAAaAAAA......", ".AAaAAAAaAA.....", "AaAAAAAAAAaA.P..", "AAASSSSSSAAA.R.G",
         "AaASKSSKSAAA.R..", "AAASSSSSSAaA.F..", "aAABSSSSBAAA.H..", ".AABBBBBBAa..H..",
         "...BBBBBB....H..", "..CCCCCCCCCSSH..", ".CCCCCCCCCC..H..", ".CCCCCCCCCC....."],
        ["..AAAaAAAA......", ".AAaAAAAaAA.....", "AaAAAAAAAAaA..P.", "AAASSSSSSAAA..RG",
         "AaASKSSKSAAA..R.", "AAASSSSSSAaA..FY", "aAABSSSSBAAA..H.", ".AABBBBBBAa...H.",
         "...BBBBBB.....H.", "..CCCCCCCCCSSSH.", ".CCCCCCCCCC...H.", ".CCCCCCCCCC....."],
        ["..AAAaAAAA......", ".AAaAAAAaAA.....", "AaAAAAAAAAaA.P..", "AAASSSSSSAAA.R.G",
         "AaASKSSKSAAA.RL.", "AAASSSSSSAaA.F.Y", "aAABSSSSBAAA.H..", ".AABBBBBBAa..H..",
         "...BBBBBB....H..", "..CCCCCCCCCSSH..", ".CCCCCCCCCC..H..", ".CCCCCCCCCC....."],
        ["..AAAaAAAA......", ".AAaAAAAaAA.....", "AaAAAAAAAAaAP...", "AAASSSSSSAAAR...",
         "AaASKSSKSAAAR.L.", "AAASSSSSSAaAF..Y", "aAABSSSSBAAAH...", ".AABBBBBBAa.H...",
         "...BBBBBB...H...", "..CCCCCCCCCSH...", ".CCCCCCCCCC.H...", ".CCCCCCCCCC....."],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["A": Color(red: 150 / 255, green: 95 / 255, blue: 55 / 255), "a": Color(red: 115 / 255, green: 70 / 255, blue: 40 / 255),
                                "S": Color(red: 238 / 255, green: 190 / 255, blue: 150 / 255), "K": Color(red: 30 / 255, green: 25 / 255, blue: 25 / 255),
                                "B": Color(red: 120 / 255, green: 75 / 255, blue: 45 / 255), "C": Color(red: 175 / 255, green: 205 / 255, blue: 230 / 255),
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
