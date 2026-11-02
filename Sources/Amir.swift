import SwiftUI

/// Amir, the file helper: a folder with a handlebar mustache, in the same pixel-art style as the running crab.
struct PixelAmir: View {
    var pixel: CGFloat = 2
    private static let rows = ["..TTTTT.........", ".TTTTTTT........", ".FFFFFFFFFFFFFF.", ".FFFFFFFFFFFFFF.",
                               ".FFFFKFFFFKFFFF.", ".FFFFKFFFFKFFFF.", ".FFFFFFFFFFFFFF.", ".FMFFFFFFFFFFMF.",
                               ".FMMMMMFFMMMMMF.", ".FFFMMMMMMMMFFF.", ".FFFFFFFFFFFFFF.", ".DDDDDDDDDDDDDD."]
    private static let colors: [Character: Color] = [
        "T": Color(red: 214 / 255, green: 150 / 255, blue: 60 / 255), "F": Color(red: 240 / 255, green: 190 / 255, blue: 82 / 255),
        "D": Color(red: 200 / 255, green: 140 / 255, blue: 55 / 255), "K": Color(red: 20 / 255, green: 14 / 255, blue: 10 / 255),
        "M": Color(red: 36 / 255, green: 22 / 255, blue: 14 / 255),
    ]

    var body: some View {
        Canvas { canvas, size in
            let left = ((size.width - 16 * pixel) / 2).rounded(), top = ((size.height - 12 * pixel) / 2).rounded()
            for (y, row) in Self.rows.enumerated() {
                for (x, mark) in row.enumerated() {
                    guard let color = Self.colors[mark] else { continue }
                    canvas.fill(Path(CGRect(x: left + CGFloat(x) * pixel, y: top + CGFloat(y) * pixel, width: pixel, height: pixel)), with: .color(color))
                }
            }
        }
        .frame(width: 16 * pixel, height: 12 * pixel)
        .accessibilityLabel("Amir")
    }
}

/// Amir's page. The tab only, for now: what Amir will do, settled on 2026-11-02 (always asks before moving, renames by
/// your own rule, unzips and sorts what is inside); the watching itself comes next.
struct AmirPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                PixelAmir(pixel: 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(md: L("Amir")).font(.system(size: 20, weight: .semibold))
                    Text(md: L("Your file helper")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Bullets(["Watches your **Downloads** while you work",
                     "Suggests a **name** and the **right folder** for each new file",
                     "**Unzips** downloads and sorts what is inside",
                     "**Always asks** before moving anything"])
            Text(md: L("Not watching yet: Amir is still being set up."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
