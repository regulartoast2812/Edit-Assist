import AppKit
import ScreenCaptureKit
import ApplicationServices
import Vision
import Security
import Carbon

/// Edit Assist only ever targets these. Matching on name as well as bundle id keeps it
/// working across yearly releases, whose bundle ids carry a version suffix.
enum TargetApp {
    static let label = "Premiere Pro or After Effects"
    static func matches(bundleID: String?, name: String?) -> Bool {
        let id = (bundleID ?? "").lowercased()
        let title = (name ?? "").lowercased()
        guard id.hasPrefix("com.adobe.") || title.contains("adobe") else { return false }
        return title.contains("premiere") || title.contains("after effects")
            || id.contains("premierepro") || id.contains("aftereffects")
    }
    static func matches(_ app: NSRunningApplication) -> Bool {
        matches(bundleID: app.bundleIdentifier, name: app.localizedName)
    }
}

struct WindowChoice: Identifiable {
    var id: CGWindowID
    var pid: pid_t
    var title: String
    var app: String
    var frame: CGRect
}

/// One line of on-screen text with its measured position, in normalized top-left coordinates.
struct TextHit: Equatable {
    var text: String
    var rect: CGRect
    var words: [(String, CGRect)] = []
    static func == (a: TextHit, b: TextHit) -> Bool { a.text == b.text && a.rect == b.rect }
}

struct Observation {
    var image: CGImage
    var window: WindowChoice
    var text: [TextHit] = []
    var timestamp = Date()
    /// When the text was read. A pixel-only look reuses an earlier reading of the layout.
    var textTimestamp = Date()
    /// Encoded only when asked for: the model path and debug dumps need it, OCR mode does not, and
    /// encoding a 2400-pixel window with its coordinate grid took 67 ms on every capture.
    @MainActor var png: Data { Desktop.gridded(image) ?? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data() }
    /// This look's pixels with an earlier look's text. Valid for anything that only needs to know
    /// where panels and the style grid are, which does not change while the list scrolls.
    func reusing(_ earlier: Observation) -> Observation {
        var copy = self
        copy.text = earlier.text
        copy.textTimestamp = earlier.textTimestamp
        return copy
    }
}

@MainActor
final class Desktop {
    static let eventTag: Int64 = 0x45444954415353
    private var monitors: [Any] = []
    let detectionHotkey = DetectionHotkey()
    private var lastActivePID: pid_t = 0
    /// Our own click-through run overlay, which must not count as a window covering the target.
    var overlayWindowID: CGWindowID = 0
    var inspectionWindowID: CGWindowID = 0
    var onOCRCapture: ((Observation) -> Void)?
    var onInterrupt: (() -> Void)?
    var onStop: (() -> Void)?
    var beforeOperation: (() async throws -> Void)?
    var armed = false
    /// One-shot capture of the user's next click, used to learn where the style control is.
    var onRecordedClick: ((CGPoint) -> Void)?
    private var recordingFor: WindowChoice?

