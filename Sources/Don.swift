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

/// Don's page (2026-11-03): he reads the script or script sheet and recommends the vibe, voice, music and graphic style,
/// which the other helpers then work from. The tab only, for now: his full UI and the ad components come later.
struct DonPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelDon(pixel: 4, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your ads expert")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Reads the project's **script** or **script sheet**",
                             "Recommends the **vibe**, **voice**, **music** and **graphic style**",
                             "Briefs the other helpers, so they all work to the same idea"], size: 11)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(md: L("WHO HE BRIEFS")).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    brief(L("Tala"), L("The voice and the music")) { PixelTala(pixel: 1.1) }
                    brief(L("Pix"), L("The graphic style of the CTA and images")) { PixelPix(pixel: 1.25) }
                    brief(L("Kino"), L("The look of the AI videos")) { PixelKino(pixel: 1.25) }
                }
                .background(.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 9))
            }
            Text(md: L("Not connected yet: Don is still being set up.")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
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
}
