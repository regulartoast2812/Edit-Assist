import SwiftUI

/// Tala ("star" in Tagalog), the voice helper: a soft pink mochi with a red bow, smiling eyes and rosy cheeks (a star
/// with eyes read as Patrick Star, not as her, 2026-11-03).
struct PixelTala: View {
    var pixel: CGFloat = 2
    var body: some View {
        PixelSprite(rows: ["..RR.RR.........", "..RRQRRPPPP.....", "..PPPPPPPPPPPP..", ".PPPPPPPPPPPPPP.",
                           ".PPPPPPPPPPPPPP.", ".PPPPPPPPPPPPPP.", ".PPPKPPPPPPKPPP.", ".PPKPKPPPPKPKPP.",
                           ".PBBPPPPPPPPBBP.", ".PPPPPPPPPPPPPP.", "..PPPPPPPPPPPP..", "...DDDDDDDDDD..."],
                    colors: ["P": Color(red: 1, green: 178 / 255, blue: 192 / 255), "D": Color(red: 235 / 255, green: 140 / 255, blue: 160 / 255),
                             "B": Color(red: 245 / 255, green: 110 / 255, blue: 140 / 255), "K": Color(red: 45 / 255, green: 20 / 255, blue: 30 / 255),
                             "R": Color(red: 232 / 255, green: 64 / 255, blue: 100 / 255), "Q": Color(red: 170 / 255, green: 30 / 255, blue: 65 / 255)],
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
