import SwiftUI

/// Penny, the numbers helper: a businessman, a platinum blob with side-parted hair, gold glasses and a charcoal suit with
/// a money-green tie, holding up a bar chart (a teal blob with a bun read as Perry the Platypus, 2026-11-03). Working:
/// the bars rise and fall and his glasses catch the light.
struct PixelPenny: View {
    /// The helper's colour, the body's: their page and sidebar button take it.
    static let theme = Color(red: 205 / 255, green: 212 / 255, blue: 222 / 255)
    var pixel: CGFloat = 2
    var busyUntil: Date?
    var previewOnHover = false
    static let rest = ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
                       ".OGKGGGKGO.A..Y.", ".OOGOOOGOO.A.PY.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
                       ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"]
    static let blink = ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
                        ".OGOGGGOGO.A..Y.", ".OOGOOOGOO.A.PY.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
                        ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"]
    static let working: [[String]] = [
        ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
         ".OGKGGGKGO.A....", ".OOGOOOGOO.A..Y.", ".OOOOOOOOO.A.PY.", ".SSSWTWSSSOAYPY.",
         ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"],
        ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
         ".OgKGGgKGO.A.P..", ".OOGOOOGOO.A.PY.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
         ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"],
        ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
         ".OGKGGGKGO.A..Y.", ".OOGOOOGOO.AY.Y.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
         ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"],
        ["...NNNNNN.......", "..NNnNNNNN......", ".NNOOOOOOO......", ".OOOOOOOOO......",
         ".OgKGGgKGO.A..Y.", ".OOGOOOGOO.A.PY.", ".OOOOOOOOO.AYPY.", ".SSSWTWSSSOAYPY.",
         ".SSSSTSSSS.AAAAA", "..SSSSSSSS......", "...D....D.......", "................"],
    ]
    var body: some View {
        AnimatedSprite(rest: Self.rest, blink: Self.blink, working: Self.working,
                       colors: ["O": Color(red: 205 / 255, green: 212 / 255, blue: 222 / 255), "D": Color(red: 95 / 255, green: 100 / 255, blue: 110 / 255),
                                "N": Color(red: 45 / 255, green: 40 / 255, blue: 40 / 255), "n": Color(red: 110 / 255, green: 100 / 255, blue: 95 / 255),
                                "G": Color(red: 205 / 255, green: 165 / 255, blue: 70 / 255), "g": Color(red: 1, green: 245 / 255, blue: 200 / 255),
                                "K": Color(red: 25 / 255, green: 25 / 255, blue: 28 / 255), "S": Color(red: 80 / 255, green: 86 / 255, blue: 100 / 255),
                                "W": Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255), "T": Color(red: 60 / 255, green: 170 / 255, blue: 90 / 255),
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
