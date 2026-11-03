import SwiftUI

/// Penny, the numbers helper: a teal blob with a bun and round glasses, holding up a bar chart. Working: the bars rise
/// and fall and her glasses catch the light.
struct PixelPenny: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 80 / 255, green: 200 / 255, blue: 190 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["....NN..........", "...NNNN.........", "..OOOOOOO.......", ".OOOOOOOOO......",
                       ".OGGGOGGGO......", ".OGKGGGKGO.A..Y.", ".OGGGOGGGO.A.PY.", ".OOOOOOOOO.AYPY.",
                       ".OOOOOOOOOOAYPY.", "..OOOOOOOO.AAAAA", "...D....D.......", "................"]
    static let blink = ["....NN..........", "...NNNN.........", "..OOOOOOO.......", ".OOOOOOOOO......",
                        ".OGGGOGGGO......", ".OGOGGGOGO.A..Y.", ".OGGGOGGGO.A.PY.", ".OOOOOOOOO.AYPY.",
                        ".OOOOOOOOOOAYPY.", "..OOOOOOOO.AAAAA", "...D....D.......", "................"]
    static let working: [[String]] = [
        ["....NN..........", "...NNNN.........", "..OOOOOOO.......", ".OOOOOOOOO......",
         ".OGGGOGGGO......", ".OGKGGGKGO.A....", ".OGGGOGGGO.A..Y.", ".OOOOOOOOO.A.PY.",
         ".OOOOOOOOOOAYPY.", "..OOOOOOOO.AAAAA", "...D....D.......", "................"],
        ["....NN..........", "...NNNN.........", "..OOOOOOO.......", ".OOOOOOOOO......",
         ".OgGGOgGGO......", ".OGKGGGKGO.A.P..", ".OGGGOGGGO.A.PY.", ".OOOOOOOOO.AYPY.",
         ".OOOOOOOOOOAYPY.", "..OOOOOOOO.AAAAA", "...D....D.......", "................"],
        ["....NN..........", "...NNNN.........", "..OOOOOOO.......", ".OOOOOOOOO......",
         ".OGGGOGGGO......", ".OGKGGGKGO.A..Y.", ".OGGGOGGGO.AY.Y.", ".OOOOOOOOO.AYPY.",
         ".OOOOOOOOOOAYPY.", "..OOOOOOOO.AAAAA", "...D....D.......", "................"],
        ["....NN..........", "...NNNN.........", "..OOOOOOO.......", ".OOOOOOOOO......",
         ".OgGGOgGGO....Y.", ".OGKGGGKGO.A..Y.", ".OGGGOGGGO.A.PY.", ".OOOOOOOOO.AYPY.",
         ".OOOOOOOOOOAYPY.", "..OOOOOOOO.AAAAA", "...D....D.......", "................"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["O": Color(red: 80 / 255, green: 200 / 255, blue: 190 / 255), "D": Color(red: 65 / 255, green: 164 / 255, blue: 155 / 255),
                                "N": Color(red: 120 / 255, green: 75 / 255, blue: 45 / 255), "G": Color(red: 235 / 255, green: 235 / 255, blue: 240 / 255),
                                "g": .white, "K": Color(red: 25 / 255, green: 25 / 255, blue: 28 / 255),
                                "A": Color(red: 200 / 255, green: 200 / 255, blue: 205 / 255), "Y": Color(red: 1, green: 214 / 255, blue: 80 / 255),
                                "P": Color(red: 240 / 255, green: 120 / 255, blue: 110 / 255)],
                       pixel: pixel, busyUntil: busyUntil, previewOnHover: previewOnHover)
            .accessibilityLabel("Penny")
    }
}

/// Penny's page (2026-11-03): the numbers of the products you run, from the company's Grafana. The tab only, for now.
struct PennyPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PixelPenny(pixel: 4, previewOnHover: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(md: L("Your numbers helper")).font(.system(size: 13, weight: .semibold))
                    Bullets(["Gets the numbers for the **products you run** from the company's **Grafana**",
                             "Shows how each product is doing, like an **accountant** and **analyst**",
                             "**Only reads**: never changes anything in Grafana"], size: 11)
                }
            }
            Text(md: L("Not connected yet: Penny is still being set up.")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