    init() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved], handler: { [weak self] event in
            guard let self, event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.eventTag else { return }
            if self.detectionHotkey.available, event.type == .keyDown, event.keyCode == 109,
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty { return }
            if let window = self.recordingFor, event.type == .leftMouseDown {
                self.recordingFor = nil
                let screen = NSEvent.mouseLocation
                let top = (NSScreen.screens.first?.frame.height ?? 0) - screen.y
                let point = CGPoint(x: (screen.x - window.frame.minX) / window.frame.width,
                                    y: (top - window.frame.minY) / window.frame.height)
                if (0...1).contains(point.x), (0...1).contains(point.y) { self.onRecordedClick?(point) }
                return
            }
            guard self.armed else { return }
            if event.type == .keyDown, event.keyCode == 53 {
                self.armed = false; self.onStop?(); return
            }
            // Pause at the next operation boundary; a short in-flight gesture finishes first.
            self.onInterrupt?()
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            // Some event sources deliver directly to the app instead of through Carbon's hotkey
            // dispatcher. Consume that local path as well; registered global events never reach it.
            if event.keyCode == 109, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                if !event.isARepeat { self?.detectionHotkey.action?() }
                return nil
            }
            if event.keyCode == 53, self?.armed == true {
                self?.armed = false; self?.onStop?(); return nil
            }
            return event
        }) { monitors.append(monitor) }
        // Edit Assist is frontmost whenever the user is typing here, so remember the editor they came from.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  TargetApp.matches(app) else { return }
            MainActor.assumeIsolated { self?.lastActivePID = app.processIdentifier }
        }
    }

    func recordNextClick(in window: WindowChoice) { recordingFor = window }
    func cancelRecording() { recordingFor = nil }

    var canCapture: Bool { CGPreflightScreenCaptureAccess() }
    var canControl: Bool { AXIsProcessTrusted() }
    func requestCapture() { CGRequestScreenCaptureAccess() }
    func requestControl() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    // macOS shows its own prompt only once per app, so always offer the Settings pane as well.
    func openScreenSettings() { openSettings("Privacy_ScreenCapture") }
    func openControlSettings() { openSettings("Privacy_Accessibility") }
    private func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
    var bundlePath: String { Bundle.main.bundleURL.path }
    /// An ad-hoc signature pins a cdhash that changes every build, so grants do not survive one.
    var signingSummary: (name: String, stable: Bool) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code else {
            return ("unknown", false)
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return ("unknown", false) }
        if let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first,
           let name = SecCertificateCopySubjectSummary(leaf) as String? {
            return (name, true)
        }
        return ("ad-hoc", false)
    }

    /// Clears this bundle's TCC rows, including orphans left by an earlier copy or signature,
    /// so the next request produces a genuine system prompt instead of matching a dead entry.
    func resetPermissions() {
        let id = Bundle.main.bundleIdentifier ?? "com.crossian.editassist"
        for service in ["ScreenCapture", "Accessibility"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, id]
            try? process.run()
            process.waitUntilExit()
        }
        relaunch()
    }

    /// Screen recording only takes effect in a fresh process.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// The supported editor the user worked in most recently. Other apps are ignored outright.
    func activeApp() -> (pid: pid_t, name: String)? {
        if lastActivePID != 0, let app = NSRunningApplication(processIdentifier: lastActivePID),
           !app.isTerminated, TargetApp.matches(app) {
            return (lastActivePID, app.localizedName ?? TargetApp.label)
        }
        lastActivePID = 0
        // Nothing suitable has activated since launch: window-server order is front to back.
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for row in rows {
            guard (row[kCGWindowLayer as String] as? Int) == 0,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = NSRunningApplication(processIdentifier: pid), TargetApp.matches(app) else { continue }
            lastActivePID = pid
            return (pid, app.localizedName ?? TargetApp.label)
        }
        return nil
    }

    /// The largest ordinary window of that app, which is the one being edited in.
    func detectTarget() async throws -> WindowChoice? {
        guard canCapture else { throw AssistError.message("Enable Screen Recording so Edit Assist can see your editor. macOS may require quitting and reopening the app.") }
        guard let active = activeApp() else { return nil }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let candidates = content.windows.filter {
            $0.owningApplication?.processID == active.pid && $0.windowLayer == 0 && $0.frame.width > 300 && $0.frame.height > 200
        }
        guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return nil }
        return WindowChoice(id: window.windowID, pid: active.pid, title: window.title ?? active.name,
                            app: window.owningApplication?.applicationName ?? active.name, frame: window.frame)
    }

    /// `sharper` captures at twice the window's point size, for text that reads poorly at the usual
    /// size, such as captions with heavy outlines. Reading takes correspondingly longer.
    func capture(_ choice: WindowChoice, readText: Bool = false, notifyOCR: Bool = true, sharper: Bool = false) async throws -> Observation {
        try await beforeOperation?()
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == choice.id && $0.owningApplication?.processID == choice.pid }) else {
            throw AssistError.message("That window has closed. Click the window you want to work in, then try again.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = sharper ? 2 : min(1.5, 2400 / window.frame.width)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.includeChildWindows = false
        config.captureResolution = .best
        // The same colour space as the live stream, so a screenshot and a streamed frame of an unchanged
        // window compare as equal; the row tracker measures scrolling from such comparisons.
        config.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        var updated = choice
        updated.frame = window.frame
        updated.title = window.title ?? choice.title
        // Recognition takes about a third of a second on a full window; doing it off the main thread
        // keeps the app and the overlay responsive while it reads.
        let text = readText ? await Task.detached(priority: .userInitiated) { Desktop.recognize(image) }.value : []
        let observation = Observation(image: image, window: updated, text: text)
        try Task.checkCancellation()
        if readText && notifyOCR { onOCRCapture?(observation) }
        return observation
    }

    /// Models estimate normalized coordinates poorly from a bare screenshot, which shows up as
    /// clicks landing near but not on the target. A faint labelled grid gives them reference lines.
    /// Only the copy sent to the model is annotated; the raw CGImage still backs the UI and style crop.
    static func gridded(_ image: CGImage) -> Data? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.width, pixelsHigh: image.height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let line = max(1, width / 2000)
        cg.setLineWidth(line)
        cg.setStrokeColor(CGColor(red: 1, green: 0.25, blue: 0.85, alpha: 0.32))
        for step in 1...9 {
            let fraction = CGFloat(step) / 10
            cg.move(to: CGPoint(x: width * fraction, y: 0))
            cg.addLine(to: CGPoint(x: width * fraction, y: height))
            cg.move(to: CGPoint(x: 0, y: height * fraction))
            cg.addLine(to: CGPoint(x: width, y: height * fraction))
        }
        cg.strokePath()
        let size = max(11, width / 150)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold),
            .foregroundColor: NSColor(red: 1, green: 0.25, blue: 0.85, alpha: 0.95),
            .backgroundColor: NSColor(white: 0, alpha: 0.65)
        ]
        for step in 1...9 {
            let fraction = CGFloat(step) / 10
            let text = String(format: "%.1f", fraction)
            // Cocoa draws from the bottom left, so y labels are flipped into top-left image terms.
            NSAttributedString(string: text, attributes: attributes)
                .draw(at: NSPoint(x: width * fraction + line + 1, y: height - size - 4))
            NSAttributedString(string: text, attributes: attributes)
                .draw(at: NSPoint(x: 3, y: height * (1 - fraction) + line + 1))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// On-device text recognition. Roughly half a second for a full window, against ~25s for a model
    /// round trip, and it returns measured boxes instead of an estimate, which is what fixes misclicks.
    nonisolated static func recognize(_ image: CGImage) -> [TextHit] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil,
              let results = request.results else { return [] }
        return results.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            // Vision reports a bottom-left origin; everything else in this app is top-left.
            func flip(_ box: CGRect) -> CGRect {
                CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            }
            var words: [(String, CGRect)] = []
            for word in text.split(separator: " ") where word.count > 1 {
                if let range = text.range(of: word), let box = try? candidate.boundingBox(for: range) {
                    words.append((String(word), flip(box.boundingBox)))
                }
            }
            return TextHit(text: text, rect: flip(observation.boundingBox), words: words)
        }
    }

    /// The exact drag a human would make to select `phrase`, derived from measured character boxes.
    struct Span {
        var start: CGPoint
        var end: CGPoint
        /// Centre of the first word. Double-clicking here selects a word; the midpoint of the whole
        /// span can land in the gap between words and only drops a caret.
        var firstWord: CGPoint
    }

    /// Words with punctuation stripped. Single characters are dropped because OCR routinely reads
    /// a capital I as a pipe, and a one-letter token is never what distinguishes a phrase.
    static func normalized(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
    }

    /// Groups recognised lines into blocks: similar size, overlapping columns, vertically adjacent.
    /// A caption that wraps onto a second line is one block, which is what lets a phrase be selected
    /// across the wrap instead of being skipped.
    static func blocks(of hits: [TextHit]) -> [[TextHit]] {
        var groups: [[TextHit]] = []
        for hit in hits.sorted(by: { $0.rect.minY < $1.rect.minY }) {
            var placed = false
            for index in groups.indices.reversed() {
                guard let previous = groups[index].last else { continue }
                let sameSize = abs(previous.rect.height - hit.rect.height) < previous.rect.height * 0.5
                let adjacent = hit.rect.minY - previous.rect.maxY < previous.rect.height * 1.3
                let overlapping = min(previous.rect.maxX, hit.rect.maxX) > max(previous.rect.minX, hit.rect.minX)
                if sameSize, adjacent, overlapping { groups[index].append(hit); placed = true; break }
            }
            if !placed { groups.append([hit]) }
        }
        return groups
    }

    static func selection(for phrase: String, in hits: [TextHit]) -> Span? {
        selection(forTokens: normalized(phrase), in: hits).flatMap {
            $0.matched == normalized(phrase).count ? $0.span : nil
        }
    }

    /// Selects as much of `needle` as is actually on screen, longest first. Premiere splits a long
    /// phrase across caption clips, so a pass styles the visible part and reports how many words it
    /// covered; the caller carries the remainder to the next clip.
    /// `minHeight`: the smallest a caption line can be, once a caption has been seen on this screen.
    /// `area`: where captions have appeared on this screen; text elsewhere (the timeline) is never one.
    static func selection(forTokens needle: [String], in hits: [TextHit], minHeight: CGFloat = 0, area: CGRect? = nil) -> (span: Span, matched: Int)? {
        guard !needle.isEmpty else { return nil }
        var length = needle.count
        while length >= 1 {
            if let span = span(of: Array(needle.prefix(length)), in: hits, minHeight: minHeight, area: area) {
                // A one-word partial is weak evidence: "65" occurs in "After 65" as well as in
                // "65% OFF", and matching it there restyles the wrong caption. A partial needs two
                // words; finishing a phrase whose remainder is a single word is still fine.
                if length < needle.count, length < 2 { return nil }
                return (span, length)
            }
            length -= 1
        }
        return nil
    }

    /// Shared with the inspection overlay so its labels show the actual matcher filter.
    static func captionBlocks(in hits: [TextHit], minHeight: CGFloat = 0, area: CGRect? = nil) -> [[TextHit]] {
        // The caption we can actually edit is the one rendered in the Program Monitor, which is video
        // content and far larger than interface text. The same words also appear in the Properties
        // panel's caption field and in timeline clip labels, where selecting them edits nothing, so
        // anything close to ordinary interface size is excluded.
        let heights = hits.map(\.rect.height).sorted()
        let interface = heights.isEmpty ? 0 : heights[heights.count / 2]
        let floor = interface * 1.8
        let all = blocks(of: hits).sorted { ($0.first?.rect.height ?? 0) > ($1.first?.rect.height ?? 0) }
        // Nothing larger than interface text means no caption is readable right now: never fall back to
        // the largest interface text. That once picked a caption clip's label in the timeline, and the
        // click, double-click and drag that followed moved the clip over its neighbour, deleting it.
        // With only a few lines in view there is no interface text to measure against (a cropped test
        // image, not Premiere's window), so nothing can be told apart and all are candidates.
        guard hits.count >= 3 else { return all }
        // The interface measure moves with how much small text was read (a sharper capture reads more),
        // so a caption height already seen on this screen sets a floor of its own.
        return all.filter { block in
            guard let first = block.first, first.rect.height >= max(floor, minHeight) else { return false }
            // Height alone can be close: two timeline labels read as one line came to 0.021 against a
            // 0.031 caption. Position cannot be: the timeline is nowhere near the Program Monitor.
            if let area { return block.contains { $0.rect.intersects(area) } }
            return true
        }
    }

    private static func span(of needle: [String], in hits: [TextHit], minHeight: CGFloat = 0, area: CGRect? = nil) -> Span? {
        guard !needle.isEmpty else { return nil }
        let ordered = captionBlocks(in: hits, minHeight: minHeight, area: area)
        for block in ordered {
            // Words of the whole block in reading order, so a phrase may span the wrap.
            // One recognised word can normalize to several tokens: "ultra-light" is "ultra" and
            // "stretch". Each token keeps its word's box, so a phrase starting mid-hyphenation still
            // resolves to a real position.
            var words: [(text: String, rect: CGRect, line: CGRect)] = []
            for line in block {
                if line.words.isEmpty {
                    for token in normalized(line.text) { words.append((token, line.rect, line.rect)) }
                } else {
                    for word in line.words {
                        for token in normalized(word.0) { words.append((token, word.1, line.rect)) }
                    }
                }
            }
            guard words.count >= needle.count else { continue }
            for start in 0...(words.count - needle.count) {
                let slice = words[start ..< start + needle.count]
                guard slice.map(\.text) == needle else { continue }
                guard let head = slice.first, let tail = slice.last else { continue }
                // Each token remembers the line it was read on. Heights alone fail for large captions set
                // tight, where two lines' centres can be closer than one line is tall; a line's own words
                // must also sit level, or they are not one line however they were read.
                let sameLine = head.line == tail.line && abs(tail.rect.midY - head.rect.midY) < max(head.rect.height, tail.rect.height)
                if sameLine {
                    // No whole-line fallback: a span wider than its line means the words came from
                    // different places, and selecting a whole caption would restyle unmarked text.
                    guard tail.rect.maxX > head.rect.minX,
                          tail.rect.maxX - head.rect.minX <= head.line.width + 0.001 else { continue }
                } else {
                    // Wrapped: the drag runs from the first word down to the last, as a person would.
                    // A gap of more than a couple of lines is not a wrap, it is two unrelated places.
                    guard tail.rect.midY > head.rect.midY,
                          tail.rect.minY - head.rect.maxY < head.rect.height * 3 else { continue }
                }
                return Span(start: CGPoint(x: head.rect.minX, y: head.rect.midY),
                            end: CGPoint(x: tail.rect.maxX, y: tail.rect.midY),
                            firstWord: CGPoint(x: head.rect.midX, y: head.rect.midY))
            }
        }
        return nil
    }

    /// How many of the phrase's leading words are present on screen. A caption clip holds only part
    /// of a long phrase, so a partial count tells the difference between "not on screen at all" and
    /// "this phrase is split across caption clips".
    static func coverage(for phrase: String, in hits: [TextHit]) -> (matched: Int, total: Int) {
        let needle = normalized(phrase)
        guard !needle.isEmpty else { return (0, 0) }
        var best = 0
        for block in blocks(of: hits) {
            var words: [String] = []
            for line in block {
                if line.words.isEmpty { words += normalized(line.text) }
                else { for word in line.words { words += normalized(word.0) } }
            }
            // The longest run shared with the phrase, anchored anywhere in either: a caption may
            // hold the tail of a phrase whose head sits on the previous clip.
            for start in words.indices {
                for offset in needle.indices {
                    var length = 0
                    while start + length < words.count, offset + length < needle.count,
                          words[start + length] == needle[offset + length] { length += 1 }
                    best = max(best, length)
                }
            }
        }
        return (best, needle.count)
    }

    /// The timeline clip holding the caption that contains `phrase`, found by matching the clip's
    /// truncated label against the caption text. Premiere will not edit a caption until its clip is
    /// selected, so this is clicked with the Selection tool before any text is touched.
    static func captionClip(for phrase: String, in hits: [TextHit]) -> CGRect? {
        let needle = normalized(phrase)
        // Anchor on the largest match: the same words appear in the Program Monitor caption and in a
        // small timeline label, and anchoring on the label leaves nothing smaller to find.
        guard !needle.isEmpty,
              let caption = hits
                .filter({ normalized($0.text).joined(separator: " ").contains(needle.joined(separator: " ")) })
                .max(by: { $0.rect.height < $1.rect.height })
        else { return nil }
        // Lines of similar size, in the same column, and vertically adjacent form one caption block.
        // Without the proximity test any same-sized text anywhere in the window joins the block and
        // the word list becomes meaningless.
        let reach = caption.rect.height * 3
        let block = hits
            .filter { abs($0.rect.height - caption.rect.height) < caption.rect.height * 0.5
                      && abs($0.rect.midX - caption.rect.midX) < 0.35
                      && $0.rect.minY > caption.rect.minY - reach
                      && $0.rect.maxY < caption.rect.maxY + reach }
            .sorted { $0.rect.minY < $1.rect.minY }
        let full = block.flatMap { normalized($0.text) }
        guard !full.isEmpty else { return nil }
        // Longest run of caption words the label reproduces in order. A timeline label is a
        // truncation of the caption, so it shares a run with it but is much smaller on screen.
        func run(_ label: [String]) -> Int {
            guard !label.isEmpty else { return 0 }
            var best = 0
            for start in full.indices {
                var length = 0
                while start + length < full.count, length < label.count, full[start + length] == label[length] { length += 1 }
                best = max(best, length)
            }
            if best == 0, let first = label.first, let at = full.firstIndex(of: first) {
                var length = 0
                while at + length < full.count, length < label.count, full[at + length] == label[length] { length += 1 }
                best = length
            }
            return best
        }
        var winner: (rect: CGRect, score: Int)?
        for hit in hits where hit.rect.height < caption.rect.height * 0.85 && !block.contains(hit) {
            let score = run(normalized(hit.text))
            guard score >= 2 else { continue }
            if winner == nil || score > winner!.score { winner = (hit.rect, score) }
        }
        return winner?.rect
    }

    /// A labelled numeric field, such as Premiere's "Font Size 65". Returns the number's own box so
    /// it can be clicked, which selects the value ready to be overtyped.
    /// Re-reads one labelled row at several magnifications and takes the majority value. Premiere
    /// draws the font size as a small isolated number, which a whole-window pass can miss entirely;
    /// worse, a two-digit number has no unambiguous orientation — "60" upside down reads as "09" —
    /// and recognition picks differently at different scales, so one reading cannot be trusted.
    static func numberField(labelled label: String, in hits: [TextHit], image: CGImage) -> (rect: CGRect, value: Int)? {
        if let direct = numberField(labelled: label, in: hits) { return direct }
        let key = normalized(label).joined(separator: " ")
        guard !key.isEmpty, let row = hits.first(where: { normalized($0.text).joined(separator: " ") == key }) else { return nil }
        let pad = row.rect.height * 0.7
        let strip = CGRect(x: max(0, row.rect.minX - 0.01), y: max(0, row.rect.minY - pad),
                           width: min(0.999 - row.rect.minX, 1), height: row.rect.height + pad * 2)
        let pixels = CGRect(x: strip.minX * CGFloat(image.width), y: strip.minY * CGFloat(image.height),
                            width: strip.width * CGFloat(image.width), height: strip.height * CGFloat(image.height))
        guard pixels.width > 20, pixels.height > 6 else { return nil }

        var votes: [Int: Int] = [:]
        var boxes: [Int: CGRect] = [:]
        for scale in [1, 2, 3, 4, 6] {
            let wide = Int(pixels.width) * scale, tall = Int(pixels.height) * scale
            guard wide < 12000, tall < 4000 else { continue }
            var buffer = patch(of: image, rect: pixels, width: wide, height: tall)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wide, pixelsHigh: tall,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: wide * 4, bitsPerPixel: 32),
                  let destination = rep.bitmapData else { continue }
            memcpy(destination, buffer, buffer.count)
            buffer.removeAll()
            guard let magnified = rep.cgImage else { continue }
            for hit in recognize(magnified) {
                let text = hit.text.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, text.allSatisfy(\.isNumber), let value = Int(text), value >= 4, value <= 400 else { continue }
                votes[value, default: 0] += 1
                let box = CGRect(x: strip.minX + hit.rect.minX * strip.width,
                                 y: strip.minY + hit.rect.minY * strip.height,
                                 width: hit.rect.width * strip.width, height: hit.rect.height * strip.height)
                if boxes[value] == nil { boxes[value] = box }   // first (smallest) scale wins
            }
        }
        guard let winner = votes.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key,
              let box = boxes[winner] else { return nil }
        return (box, winner)
    }

    static func numberField(labelled label: String, in hits: [TextHit]) -> (rect: CGRect, value: Int)? {
        let key = normalized(label).joined(separator: " ")
        guard !key.isEmpty, let row = hits.first(where: { normalized($0.text).joined(separator: " ") == key }) else { return nil }
        let sameRow = hits.filter {
            $0.rect.minX >= row.rect.maxX - 0.002
            && abs($0.rect.midY - row.rect.midY) < max(row.rect.height, $0.rect.height) * 0.9
        }
        let numbers = sameRow.compactMap { hit -> (CGRect, Int)? in
            let text = hit.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.allSatisfy(\.isNumber), let value = Int(text) else { return nil }
            return (hit.rect, value)
        }
        // The value sits at the far right of the row.
        guard let best = numbers.max(by: { $0.0.minX < $1.0.minX }) else { return nil }
        return (best.0, best.1)
    }

    // MARK: - Finding controls without recording a position

    /// Grayscale samples on a fixed grid. A bitmap context stores rows top-down, so row 0 is the top
    /// of the image and matches the top-left normalized coordinates used everywhere else.
    static func grid(_ image: CGImage, width: Int = 700, height: Int = 460) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: width * height)
        buffer.withUnsafeMutableBytes { raw in
            if let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                       bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        return buffer
    }

    /// The last icon-shaped control on a row, for buttons OCR cannot see, such as Premiere's
    /// four-square style button. The row band is sampled at native resolution — downscaling a whole
    /// window to a few hundred pixels smears a 20px icon into the background — and clusters are
    /// filtered to roughly square, icon-sized ones so a scrollbar or panel edge is not mistaken for it.
    static func lastControl(onRowOf anchor: CGRect, in image: CGImage, before limit: CGFloat = 1.0) -> CGPoint? {
        let imageWidth = CGFloat(image.width), imageHeight = CGFloat(image.height)
        let centre = anchor.midY * imageHeight
        let band = max(10, anchor.height * imageHeight * 1.8)
        let top = max(0, Int(centre - band / 2))
        let height = min(image.height - top, Int(band))
        let left = min(image.width - 1, Int(anchor.maxX * imageWidth) + 2)
        let right = min(image.width, Int(limit * imageWidth))
        guard height > 2, right - left > 8 else { return nil }

        let width = right - left
        var samples = [UInt8](repeating: 0, count: width * height)
        samples.withUnsafeMutableBytes { raw in
            if let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                       bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                context.draw(image, in: CGRect(x: -CGFloat(left), y: -(imageHeight - CGFloat(top) - CGFloat(height)),
                                               width: imageWidth, height: imageHeight))
            }
        }
        var column = [Int](repeating: 0, count: width)
        for x in 0..<width { for y in 0..<height { column[x] = max(column[x], Int(samples[y * width + x])) } }
        let background = column.sorted()[column.count / 2]
        let inked = column.map { abs($0 - background) > 24 }

        // Group inked columns into clusters, tolerating a small gap inside one glyph.
        var clusters: [(start: Int, end: Int)] = []
        var index = 0
        while index < width {
            guard inked[index] else { index += 1; continue }
            var end = index
            var gap = 0
            var scan = index + 1
            while scan < width {
                if inked[scan] { end = scan; gap = 0 }
                else { gap += 1; if gap > max(2, height / 6) { break } }
                scan += 1
            }
            clusters.append((index, end))
            index = end + 1
        }
        /// How many rows of the band this cluster actually paints. A scrollbar or panel divider runs
        /// the full height of the band; a button glyph does not.
        func verticalExtent(_ cluster: (start: Int, end: Int)) -> Int {
            var top = height, bottom = -1
            for y in 0..<height {
                var any = false
                for x in cluster.start...cluster.end where abs(Int(samples[y * width + x]) - background) > 24 { any = true; break }
                if any { top = min(top, y); bottom = max(bottom, y) }
            }
            return bottom >= top ? bottom - top + 1 : 0
        }
        // A button is roughly square and sits inside the row. A scrollbar is narrow and full height,
        // and simply taking the rightmost cluster picks it instead of the button.
        let candidates = clusters.filter {
            let span = $0.end - $0.start + 1
            guard span >= height / 3, span <= height * 2 else { return false }
            let tall = verticalExtent($0)
            guard tall > 0, tall <= Int(Double(height) * 0.85) else { return false }
            let ratio = Double(span) / Double(tall)
            return ratio >= 0.5 && ratio <= 2.0
        }
        guard let pick = candidates.last else { return nil }
        let x = (CGFloat(left) + (CGFloat(pick.start) + CGFloat(pick.end)) / 2) / imageWidth
        return CGPoint(x: x, y: anchor.midY)
    }

    /// Colour samples, four bytes per pixel. Style tiles differ mainly by hue: a blue and a pink
    /// swatch are only 0.085 apart in luminance, so matching them in grayscale picks the wrong tile.
    static func colourGrid(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            if let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        return buffer
    }

    /// A region of `image` resampled to width x height, in RGBA. `rect` is in top-left pixels.
    static func patch(of image: CGImage, rect: CGRect, width: Int, height: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            let scaleX = CGFloat(width) / rect.width, scaleY = CGFloat(height) / rect.height
            let bottom = CGFloat(image.height) - rect.maxY
            context.draw(image, in: CGRect(x: -rect.minX * scaleX, y: -bottom * scaleY,
                                           width: CGFloat(image.width) * scaleX, height: CGFloat(image.height) * scaleY))
        }
        return buffer
    }

    /// Colour difference plus an edge-difference term. Style tiles can share a hue and a typeface and
    /// differ only in stroke weight; stroke shows up in the gradients, not in the average colour, so
    /// edges are weighted to separate tiles that otherwise look identical.
    static func detailScore(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int) -> Int {
        var colour = 0, edges = 0, count = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                colour += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
                if x + 1 < width {
                    let j = (y * width + x + 1) * 4
                    let gradientA = abs(Int(a[j]) - Int(a[i])) + abs(Int(a[j + 1]) - Int(a[i + 1])) + abs(Int(a[j + 2]) - Int(a[i + 2]))
                    let gradientB = abs(Int(b[j]) - Int(b[i])) + abs(Int(b[j + 1]) - Int(b[i + 1])) + abs(Int(b[j + 2]) - Int(b[i + 2]))
                    edges += abs(gradientA - gradientB)
                }
                count += 1
            }
        }
        guard count > 0 else { return Int.max }
        return colour / (count * 3) + 2 * (edges / (count * 3))
    }

    /// Locates a small reference image inside a capture, so the chosen style tile is found by how it
    /// looks rather than where it was clicked. A coarse colour sweep over several scales proposes
    /// candidates, then every candidate is rescored at the reference's own resolution, where stroke
    /// weight is still visible. Returns the best score too, so a near miss can be reported.
    static func styleCandidates(_ template: CGImage, in image: CGImage, minX: CGFloat = 0) -> [StyleMatch] {
        let width = 700, height = 460
        let scene = colourGrid(image, width: width, height: height)
        let baseWidth = CGFloat(template.width) / CGFloat(image.width) * CGFloat(width)
        let baseHeight = CGFloat(template.height) / CGFloat(image.height) * CGFloat(height)
        var proposals: [(x: Int, y: Int, tileWidth: Int, tileHeight: Int)] = []

        // A resized Properties panel renders tiles well outside a narrow range: on a real
        // capture the reference was 1.4x the tile actually on screen.
        for scale in [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 1.15, 1.3, 1.5] as [CGFloat] {
            let tileWidth = Int(baseWidth * scale), tileHeight = Int(baseHeight * scale)
            guard tileWidth >= 6, tileHeight >= 6, tileWidth < width / 2, tileHeight < height / 2 else { continue }
            let patchGrid = colourGrid(template, width: tileWidth, height: tileHeight)
            var scored: [(score: Int, x: Int, y: Int)] = []
            // Abandon a position as soon as it is worse than the worst candidate worth keeping,
            // which is what makes a nine-scale sweep affordable.
            var ceiling = Int.max
            var column = max(0, Int(minX * CGFloat(width)))
            while column + tileWidth < width {
                var row = 0
                while row + tileHeight < height {
                    var total = 0, count = 0, sampleRow = 0
                    var abandoned = false
                    while sampleRow < tileHeight {
                        var sampleColumn = 0
                        while sampleColumn < tileWidth {
                            let a = ((row + sampleRow) * width + column + sampleColumn) * 4
                            let b = (sampleRow * tileWidth + sampleColumn) * 4
                            total += abs(Int(scene[a]) - Int(patchGrid[b]))
                                + abs(Int(scene[a + 1]) - Int(patchGrid[b + 1]))
                                + abs(Int(scene[a + 2]) - Int(patchGrid[b + 2]))
                            count += 1
                            sampleColumn += 4
                        }
                        sampleRow += 4
                        // Only prune using a lower bound on the FINAL score. A partial
                        // average can reject a good tile merely because its top edge differs.
                        let totalSamples = ((tileHeight + 3) / 4) * ((tileWidth + 3) / 4)
                        if ceiling != Int.max, total / (totalSamples * 3) > ceiling { abandoned = true; break }
                    }
                    if !abandoned, count > 0 {
                        let score = total / (count * 3)
                        scored.append((score, column, row))
                        if scored.count > 48 {
                            scored.sort { $0.score < $1.score }
                            scored.removeLast(scored.count - 24)
                            ceiling = scored.last?.score ?? Int.max
                        }
                    }
                    row += 4
                }
                column += 4
            }
            // Keep the best few well-separated positions for THIS scale. Deduping against other
            // scales would be wrong: the same position at a different size is a different candidate,
            // and it is exactly the one that wins when the panel has been resized.
            var atThisScale: [(x: Int, y: Int)] = []
            for entry in scored.sorted(by: { $0.score < $1.score }) {
                guard atThisScale.count < 6, proposals.count < 64 else { break }
                let clash = atThisScale.contains {
                    abs($0.x - entry.x) < tileWidth / 2 && abs($0.y - entry.y) < tileHeight / 2
                }
                guard !clash else { continue }
                atThisScale.append((entry.x, entry.y))
                proposals.append((entry.x, entry.y, tileWidth, tileHeight))
            }
        }

        let reference = colourGrid(template, width: template.width, height: template.height)
        var candidates: [StyleMatch] = []
        for proposal in proposals {
            let rect = CGRect(x: CGFloat(proposal.x) / CGFloat(width) * CGFloat(image.width),
                              y: CGFloat(proposal.y) / CGFloat(height) * CGFloat(image.height),
                              width: CGFloat(proposal.tileWidth) / CGFloat(width) * CGFloat(image.width),
                              height: CGFloat(proposal.tileHeight) / CGFloat(height) * CGFloat(image.height))
            guard rect.width >= 4, rect.height >= 4 else { continue }
            let region = patch(of: image, rect: rect, width: template.width, height: template.height)
            let score = detailScore(region, reference, width: template.width, height: template.height)
            candidates.append(StyleMatch(rect: CGRect(x: rect.minX / CGFloat(image.width), y: rect.minY / CGFloat(image.height),
                                                       width: rect.width / CGFloat(image.width), height: rect.height / CGFloat(image.height)), score: score))
        }
        return distinctStyles(candidates)
    }

    struct StyleMatch {
        let rect: CGRect
        let score: Int
        var point: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    }

    /// Multiple scales at one tile are one candidate, not competing styles.
    static func distinctStyles(_ candidates: [StyleMatch]) -> [StyleMatch] {
        var result: [StyleMatch] = []
        for candidate in candidates.sorted(by: { $0.score < $1.score }) {
            if result.contains(where: {
                abs($0.point.x - candidate.point.x) < min($0.rect.width, candidate.rect.width) * 0.5 &&
                abs($0.point.y - candidate.point.y) < min($0.rect.height, candidate.rect.height) * 0.5
            }) { continue }
            result.append(candidate)
        }
        return result
    }

    // Heuristic distance margin, not a probability or calibrated confidence percentage.
    static let styleSeparation = 5
    static func unambiguousStyle(_ candidates: [StyleMatch]) -> StyleMatch? {
        let ranked = distinctStyles(candidates)
        guard let best = ranked.first, best.score < styleMatchLimit else { return nil }
        if ranked.count > 1, ranked[1].score - best.score < styleSeparation { return nil }
        return best
    }

    @MainActor
    /// The tiles of the style browser, found from their own "Ag" labels: every preset renders as
    /// "Ag", so OCR draws a box on each one. Their union is the scrollable grid.
    private static func isTileLabel(_ token: String) -> Bool {
        // "ag", or tiles merged without a space ("agag"); serif presets read as "aơ", "ad", "aa".
        let letters = Array(token)
        guard letters.count >= 2, letters.count % 2 == 0 else { return false }
        return stride(from: 0, to: letters.count, by: 2).allSatisfy { letters[$0] == "a" }
    }

    /// Whether an OCR line is only style-tile labels ("Ag", or a merged "Ag Ag") inside the browser.
    static func isStyleTileHit(_ hit: TextHit, left: CGFloat) -> Bool {
        let tokens = normalized(hit.text)
        // The first column starts left of the browser's own labels, so allow some margin.
        return hit.rect.minX >= left - 0.08 && !tokens.isEmpty && tokens.allSatisfy(isTileLabel)
    }

    static func styleGridArea(in hits: [TextHit], left: CGFloat) -> CGRect? {
        let tiles = hits.filter { hit in
            let tokens = normalized(hit.text)
            return hit.rect.minX >= left - 0.01 && !tokens.isEmpty && tokens.allSatisfy(isTileLabel)
        }
        guard let first = tiles.first else { return nil }
        return tiles.dropFirst().reduce(first.rect) { $0.union($1.rect) }
    }

    /// Tiles visible right now. A merged OCR box such as "Ag Ag" counts as two.
    static func styleTileCount(in hits: [TextHit], left: CGFloat) -> Int {
        hits.filter { $0.rect.minX >= left - 0.01 }
            .reduce(0) { $0 + normalized($1.text).filter(isTileLabel).reduce(0) { $0 + $1.count / 2 } }
    }

    /// Mean colour difference of one region between two captures. Used to tell whether a scroll
    /// moved the style browser; it does not move once the list has reached its end.
    static func regionDifference(_ a: CGImage, _ b: CGImage, rect: CGRect) -> Int {
        func pixels(_ image: CGImage) -> CGRect {
            CGRect(x: rect.minX * CGFloat(image.width), y: rect.minY * CGFloat(image.height),
                   width: rect.width * CGFloat(image.width), height: rect.height * CGFloat(image.height))
        }
        let side = 96
        let first = patch(of: a, rect: pixels(a), width: side, height: side)
        let second = patch(of: b, rect: pixels(b), width: side, height: side)
        var total = 0
        for i in stride(from: 0, to: first.count, by: 4) {
            total += abs(Int(first[i]) - Int(second[i])) + abs(Int(first[i + 1]) - Int(second[i + 1])) + abs(Int(first[i + 2]) - Int(second[i + 2]))
        }
        return total / (side * side * 3)
    }

    /// The style browser's tiles as rows of cells, top to bottom and left to right. Found from the
    /// pixels rather than the "Ag" OCR boxes, which merge neighbouring tiles or miss some entirely:
    /// the gaps between tiles are flat panel background, so a column or row whose brightness barely
    /// varies is a gap, and everything between gaps is a tile. OCR only says where the grid is.
    static func styleCells(in hits: [TextHit], image: CGImage, left: CGFloat) -> [[CGRect]] {
        styleGrid(in: hits, image: image, left: left).cells
    }

    /// The grid plus whether the browser is scrolled to the top, judged from this one look: scrolled,
    /// a cut-off row of tiles sits between the Open Projects box and the first full row; at the top
    /// that strip holds only the box edge, a separator and flat background. Nil when it cannot tell.
    static func styleGrid(in hits: [TextHit], image: CGImage, left: CGFloat) -> (cells: [[CGRect]], atTop: Bool?) {
        let labels = hits.filter { hit in
            let tokens = normalized(hit.text)
            return hit.rect.minX >= left - 0.08 && !tokens.isEmpty && tokens.allSatisfy(isTileLabel)
        }
        guard let first = labels.first else { return ([], nil) }
        let seed = labels.dropFirst().reduce(first.rect) { $0.union($1.rect) }
        let boxHeight = labels.map(\.rect.height).sorted()[labels.count / 2]
        let boxWidth = labels.map { $0.rect.width / CGFloat(max(1, normalized($0.text).count)) }.sorted()[labels.count / 2]
        var region = CGRect(x: seed.minX - boxWidth * 0.45, y: seed.minY - boxHeight * 0.7,
                            width: seed.width + boxWidth * 0.9, height: seed.height + boxHeight * 1.4)
        // Reach up to the Open Projects box, so a row cut off at the top of the view is inside the
        // region and can be told apart from the flat strip that sits there at the top of the list.
        let header = hits.filter { hit in
            let text = normalized(hit.text).joined(separator: " ")
            return (text.contains("open projects") || text.contains("local styles")) && hit.rect.maxY <= seed.minY
        }.max { $0.rect.maxY < $1.rect.maxY }
        if let header { region = region.union(CGRect(x: region.minX, y: header.rect.maxY + header.rect.height * 0.6, width: region.width, height: 0.0001)) }
        region = region.intersection(CGRect(x: max(0, left - 0.01), y: 0, width: 1, height: 1))
        guard !region.isNull, region.width > 0.02, region.height > 0.02 else { return ([], nil) }
        let pixels = CGRect(x: region.minX * CGFloat(image.width), y: region.minY * CGFloat(image.height),
                            width: region.width * CGFloat(image.width), height: region.height * CGFloat(image.height))
        let width = max(8, Int(pixels.width / 2)), height = max(8, Int(pixels.height / 2))
        let rgba = patch(of: image, rect: pixels, width: width, height: height)
        var luma = [Int](repeating: 0, count: width * height)
        for i in 0 ..< width * height {
            luma[i] = (Int(rgba[i * 4]) * 30 + Int(rgba[i * 4 + 1]) * 59 + Int(rgba[i * 4 + 2]) * 11) / 100
        }
        var histogram = [Int](repeating: 0, count: 256)
        for value in luma { histogram[value] += 1 }
        let tileLevel = histogram.indices.max { histogram[$0] < histogram[$1] } ?? 0
        func runs(_ share: [Double]) -> [(Int, Int)] {
            var found: [(Int, Int)] = []
            var index = 0
            while index < share.count {
                guard share[index] < 0.6 else { index += 1; continue }
                var end = index
                while end + 1 < share.count, share[end + 1] < 0.6 { end += 1 }
                found.append((index, end))
                index = end + 1
            }
            return found
        }
        /// Gaps are columns and rows that are mostly the given background level. A separator line or
        /// a sliver of another control crossing a gap only lowers that share a little.
        func grid(_ background: Int) -> (columns: [(Int, Int)], rows: [(Int, Int)]) {
            func isBackground(_ value: Int) -> Bool { abs(value - background) <= 5 }
            var columnShare = [Double](repeating: 0, count: width), rowShare = [Double](repeating: 0, count: height)
            for y in 0 ..< height {
                var count = 0
                for x in 0 ..< width where isBackground(luma[y * width + x]) { count += 1 }
                rowShare[y] = Double(count) / Double(width)
            }
            let rows = runs(rowShare)
            // Columns are measured across the bands of tiles only. Over the whole region, the empty panel
            // beside a short last row reads as gap in every column it leaves out, and with enough of it
            // in view those columns vanish and the grid with them.
            let lines = rows.isEmpty ? Array(0 ..< height) : rows.flatMap { Array($0.0 ... $0.1) }
            for x in 0 ..< width {
                var count = 0
                for y in lines where isBackground(luma[y * width + x]) { count += 1 }
                columnShare[x] = Double(count) / Double(lines.count)
            }
            return (runs(columnShare), rows)
        }
        // The panel background is one of the darker common levels, but not necessarily the most common
        // of them: scrolled, a cut-off row brings the darker Local Styles box into view. Try the likely
        // levels and keep the one that actually produces a grid of tiles.
        // Scrolled, the empty panel below a cut-off row can make the background the most common level
        // of all, so the tile colour is not assumed to be the mode: every common level is a candidate.
        _ = tileLevel
        var peaks: [Int] = []
        for level in (12 ..< 200).sorted(by: { histogram[$0] > histogram[$1] }) {
            if peaks.count == 6 { break }
            if histogram[level] == 0 { break }
            if peaks.allSatisfy({ abs($0 - level) > 6 }) { peaks.append(level) }
        }
        /// A real tile grid has a recognisable shape: square tiles of one size at a regular pitch with
        /// narrow gaps. A wrong background level carves glyphs into slivers of every width instead, which
        /// would win on cell count alone. Tiles are square, so the column width also says how tall a full
        /// row is: a row cut off at the top or bottom of the visible grid is dropped, as is a scrollbar.
        func shaped(_ found: (columns: [(Int, Int)], rows: [(Int, Int)])) -> (columns: [(Int, Int)], rows: [(Int, Int)], size: Int)? {
            let widths = found.columns.map { $0.1 - $0.0 + 1 }.sorted()
            guard !widths.isEmpty else { return nil }
            let size = Double(widths[widths.count / 2])
            func tileSized(_ run: (Int, Int)) -> Bool {
                let extent = Double(run.1 - run.0 + 1)
                return extent >= size * 0.75 && extent <= size * 1.3
            }
            // A row must be all there: tiles are square, so one shorter than it is wide is cut off by
            // the top or bottom of the view, and neither counted nor clicked nor used as a reference.
            func fullHeight(_ run: (Int, Int)) -> Bool {
                let extent = Double(run.1 - run.0 + 1)
                return extent >= size * 0.92 && extent <= size * 1.3
            }
            let columns = found.columns.filter(tileSized), rows = found.rows.filter(fullHeight)
            guard columns.count >= 2, !rows.isEmpty else { return nil }
            let pitches = zip(columns.dropFirst(), columns).map { Double($0.0 - $1.0) }.sorted()
            let pitch = pitches[pitches.count / 2]
            guard pitch >= size, pitch - size <= size * 0.4,
                  pitches.allSatisfy({ abs($0 - pitch) <= pitch * 0.15 }) else { return nil }
            return (columns, rows, Int(size))
        }
        var best: (columns: [(Int, Int)], rows: [(Int, Int)], size: Int) = ([], [], 0)
        var background = 0
        for level in peaks {
            guard let candidate = shaped(grid(level)) else { continue }
            let cells = candidate.columns.count * candidate.rows.count, held = best.columns.count * best.rows.count
            if cells > held || (cells == held && candidate.size > best.size) { best = candidate; background = level }
        }
        var columns = best.columns
        let rows = best.rows
        guard !columns.isEmpty, !rows.isEmpty else { return ([], nil) }
        // Measure the columns again across the full rows only. Over the whole region, the empty space
        // beside a short last row reads as gap in every column it leaves out, which trims the tiles'
        // edges where only a glyph-free strip of tile remains.
        let rowLines = rows.flatMap { Array($0.0 ... $0.1) }
        var withinRows = [Double](repeating: 0, count: width)
        for x in 0 ..< width {
            var count = 0
            for y in rowLines where abs(luma[y * width + x] - background) <= 5 { count += 1 }
            withinRows[x] = Double(count) / Double(rowLines.count)
        }
        let refined = runs(withinRows).filter { Double($0.1 - $0.0 + 1) >= Double(best.size) * 0.75 && Double($0.1 - $0.0 + 1) <= Double(best.size) * 1.3 }
        if refined.count >= columns.count { columns = refined }
        // Between the top of the region and the first full row: tile-coloured in tile columns and
        // background in the gaps means a cut-off row, so the list is scrolled. Uniform across both
        // means the box edge and background only, so it is at the top.
        var atTop: Bool?
        if header != nil, let firstRow = rows.first?.0, firstRow > 6,
           let left = columns.first?.0, let right = columns.last?.1 {
            let inTile = columns.flatMap { Array($0.0 ... $0.1) }
            let inGap = (left ... right).filter { x in !columns.contains { x >= $0.0 && x <= $0.1 } }
            if !inGap.isEmpty {
                var structured = 0, longest = 0
                for y in 0 ..< max(0, firstRow - 3) {
                    let tile = inTile.reduce(0) { $0 + luma[y * width + $1] } / inTile.count
                    let gap = inGap.reduce(0) { $0 + luma[y * width + $1] } / inGap.count
                    structured = tile - gap >= 8 ? structured + 1 : 0
                    longest = max(longest, structured)
                }
                atTop = longest < 3
            }
        }
        var cells = rows.map { row in
            columns.map { column in
                CGRect(x: region.minX + CGFloat(column.0) / CGFloat(width) * region.width,
                       y: region.minY + CGFloat(row.0) / CGFloat(height) * region.height,
                       width: CGFloat(column.1 - column.0 + 1) / CGFloat(width) * region.width,
                       height: CGFloat(row.1 - row.0 + 1) / CGFloat(height) * region.height)
            }
        }
        // The last row of a list is often short: one tile of six is mostly background, so it never
        // shows up as a row above. Look one row pitch further down, column by column from the left,
        // for tiles that are fully visible: tile-coloured just inside their top and bottom edges, which
        // a tile cut off by the bottom of the view is not. A tile is lighter than the panel, hovered
        // or not.
        if let template = cells.last {
            let pitch = cells.count >= 2 ? cells[1][0].minY - cells[0][0].minY
                : template.count >= 2 ? (template[1].minX - template[0].minX) * CGFloat(image.width) / CGFloat(image.height) : 0
            func isTile(_ cell: CGRect) -> Bool {
                guard cell.minY >= 0, cell.maxY <= 1 else { return false }
                let side = 24
                let rgba = patch(of: image, rect: CGRect(x: cell.minX * CGFloat(image.width), y: cell.minY * CGFloat(image.height),
                                                         width: cell.width * CGFloat(image.width), height: cell.height * CGFloat(image.height)),
                                 width: side, height: side)
                func lit(_ lines: ClosedRange<Int>) -> Bool {
                    var count = 0, total = 0
                    for y in lines {
                        for x in 6 ... 17 {
                            let i = (y * side + x) * 4
                            let value = (Int(rgba[i]) * 30 + Int(rgba[i + 1]) * 59 + Int(rgba[i + 2]) * 11) / 100
                            if value >= background + 8 { count += 1 }
                            total += 1
                        }
                    }
                    return Double(count) >= Double(total) * 0.6
                }
                return lit(1 ... 3) && lit(20 ... 22)
            }
            var y = template[0].minY + pitch
            while pitch > 0, cells.count < 40 {
                var found: [CGRect] = []
                for column in template {
                    let cell = CGRect(x: column.minX, y: y, width: column.width, height: column.height)
                    guard isTile(cell) else { break }
                    found.append(cell)
                }
                // A full row here would have been found already; this only adds a shorter one.
                guard !found.isEmpty, found.count < template.count else { break }
                cells.append(found)
                y += pitch
            }
        }
        return (cells, atTop)
    }

    /// Keeps row numbers absolute while the style browser scrolls: R3 stays R3 as it moves, a row
    /// sliding off does not disturb the others, and a row appearing gets the next number. Rather than
    /// matching whole rows, it follows the scroll itself: between two looks it measures how far the
    /// grid moved, using every visible pixel of it, partly visible rows included. The scroll position
    /// then gives each row its number from where it sits. The browser opens at the top, and any look
    /// at the top re-anchors the count.
    @MainActor final class StyleRowTracker {
        /// Absolute index of the first fully visible row, or nil once tracking is lost.
        private(set) var offset: Int?
        /// How far the list is scrolled from its top, in capture pixels.
        private var scroll: Double?
        private var anchor = 0.0, pitch = 0.0
        private var strip: CGRect?
        private var previous: [Int] = []
        private var size = (width: 0, height: 0)
        private var imageSize = (0, 0)
        /// The last measured movement, in capture pixels. Live looks arrive many times a second, so the
        /// next movement is close to it.
        private var velocity = 0.0
        private var fresh = true
        /// Scrollbar thumb positions against the scroll measured at the same time. Once they span a few
        /// pixels, the thumb alone gives the scroll: it recovers a lost count and corrects a slip.
        private var thumbFit: [(thumb: Double, scroll: Double)] = []
        /// Where the thumb sits with the list at its top, and whether the browser was seen closed since.
        private var topThumb: Double?
        private var sawClosed = false
        private var closedSince: Date?
        /// How long the browser must be gone before it counts as closed.
        var closedAfter: TimeInterval = 1.5
        /// The direction the routine is scrolling: 1 down, -1 up, 0 unknown. Movement the other way
        /// is not believed, so a row that looks like its neighbour cannot pull the count backwards.
        var expected = 0

        /// `panelOpen` false means the style browser itself is not on screen. Empty `cells` with the panel
        /// open is only a look where the grid could not be made out, often mid-scroll: the scroll is
        /// still followed from its pixels, and the count is kept.
        func observe(_ cells: [[CGRect]], image: CGImage, atTop: Bool? = nil, panelOpen: Bool = true) -> Int? {
            guard panelOpen else {
                // Gone for a while: the browser was closed, and reopens at the top. Measured in time, not
                // looks: one text reading that misses the panel's labels is reused for many live frames,
                // and must not reset a count that is being followed.
                let since = closedSince ?? Date()
                closedSince = since
                if Date().timeIntervalSince(since) >= closedAfter { fresh = true; strip = nil; scroll = nil; velocity = 0; offset = nil }
                // Even a short close counts as a reopen if the next look clearly shows the top.
                sawClosed = true
                return offset
            }
            closedSince = nil
            // Another window size moves everything the strip was measured on.
            // The scrollbar's measures belong to one window size; they survive the browser closing.
            if imageSize != (image.width, image.height) { scroll = nil; offset = nil; strip = nil; thumbFit = []; topThumb = nil }
            guard let firstRow = cells.first, let firstCell = firstRow.first, let lastCell = firstRow.last,
                  let bottomCell = cells.last?.first else {
                follow(image)
                return nil
            }
            let width = Double(image.width), height = Double(image.height)
            let rowTop = Double(firstCell.minY) * height
            // Tiles are square, so the column pitch is the row pitch even when one row is visible.
            if cells.count >= 2 { pitch = Double(cells[1][0].minY - cells[0][0].minY) * height }
            else if firstRow.count >= 2 { pitch = Double(firstRow[1].minX - firstRow[0].minX) * width }
            guard pitch > 4 else { return offset }

            // Scrolled by exactly a whole number of rows, a view looks just like the top, so the tiles alone
            // never reset a count. What does: the routine scrolling to the top; a freshly opened browser;
            // the scrollbar thumb back where it sat at the top (a measurement, not a resemblance); and,
            // until that is known, a browser just reopened that looks like the top, since it opens there.
            let thumb = Desktop.scrollThumb(in: image, cells: cells)
            let thumbAtTop = thumb.flatMap { now in topThumb.map { abs(now - $0) <= 2 } } ?? false
            let reopenedAtTop = sawClosed && atTop == true && topThumb == nil
            if forceTop || (fresh && atTop != false) || (thumbAtTop && (scroll == nil || offset != 0)) || (scroll == nil && reopenedAtTop) {
                forceTop = false; sawClosed = false
                if let thumb { topThumb = thumb }
                // At the top: the first full row is row 1. Sample within the visible rows, which sit
                // inside the scrolling viewport, so nothing that stays still is compared.
                let gap = pitch - Double(firstCell.height) * height
                strip = CGRect(x: Double(firstCell.minX) * width, y: max(0, rowTop - gap * 0.5),
                               width: Double(lastCell.maxX - firstCell.minX) * width,
                               height: min(height, Double(bottomCell.maxY) * height + gap * 0.5) - max(0, rowTop - gap * 0.5))
                imageSize = (image.width, image.height)
                previous = sample(image); sampleKind = image.bitmapInfo.rawValue
                anchor = rowTop; scroll = 0; velocity = 0; fresh = false; offset = 0
                if let thumb { thumbFit.append((thumb, 0)); if thumbFit.count > 60 { thumbFit.removeFirst() } }
                return 0
            }
            fresh = false; sawClosed = false
            let followed = follow(image)
            if let thumb, let fromThumb = scrollFrom(thumb: thumb) {
                if !followed || scroll == nil {
                    // Lost: the scrollbar says where the list is.
                    scroll = fromThumb; previous = sample(image); sampleKind = image.bitmapInfo.rawValue
                } else if let now = scroll, abs(now - fromThumb) > pitch * 0.5 {
                    // The pixels slipped by a row of look-alikes; the scrollbar does not.
                    scroll = fromThumb
                }
            }
            guard let now = scroll, strip != nil else { offset = nil; return nil }
            if followed, let thumb {
                thumbFit.append((thumb, now))
                if thumbFit.count > 60 { thumbFit.removeFirst() }
            }
            offset = max(0, Int(((rowTop + now - anchor) / pitch).rounded()))
            return offset
        }

        /// The scroll a thumb position stands for, from a straight-line fit of the pairs seen so far.
        /// Needs the thumb to have moved at least 8 pixels, so the slope is measured, not guessed.
        private func scrollFrom(thumb: Double) -> Double? {
            guard thumbFit.count >= 3 else { return nil }
            let xs = thumbFit.map(\.thumb), ys = thumbFit.map(\.scroll)
            guard let low = xs.min(), let high = xs.max(), high - low >= 8 else { return nil }
            let meanX = xs.reduce(0, +) / Double(xs.count), meanY = ys.reduce(0, +) / Double(ys.count)
            var top = 0.0, bottom = 0.0
            for (x, y) in zip(xs, ys) { top += (x - meanX) * (y - meanY); bottom += (x - meanX) * (x - meanX) }
            guard bottom > 0 else { return nil }
            return meanY + top / bottom * (thumb - meanX)
        }

        /// What produced the last sample. A screenshot and a streamed frame of the same, unmoved list
        /// differ by about 8 in brightness on average (window corners, scaling), most of what a real
        /// match is allowed, so a change of kind is a new reference, not a movement.
        private var sampleKind: UInt32 = 0

        /// Adds the movement since the last look to the scroll position. Returns false once lost.
        @discardableResult
        private func follow(_ image: CGImage) -> Bool {
            guard let known = scroll, strip != nil else { return false }
            let current = sample(image)
            let kind = image.bitmapInfo.rawValue
            if kind != sampleKind { sampleKind = kind; previous = current; return true }
            guard let moved = displacement(previous, current) else { scroll = nil; offset = nil; return false }
            scroll = known + moved; previous = current; velocity = moved
            return true
        }

        /// The list would not scroll further up: its first visible row is row 1. The next look with a
        /// grid re-anchors there, even if the count had been lost.
        func atTop() { forceTop = true; offset = 0 }
        private var forceTop = false

        private func sample(_ image: CGImage) -> [Int] {
            guard let area = strip else { return [] }
            size = (96, max(8, Int(area.height / 2)))
            let rgba = Desktop.patch(of: image, rect: area, width: size.width, height: size.height)
            return (0 ..< size.width * size.height).map {
                (Int(rgba[$0 * 4]) * 30 + Int(rgba[$0 * 4 + 1]) * 59 + Int(rgba[$0 * 4 + 2]) * 11) / 100
            }
        }

        /// How far the content moved up between two samples, in capture pixels: the shift at which the
        /// overlapping parts agree, provided it agrees clearly better than any shift a row away.
        private func displacement(_ before: [Int], _ after: [Int]) -> Double? {
            let (columns, rows) = size
            guard before.count == columns * rows, after.count == before.count, let area = strip else { return nil }
            let scale = Double(area.height) / Double(rows)
            let rowPitch = pitch / scale
            var errors: [(shift: Int, error: Double)] = []
            let limit = Int(Double(rows) * 0.7)
            for shift in -limit ... limit {
                let top = max(0, -shift), bottom = min(rows, rows - shift)
                guard bottom - top >= rows * 3 / 10 else { continue }
                var total = 0, count = 0
                for y in top ..< bottom {
                    for x in stride(from: 0, to: columns, by: 2) {
                        total += abs(before[(y + shift) * columns + x] - after[y * columns + x]); count += 1
                    }
                }
                errors.append((shift, Double(total) / Double(max(1, count))))
            }
            guard let best = errors.min(by: { $0.error < $1.error }), best.error < 10 else { return nil }
            // Rows of presets look alike, so a shift one row away can match nearly as well. Near the
            // movement just measured, within half a row, no such alias fits: when the match there is a
            // genuine one (a true shift scores under 1 on real captures; a jump to other rows about 9)
            // and about as good as any, it is the movement.
            // Known direction: drop shifts the other way, beyond a little settle back.
            if expected != 0 {
                errors = errors.filter { Double($0.shift * expected) >= -rowPitch * 0.1 }
                guard let allowed = errors.min(by: { $0.error < $1.error }), allowed.error < 10 else { return nil }
                if allowed.shift != best.shift { return Double(allowed.shift) * scale }
            }
            let predicted = velocity / scale
            if let near = errors.filter({ abs(Double($0.shift) - predicted) <= rowPitch * 0.45 }).min(by: { $0.error < $1.error }),
               near.error < 4, near.error <= best.error * 1.3 + 1 {
                return Double(near.shift) * scale
            }
            let rivals = errors.filter { abs(Double($0.shift - best.shift)) > rowPitch * 0.3 }
            if let rival = rivals.min(by: { $0.error < $1.error }), best.error >= rival.error * 0.7 { return nil }
            return Double(best.shift) * scale
        }
    }

    static let styleRows = StyleRowTracker()

    /// The top of the style list's scrollbar thumb, in capture pixels: a narrow, light grey bar just
    /// right of the tiles. Where it sits says how far the list is scrolled, whatever the tiles look like.
    static func scrollThumb(in image: CGImage, cells: [[CGRect]]) -> Double? {
        guard let right = cells.flatMap({ $0 }).map(\.maxX).max(), let top = cells.first?.first?.minY,
              let bottom = cells.last?.first?.maxY, let tile = cells.first?.first?.height else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let band = CGRect(x: right * width + 2, y: max(0, (top - tile * 1.6) * height),
                          width: min(width - right * width - 2, width * 0.035), height: 0)
        let span = min(height, (bottom + tile * 1.6) * height) - band.minY
        guard band.width >= 4, span > 20 else { return nil }
        let rect = CGRect(x: band.minX, y: band.minY, width: band.width, height: span)
        let columns = max(4, Int(rect.width)), rows = max(20, Int(rect.height / 2))
        let rgba = patch(of: image, rect: rect, width: columns, height: rows)
        func thumbPixel(_ x: Int, _ y: Int) -> Bool {
            let i = (y * columns + x) * 4
            let r = Int(rgba[i]), g = Int(rgba[i + 1]), b = Int(rgba[i + 2])
            return max(r, g, b) - min(r, g, b) < 25 && (r * 30 + g * 59 + b * 11) / 100 >= 62
        }
        var best: (length: Int, start: Int, x: Int)?
        for x in 0 ..< columns {
            var y = 0
            while y < rows {
                guard thumbPixel(x, y) else { y += 1; continue }
                var end = y
                while end + 1 < rows, thumbPixel(x, end + 1) { end += 1 }
                let length = end - y + 1
                if best.map({ length > $0.length }) ?? true { best = (length, y, x) }
                y = end + 1
            }
        }
        // A thumb is a real bar: a good part of the view tall, never all of it, and narrow.
        guard let found = best, found.length >= rows / 12, found.length < rows * 95 / 100 else { return nil }
        let wide = (0 ..< columns).filter { x in (found.start ..< found.start + found.length).filter { thumbPixel(x, $0) }.count > found.length * 3 / 4 }.count
        guard Double(wide) <= max(3, Double(columns) * 0.5) else { return nil }
        return Double(rect.minY) + Double(found.start) * Double(rect.height) / Double(rows)
    }

    /// The tile's appearance, inset so the rounded edge and hover tint matter less than the glyph.
    static func cellPatch(_ image: CGImage, cell: CGRect, side: Int = 48) -> [UInt8] {
        let inner = cell.insetBy(dx: cell.width * 0.15, dy: cell.height * 0.15)
        return patch(of: image, rect: CGRect(x: inner.minX * CGFloat(image.width), y: inner.minY * CGFloat(image.height),
                                             width: inner.width * CGFloat(image.width), height: inner.height * CGFloat(image.height)),
                     width: side, height: side)
    }

    /// The style you picked, by position. The browser opens scrolled to the top, so the absolute row
    /// and the column identify the same preset every time. The appearance is kept only to confirm the
    /// slot still holds the same tile before clicking.
    @MainActor struct StyleSlot {
        /// Absolute row, counted from the top of the browser.
        var row: Int
        var column: Int
        /// False when you scrolled further than could be followed: then the tile is found by appearance.
        var positionKnown: Bool
        var appearance: [UInt8]
        /// The tile you clicked, as captured at full resolution: the second reference beside its row
        /// and column, shown during the run and saved with the project's files.
        var image: CGImage? = nil
        static let side = 48
        /// Shape difference, with colour as a hard gate: a tile of another colour is never close,
        /// however alike the letters. The same tile measured 1-16 apart in colour across captures;
        /// different colours 52 and more (pink against maroon, about 90).
        func difference(from other: [UInt8]) -> Int {
            let shape = Desktop.glyphDifference(appearance, other)
            return Desktop.colorDistance(appearance, other) < Desktop.sameColor ? shape : 500 + shape
        }
    }

    /// Difference between two tile patches over the glyph only. Hovering a tile tints its background,
    /// and the tile you click is captured while the pointer is on it, so the background is ignored:
    /// each patch's own most common brightness is taken as its background, and only pixels that are
    /// glyph in either patch are compared.
    static func glyphDifference(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count, !a.isEmpty else { return Int.max }
        func luma(_ p: [UInt8], _ i: Int) -> Int { (Int(p[i]) * 30 + Int(p[i + 1]) * 59 + Int(p[i + 2]) * 11) / 100 }
        func backgroundLevel(_ p: [UInt8]) -> Int {
            var histogram = [Int](repeating: 0, count: 256)
            for i in stride(from: 0, to: p.count, by: 4) { histogram[luma(p, i)] += 1 }
            return histogram.indices.max { histogram[$0] < histogram[$1] } ?? 0
        }
        let backgroundA = backgroundLevel(a), backgroundB = backgroundLevel(b)
        var total = 0, count = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            let glyphA = abs(luma(a, i) - backgroundA) > 10, glyphB = abs(luma(b, i) - backgroundB) > 10
            guard glyphA || glyphB else { continue }
            total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
            count += 1
        }
        return count == 0 ? Int.max : total / (count * 3)
    }

    /// The pixels inside one tile, at the capture's full resolution.
    static func crop(_ image: CGImage, cell: CGRect) -> CGImage? {
        image.cropping(to: CGRect(x: cell.minX * CGFloat(image.width), y: cell.minY * CGFloat(image.height),
                                  width: cell.width * CGFloat(image.width), height: cell.height * CGFloat(image.height)).integral)
    }

    /// A tile's colour: the share of its pixels that are strongly coloured, and their average colour.
    /// White and black styles have almost none. Hover tint and shadows are grey, so they do not count.
    static func colorSignature(_ patch: [UInt8]) -> (share: Double, red: Double, green: Double, blue: Double) {
        var count = 0, total = 0, red = 0, green = 0, blue = 0
        for i in stride(from: 0, to: patch.count, by: 4) {
            let r = Int(patch[i]), g = Int(patch[i + 1]), b = Int(patch[i + 2])
            let high = max(r, g, b), low = min(r, g, b)
            total += 1
            guard high >= 50, Double(high - low) >= Double(high) * 0.35 else { continue }
            count += 1; red += r; green += g; blue += b
        }
        guard count > 0 else { return (0, 0, 0, 0) }
        return (Double(count) / Double(max(1, total)), Double(red) / Double(count), Double(green) / Double(count), Double(blue) / Double(count))
    }

    static let sameColor = 30.0

    /// Distance between two tiles' colours: 0 for the same colour, 255 or more for a different one.
    static func colorDistance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let x = colorSignature(a), y = colorSignature(b)
        if x.share < 0.03 && y.share < 0.03 { return 0 }                 // both white/black styles
        if x.share < 0.03 || y.share < 0.03 { return 255 }               // one coloured, one not
        let mean = ((x.red - y.red) * (x.red - y.red) + (x.green - y.green) * (x.green - y.green) + (x.blue - y.blue) * (x.blue - y.blue)).squareRoot()
        return mean + abs(x.share - y.share) * 200
    }

    static func slot(containing point: CGPoint, in cells: [[CGRect]]) -> (row: Int, column: Int)? {
        for (row, cellsInRow) in cells.enumerated() {
            for (column, cell) in cellsInRow.enumerated() where cell.contains(point) { return (row, column) }
        }
        return nil
    }

    @MainActor struct StyleLock {
        /// How many scroll steps down from the top of the style browser the tile sits.
        var page = 0
        let match: StyleMatch
        let frame: CGRect
        let reference: Data
        let pixels: [UInt8]
        let width: Int
        let height: Int

        init(match: StyleMatch, image: CGImage, frame: CGRect, reference: Data) {
            self.match = match; self.frame = frame; self.reference = reference
            width = min(128, max(8, Int(match.rect.width * CGFloat(image.width))))
            height = min(128, max(8, Int(match.rect.height * CGFloat(image.height))))
            pixels = Desktop.patch(of: image, rect: CGRect(x: match.rect.minX * CGFloat(image.width), y: match.rect.minY * CGFloat(image.height), width: match.rect.width * CGFloat(image.width), height: match.rect.height * CGFloat(image.height)), width: width, height: height)
        }

        func difference(in image: CGImage) -> Int {
            Desktop.detailScore(pixels, Desktop.patch(of: image, rect: CGRect(x: match.rect.minX * CGFloat(image.width), y: match.rect.minY * CGFloat(image.height), width: match.rect.width * CGFloat(image.width), height: match.rect.height * CGFloat(image.height)), width: width, height: height), width: width, height: height)
        }

        func isValid(in image: CGImage, frame: CGRect, reference: Data) -> Bool {
            self.frame == frame && self.reference == reference && difference(in: image) < 8
        }
    }

    static func locateDetailed(_ template: CGImage, in image: CGImage, minX: CGFloat = 0) -> (point: CGPoint, score: Int)? {
        guard let best = styleCandidates(template, in: image, minX: minX).first else { return nil }
        return (best.point, best.score)
    }

    /// The left edge of the style browser, taken from its own labels, so the tile search covers the
    /// panel instead of the whole window.
    static func stylePanelLeft(in hits: [TextHit]) -> CGFloat? {
        let names = ["back", "my styles", "local styles", "open projects"]
        let edges = hits.compactMap { hit -> CGFloat? in
            let text = normalized(hit.text).joined(separator: " ")
            return names.contains(where: { text.contains($0) }) ? hit.rect.minX : nil
        }
        guard let left = edges.min() else { return nil }
        return max(0, left - 0.04)
    }

    /// Measured: the correct tile scores 23 on a real capture, a wrong scale 32 or more.
    static let styleMatchLimit = 28

    static func locate(_ template: CGImage, in image: CGImage, minX: CGFloat = 0) -> CGPoint? {
        guard let found = locateDetailed(template, in: image, minX: minX), found.score < 30 else { return nil }
        return found.point
    }

    /// The playhead's x position, found by its blue vertical line inside a track row. If a caption
    /// is rendering in the Program Monitor then the playhead is on that clip, so this locates the
    /// clip to click directly, with no need to match its truncated label in the timeline.
    static func playheadX(inRowOf anchor: CGRect, in image: CGImage, hint: CGFloat? = nil) -> CGFloat? {
        let imageWidth = CGFloat(image.width), imageHeight = CGFloat(image.height)
        let centre = anchor.midY * imageHeight
        let band = max(8, anchor.height * imageHeight * 1.6)
        let top = max(0, Int(centre - band / 2))
        let height = min(image.height - top, Int(band))
        let left = min(image.width - 1, Int(anchor.maxX * imageWidth) + 4)
        let width = image.width - left
        guard height > 2, width > 16 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            if let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(image, in: CGRect(x: -CGFloat(left), y: -(imageHeight - CGFloat(top) - CGFloat(height)),
                                               width: imageWidth, height: imageHeight))
            }
        }
        // Premiere draws the playhead as a saturated blue line. Caption clips are orange, so blue
        // dominance separates them cleanly.
        var score = [Int](repeating: 0, count: width)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                if b > 90, b - r > 45, b - g > 25 { score[x] += 1 }
            }
        }
        // Every blue vertical line in the row: the playhead, but also the timeline's scrollbar and any
        // panel divider, which are indistinguishable by colour.
        var runs: [(centre: CGFloat, peak: Int)] = []
        var index = 0
        while index < width {
            guard score[index] >= max(2, height / 2) else { index += 1; continue }
            var end = index, peak = score[index]
            while end + 1 < width, score[end + 1] >= max(2, height / 2) { end += 1; peak = max(peak, score[end]) }
            runs.append(((CGFloat(left) + (CGFloat(index) + CGFloat(end)) / 2) / imageWidth, peak))
            index = end + 1
        }
        guard !runs.isEmpty else { return nil }
        if let expected = hint {
            // Prefer the line nearest where the ruler says the playhead is.
            return runs.min { abs($0.centre - expected) < abs($1.centre - expected) }?.centre
        }
        return runs.max { $0.peak < $1.peak }?.centre
    }

    /// Seconds for a HH:MM:SS:FF timecode. Frames are divided by a nominal 30; across a timeline
    /// ruler that is a few pixels either way, far below the width of a clip.
    static func seconds(ofTimecode text: String) -> Double? {
        let parts = text.split(whereSeparator: { !$0.isNumber })
        guard parts.count == 4, parts.allSatisfy({ $0.count == 2 }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == 4 else { return nil }
        return Double(values[0]) * 3600 + Double(values[1]) * 60 + Double(values[2]) + Double(values[3]) / 30
    }

    /// Timecodes recognised on screen, split into the ruler's row and the rest.
    private static func timecodes(in hits: [TextHit]) -> (ruler: [(time: Double, rect: CGRect)], others: [(time: Double, rect: CGRect)]) {
        let stamps = hits.compactMap { hit -> (time: Double, rect: CGRect)? in
            guard let time = seconds(ofTimecode: hit.text) else { return nil }
            return (time, hit.rect)
        }
        // Rows of two or more timecodes. The Program Monitor shows its own pair, the current time and
        // the duration, which is indistinguishable from a ruler by count alone — so the ruler is
        // identified by position: it is the row directly above the track rows.
        var rows: [[(time: Double, rect: CGRect)]] = []
        var seen: [CGFloat] = []
        for candidate in stamps {
            guard !seen.contains(where: { abs($0 - candidate.rect.midY) < candidate.rect.height }) else { continue }
            seen.append(candidate.rect.midY)
            let row = stamps.filter { abs($0.rect.midY - candidate.rect.midY) < candidate.rect.height * 0.8 }
            if row.count >= 2 { rows.append(row) }
        }
        let trackNames = ["subtitle", "caption", "captions"]
        let trackTop = hits.first { trackNames.contains(normalized($0.text).joined(separator: " ")) }?.rect.minY
        var chosen: [(time: Double, rect: CGRect)] = []
        if let trackTop {
            chosen = rows
                .filter { ($0.first?.rect.midY ?? 1) < trackTop }
                .max { ($0.first?.rect.midY ?? 0) < ($1.first?.rect.midY ?? 0) } ?? []
        }
        if chosen.isEmpty { chosen = rows.max { $0.count < $1.count } ?? [] }
        let ruler = chosen.sorted { $0.rect.midX < $1.rect.midX }
        let others = stamps.filter { stamp in !ruler.contains { $0.rect == stamp.rect } }
        return (ruler, others)
    }

    /// The playhead's current time, read from the timecode in the timeline header. Used to tell
    /// whether stepping to the next edit point actually moved, which is how the end of the sequence
    /// is detected rather than guessed from a step count.
    static func playheadTime(in hits: [TextHit]) -> Double? {
        let found = timecodes(in: hits)
        guard found.ruler.count >= 2 else { return found.others.first?.time }
        return found.others.min { $0.rect.minY < $1.rect.minY }?.time
    }

    /// Where the playhead should be, derived from the timeline ruler rather than from pixels: the
    /// ruler's timecodes are centred on their ticks, so two of them give the seconds-to-x mapping,
    /// and the current timecode gives the position. Used to tell the playhead from a scrollbar,
    /// which looks identical to a colour test.
    static func playheadFromRuler(in hits: [TextHit]) -> CGFloat? {
        let found = timecodes(in: hits)
        let ruler = found.ruler
        guard let first = ruler.first, let last = ruler.last,
              ruler.count >= 2, last.time > first.time,
              last.rect.midX > first.rect.midX else { return nil }
        let perSecond = (last.rect.midX - first.rect.midX) / CGFloat(last.time - first.time)
        guard perSecond > 0 else { return nil }
        let span = (min: first.rect.midX - perSecond * 2, max: last.rect.midX + perSecond * 2)
        for stamp in found.others.sorted(by: { $0.rect.minY < $1.rect.minY }) {
            let x = first.rect.midX + perSecond * CGFloat(stamp.time - first.time)
            if x >= span.min, x <= span.max { return x }
        }
        return nil
    }

    /// The caption track's header label. Clicking it gives the Timeline keyboard focus when the
    /// playhead itself is scrolled out of view and so cannot be clicked.
    static func trackHeader(in hits: [TextHit]) -> CGPoint? {
        let names = ["subtitle", "caption", "captions"]
        guard let row = hits.first(where: { hit in
            let words = normalized(hit.text)
            return words.count == 1 && names.contains(words[0])
        }) else { return nil }
        return CGPoint(x: row.rect.midX, y: row.rect.midY)
    }

    /// The caption clip to click: the point on the caption track directly under the playhead.
    static func clipAtPlayhead(in hits: [TextHit], image: CGImage) -> CGPoint? {
        let names = ["subtitle", "caption", "captions"]
        let rows = hits.filter { hit in
            let words = normalized(hit.text)
            return words.count == 1 && names.contains(words[0])
        }
        let hint = playheadFromRuler(in: hits)
        for row in rows.sorted(by: { $0.rect.minY < $1.rect.minY }) {
            if let x = playheadX(inRowOf: row.rect, in: image, hint: hint) {
                return CGPoint(x: x, y: row.rect.midY)
            }
            // No blue line in view, but the ruler still says where the playhead is.
            if let hint { return CGPoint(x: hint, y: row.rect.midY) }
        }
        return nil
    }

    /// Whether a clip is selected, read from the Properties panel: with nothing selected Premiere
    /// shows "Select a clip in the timeline to view properties."
    static func clipIsSelected(in hits: [TextHit]) -> Bool {
        let joined = hits.map { normalized($0.text).joined(separator: " ") }
        if joined.contains(where: { $0.contains("select clip in the timeline") || $0.contains("select a clip in the timeline") }) {
            return false
        }
        // A caption shows "C1: Subtitle" and a Track Style row; a graphic, or a caption upgraded to one,
        // shows its own name and goes straight to Text and Appearance. Any of these means a clip with
        // editable text is selected, as does the style browser that only opens for one.
        return joined.contains { line in
            line.contains("track style") || line.contains("subtitle") && line.contains("c1")
                || line == "font size" || line == "v text" || line.contains("my styles")
        }
    }

    /// Premiere's four-square style browser button. It sits on the Track Style *value* row, the one
    /// showing the current style, not on the Track Style header row, whose right-hand control is the
    /// + that creates a new style. Anchoring on the header would press the wrong button.
    static func styleBrowserButton(in hits: [TextHit], image: CGImage) -> CGPoint? {
        guard let header = hits.first(where: { normalized($0.text).joined(separator: " ").contains("track style") }) else { return nil }
        let valueRow = hits
            .filter { $0.rect.minY > header.rect.minY + header.rect.height * 0.4
                      && $0.rect.minY < header.rect.maxY + header.rect.height * 4
                      && abs($0.rect.minX - header.rect.minX) < 0.08 }
            .min { $0.rect.minY < $1.rect.minY }
        guard let row = valueRow else { return nil }
        // Size the scan from the header too: OCR sometimes reads the value ("None") as a squashed box a
        // third of its real height, and a band that thin rejects the four-square as too wide for a square
        // icon, leaving the "0 ⌄" chevron beside it as the last control.
        let height = max(row.rect.height, header.rect.height)
        return lastControl(onRowOf: CGRect(x: row.rect.minX, y: row.rect.midY - height / 2, width: row.rect.width, height: height), in: image)
    }

    /// A button identified by its own label, such as the style panel's Back.
    static func button(labelled label: String, in hits: [TextHit]) -> CGPoint? {
        let key = normalized(label).joined(separator: " ")
        guard let hit = hits.first(where: { normalized($0.text).joined(separator: " ") == key }) else { return nil }
        return CGPoint(x: hit.rect.midX, y: hit.rect.midY)
    }

    func activate(_ choice: WindowChoice) throws {
        guard canControl else { throw AssistError.message("Enable Accessibility for Edit Assist before running mouse or keyboard actions.") }
        guard let app = NSRunningApplication(processIdentifier: choice.pid) else { throw AssistError.message("\(choice.app) is no longer running.") }
        app.activate(options: [])
    }

    private func validateWindow(_ observation: Observation) throws {
        try Task.checkCancellation()
        guard armed, canControl else { throw AssistError.message("Desktop control is stopped or Accessibility permission is missing.") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == observation.window.pid else {
            throw AssistError.message("Focus left \(observation.window.app). Paused without clicking.")
        }
        let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let row = all.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == observation.window.id }),
              let bounds = row[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              abs(frame.minX - observation.window.frame.minX) < 1,
              abs(frame.minY - observation.window.frame.minY) < 1,
              abs(frame.width - observation.window.frame.width) < 1,
              abs(frame.height - observation.window.frame.height) < 1 else {
            throw AssistError.message("The \(observation.window.app) window moved or resized. Capture again before acting.")
        }
    }

    private func emit(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        event?.post(tap: .cghidEventTap)
    }

    private func point(_ x: Double, _ y: Double, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + x * frame.width, y: frame.minY + y * frame.height)
    }

    /// The name of whatever covers `p` ahead of the target window, or nil when the point is clear.
    /// Window-server order is front to back.
    func covering(_ p: CGPoint, of window: WindowChoice) -> String? {
        let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for row in all {
            guard let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(p),
                  (row[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = row[kCGWindowNumber as String] as? NSNumber else { continue }
            if id.uint32Value == window.id { return nil }
            if (overlayWindowID != 0 && id.uint32Value == overlayWindowID) || (inspectionWindowID != 0 && id.uint32Value == inspectionWindowID) { continue }
            return (row[kCGWindowOwnerName as String] as? String) ?? "Another window"
        }
        return "Nothing on screen"
    }

    private func checkHit(_ p: CGPoint, window: WindowChoice) throws {
        if let what = covering(p, of: window) {
            throw AssistError.blocked(what)
        }
    }

    func execute(_ action: AgentAction, on observation: Observation) async throws {
        try await beforeOperation?()
        try ActionPolicy.validate(action)
        try validateWindow(observation)
        let source = CGEventSource(stateID: .privateState)
        var action = action
        // Resolve a named span to measured coordinates, then run it as an ordinary drag.
        if action.kind == "selectSpan" {
            guard let span = Self.selection(for: action.phrase, in: observation.text) else {
                throw AssistError.message("Could not find “\(action.phrase)” in the text on screen. Scroll it into view or select it another way.")
            }
            action.kind = "drag"
            action.x = span.start.x; action.y = span.start.y
            action.endX = span.end.x; action.endY = span.end.y
            try ActionPolicy.validate(action)
        }
        let p = point(action.x, action.y, in: observation.window.frame)
        switch action.kind {
        case "click", "doubleClick":
            try checkHit(p, window: observation.window)
            // Some controls, the style browser's tiles among them, ignore a press that arrives with no
            // pointer movement before it and no time held: arrive, let the hover register, then press.
            let deliberate = action.keys.contains("hover")
            if deliberate {
                emit(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x - 3, y: p.y - 3), mouseButton: .left))
                try await Task.sleep(for: .milliseconds(12))
                emit(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
                try await Task.sleep(for: .milliseconds(45))
            }
            for count in 1...(action.kind == "doubleClick" ? 2 : 1) {
                try validateWindow(observation)
                let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
                down?.setIntegerValueField(.mouseEventClickState, value: Int64(count)); emit(down)
                if deliberate { try await Task.sleep(for: .milliseconds(30)) }
                let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
                up?.setIntegerValueField(.mouseEventClickState, value: Int64(count)); emit(up)
                if count == 1 && action.kind == "doubleClick" { try await Task.sleep(for: .milliseconds(45)) }
            }
        case "drag":
            let end = point(action.endX, action.endY, in: observation.window.frame)
            for i in 0...12 {
                let t = Double(i) / 12
                try checkHit(CGPoint(x: p.x + (end.x - p.x) * t, y: p.y + (end.y - p.y) * t), window: observation.window)
            }
            emit(CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left))
            var current = p
            defer { emit(CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: current, mouseButton: .left)) }
            // Few steps, close together: text selection follows the last position, not the path.
            for i in 1...6 {
                try validateWindow(observation)
                let t = Double(i) / 6
                current = CGPoint(x: p.x + (end.x - p.x) * t, y: p.y + (end.y - p.y) * t)
                emit(CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: current, mouseButton: .left))
                try await Task.sleep(for: .milliseconds(6))
            }
        case "key":
            let codes: [String: CGKeyCode] = ["left":123, "right":124, "down":125, "up":126, "home":115, "end":119, "pageup":116, "pagedown":121, "tab":48, "escape":53, "return":36, "space":49, "t":17, "v":9, "d":2]
            var flags: CGEventFlags = []
            let keys = action.keys.map { $0.lowercased() }
            if keys.contains("shift") { flags.insert(.maskShift) }
            if keys.contains("command") { flags.insert(.maskCommand) }
            if keys.contains("option") { flags.insert(.maskAlternate) }
            if keys.contains("control") { flags.insert(.maskControl) }
            guard let key = keys.compactMap({ codes[$0] }).first else { throw AssistError.message("Unknown key.") }
            let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
            down?.flags = flags; emit(down)
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
            up?.flags = flags; emit(up)
        case "scroll":
            try checkHit(p, window: observation.window)
            // A wheel event goes to whatever is under the pointer when it is handled, which can still be
            // where the pointer was a moment ago. Move there, give it a moment, and place the event too.
            emit(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
            try await Task.sleep(for: .milliseconds(12))
            let wheel = CGEvent(scrollWheelEvent2Source: source, units: action.keys.contains("pixels") ? .pixel : .line,
                                wheelCount: 1, wheel1: Int32(action.scroll), wheel2: 0, wheel3: 0)
            wheel?.location = p
            emit(wheel)
        case "typeNumber":
            for scalar in action.phrase.unicodeScalars {
                try validateWindow(observation)
                var unit = UniChar(scalar.value)
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                emit(down)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                emit(up)
                try await Task.sleep(for: .milliseconds(12))
            }
        case "wait": try await Task.sleep(for: .seconds(1))
        default: break
        }
    }
}

/// A registered shortcut consumes F10 before the editor can use it, including while Edit Assist
/// is in the background. Release tracking prevents a held key from repeatedly toggling detection.
@MainActor
final class DetectionHotkey {
    var action: (() -> Void)?
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var held = false
    private(set) var available = false

    init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                         MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard read == noErr, identifier.signature == 0x45414454, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<DetectionHotkey>.fromOpaque(context).takeUnretainedValue()
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.held = false }
                else if !owner.held { owner.held = true; owner.action?() }
            }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return }
        let registered = RegisterEventHotKey(UInt32(kVK_F10), 0, EventHotKeyID(signature: 0x45414454, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        available = registered == noErr
    }

    deinit {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
