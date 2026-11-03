import SwiftUI

/// Kino, the AI video helper: an orange blob in a red director's beret, holding a clapperboard. Working: the clapper
/// opens and snaps shut, and sparks of AI fly off it.
struct PixelKino: View {
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO.....",
                       ".OOOOOOOOOO.....", ".OOKOOOOKOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
                       ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"]
    static let blink = ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO.....",
                        ".OOOOOOOOOO.....", ".OOOOOOOOOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
                        ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"]
    static let working: [[String]] = [
        ["..RRRRRr....S...", ".RRRRRRR.......W", "..OOOOOOO.....B.", ".OOOOOOOOOO..W..",
         ".OOOOOOOOOO.B...", ".OOKOOOOKOOW....", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"],
        ["..RRRRRr....s...", ".RRRRRRR........", "..OOOOOOO.......", ".OOOOOOOOOO...S.",
         ".OOOOOOOOOO.....", ".OOKOOOOKOOWBWBW", ".OOKOOOOKOOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.......", "................"],
        ["..RRRRRr........", ".RRRRRRR.......W", "..OOOOOOO.....B.", ".OOOOOOOOOO.sW..",
         ".OOOOOOOOOO.B...", ".OOOKOOOOKOW....", ".OOOKOOOOKOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D....S..", "................"],
        ["..RRRRRr........", ".RRRRRRR........", "..OOOOOOO...S...", ".OOOOOOOOOO.....",
         ".OOOOOOOOOO.....", ".OOOKOOOOKOWBWBW", ".OOOKOOOOKOBBBBB", ".OOOOOOOOOOBWWWB",
         ".OOOOOOOOOOOWWBB", "..OOOOOOOO.BBBBB", "...D....D.....s.", "................"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["O": Color(red: 250 / 255, green: 160 / 255, blue: 70 / 255), "D": Color(red: 205 / 255, green: 131 / 255, blue: 57 / 255),
                                "R": Color(red: 215 / 255, green: 55 / 255, blue: 60 / 255), "r": Color(red: 160 / 255, green: 35 / 255, blue: 45 / 255),
                                "K": Color(red: 25 / 255, green: 25 / 255, blue: 28 / 255), "B": Color(red: 95 / 255, green: 95 / 255, blue: 108 / 255),
                                "W": Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255), "S": Color(red: 1, green: 230 / 255, blue: 120 / 255),
                                "s": Color(red: 150 / 255, green: 220 / 255, blue: 1)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Kino")
    }
}

/// Kino's page (2026-11-03): AI videos made with Kling and Higgsfield, from your media and prompts. The tab only, for now.
struct KinoPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelKino(pixel: 4, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your AI video helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Makes **AI videos** with **Kling** and **Higgsfield**",
                             "Connects your **media** (images, clips) to the **prompts**",
                             "Works to the look in **Don's** brief"], size: 11)
                }
            }
            Text(md: L("Not connected yet: Kino is still being set up.")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
