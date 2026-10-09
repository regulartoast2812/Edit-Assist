import AppKit

// Replays recorded decisions through today's code and fails if any comes out differently.
//
// Sources: Tests/Fixtures (real screens, decisions checked by hand) and every recording kept from
// the app (Diagnostics → Keep last recording as a test). A screen that once worked is a screen
// that must keep working; a change that decides differently on one fails here, before a build is
// installed, instead of in the middle of your next run.
@main
struct Replay {
    @MainActor static func main() {
        var folders = [URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/Fixtures")]
        let dataDir = ProcessInfo.processInfo.environment["EDIT_ASSIST_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Edit Assist")
        let kept = Recorder.kept(in: dataDir)
        if let runs = try? FileManager.default.contentsOfDirectory(at: kept, includingPropertiesForKeys: nil) {
            folders += runs.filter { $0.hasDirectoryPath }.sorted { $0.path < $1.path }
        }
        var passed = 0, failed: [String] = []
        for folder in folders {
            let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                guard let data = try? Data(contentsOf: file), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
                    failed.append("\(file.path): unreadable"); continue
                }
                let image = snapshot.image.flatMap { name -> CGImage? in
                    NSImage(contentsOf: folder.appendingPathComponent(name))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }
                if let problem = check(snapshot, image: image) {
                    failed.append("\(folder.lastPathComponent)/\(file.lastPathComponent) [\(snapshot.kind)] \(snapshot.note): \(problem)")
                } else { passed += 1 }
            }
        }
        for failure in failed { print("FAIL: \(failure)") }
        print("\(passed) recorded decisions replayed unchanged, \(failed.count) changed (\(folders.count) source\(folders.count == 1 ? "" : "s")).")
        exit(failed.isEmpty ? 0 : 1)
    }

    static func close(_ a: [Double]?, _ b: [Double]?, within: Double = 0.004) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.count == y.count && zip(x, y).allSatisfy { abs($0 - $1) <= within }
        default: return false
        }
    }

    /// nil when today's code decides as recorded; otherwise what differs.
    @MainActor static func check(_ s: Snapshot, image: CGImage?) -> String? {
        let hits = s.hits.map(\.hit)
        let area = s.area.map { CGRect(recorded: $0) }
        let minHeight = CGFloat(s.minHeight ?? 0)
        switch s.kind {
        case "phrase":
            let candidates = s.candidates ?? []
            var found: Int?, matched: Int?, span: [Double]?
            for (index, tokens) in candidates.enumerated() {
                if let hit = Desktop.selection(forTokens: tokens, in: hits, minHeight: minHeight, area: area) {
                    found = index; matched = hit.matched
                    span = [Double(hit.span.start.x), Double(hit.span.start.y), Double(hit.span.end.x), Double(hit.span.end.y)]
                    break
                }
            }
            if found != s.found || matched != s.matched { return "matched candidate \(found.map(String.init) ?? "none") with \(matched.map(String.init) ?? "-") words, recorded \(s.found.map(String.init) ?? "none") with \(s.matched.map(String.init) ?? "-")" }
            if !close(span, s.span) { return "span \(span ?? []) differs from \(s.span ?? [])" }
        case "selected":
            let now = Desktop.clipIsSelected(in: hits)
            if now != s.bool { return "selected is \(now), recorded \(s.bool.map(String.init) ?? "-")" }
        case "panel":
            let now = Desktop.button(labelled: "Back", in: hits) != nil
            if now != s.bool { return "style browser open is \(now), recorded \(s.bool.map(String.init) ?? "-")" }
        case "fontSize":
            guard let image else { return "image missing" }
            let now = Desktop.numberField(labelled: "Font Size", in: hits, image: image)?.value
            if now != s.number { return "font size read \(now.map(String.init) ?? "none"), recorded \(s.number.map(String.init) ?? "none")" }
        case "styleButton":
            guard let image else { return "image missing" }
            let now = Desktop.styleBrowserButton(in: hits, image: image).map { [Double($0.x), Double($0.y)] }
            if !close(now, s.location) { return "style button at \(now ?? []), recorded \(s.location ?? [])" }
        case "styleGrid", "tile":
            guard let image, let left = s.left else { return "image or panel edge missing" }
            let cells = Desktop.styleGrid(in: hits, image: image, left: CGFloat(left)).cells
            if let rows = s.rows, cells.map(\.count) != rows { return "grid rows \(cells.map(\.count)), recorded \(rows)" }
            if let wanted = s.cell, !cells.flatMap({ $0 }).contains(where: { close($0.recorded, wanted) }) {
                return "the tile that was clicked is no longer a cell of the grid"
            }
            if s.kind == "tile", let appearance = s.appearance, let wanted = s.cell, let recorded = s.difference {
                let slot = Desktop.StyleSlot(row: 0, column: 0, positionKnown: true, appearance: appearance)
                let now = slot.difference(from: Desktop.cellPatch(image, cell: CGRect(recorded: wanted)))
                if (now >= 500) != (recorded >= 500) { return "colour match is \(now < 500), recorded \(recorded < 500)" }
                if abs(now - recorded) > 6 { return "difference \(now), recorded \(recorded)" }
            }
        case "dragGuard":
            guard let point = s.point else { return "point missing" }
            let now = Desktop.captionBlocks(in: hits, minHeight: minHeight, area: area).flatMap { $0 }
                .contains { $0.rect.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: point[0], y: point[1])) }
            if now != s.bool { return "drag allowed is \(now), recorded \(s.bool.map(String.init) ?? "-")" }
        default:
            return "unknown kind"
        }
        return nil
    }
}
