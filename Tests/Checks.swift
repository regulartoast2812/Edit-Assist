import Foundation
import AppKit

@main
struct Checks {
    static func main() async throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAIL: \(name)") }
            count += 1
            print("PASS: \(name)")
        }
        func rejects(_ action: AgentAction) -> Bool { do { try ActionPolicy.validate(action); return false } catch { return true } }
        func action(_ kind: String = "click", keys: [String] = [], x: Double = 0.5, scroll: Int = 0) -> AgentAction {
            AgentAction(kind: kind, x: x, y: 0.5, endX: 0.7, endY: 0.5, keys: keys, scroll: scroll, purpose: "test")
        }
        let lines = try ScriptParser.parse("Now enjoy **buttery-soft, stretchy** real jacket\n**65% OFF**\nNothing highlighted")
        check(lines.count == 3, "Keep unhighlighted lines for matching context")
        check(lines[0].text == "Now enjoy buttery-soft, stretchy real jacket", "Remove only formatting markers")
        check(lines[0].highlights == [TextSpan(start: 10, end: 32, text: "buttery-soft, stretchy")], "Exact highlighted range")
        check(lines[2].highlights.isEmpty, "Plain line creates no targets")
        let repeated = try ScriptParser.parse("**jacket** and **jacket**")
        check(repeated[0].highlights.map(\.start) == [0, 11], "Repeated words remain separate occurrences")
        let split = try ScriptParser.parse("The **high-neck\nultra-light** lining")
        check(split[0].highlights.first?.text == "high-neck" && split[1].highlights.first?.text == "ultra-light", "Bold range spans lines")
        let unicode = try ScriptParser.parse("👖 **êm ái**!")
        check(unicode[0].highlights.first?.start == 2 && unicode[0].highlights.first?.end == 7, "Unicode character offsets")
        let escaped = try ScriptParser.parse("literal \\*\\* stars and **bold**")
        check(escaped[0].text == "literal ** stars and bold", "Escaped markers remain literal")
        do { _ = try ScriptParser.parse("Unclosed **bold"); fatalError("Accepted malformed bold") } catch { count += 1; print("PASS: Reject unclosed formatting") }
        let punctuation = try ScriptParser.parse("**this jacket.**\r\n**GET YOURS NOW!**")
        check(punctuation.map { $0.highlights[0].text } == ["this jacket.", "GET YOURS NOW!"], "Preserve punctuation and CRLF")
        try ActionPolicy.validate(action("key", keys: ["shift", "option", "right"]))
        count += 1; print("PASS: Allow text-range navigation")
        check(rejects(action(x: -0.01)), "Reject out-of-window actions")
        check(rejects(action(x: Double.nan)), "Reject nonfinite coordinates")
        check(rejects(action("shell")), "Reject arbitrary execution")
        check(rejects(action("key", keys: ["delete"])), "Reject deletion")
        check(rejects(action("key", keys: ["command", "v"])), "Reject paste")
        check(rejects(action("key", keys: ["command", "q"])), "Reject quitting app")
        check(rejects(action("key", keys: ["left", "right"])), "Reject multiple base keys")
        check(rejects(action("scroll", scroll: 99)), "Bound scroll distance")
        let project = Project(name: "Test", script: "**text**", style: "Blue", styleImage: Data([1, 2, 3]))
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        check(decoded.id == project.id && decoded.styleImage == project.styleImage, "Project memory round trip")
        var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as! [String: Any]
        legacyObject.removeValue(forKey: "keepStyle")
        legacyObject.removeValue(forKey: "rememberedStyle")
        let legacyProject = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        check(legacyProject.keepsStyle && legacyProject.rememberedStyle == nil, "Old projects load with Keep style enabled")
        var rememberedProject = project
        rememberedProject.keepStyle = false
        rememberedProject.rememberedStyle = RememberedStyle(row: 4, column: 2, positionKnown: true,
                                                            appearance: [1, 2, 3, 4], imagePNG: Data([5, 6]))
        let restoredProject = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(rememberedProject))
        check(!restoredProject.keepsStyle && restoredProject.rememberedStyle?.row == 4
              && restoredProject.rememberedStyle?.column == 2 && restoredProject.rememberedStyle?.positionKnown == true
              && restoredProject.rememberedStyle?.appearance == [1, 2, 3, 4]
              && restoredProject.rememberedStyle?.imagePNG == Data([5, 6]), "Keep style preference and complete tile memory survive relaunch")
        check(project.rememberedStyle == nil, "Style memory belongs only to its project")
        let schema = AIClient.schema
        check((schema["additionalProperties"] as? Bool) == false, "Strict output schema")
        let data = try JSONSerialization.data(withJSONObject: schema)
        check(!data.isEmpty, "Schema serializes as valid JSON")
        let attributed = NSMutableAttributedString(string: "Now enjoy ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        attributed.append(NSAttributedString(string: "buttery-soft", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]))
        check(RichScript.markdown(attributed) == "Now enjoy **buttery-soft**", "Rich-text bold survives import")
        let semibold = NSAttributedString(string: "Highlight", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)])
        check(RichScript.markdown(semibold) == "**Highlight**", "Detect font-weight emphasis without bold trait")
        let legacyMessage = try JSONDecoder().decode(Message.self, from: Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"role\":\"user\",\"text\":\"hello\"}".utf8))
        check(legacyMessage.images == nil, "Existing conversations load without attachments")
        let attachmentMessage = Message(role: "user", text: "See this", images: [Data([1, 2, 3])])
        let restoredMessage = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(attachmentMessage))
        check(restoredMessage.images == attachmentMessage.images, "Screenshot attachments survive project save")
        let decision = Decision(message: "Ready", styleUpdate: nil, routineUpdate: nil, instructionUpdate: nil, clearStyleReference: false, action: action("ask"), confidence: 0.99, evidence: "Test")
        let decisionData = try JSONEncoder().encode(decision)
        let codexResult = try CLIClient.decode(decisionData, provider: "Codex")
        check(codexResult.message == "Ready", "Decode Codex decision file")
        let object = try JSONSerialization.jsonObject(with: decisionData)
        let claudeData = try JSONSerialization.data(withJSONObject: ["is_error": false, "structured_output": object])
        let claudeResult = try CLIClient.decode(claudeData, provider: "Claude")
        check(claudeResult.action.kind == "ask", "Decode Claude structured result")
        var stream = Data("{\"type\":\"system\",\"subtype\":\"init\"}\n".utf8)
        stream.append(try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "structured_output": object])); stream.append(10)
        let streamed = try CLIClient.decode(stream, provider: "Claude")
        check(streamed.message == "Ready", "Decode Claude streaming final result")
        var antigravityStream = Data("{\"event\":\"init\"}\n".utf8)
        antigravityStream.append(try JSONSerialization.data(withJSONObject: ["event": "result", "result": ["status": "SUCCESS", "structured_output": object]])); antigravityStream.append(10)
        let antigravityStreamed = try CLIClient.decode(antigravityStream, provider: "Antigravity")
        check(antigravityStreamed.message == "Ready", "Decode Antigravity streaming result")
        let antigravityPlain = try JSONSerialization.data(withJSONObject: ["status": "SUCCESS", "response": "```json\n" + String(decoding: decisionData, as: UTF8.self) + "\n```"])
        let antigravityFenced = try CLIClient.decode(antigravityPlain, provider: "Antigravity")
        check(antigravityFenced.message == "Ready", "Decode Antigravity fenced response")
        let antigravityDenied = try JSONSerialization.data(withJSONObject: ["status": "SUCCESS", "response": "", "denied_actions": [["action": "run_command"]]])
        do { _ = try CLIClient.decode(antigravityDenied, provider: "Antigravity"); fatalError("Accepted a denied-tool run") } catch { count += 1; print("PASS: Antigravity denied tools surface as an error") }
        do { _ = try CLIClient.decode(Data("{\"is_error\":true}".utf8), provider: "Claude"); fatalError("Accepted CLI error") } catch { count += 1 }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("edit-assist-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for provider in CLIProvider.allCases where provider.executable != nil {
            let prepared = try CLIClient.prepare(settings: AISettings(provider: provider.rawValue, model: ""), context: "Literal @/private/file $(no-shell) `text`", screenshot: Data([1]), previous: nil, style: nil, directory: directory)
            if let fast = provider.fastestModel {
                check(prepared.arguments.contains("--model") && prepared.arguments.contains(fast),
                      "\(provider.rawValue) defaults to its fast model rather than the slow CLI default")
                let pinned = try CLIClient.prepare(settings: AISettings(provider: provider.rawValue, model: "custom-model"), context: "c", screenshot: nil, previous: nil, style: nil, directory: directory)
                check(pinned.arguments.contains("custom-model") && !pinned.arguments.contains(fast), "\(provider.rawValue) still honours an explicit model override")
            } else {
                check(!prepared.arguments.contains("--model"), "\(provider.rawValue) uses CLI default model")
            }
            if provider == .claude {
                let input = try JSONSerialization.jsonObject(with: prepared.input) as! [String: Any]
                let blocks = (input["message"] as! [String: Any])["content"] as! [[String: Any]]
                check(blocks.last?["type"] as? String == "image", "Claude receives an actual image block")
            } else if provider == .antigravity {
                check(!prepared.arguments.joined().contains("/private/file"), "Antigravity does not expand user text as file paths")
                let input = try JSONSerialization.jsonObject(with: prepared.input) as! [String: Any]
                let blocks = ((input["message"] as! [String: Any])["content"] as! [[String: Any]])
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
                check(text.contains("latest-observation.png"), "Antigravity is told to view the screenshot file")
                check(prepared.environment["ANTIGRAVITY_EXECUTABLE_DATA_DIR"] != nil, "Antigravity uses a request-local config directory")
                let settings = prepared.environment["ANTIGRAVITY_EXECUTABLE_DATA_DIR"].map { URL(fileURLWithPath: $0).appendingPathComponent("settings.json") }
                let allowed = settings.flatMap { try? Data(contentsOf: $0) }.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
                check(allowed.contains("view_file") && !allowed.contains("run_command") && !allowed.contains("write"), "Antigravity may only view files, not run or write")
            } else { check(prepared.arguments.contains("--image"), "Codex attaches screenshot") }
        }
        // Deterministic span selection from measured OCR boxes.
        func word(_ t: String, _ x: Double, _ w: Double, _ y: Double) -> (String, CGRect) { (t, CGRect(x: x, y: y, width: w, height: 0.02)) }
        let line = TextHit(text: "until I found this jacket", rect: CGRect(x: 0.2, y: 0.74, width: 0.32, height: 0.02),
                           words: [word("until", 0.20, 0.05, 0.74), word("found", 0.33, 0.05, 0.74), word("this", 0.40, 0.05, 0.74), word("jacket", 0.46, 0.06, 0.74)])
        let span = Desktop.selection(for: "this jacket", in: [line])
        check(span != nil && abs(span!.start.x - 0.40) < 0.001 && abs(span!.end.x - 0.52) < 0.001, "Span selection uses measured first and last word boxes")
        check(Desktop.selection(for: "not on screen", in: [line]) == nil, "Span selection returns nothing rather than guessing")
        let twoLines = TextHit(text: "this jacket", rect: CGRect(x: 0.2, y: 0.74, width: 0.3, height: 0.02),
                            words: [word("this", 0.40, 0.05, 0.74), word("jacket", 0.46, 0.06, 0.90)])
        check(Desktop.selection(for: "this jacket", in: [twoLines]) == nil, "Span selection rejects words too far apart to be a wrap")
        let wide = TextHit(text: "this jacket", rect: CGRect(x: 0.2, y: 0.74, width: 0.05, height: 0.02),
                           words: [word("this", 0.20, 0.05, 0.74), word("jacket", 0.80, 0.06, 0.74)])
        check(Desktop.selection(for: "this jacket", in: [wide]) == nil, "Span selection rejects a span wider than its line")
        // Script markdown keeps punctuation and spacing the rendered caption does not have.
        let punctuated = TextHit(text: "until I found this jacket", rect: CGRect(x: 0.2, y: 0.74, width: 0.32, height: 0.02),
                                 words: [word("until", 0.20, 0.05, 0.74), word("found", 0.33, 0.05, 0.74), word("this", 0.40, 0.05, 0.74), word("jacket", 0.46, 0.06, 0.74)])
        check(Desktop.selection(for: "this jacket.", in: [punctuated]) != nil, "Span selection ignores trailing punctuation from the script")
        check(Desktop.selection(for: "  This   Jacket  ", in: [punctuated]) != nil, "Span selection ignores case and extra spacing")

        // Premiere ignores text edits until the caption's clip is selected in the timeline.
        func big(_ t: String, _ y: Double) -> TextHit {
            TextHit(text: t, rect: CGRect(x: 0.06, y: y, width: 0.18, height: 0.05),
                    words: t.split(separator: " ").enumerated().map { (String($1), CGRect(x: 0.06 + Double($0) * 0.06, y: y, width: 0.05, height: 0.05)) })
        }
        func clip(_ t: String, _ x: Double) -> TextHit {
            TextHit(text: t, rect: CGRect(x: x, y: 0.68, width: 0.12, height: 0.012), words: [])
        }
        let screen = [big("until I found", 0.35), big("this jacket", 0.41),
                      clip("I thought...", 0.47), clip("meant sque...", 0.57),
                      clip("until I found these...", 0.66), clip("The high-...", 0.80)]
        let picked = Desktop.captionClip(for: "this jacket.", in: screen)
        check(picked != nil && abs(picked!.minX - 0.66) < 0.001, "Caption clip matches the timeline label, not a neighbouring clip")
        check(Desktop.captionClip(for: "this jacket.", in: Array(screen.prefix(2))) == nil, "Caption clip returns nothing when no timeline label matches")
        let spanned = Desktop.selection(for: "this jacket.", in: screen)
        check(spanned != nil && spanned!.firstWord.x > spanned!.start.x && spanned!.firstWord.x < spanned!.end.x,
              "First-word target sits inside the span, not in the gap between words")

        // Font size: read the number at the right of its label, not the label itself.
        let sizeRow = [TextHit(text: "Font Size", rect: CGRect(x: 0.05, y: 0.40, width: 0.10, height: 0.02), words: []),
                       TextHit(text: "65", rect: CGRect(x: 0.90, y: 0.40, width: 0.04, height: 0.02), words: []),
                       TextHit(text: "Poppins", rect: CGRect(x: 0.05, y: 0.46, width: 0.10, height: 0.02), words: [])]
        let field = Desktop.numberField(labelled: "Font Size", in: sizeRow)
        check(field?.value == 65 && (field?.rect.midX ?? 0) > 0.8, "Font size reads the value at the right of its row")
        check(Desktop.numberField(labelled: "Font Size", in: Array(sizeRow.dropFirst(1))) == nil, "Font size returns nothing when the label is absent")
        var typing = action("typeNumber"); typing.phrase = "70"
        try ActionPolicy.validate(typing)
        count += 1; print("PASS: typeNumber accepts digits")
        var letters = action("typeNumber"); letters.phrase = "delete all"
        do { _ = try ActionPolicy.validate(letters); fatalError("Accepted non-digits") } catch { count += 1; print("PASS: typeNumber refuses anything but digits") }

        // Controls are located from the screenshot, never from a recorded click, so a project
        // carries to another machine with a different layout.
        check(Desktop.button(labelled: "Back", in: [TextHit(text: "Back", rect: CGRect(x: 0.05, y: 0.1, width: 0.06, height: 0.02), words: [])]) != nil,
              "Back is found by its own label")
        check(Desktop.button(labelled: "Back", in: [TextHit(text: "Forward", rect: .zero, words: [])]) == nil,
              "Back is not invented when absent")
        // A bitmap context stores rows top-down; an inverted grid would look for controls in the
        // wrong half of the window.
        let swatch = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let swatchContext = NSGraphicsContext(bitmapImageRep: swatch)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = swatchContext
        swatchContext.cgContext.setFillColor(.black); swatchContext.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        swatchContext.cgContext.setFillColor(.white); swatchContext.cgContext.fill(CGRect(x: 0, y: 28, width: 40, height: 12))
        NSGraphicsContext.restoreGraphicsState()
        let rows = Desktop.grid(swatch.cgImage!, width: 20, height: 20)
        check(rows[2 * 20 + 10] > 200 && rows[17 * 20 + 10] < 60, "Sample grid row 0 is the top of the image")

        // The playhead and the timeline scrollbar are both thin blue vertical lines. The ruler tells
        // them apart: its timecodes are centred on their ticks, so two of them give seconds-to-x.
        func stamp(_ text: String, _ x: Double, _ y: Double) -> TextHit {
            TextHit(text: text, rect: CGRect(x: x, y: y, width: 0.036, height: 0.012), words: [])
        }
        // Exactly as a real capture reads: the ruler row (05:00, 10:00) sits above the track rows,
        // and the Program Monitor has its own pair of timecodes — current time and duration — that
        // is indistinguishable from a ruler by count alone and sits below the tracks.
        let trackRow = TextHit(text: "Subtitle", rect: CGRect(x: 0.41, y: 0.6019, width: 0.025, height: 0.0092), words: [])
        let ruler = [stamp("00:00:07:06", 0.0160, 0.8509), stamp("00:00:33:20", 0.2340, 0.8519),
                     stamp("00:00:07:06", 0.3401, 0.5463), stamp("00:00:05:00", 0.5799, 0.5694),
                     stamp("00:00:10:00", 0.7791, 0.5694), trackRow]
        let predicted = Desktop.playheadFromRuler(in: ruler)
        check(predicted != nil && abs(predicted! - 0.6863) < 0.004,
              "Playhead position is derived from the ruler, matching the measured line")
        check(Desktop.playheadTime(in: ruler).map { abs($0 - 7.2) < 0.01 } == true,
              "The playhead's current time is read from the timeline header, not the monitor's duration")
        check(Desktop.seconds(ofTimecode: "00:00:07:06").map { abs($0 - 7.2) < 0.01 } == true, "A timecode converts to seconds")
        check(Desktop.seconds(ofTimecode: "not a timecode") == nil, "Non-timecode text is not read as a time")
        check(Desktop.playheadFromRuler(in: [stamp("00:00:05:00", 0.58, 0.57)]) == nil, "One ruler label is not enough to place the playhead")

        // The font size is small, isolated and low contrast, and a two-digit number has no
        // unambiguous orientation: "60" upside down reads as "09". One reading cannot be trusted.
        let sizeRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 300, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let sizeContext = NSGraphicsContext(bitmapImageRep: sizeRep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = sizeContext
        sizeContext.cgContext.setFillColor(CGColor(gray: 0.13, alpha: 1))
        sizeContext.cgContext.fill(CGRect(x: 0, y: 0, width: 1200, height: 300))
        NSAttributedString(string: "Font Size", attributes: [.font: NSFont.systemFont(ofSize: 22),
            .foregroundColor: NSColor(white: 0.85, alpha: 1)]).draw(at: NSPoint(x: 60, y: 150))
        NSAttributedString(string: "72", attributes: [.font: NSFont.systemFont(ofSize: 22),
            .foregroundColor: NSColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1)]).draw(at: NSPoint(x: 1080, y: 150))
        NSGraphicsContext.restoreGraphicsState()
        let sizeImage = sizeRep.cgImage!
        let sizeHits = Desktop.recognize(sizeImage)
        let read = Desktop.numberField(labelled: "Font Size", in: sizeHits, image: sizeImage)
        check(read?.value == 72, "The font size is read from its row, by majority across magnifications")
        check(Desktop.numberField(labelled: "Leading", in: sizeHits, image: sizeImage) == nil,
              "A label that is not on screen yields no value")

        // A one-word partial is weak evidence: "65" occurs in "After 65" as well as in "65% OFF".
        func capLine(_ t: String) -> TextHit {
            TextHit(text: t, rect: CGRect(x: 0.10, y: 0.63, width: 0.25, height: 0.04),
                    words: t.split(separator: " ").enumerated().map {
                        (String($1), CGRect(x: 0.10 + Double($0) * 0.07, y: 0.63, width: 0.06, height: 0.04)) })
        }
        check(Desktop.selection(forTokens: Desktop.normalized("65% OFF"), in: [capLine("After 65")]) == nil,
              "A single shared word does not count as a partial match")
        check(Desktop.selection(forTokens: Desktop.normalized("high-neck, ultra"), in: [capLine("The high-neck,")])?.matched == 2,
              "A two-word partial is still accepted")
        check(Desktop.selection(forTokens: ["lining"], in: [capLine("ultra-light lining")])?.matched == 1,
              "Finishing a phrase whose remainder is one word still works")
        // A screen where only interface-size text is readable has no caption: a caption clip's label in the
        // timeline is never taken for one (clicking and dragging it there moved the clip over another).
        var interfaceOnly = (0..<12).map { TextHit(text: "Label \($0)", rect: CGRect(x: 0.5, y: 0.05 * Double($0), width: 0.05, height: 0.015)) }
        interfaceOnly.append(TextHit(text: "ultra-light lini...", rect: CGRect(x: 0.772, y: 0.598, width: 0.05, height: 0.015),
                                     words: [("ultra-light", CGRect(x: 0.772, y: 0.598, width: 0.03, height: 0.015)), ("wais...", CGRect(x: 0.803, y: 0.598, width: 0.019, height: 0.015))]))
        check(Desktop.selection(forTokens: ["ultra", "light"], in: interfaceOnly) == nil,
              "With no caption readable, a timeline clip label is never selected as the caption")
        // Measured: a timeline clip label 0.0166 tall beside a 0.040 caption. With the caption height known
        // from an earlier phrase, the label is never taken for the rest of a split phrase.
        var timeline = (0..<12).map { TextHit(text: "Label \($0)", rect: CGRect(x: 0.5, y: 0.05 * Double($0), width: 0.05, height: 0.009)) }
        timeline.append(TextHit(text: "stretchy realj.. for all", rect: CGRect(x: 0.8619, y: 0.5969, width: 0.0785, height: 0.0166),
                                words: [("stretchy", CGRect(x: 0.8619, y: 0.5969, width: 0.025, height: 0.0166))]))
        check(Desktop.selection(forTokens: ["stretchy"], in: timeline) != nil, "Precondition: with only small text around, the label passes the plain filter")
        check(Desktop.selection(forTokens: ["stretchy"], in: timeline, minHeight: 0.0306 * 0.65) == nil,
              "Once a caption's height is known, a timeline clip label is not taken for the caption")
        // Measured: a timeline clip label read 0.0208 tall, close to a 0.031 caption. Where captions have
        // appeared (the Program Monitor, x 0.09-0.21) rules it out whatever its height.
        var beside = (0..<12).map { TextHit(text: "Label \($0)", rect: CGRect(x: 0.5, y: 0.05 * Double($0), width: 0.05, height: 0.0116)) }
        beside.append(TextHit(text: "ultra-light lini...", rect: CGRect(x: 0.772, y: 0.594, width: 0.05, height: 0.0215),
                              words: [("ultra-light", CGRect(x: 0.772, y: 0.594, width: 0.03, height: 0.0215))]))
        let monitor = CGRect(x: 0.09, y: 0.596, width: 0.12, height: 0.038).insetBy(dx: -0.10, dy: -0.40)
        check(Desktop.selection(forTokens: ["ultra", "light"], in: beside, minHeight: 0.0306 * 0.65) != nil,
              "Precondition: a tall timeline label can pass the height floor")
        check(Desktop.selection(forTokens: ["ultra", "light"], in: beside, minHeight: 0.0306 * 0.65, area: monitor) == nil,
              "Text outside the area where captions appear is never taken for a caption")
        // A recorded decision reads back exactly as written, so a kept run replays what it decided.
        let recordedHit = TextHit(text: "this jacket", rect: CGRect(x: 0.1, y: 0.6, width: 0.1, height: 0.03),
                                  words: [("this", CGRect(x: 0.1, y: 0.6, width: 0.04, height: 0.03))])
        let snapshot = Snapshot(kind: "phrase", note: "round trip", hits: [RecordedHit(recordedHit)], candidates: [["this", "jacket"]],
                                minHeight: 0.02, area: CGRect(x: 0, y: 0.5, width: 0.3, height: 0.3).recorded, found: 0, matched: 2, span: [0.1, 0.615, 0.2, 0.615])
        let readBack = try JSONDecoder().decode(Snapshot.self, from: try JSONEncoder().encode(snapshot))
        check(readBack.hits.first?.hit == recordedHit && readBack.hits.first?.hit.words.first?.1 == recordedHit.words.first?.1
              && readBack.candidates == snapshot.candidates && readBack.area == snapshot.area && readBack.span == snapshot.span,
              "A recorded decision reads back exactly as it was written")
        // A large caption set tight: the lines' centres are closer than a line is tall (measured on a
        // real styled caption). The rest of the phrase still runs across the wrap.
        let tight = [TextHit(text: "ultra-light", rect: CGRect(x: 0.283, y: 0.316, width: 0.283, height: 0.061), words: [("ultra-light", CGRect(x: 0.283, y: 0.316, width: 0.283, height: 0.061))]),
                     TextHit(text: "lining", rect: CGRect(x: 0.304, y: 0.380, width: 0.271, height: 0.070), words: [("lining", CGRect(x: 0.304, y: 0.380, width: 0.271, height: 0.070))])]
        check(Desktop.selection(forTokens: ["ultra", "light", "lining"], in: tight)?.matched == 3,
              "A phrase wrapping in a large, tightly spaced caption is selected across both lines")
        // The track header is the fallback for focusing the timeline when the playhead is off-screen.
        let header = Desktop.trackHeader(in: [TextHit(text: "Subtitle", rect: CGRect(x: 0.41, y: 0.60, width: 0.03, height: 0.01), words: [])])
        check(header != nil && abs(header!.x - 0.425) < 0.01, "The caption track header can be clicked to focus the timeline")
        check(Desktop.trackHeader(in: [TextHit(text: "Lumetri Scopes", rect: .zero, words: [])]) == nil, "An unrelated label is not used as the track header")

        // The style browser scrolls. Its tiles are found from their "Ag" labels, counted (a merged
        // "Ag Ag" box is two), and a scroll is detected by the grid actually changing.
        func tileHit(_ text: String, _ x: Double, _ y: Double) -> TextHit {
            TextHit(text: text, rect: CGRect(x: x, y: y, width: 0.05, height: 0.04), words: [])
        }
        let styleGrid = [TextHit(text: "Local Styles", rect: CGRect(x: 0.62, y: 0.20, width: 0.06, height: 0.02), words: []),
                       tileHit("Ag", 0.64, 0.30), tileHit("Ag", 0.72, 0.30), tileHit("Ag Ag", 0.80, 0.30),
                       tileHit("Ag", 0.64, 0.40), tileHit("Captions", 0.10, 0.40)]
        let browserLeft = Desktop.stylePanelLeft(in: styleGrid) ?? 0
        check(Desktop.styleTileCount(in: styleGrid, left: browserLeft) == 5, "Style tiles are counted from their labels, a merged box counting twice")
        let gridArea = Desktop.styleGridArea(in: styleGrid, left: browserLeft)
        check(gridArea != nil && gridArea!.minX >= 0.63 && gridArea!.maxY <= 0.45, "The style grid is the union of its tiles, not the rest of the window")
        func stripes(_ offset: Int) -> CGImage {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 400, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            context.cgContext.setFillColor(CGColor(gray: 0.12, alpha: 1)); context.cgContext.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            context.cgContext.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
            for row in stride(from: offset, to: 400, by: 60) { context.cgContext.fill(CGRect(x: 40, y: row, width: 320, height: 30)) }
            NSGraphicsContext.restoreGraphicsState()
            return rep.cgImage!
        }
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        check(Desktop.regionDifference(stripes(0), stripes(0), rect: whole) < 2, "An unscrolled browser reads as not moved, which ends the scan")
        check(Desktop.regionDifference(stripes(0), stripes(30), rect: whole) >= 2, "A scrolled browser reads as moved")
        var pagedLock = Desktop.StyleLock(match: .init(rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), score: 9), image: stripes(0), frame: .zero, reference: Data([1]))
        pagedLock.page = 2
        check(pagedLock.page == 2, "A style lock remembers which page of the browser its tile is on")

        // Your style is learned as a row and column of the browser grid. Cells come from the pixels:
        // a separator line above the grid, a scrollbar sliver and a cut-off bottom row must not count.
        let gridRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 700, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let gridContext = NSGraphicsContext(bitmapImageRep: gridRep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gridContext
        let ink = gridContext.cgContext
        ink.setFillColor(CGColor(gray: 31.0 / 255, alpha: 1)); ink.fill(CGRect(x: 0, y: 0, width: 1000, height: 700))
        ink.setFillColor(CGColor(gray: 0.45, alpha: 1)); ink.fill(CGRect(x: 0, y: 600, width: 1000, height: 3))       // separator line
        ink.fill(CGRect(x: 960, y: 200, width: 6, height: 380))                                                       // scrollbar sliver
        var tileCentres: [[CGPoint]] = []
        for (row, top) in [560, 362].enumerated() {                                                                   // two full rows (CG y is bottom-up)
            var centres: [CGPoint] = []
            for column in 0..<4 {
                let x = 40 + column * 198
                ink.setFillColor(CGColor(gray: 46.0 / 255, alpha: 1)); ink.fill(CGRect(x: x, y: top - 172, width: 172, height: 172))
                let hue: [CGColor] = [CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1), CGColor(gray: 1, alpha: 1),
                                      CGColor(red: 0.9, green: 0.3, blue: 0.5, alpha: 1), CGColor(red: 0.95, green: 0.7, blue: 0.2, alpha: 1)]
                ink.setFillColor(hue[(column + row) % 4]); ink.fill(CGRect(x: x + 50, y: top - 120, width: 72 + row * 10, height: 60))
                centres.append(CGPoint(x: (CGFloat(x) + 86) / 1000, y: (700 - CGFloat(top) + 86) / 700))
            }
            tileCentres.append(centres)
            _ = row
        }
        ink.setFillColor(CGColor(gray: 46.0 / 255, alpha: 1))
        for column in 0..<4 { ink.fill(CGRect(x: 40 + column * 198, y: 140, width: 172, height: 24)) }                   // cut-off third row
        NSGraphicsContext.restoreGraphicsState()
        let gridImage = gridRep.cgImage!
        var gridLabels = [TextHit(text: "Local Styles", rect: CGRect(x: 0.03, y: 0.10, width: 0.08, height: 0.02), words: [])]
        for row in tileCentres { for centre in row {
            gridLabels.append(TextHit(text: "Ag", rect: CGRect(x: centre.x - 0.05, y: centre.y - 0.05, width: 0.10, height: 0.10), words: []))
        } }
        let cells = Desktop.styleCells(in: gridLabels, image: gridImage, left: Desktop.stylePanelLeft(in: gridLabels) ?? 0)
        check(cells.count == 2 && cells.allSatisfy { $0.count == 4 }, "The style grid is read as rows and columns, ignoring a separator, a scrollbar and a cut-off row")
        check(Desktop.slot(containing: tileCentres[1][2], in: cells).map { $0.row == 1 && $0.column == 2 } == true,
              "A click on a tile is resolved to its row and column")
        check(Desktop.slot(containing: CGPoint(x: 0.99, y: 0.5), in: cells) == nil, "A click outside the tiles is not taken as a choice")
        // The end of a list: a short last row, one tile fully visible, then empty panel. Optionally that
        // tile is cut off by the bottom of the view, which must not count.
        func shortRowLook(lastCut: Bool, fullRows: Int = 2) -> [[CGRect]] {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 800, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            let pen = context.cgContext
            pen.setFillColor(CGColor(gray: 31.0 / 255, alpha: 1)); pen.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
            var labels = [TextHit(text: "Local Styles", rect: CGRect(x: 0.03, y: 0.05, width: 0.08, height: 0.02), words: [])]
            let tops = fullRows == 2 ? [720, 522, 324] : [640, 442]
            for (row, top) in tops.enumerated() {
                let short = row == tops.count - 1
                for column in 0 ..< (short ? 1 : 4) {
                    let x = 40 + column * 198
                    let height = short && lastCut ? 120 : 172
                    pen.setFillColor(CGColor(gray: 46.0 / 255, alpha: 1)); pen.fill(CGRect(x: x, y: top - height, width: 172, height: height))
                    pen.setFillColor(CGColor(red: 0.9, green: 0.4 + CGFloat(column) * 0.1, blue: 0.2, alpha: 1))
                    pen.fill(CGRect(x: x + 40, y: top - 120, width: 92, height: 60))
                    labels.append(TextHit(text: "Ag", rect: CGRect(x: (CGFloat(x) + 36) / 1000, y: (800 - CGFloat(top) + 50) / 800, width: 0.10, height: 0.09), words: []))
                }
            }
            if lastCut { pen.setFillColor(CGColor(gray: 20.0 / 255, alpha: 1)); pen.fill(CGRect(x: 0, y: 0, width: 1000, height: 204)) }   // panel edge
            NSGraphicsContext.restoreGraphicsState()
            return Desktop.styleCells(in: labels, image: rep.cgImage!, left: Desktop.stylePanelLeft(in: labels) ?? 0)
        }
        let shortRow = shortRowLook(lastCut: false)
        check(shortRow.map(\.count) == [4, 4, 1], "A short last row is read as a row of its own")
        check(shortRow.flatMap { $0 }.allSatisfy { abs($0.width - 0.172) < 0.01 }, "Tiles keep their full width beside a short last row")
        check(shortRowLook(lastCut: true).map(\.count) == [4, 4], "A short last row cut off by the view is not counted")
        check(shortRowLook(lastCut: false, fullRows: 1).map(\.count) == [4, 1],
              "Scrolled to the end, one full row and a short one above empty panel still read as a grid")
        let picture = Desktop.crop(gridImage, cell: cells[1][2])
        check(picture.map { abs($0.width - 172) <= 2 && abs($0.height - 172) <= 2 } == true, "The clicked tile is captured as an image of exactly that tile")
        let mine = Desktop.cellPatch(gridImage, cell: cells[1][2])
        let other = Desktop.cellPatch(gridImage, cell: cells[0][2])
        check(Desktop.glyphDifference(mine, mine) == 0, "A tile matches itself")
        check(Desktop.glyphDifference(mine, other) > 15, "A different preset in the same column does not pass for your style")

        // The overlay shows the grid as it is counted — one box per rounded tile, a colour per row —
        // instead of OCR's "Ag" boxes, which merge neighbouring tiles into one.
        let drawn = RunOverlay.ocrBoxes(gridLabels, image: gridImage)
        let rowsDrawn = drawn.filter { !$0.marker }.compactMap { box -> Int? in if case let .styleRow(row) = box.kind { return row }; return nil }
        check(rowsDrawn.count == 8 && Set(rowsDrawn) == [0, 1], "The overlay draws every tile, each row in its own colour")
        check(drawn.filter(\.marker).map(\.label) == ["1", "2"], "Each detected row is numbered on its left")
        check(!drawn.contains { $0.text == "Ag" && $0.kind != .styleRow(0) && $0.kind != .styleRow(1) },
              "OCR's merged tile boxes are not drawn over the grid")

        // Rows keep absolute numbers while the browser scrolls. Synthetic list: five rows of distinct
        // presets; a view shows two full rows starting at a given row.
        func listView(startingAt top: Int) -> (cells: [[CGRect]], image: CGImage) {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 500, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            let pen = context.cgContext
            pen.setFillColor(CGColor(gray: 31.0 / 255, alpha: 1)); pen.fill(CGRect(x: 0, y: 0, width: 900, height: 500))
            var cells: [[CGRect]] = []
            for visible in 0..<2 {
                let absolute = top + visible
                let y = 480 - (visible + 1) * 220
                var row: [CGRect] = []
                for column in 0..<4 {
                    let x = 30 + column * 210
                    pen.setFillColor(CGColor(gray: 46.0 / 255, alpha: 1)); pen.fill(CGRect(x: x, y: y, width: 190, height: 190))
                    // each preset differs by row and column: colour and glyph shape
                    let hue = CGFloat((absolute * 4 + column) % 7) / 7
                    pen.setFillColor(NSColor(hue: hue, saturation: 0.8, brightness: 0.95, alpha: 1).cgColor)
                    pen.fill(CGRect(x: x + 40 + absolute * 6, y: y + 50, width: 60 + column * 8, height: 80 - absolute * 9))
                    row.append(CGRect(x: CGFloat(x) / 900, y: CGFloat(500 - y - 190) / 500, width: 190.0 / 900, height: 190.0 / 500))
                }
                cells.append(row)
            }
            NSGraphicsContext.restoreGraphicsState()
            return (cells, rep.cgImage!)
        }
        let tracker = Desktop.StyleRowTracker()
        let atTopView = listView(startingAt: 0)
        check(tracker.observe(atTopView.cells, image: atTopView.image) == 0, "Rows are counted from the top when the browser opens")
        let oneDown = listView(startingAt: 1)
        check(tracker.observe(oneDown.cells, image: oneDown.image) == 1, "Scrolling down one row keeps rows numbered from the top")
        check(tracker.observe(atTopView.cells, image: atTopView.image) == 0, "Scrolling back up is followed too")
        let farDown = listView(startingAt: 3)
        check(tracker.observe(farDown.cells, image: farDown.image) == nil, "A jump further than one view is reported as lost, not guessed")
        tracker.atTop()
        check(tracker.offset == 0, "Reaching the top re-establishes the count")
        let anchored = Desktop.StyleRowTracker()
        _ = anchored.observe(listView(startingAt: 0).cells, image: listView(startingAt: 0).image)
        _ = anchored.observe(listView(startingAt: 3).cells, image: listView(startingAt: 3).image)
        anchored.atTop()
        _ = anchored.observe(atTopView.cells, image: atTopView.image, atTop: false)
        check(anchored.observe(oneDown.cells, image: oneDown.image) == 1,
              "After scrolling to the top, a lost count is re-anchored and then followed down")
        _ = tracker.observe(atTopView.cells, image: atTopView.image)
        _ = tracker.observe([], image: atTopView.image, panelOpen: false); _ = tracker.observe([], image: atTopView.image, panelOpen: false)
        check(tracker.observe(oneDown.cells, image: oneDown.image) == 1, "A brief gap in the panel's text does not reset the count")
        tracker.closedAfter = 0
        // Really closed: the tiles are gone from the screen, not just from the text reading.
        let closedPanel = CGContext(data: nil, width: 900, height: 500, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        _ = tracker.observe([], image: closedPanel, panelOpen: false)
        check(tracker.observe(oneDown.cells, image: oneDown.image) == 0, "A browser closed and reopened starts again at row 1")

        // Live scrolling: frames a few pixels apart, rows that look nearly alike, and some frames where
        // the grid cannot be made out. The count must hold all the way down and back.
        func smoothView(scroll: Int, thumb: Bool = false) -> (cells: [[CGRect]], image: CGImage) {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 500, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            let pen = context.cgContext
            pen.setFillColor(CGColor(gray: 31.0 / 255, alpha: 1)); pen.fill(CGRect(x: 0, y: 0, width: 900, height: 500))
            var cells: [[CGRect]] = []
            for absolute in 0..<8 {
                let top = 20 + absolute * 220 - scroll          // top-left coordinates
                guard top + 190 > 0, top < 500 else { continue }
                var row: [CGRect] = []
                for column in 0..<4 {
                    let x = 30 + column * 210
                    pen.setFillColor(CGColor(gray: 46.0 / 255, alpha: 1)); pen.fill(CGRect(x: x, y: 500 - top - 190, width: 190, height: 190))
                    // the same glyph in every row; only its colour varies a little from row to row
                    pen.setFillColor(NSColor(hue: CGFloat(column) / 4, saturation: 0.7, brightness: 0.9 - CGFloat(absolute % 3) * 0.04, alpha: 1).cgColor)
                    pen.fill(CGRect(x: x + 50, y: 500 - top - 140, width: 90, height: 90))
                    row.append(CGRect(x: CGFloat(x) / 900, y: CGFloat(top) / 500, width: 190.0 / 900, height: 190.0 / 500))
                }
                if top >= 0 && top + 190 <= 500 { cells.append(row) }
            }
            if thumb {
                // a scrollbar thumb right of the tiles, moving a third as far as the list
                pen.setFillColor(CGColor(gray: 0.5, alpha: 1))
                pen.fill(CGRect(x: 872, y: 500 - (20 + scroll / 3) - 120, width: 6, height: 120))
            }
            NSGraphicsContext.restoreGraphicsState()
            return (cells, rep.cgImage!)
        }
        let live = Desktop.StyleRowTracker()
        var positions = Array(stride(from: 0, through: 640, by: 23)) + Array(stride(from: 640, through: 150, by: -31))
        positions += Array(stride(from: 150, through: 900, by: 47))
        var held = true, frame = 0
        for position in positions {
            let view = smoothView(scroll: position)
            frame += 1
            let first = (0..<8).first { 20 + $0 * 220 - position >= 0 } ?? 0
            let seen = live.observe([3, 4].contains(frame % 6) ? [] : view.cells, image: view.image, atTop: position == 0)
            if ![3, 4].contains(frame % 6), !view.cells.isEmpty, seen != first { held = false; print("  frame \(frame) scroll \(position): \(seen.map(String.init) ?? "lost"), expected \(first)") }
        }
        check(held, "Live scrolling over look-alike rows keeps the count, through frames without a grid")
        let downward = Desktop.StyleRowTracker()
        downward.expected = 1
        var counts: [Int?] = []
        for position in stride(from: 0, through: 900, by: 37) {
            let view = smoothView(scroll: position)
            let expected = (0..<8).first { 20 + $0 * 220 - position >= 0 } ?? 0
            let seen = downward.observe(view.cells, image: view.image, atTop: position == 0)
            if !view.cells.isEmpty { counts.append(seen == expected ? seen : -1) }
        }
        check(!counts.contains(-1) && counts.compactMap { $0 } == counts.compactMap { $0 }.sorted(),
              "Scrolling down, the count only ever goes up and stays right")
        // A screenshot first, then the live stream's frames: a different kind of image of the same list
        // is a new reference, not a jump, and the count carries on.
        func asStreamFrame(_ image: CGImage) -> CGImage {
            let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            // the stream's frame differs a little, as a real one does
            context.setFillColor(CGColor(gray: 0, alpha: 0.12)); context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context.makeImage()!
        }
        let switching = Desktop.StyleRowTracker()
        _ = switching.observe(smoothView(scroll: 0).cells, image: smoothView(scroll: 0).image, atTop: true)
        var mixedHeld = true
        for position in stride(from: 0, through: 460, by: 23) {
            let view = smoothView(scroll: position)
            let expected = (0..<8).first { 20 + $0 * 220 - position >= 0 } ?? 0
            if switching.observe(view.cells, image: asStreamFrame(view.image)) != expected, !view.cells.isEmpty { mixedHeld = false }
        }
        check(mixedHeld, "Switching from a screenshot to streamed frames does not lose the count")
        // Lost in the live overlay, nothing scrolls to the top for the tracker: the thumb back at its top
        // position, or a reopened browser showing the top, has to bring the count back by itself.
        let browsing = Desktop.StyleRowTracker()
        _ = browsing.observe(smoothView(scroll: 0, thumb: true).cells, image: smoothView(scroll: 0, thumb: true).image, atTop: true)
        // A frame of something else entirely (the panel mid-redraw): nothing to follow, so the count is lost.
        let blank = CGContext(data: nil, width: 900, height: 500, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        _ = browsing.observe([], image: blank)
        check(browsing.offset == nil, "Precondition: a jump with an uncalibrated scrollbar loses the count")
        check(browsing.observe(smoothView(scroll: 0, thumb: true).cells, image: smoothView(scroll: 0, thumb: true).image, atTop: false) == 0,
              "Scrolled back to the top, the scrollbar thumb at its top position restores the count")
        let reopened = Desktop.StyleRowTracker()
        _ = reopened.observe(smoothView(scroll: 0).cells, image: smoothView(scroll: 0).image, atTop: true)
        _ = reopened.observe([], image: blank)
        _ = reopened.observe([], image: smoothView(scroll: 0).image, panelOpen: false)
        check(reopened.observe(smoothView(scroll: 0).cells, image: smoothView(scroll: 0).image, atTop: true) == 0,
              "A browser closed briefly and reopened at the top counts from row 1 again")
        // A reading that misses the panel's labels mid-scroll says "not open"; the list still on screen
        // says otherwise. The count must hold, and no later look may restart it at R1.
        let missed = Desktop.StyleRowTracker()
        var resets: [String] = []
        missed.onReset = { resets.append($0) }
        missed.closedAfter = 0   // the bad reading persists, as a reading of unchanged areas can
        _ = missed.observe(smoothView(scroll: 0).cells, image: smoothView(scroll: 0).image, atTop: true)
        var missedHeld = true
        for position in stride(from: 0, through: 460, by: 23) {
            let view = smoothView(scroll: position)
            let expected = (0..<8).first { 20 + $0 * 220 - position >= 0 } ?? 0
            if position == 230 || position == 253 { _ = missed.observe([], image: view.image, panelOpen: false); continue }
            // just after the missed reading, a view at a row boundary that looks like the top
            if missed.observe(view.cells, image: view.image, atTop: position % 220 == 0) != expected, !view.cells.isEmpty { missedHeld = false }
        }
        check(missedHeld && resets.isEmpty, "A reading that misses the panel's labels mid-scroll does not restart the row count")
        let barred = Desktop.StyleRowTracker()
        for position in stride(from: 0, through: 300, by: 25) {
            let view = smoothView(scroll: position, thumb: true)
            _ = barred.observe(view.cells, image: view.image, atTop: position == 0)
        }
        let jumped = smoothView(scroll: 1100, thumb: true)
        check(barred.observe(jumped.cells, image: jumped.image) == 5,
              "After a jump the pixels cannot follow, the scrollbar gives the right row")

        // Colour is a hard gate: the same letters in pink and in maroon never match.
        func tilePatch(_ colour: CGColor) -> [UInt8] {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 200, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            context.cgContext.setFillColor(CGColor(gray: 46.0 / 255, alpha: 1)); context.cgContext.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            context.cgContext.setFillColor(CGColor(gray: 1, alpha: 1)); context.cgContext.fill(CGRect(x: 40, y: 50, width: 120, height: 100))
            context.cgContext.setFillColor(colour); context.cgContext.fill(CGRect(x: 50, y: 60, width: 100, height: 80))
            NSGraphicsContext.restoreGraphicsState()
            return Desktop.cellPatch(rep.cgImage!, cell: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let maroon = Desktop.StyleSlot(row: 0, column: 0, positionKnown: true, appearance: tilePatch(CGColor(red: 0.63, green: 0.16, blue: 0.25, alpha: 1)))
        check(maroon.difference(from: tilePatch(CGColor(red: 0.63, green: 0.16, blue: 0.25, alpha: 1))) < 12, "The same coloured tile matches")
        check(maroon.difference(from: tilePatch(CGColor(red: 0.92, green: 0.30, blue: 0.55, alpha: 1))) >= 500, "Pink never passes for maroon")

        // "At the top" is read from one look, so a lost count recovers by itself. At the top, only the
        // header's edge and flat background sit above the first full row; scrolled, a cut-off row does.
        let topLook = Desktop.styleGrid(in: gridLabels, image: gridImage, left: Desktop.stylePanelLeft(in: gridLabels) ?? 0)
        check(topLook.atTop == true, "A browser at the top of its list is recognised from one look")
        let scrolledRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 700, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        scrolledRep.bitmapData!.update(from: gridRep.bitmapData!, count: gridRep.bytesPerRow * 700)
        let scrolledContext = NSGraphicsContext(bitmapImageRep: scrolledRep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = scrolledContext
        scrolledContext.cgContext.setFillColor(CGColor(gray: 46.0 / 255, alpha: 1))
        for column in 0..<4 { scrolledContext.cgContext.fill(CGRect(x: 40 + column * 198, y: 568, width: 172, height: 28)) }   // a cut-off row above
        NSGraphicsContext.restoreGraphicsState()
        let scrolledLook = Desktop.styleGrid(in: gridLabels, image: scrolledRep.cgImage!, left: Desktop.stylePanelLeft(in: gridLabels) ?? 0)
        check(scrolledLook.atTop == false, "A scrolled browser is recognised by the cut-off row above the first full row")
        let recovering = Desktop.StyleRowTracker()
        _ = recovering.observe(listView(startingAt: 0).cells, image: listView(startingAt: 0).image)
        _ = recovering.observe(listView(startingAt: 3).cells, image: listView(startingAt: 3).image)
        check(recovering.offset == nil, "Precondition: the count is lost")
        check(recovering.observe(listView(startingAt: 0).cells, image: listView(startingAt: 0).image, atTop: true) == nil,
              "One look that resembles the top does not reset a lost count; a wrong number would be clicked")
        recovering.atTop()
        check(recovering.observe(listView(startingAt: 0).cells, image: listView(startingAt: 0).image) == 0,
              "Scrolling to the top recovers a lost count")
        let fresh = Desktop.StyleRowTracker()
        check(fresh.observe(listView(startingAt: 1).cells, image: listView(startingAt: 1).image, atTop: false) == nil,
              "A first look that is visibly scrolled is not assumed to be the top")

        // Something covering the target is recoverable: the run waits for it to be cleared.
        let blocked = AssistError.blocked("Finder")
        check(blocked.localizedDescription.contains("Finder") && blocked.localizedDescription.contains("covering"),
              "A blocked target names what is in the way")
        var caught = false
        do { throw AssistError.blocked("Mail") } catch AssistError.blocked { caught = true } catch { }
        check(caught, "A blocked target is catchable separately from an ordinary failure")
        var ordinary = false
        do { throw AssistError.message("something else") } catch AssistError.blocked { } catch { ordinary = true }
        check(ordinary, "An ordinary failure is not mistaken for a blocked target")

        // Whether a clip is selected is read from the Properties panel, which is what makes the D
        // shortcut verifiable rather than hopeful.
        func panelLine(_ t: String) -> TextHit { TextHit(text: t, rect: CGRect(x: 0.6, y: 0.1, width: 0.2, height: 0.015), words: []) }
        check(Desktop.clipIsSelected(in: [panelLine("C1:Subtitle"), panelLine("Track Style"), panelLine("None")]),
              "A selected caption clip is recognised from the Properties panel")
        check(Desktop.clipIsSelected(in: [panelLine("4 After 65"), panelLine("After 65"), panelLine("V Text"), panelLine("Poppins"), panelLine("Font Size"), panelLine("V Appearance")]),
              "A selected graphic, which has no C1 header or Track Style row, is recognised as selected")
        check(!Desktop.clipIsSelected(in: [panelLine("Select a clip in the timeline to view properties.")]),
              "The empty Properties panel is recognised as nothing selected")
        check(!Desktop.clipIsSelected(in: [panelLine("Lumetri Scopes"), panelLine("Ready to send")]),
              "An unrelated panel is not mistaken for a selection")
        var pressD = action("key"); pressD.keys = ["d"]
        try ActionPolicy.validate(pressD)
        count += 1; print("PASS: d is allowed as Select Clip at Playhead")

        // The caption text also appears in the Properties panel field and in timeline clip labels,
        // at interface size. Selecting there edits nothing, so only monitor-sized text counts.
        func uiLine(_ text: String, _ y: Double, _ height: Double) -> TextHit {
            TextHit(text: text, rect: CGRect(x: 0.1, y: y, width: 0.25, height: height),
                    words: text.split(separator: " ").enumerated().map {
                        (String($1), CGRect(x: 0.1 + Double($0) * 0.06, y: y, width: 0.05, height: height)) })
        }
        let mixed = [uiLine("The high-neck", 0.60, 0.032),
                     uiLine("until I found this jacket", 0.09, 0.014),
                     uiLine("until I found these...", 0.80, 0.012),
                     uiLine("Lumetri Scopes", 0.05, 0.015),
                     uiLine("Auto Captions", 0.30, 0.015),
                     uiLine("Ready to send", 0.40, 0.015)]
        check(Desktop.selection(for: "this jacket.", in: mixed) == nil,
              "A phrase only present in interface text is not selected")
        check(Desktop.selection(forTokens: Desktop.normalized("high-neck, ultra"), in: mixed)?.matched == 2,
              "The monitor caption is still matched when interface text is excluded")

        // A caption that wraps is one phrase across two lines, and must still be selectable.
        func wrapLine(_ text: String, _ y: Double) -> TextHit {
            TextHit(text: text, rect: CGRect(x: 0.10, y: y, width: 0.26, height: 0.05),
                    words: text.split(separator: " ").enumerated().map {
                        (String($1), CGRect(x: 0.10 + Double($0) * 0.13, y: y, width: 0.12, height: 0.05))
                    })
        }
        let wrapped = Desktop.selection(for: "ultra-light lining ", in: [wrapLine("ultra-light", 0.34), wrapLine("lining", 0.41)])
        check(wrapped != nil && wrapped!.end.y > wrapped!.start.y, "A phrase wrapped onto a second line is selected across the wrap")
        check(Desktop.selection(for: "ultra-light", in: [wrapLine("ultra-light", 0.34)]) != nil, "A hyphenated word matches as one word")
        let cover = Desktop.coverage(for: "high-neck, ultra-light lining", in: [wrapLine("ultra-light", 0.34), wrapLine("lining", 0.41)])
        check(cover.matched == 3 && cover.total == 5, "Coverage reports a phrase only partly on screen")

        // Premiere splits a long phrase across caption clips, so a pass styles the visible part and
        // the remainder carries to the next clip.
        let phraseWords = Desktop.normalized("high-neck, ultra-light lining ")
        check(phraseWords == ["high", "neck", "ultra", "light", "lining"], "A phrase splits into its words")
        let firstClip = Desktop.selection(forTokens: phraseWords, in: [wrapLine("The high-neck,", 0.34)])
        check(firstClip?.matched == 2, "Only the words present on this clip are selected")
        let secondClip = Desktop.selection(forTokens: Array(phraseWords.dropFirst(2)), in: [wrapLine("ultra-light", 0.34), wrapLine("lining", 0.41)])
        check(secondClip?.matched == 3, "The remainder is selected on the next clip")
        check(Desktop.selection(forTokens: phraseWords, in: [wrapLine("nothing here", 0.34)]) == nil, "No words present means no selection")
        // A full match must still require every word, so a partial never counts as complete.
        check(Desktop.selection(for: "high-neck, ultra-light lining ", in: [wrapLine("The high-neck,", 0.34)]) == nil,
              "A partial match is not reported as the whole phrase")

        // The same words appear in the big Program Monitor caption and in a small timeline clip
        // label. Selecting inside the clip label would edit nothing, so the larger one wins.
        func sized(_ text: String, _ y: Double, _ height: Double) -> TextHit {
            TextHit(text: text, rect: CGRect(x: 0.1, y: y, width: 0.3, height: height),
                    words: text.split(separator: " ").enumerated().map {
                        (String($1), CGRect(x: 0.1 + Double($0) * 0.08, y: y, width: 0.07, height: height))
                    })
        }
        let monitorLine = sized("this jacket", 0.40, 0.05)
        let clipLabel = sized("this jacket", 0.80, 0.009)
        let bigger = Desktop.selection(for: "this jacket", in: [clipLabel, monitorLine])
        check(bigger != nil && abs(bigger!.start.y - 0.425) < 0.02, "Selection prefers the large caption over a small timeline label")

        // Same-sized text elsewhere in the window must not join the caption block, or the word
        // list it is matched against becomes the whole UI.
        let farAway = TextHit(text: "until I found this jacket in the timeline", rect: CGRect(x: 0.12, y: 0.05, width: 0.3, height: 0.05),
                              words: [], )
        let nearLine = sized("until I found", 0.34, 0.05)
        let anchorLine = sized("this jacket", 0.40, 0.05)
        let label = TextHit(text: "until I found these...", rect: CGRect(x: 0.55, y: 0.80, width: 0.12, height: 0.009), words: [])
        check(Desktop.captionClip(for: "this jacket", in: [farAway, nearLine, anchorLine, label]) != nil,
              "Caption block ignores same-sized text far from the caption")

        // A caption rendering in the monitor means the playhead is on its clip, so the clip is found
        // under the playhead rather than by matching a truncated label.
        let headRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 900, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let headContext = NSGraphicsContext(bitmapImageRep: headRep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = headContext
        headContext.cgContext.setFillColor(CGColor(gray: 0.15, alpha: 1))
        headContext.cgContext.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        // orange caption clips along the track, then the blue playhead crossing them
        headContext.cgContext.setFillColor(CGColor(red: 0.95, green: 0.74, blue: 0.33, alpha: 1))
        headContext.cgContext.fill(CGRect(x: 400, y: 300, width: 1100, height: 40))
        headContext.cgContext.setFillColor(CGColor(red: 0.18, green: 0.55, blue: 0.95, alpha: 1))
        headContext.cgContext.fill(CGRect(x: 980, y: 200, width: 5, height: 300))
        NSGraphicsContext.restoreGraphicsState()
        let trackLabel = TextHit(text: "Subtitle", rect: CGRect(x: 0.14, y: 0.615, width: 0.05, height: 0.03), words: [])
        let atPlayhead = Desktop.clipAtPlayhead(in: [trackLabel], image: headRep.cgImage!)
        check(atPlayhead != nil && abs(atPlayhead!.x - 0.614) < 0.01, "Clip is found under the playhead, not by its label")
        check(atPlayhead != nil && abs(atPlayhead!.y - 0.63) < 0.03, "Clip click lands on the caption track row")
        // No playhead drawn: it must not invent one from the orange clips.
        let noHead = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 900, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let plainContext = NSGraphicsContext(bitmapImageRep: noHead)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = plainContext
        plainContext.cgContext.setFillColor(CGColor(gray: 0.15, alpha: 1))
        plainContext.cgContext.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        plainContext.cgContext.setFillColor(CGColor(red: 0.95, green: 0.74, blue: 0.33, alpha: 1))
        plainContext.cgContext.fill(CGRect(x: 400, y: 300, width: 1100, height: 40))
        NSGraphicsContext.restoreGraphicsState()
        check(Desktop.clipAtPlayhead(in: [trackLabel], image: noHead.cgImage!) == nil, "No playhead means no guess")

        // The clip finder must anchor on the monitor caption too, or there is nothing smaller left
        // to match the timeline label against.
        let monitorBlock = [sized("until I found", 0.34, 0.05), sized("this jacket", 0.40, 0.05)]
        let timelineLabel = TextHit(text: "until I found these...", rect: CGRect(x: 0.55, y: 0.80, width: 0.12, height: 0.009), words: [])
        let anchoredBig = Desktop.captionClip(for: "this jacket", in: monitorBlock + [timelineLabel, clipLabel])
        check(anchoredBig != nil && abs(anchoredBig!.minX - 0.55) < 0.001, "Caption clip anchors on the monitor caption, not a timeline label")

        // Tiles can share hue, typeface and size and differ only in stroke weight. Average colour
        // barely separates them; the edge term is what does.
        func strokeTile(_ stroke: CGFloat) -> CGImage {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 160, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            context.cgContext.setFillColor(CGColor(gray: 0.22, alpha: 1))
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            NSAttributedString(string: "Ag", attributes: [
                .font: NSFont.systemFont(ofSize: 76, weight: .heavy),
                .foregroundColor: NSColor(red: 0.16, green: 0.45, blue: 0.85, alpha: 1),
                .strokeColor: NSColor.white, .strokeWidth: -stroke]).draw(at: NSPoint(x: 24, y: 44))
            NSGraphicsContext.restoreGraphicsState()
            return rep.cgImage!
        }
        let thin = strokeTile(4), thick = strokeTile(13)
        let thinPixels = Desktop.colourGrid(thin, width: thin.width, height: thin.height)
        let thickPixels = Desktop.colourGrid(thick, width: thick.width, height: thick.height)
        let sameTile = Desktop.detailScore(thickPixels, thickPixels, width: thick.width, height: thick.height)
        let otherTile = Desktop.detailScore(thinPixels, thickPixels, width: thick.width, height: thick.height)
        check(sameTile == 0, "A style tile scores zero against itself")
        check(otherTile > 10, "A different stroke weight scores far from a match, so the right tile wins")

        // The four-square browser button is on the Track Style VALUE row. The header row's
        // right-hand control is +, which creates a style instead of opening the browser. Rendered at
        // a realistic window size, because downscaling smears a 20px icon into the background.
        let styleRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2400, pixelsHigh: 1000, bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let styleContext = NSGraphicsContext(bitmapImageRep: styleRep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = styleContext
        styleContext.cgContext.setFillColor(CGColor(gray: 0.13, alpha: 1))
        styleContext.cgContext.fill(CGRect(x: 0, y: 0, width: 2400, height: 1000))
        styleContext.cgContext.setFillColor(CGColor(gray: 0.9, alpha: 1))
        styleContext.cgContext.fill(CGRect(x: 2300, y: 880, width: 20, height: 20))      // + on the header row
        styleContext.cgContext.fill(CGRect(x: 2300, y: 780, width: 24, height: 24))      // four-square on the value row
        styleContext.cgContext.setFillColor(CGColor(gray: 0.45, alpha: 1))
        styleContext.cgContext.fill(CGRect(x: 2386, y: 300, width: 6, height: 600))      // scrollbar at the far right
        NSGraphicsContext.restoreGraphicsState()
        let styleImage = styleRep.cgImage!
        let headerRow = TextHit(text: "Track Style", rect: CGRect(x: 0.60, y: 0.09, width: 0.12, height: 0.03), words: [])
        let valueRow = TextHit(text: "None", rect: CGRect(x: 0.61, y: 0.19, width: 0.07, height: 0.03), words: [])
        let browser = Desktop.styleBrowserButton(in: [headerRow, valueRow], image: styleImage)
        check(browser != nil && browser!.y > 0.17 && browser!.y < 0.24, "Style browser button is taken from the value row, not the header's +")
        check(browser != nil && browser!.x > 0.955 && browser!.x < 0.975, "Style browser button is the icon, not the scrollbar at the panel edge")
        check(Desktop.styleBrowserButton(in: [headerRow], image: styleImage) == nil, "Style browser button is not guessed when the value row is missing")

        // Style tiles differ by hue, not brightness: a grayscale match picks a pink tile when the
        // project's style is blue, which is what happened in practice.
        let blue = NSColor(red: 0.16, green: 0.45, blue: 0.85, alpha: 1)
        let pink = NSColor(red: 0.93, green: 0.26, blue: 0.55, alpha: 1)
        func scene(target: NSColor?, filler: NSColor) -> CGImage {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 400, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            context.cgContext.setFillColor(CGColor(gray: 0.12, alpha: 1))
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            for index in 0..<4 {
                let colour = (index == 2 ? target : nil) ?? filler
                context.cgContext.setFillColor(colour.cgColor)
                context.cgContext.fill(CGRect(x: 30 + (index % 2) * 190, y: 30 + (index / 2) * 190, width: 150, height: 150))
            }
            NSGraphicsContext.restoreGraphicsState()
            return rep.cgImage!
        }
        func tile(_ colour: NSColor) -> CGImage {
            scene(target: colour, filler: colour).cropping(to: CGRect(x: 40, y: 40, width: 120, height: 120))!
        }
        check(Desktop.locate(tile(blue), in: scene(target: blue, filler: pink)) != nil, "A blue style tile is found among pink ones")
        check(Desktop.locate(tile(blue), in: scene(target: nil, filler: pink)) == nil, "A blue style does not match a panel of pink tiles of the same luminance")

        let firstTile = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        let secondTile = CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3)
        let closeStyles = [Desktop.StyleMatch(rect: firstTile, score: 12), Desktop.StyleMatch(rect: secondTile, score: 14)]
        check(Desktop.unambiguousStyle(closeStyles) == nil, "Reject two near-equal styles even when both pass the absolute threshold")
        check(Desktop.unambiguousStyle([.init(rect: firstTile, score: 12), .init(rect: secondTile, score: 22)])?.point == CGPoint(x: 0.25, y: 0.25), "Accept a distinct best style")
        check(Desktop.unambiguousStyle([.init(rect: firstTile, score: 29)]) == nil, "Reject a unique but poor style match")
        check(Desktop.distinctStyles([.init(rect: firstTile, score: 12), .init(rect: firstTile.insetBy(dx: 0.01, dy: 0.01), score: 13)]).count == 1, "Scale proposals at one tile do not cause false ambiguity")
        let sourceScene = scene(target: blue, filler: pink)
        let lockFrame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let referenceID = Data([1, 2, 3])
        let lock = Desktop.StyleLock(match: .init(rect: firstTile, score: 12), image: sourceScene, frame: lockFrame, reference: referenceID)
        check(lock.isValid(in: sourceScene, frame: lockFrame, reference: referenceID), "Reuse unchanged locked tile")
        check(!lock.isValid(in: scene(target: nil, filler: pink), frame: lockFrame, reference: referenceID), "Reject replacement of locked blue tile with a different style")
        check(!lock.isValid(in: sourceScene, frame: lockFrame.offsetBy(dx: 10, dy: 0), reference: referenceID), "Invalidate style lock when window geometry changes")
        check(!lock.isValid(in: sourceScene, frame: lockFrame, reference: Data([4])), "Invalidate style lock when project reference changes")
        let duplicateCandidates = Desktop.styleCandidates(tile(blue), in: scene(target: blue, filler: blue))
        check(duplicateCandidates.count >= 2 && Desktop.unambiguousStyle(duplicateCandidates) == nil, "Image matcher rejects equally blue tiles at separate positions")

        let inspectionHit = TextHit(text: "this jacket", rect: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.05))
        let inspectionBoxes = RunOverlay.ocrBoxes([inspectionHit])
        check(inspectionBoxes.count == 1 && inspectionBoxes[0].kind == .candidate, "Inspection uses the matcher's caption eligibility")
        check(inspectionBoxes[0].displayedLabel(text: true, details: false) == "this jacket", "Text-only detection hides classification and geometry")
        check(!inspectionBoxes[0].displayedLabel(text: false, details: true).contains("this jacket"), "Details-only detection hides recognized text")
        check(inspectionBoxes[0].displayedLabel(text: false, details: false).isEmpty, "Boxes-only detection has no labels")
        check(inspectionBoxes[0].displayedLabel(text: true, details: true).contains("Caption candidate"), "Combined detection shows classification")

        var pixelScroll = action("scroll"); pixelScroll.keys = ["pixels"]; pixelScroll.scroll = 192
        try ActionPolicy.validate(pixelScroll)
        count += 1; print("PASS: A pixel scroll as far as eight lines is accepted")
        var lineScroll = action("scroll"); lineScroll.scroll = 192
        do { try ActionPolicy.validate(lineScroll); fatalError("Accepted a 192-line scroll") } catch { count += 1; print("PASS: A line scroll beyond eight lines is refused") }
        var selectAction = action("selectSpan"); selectAction.phrase = "this jacket"
        try ActionPolicy.validate(selectAction)
        count += 1; print("PASS: selectSpan with a phrase is accepted")
        do { _ = try ActionPolicy.validate(action("selectSpan")); fatalError("Accepted selectSpan without a phrase") } catch { count += 1; print("PASS: selectSpan without a phrase is refused") }

        let echo = CLIRequest(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], input: Data("literal $(echo nope)".utf8), outputFile: nil)
        let echoed = try await CLIProcess.run(echo, directory: directory, timeout: 15)
        check(String(decoding: echoed, as: UTF8.self) == "literal $(echo nope)", "Subprocess stdin is not interpreted as shell")
        let sleeper = CLIRequest(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], input: Data(), outputFile: nil)
        do { _ = try await CLIProcess.run(sleeper, directory: directory, timeout: 0.2); fatalError("Timeout did not stop process") } catch { count += 1; print("PASS: CLI timeout terminates process") }
        let pending = Task { try await CLIProcess.run(sleeper, directory: directory, timeout: 30) }
        try await Task.sleep(for: .milliseconds(150)); pending.cancel()
        do { _ = try await pending.value; fatalError("Cancellation did not stop process") } catch is CancellationError { count += 1; print("PASS: CLI cancellation stops process") }
        check(CLIProcess.loginRequired("Opening authentication page in your browser. Do you want to continue? [Y/n]: "), "Detect interactive CLI login instead of hanging")
        print("\(count) checks passed. No desktop input was sent.")
        // Exit explicitly: AppKit objects created by the checks keep the process alive after main
        // returns, which left finished runs hanging and made ./test.sh appear to time out.
        exit(0)
    }
}
