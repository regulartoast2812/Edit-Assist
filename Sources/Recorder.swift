import AppKit

/// One decision the routine made, with everything it was based on, so it can be made again later
/// and compared. Tests/Replay.swift feeds these back through the same functions on every build: a
/// change that would decide differently on a screen that once worked fails there, not in a run.
struct Snapshot: Codable {
    /// phrase, selected, panel, fontSize, styleButton, styleGrid, tile, dragGuard, textSection
    var kind: String
    var note: String = ""
    var image: String?
    var hits: [RecordedHit]

    // Inputs
    /// phrase: for each phrase still to do, in order, the words still to style.
    var candidates: [[String]]?
    var minHeight: Double?
    var area: [Double]?
    /// dragGuard: the point the drag would start from.
    var point: [Double]?
    /// styleGrid / tile: the style browser's left edge.
    var left: Double?
    /// tile: your picked tile's appearance, and the cell that was clicked.
    var appearance: [UInt8]?
    var cell: [Double]?

    // Results
    var bool: Bool?
    var number: Int?
    /// phrase: which candidate matched, how many words, and the drag span (start x, y, end x, y).
    var found: Int?
    var matched: Int?
    var span: [Double]?
    /// styleButton: where it would click.
    var location: [Double]?
    /// styleGrid: tiles in each row.
    var rows: [Int]?
    /// tile: the clicked tile's difference from your image.
    var difference: Int?
    /// textSection: every control read, as "name=value|on" (value and state empty when absent), with
    /// its click point.
    var controls: [String]?
    var points: [[Double]]?
}

struct RecordedHit: Codable {
    var text: String
    var rect: [Double]
    var words: [RecordedWord]
}

struct RecordedWord: Codable {
    var text: String
    var rect: [Double]
}

extension CGRect {
    var recorded: [Double] { [Double(minX), Double(minY), Double(width), Double(height)] }
    init(recorded values: [Double]) {
        self.init(x: values[0], y: values[1], width: values[2], height: values[3])
    }
}

extension RecordedHit {
    init(_ hit: TextHit) {
        self.init(text: hit.text, rect: hit.rect.recorded,
                  words: hit.words.map { RecordedWord(text: $0.0, rect: $0.1.recorded) })
    }
    var hit: TextHit {
        TextHit(text: text, rect: CGRect(recorded: rect), words: words.map { ($0.text, CGRect(recorded: $0.rect)) })
    }
}

/// Saves a run's decisions to recordings/<date>/, numbered in the order they were made. Off unless
/// you ask for a recorded run. "Keep as a test" moves a recording to recordings/kept/, which the
/// replay reads on every build.
@MainActor
final class Recorder {
    private(set) var folder: URL?
    private var count = 0
    private var lastImage: (CGImage, String)?

    static func root(in base: URL) -> URL { base.appendingPathComponent("recordings", isDirectory: true) }
    static func kept(in base: URL) -> URL { root(in: base).appendingPathComponent("kept", isDirectory: true) }

    func start(in base: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = Self.root(in: base).appendingPathComponent(stamp, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folder = url; count = 0; lastImage = nil
    }

    func stop() { folder = nil; lastImage = nil }

    var isOn: Bool { folder != nil }

    /// Records one decision. Pass the image only when the decision depended on pixels; one screen
    /// used by several decisions in a row is written once.
    func note(_ snapshot: Snapshot, image: CGImage? = nil) {
        guard let folder else { return }
        count += 1
        var entry = snapshot
        if let image {
            if let last = lastImage, last.0 === image {
                entry.image = last.1
            } else if let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                let name = String(format: "%03d-%@.png", count, snapshot.kind)
                try? png.write(to: folder.appendingPathComponent(name))
                entry.image = name; lastImage = (image, name)
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(entry) {
            try? data.write(to: folder.appendingPathComponent(String(format: "%03d-%@.json", count, snapshot.kind)))
        }
    }
}
