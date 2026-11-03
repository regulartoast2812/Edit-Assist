import SwiftUI

/// Tala ("star" in Tagalog), the voice helper: a coral star with rosy cheeks.
struct PixelTala: View {
    var pixel: CGFloat = 2
    var body: some View {
        PixelSprite(rows: [".......S........", "......SSS.......", "......SSS.......", "SSSSSSSSSSSSSSS.",
                           ".SSSSKSSSKSSSS..", "..SSSKSSSKSSS...", "...BSSSSSSSB....", "...SSSSSSSSS....",
                           "..SSSSS.SSSSS...", "..SSSS...SSSS...", ".SSS.......SSS..", ".S...........S.."],
                    colors: ["S": Color(red: 1, green: 150 / 255, blue: 170 / 255), "B": Color(red: 235 / 255, green: 95 / 255, blue: 130 / 255),
                             "K": Color(red: 40 / 255, green: 18 / 255, blue: 26 / 255)],
                    pixel: pixel)
            .accessibilityLabel("Tala")
    }
}

/// Tala's page. The tab only, for now (2026-11-03): voice-overs through the ElevenLabs API and music that suits the voice.
struct TalaPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelTala(pixel: 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your voice helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Turns your script into a **voice-over** with **ElevenLabs**",
                             "Finds **music** that suits the voice",
                             "The first helper that works with **AI**"], size: 11)
                }
            }
            Text(md: L("Not connected yet: Tala is still being set up."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
