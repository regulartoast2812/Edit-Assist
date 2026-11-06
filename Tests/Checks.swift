import Foundation
import AppKit

@main
struct Checks {
    static func main() async throws {
        // A run stopped inside the language checks leaves Vietnamese saved; every run starts in the Mac's language.
        UserDefaults.standard.removeObject(forKey: "appLanguage")
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
        // Highlight graphics scrolls the Properties panel in bursts of these steps (Store.scrollBurst); a step
        // the policy refuses would stop every graphics run at its first phrase.
        check(!rejects(action("scroll", keys: ["pixels"], scroll: -192)) && !rejects(action("scroll", keys: ["pixels"], scroll: 192))
              && !rejects(action("scroll", keys: ["pixels"], scroll: 96)), "Allow the graphics scroll steps")
        check(rejects(action("scroll", scroll: 12)), "Refuse a scroll beyond eight lines a step")
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
        // Panel tabs, as read on a real screen: a row of tabs, the Properties menu icon, tabs with a sequence
        // or project name. "Text" as a section header inside Properties is not a tab.
        func tab(_ text: String, _ x: Double, _ y: Double) -> TextHit { TextHit(text: text, rect: CGRect(x: x, y: y, width: 0.04, height: 0.0116)) }
        var tabScreen = [tab("Properties =", 0.635, 0.051), tab("Effect Controls", 0.688, 0.051), tab("Lumetri Color", 0.752, 0.051),
                         tab("Captioneer", 0.814, 0.051), tab("Text", 0.869, 0.051), tab("Program: Tool Test", 0.10, 0.03),
                         tab("Audio Track Mixer: Tool Test | = Project: EasyShape", 0.30, 0.03), tab("V Text", 0.637, 0.257), tab("Font Size", 0.645, 0.347)]
        tabScreen += (0..<8).map { tab("label \($0)", 0.4, 0.5 + 0.02 * Double($0)) }
        let foundTabs = Set(Desktop.panelTabs(in: tabScreen).map(\.panel))
        check(foundTabs == ["Properties", "Effect Controls", "Lumetri Color", "Text", "Program", "Audio Track Mixer", "Project"],
              "Premiere's panels are recognised by their tab names, also when two tabs read as one line, and a Text section header is not a tab")
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
        func smoothView(scroll: Int, thumb: Bool = false, thumbAt: Int? = nil) -> (cells: [[CGRect]], image: CGImage) {
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
                pen.fill(CGRect(x: 872, y: 500 - (20 + (thumbAt ?? scroll / 3)) - 120, width: 6, height: 120))
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
        _ = browsing.observe(smoothView(scroll: 0, thumb: true).cells, image: smoothView(scroll: 0, thumb: true).image, atTop: false)
        check(browsing.observe(smoothView(scroll: 0, thumb: true).cells, image: smoothView(scroll: 0, thumb: true).image, atTop: false) == 0,
              "Scrolled back to the top, the scrollbar thumb at its top position restores the count")
        // A count being followed is never replaced by a frame that merely reads as the top. A short list's
        // thumb barely moves (here 1 px per 40 of scroll), so scrolled by whole rows to R3 the thumb is still level
        // with the first full row and no row shows above: the old rule took that for the top and restarted at R1
        // (2026-10-13, four times). The count stays R3.
        let followed = Desktop.StyleRowTracker()
        for scroll in stride(from: 0, through: 440, by: 20) {
            let view = smoothView(scroll: scroll, thumb: true, thumbAt: scroll / 40)
            _ = followed.observe(view.cells, image: view.image, atTop: scroll == 0)
        }
        let followedBefore = followed.offset
        let falseTop = smoothView(scroll: 440, thumb: true, thumbAt: 11)
        for _ in 0 ..< 8 { _ = followed.observe(falseTop.cells, image: falseTop.image) }
        check(followedBefore == 2 && followed.offset == 2, "A followed count is not replaced by a frame that reads as the top (R\((followedBefore ?? -1) + 1) stays, now R\((followed.offset ?? -1) + 1))")
        let reopened = Desktop.StyleRowTracker()
        _ = reopened.observe(smoothView(scroll: 0).cells, image: smoothView(scroll: 0).image, atTop: true)
        _ = reopened.observe([], image: blank)
        // Closed: the tiles are gone from the screen as well as from the reading, for two looks.
        _ = reopened.observe([], image: blank, panelOpen: false); _ = reopened.observe([], image: blank, panelOpen: false)
        check(reopened.observe(smoothView(scroll: 0).cells, image: smoothView(scroll: 0).image, atTop: true) == 0,
              "A browser closed briefly and reopened at the top counts from row 1 again")
        // A reading that misses the panel's labels mid-scroll says "not open"; the list still on screen
        // says otherwise. The count must hold, and no later look may restart it at R1.
        let missed = Desktop.StyleRowTracker()
        var resets: [String] = []
        missed.onReset = { why, _, _ in resets.append(why) }
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
        // Scrolled down, the browser closed (the tiles gone), then reopened at the top a moment later:
        // the count starts again at R1, it is not left lost.
        let reopening = Desktop.StyleRowTracker()
        // With a scrollbar, so the counter has learned where it sits at the top...
        for position in stride(from: 0, through: 460, by: 23) {
            _ = reopening.observe(smoothView(scroll: position, thumb: true).cells, image: smoothView(scroll: position, thumb: true).image, atTop: position == 0)
        }
        let gone = CGContext(data: nil, width: 900, height: 500, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        _ = reopening.observe([], image: gone, panelOpen: false); _ = reopening.observe([], image: gone, panelOpen: false)
        // ...but on reopening it does not read the same (here: not at all), which must not leave it lost.
        check(reopening.observe(smoothView(scroll: 0).cells, image: smoothView(scroll: 0).image, atTop: true) == 0,
              "Closed and reopened within a moment, the browser counts from R1 again")
        // Rows cut off by the edges of the view are found too (they are clickable), tile by tile; at the
        // top of the list there is nothing above the first row.
        let halfway = smoothView(scroll: 330)
        let cut = Desktop.partialStyleRows(in: halfway.image, cells: halfway.cells)
        let topView = smoothView(scroll: 0)
        check(cut.above.count == 4 && cut.below.count == 4 && Desktop.partialStyleRows(in: topView.image, cells: topView.cells).above.isEmpty,
              "Style rows cut off at the top and bottom of the view are recognised, and none above the top of the list")
        // The panel made wider mid-session reflows the list (more tiles a row, fewer rows): a calibration
        // learned before must not turn into wrong row numbers. The count is lost, never made up.
        func reflowView(scroll: Int, columns: Int) -> (cells: [[CGRect]], image: CGImage) {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2200, pixelsHigh: 500, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            let pen = context.cgContext
            pen.setFillColor(CGColor(gray: 31.0 / 255, alpha: 1)); pen.fill(CGRect(x: 0, y: 0, width: 2200, height: 500))
            var cells: [[CGRect]] = []
            for absolute in 0..<10 {
                let top = 20 + absolute * 220 - scroll
                guard top + 190 > 0, top < 500 else { continue }
                var row: [CGRect] = []
                for column in 0..<columns {
                    let x = 30 + column * 210
                    pen.setFillColor(CGColor(gray: 46.0 / 255, alpha: 1)); pen.fill(CGRect(x: x, y: 500 - top - 190, width: 190, height: 190))
                    pen.setFillColor(NSColor(hue: CGFloat((absolute * columns + column) % 9) / 9, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor)
                    pen.fill(CGRect(x: x + 50, y: 500 - top - 140, width: 90, height: 90))
                    row.append(CGRect(x: CGFloat(x) / 2200, y: CGFloat(top) / 500, width: 190.0 / 2200, height: 190.0 / 500))
                }
                if top >= 0 && top + 190 <= 500 { cells.append(row) }
            }
            // the scrollbar: with fewer, longer rows the list is shorter and the thumb moves further per pixel
            let travel = columns == 5 ? 4.0 : 2.2
            pen.setFillColor(CGColor(gray: 0.5, alpha: 1)); pen.fill(CGRect(x: 30 + columns * 210, y: 500 - (20 + Int(Double(scroll) / travel)) - 100, width: 6, height: 100))
            NSGraphicsContext.restoreGraphicsState()
            return (cells, rep.cgImage!)
        }
        let resized = Desktop.StyleRowTracker()
        for position in stride(from: 0, through: 660, by: 22) {
            _ = resized.observe(reflowView(scroll: position, columns: 5).cells, image: reflowView(scroll: position, columns: 5).image, atTop: position == 0)
        }
        let wider = reflowView(scroll: 450, columns: 9)
        let afterResize = resized.observe(wider.cells, image: wider.image)
        check(afterResize == nil, "After the panel is made wider mid-session, the row count is lost rather than made up")
        // Back at the top in the new layout, the scrollbar beside the first row says so: counting restarts.
        let backAtTop = reflowView(scroll: 0, columns: 9)
        _ = resized.observe(backAtTop.cells, image: backAtTop.image, atTop: true)     // a top must hold for more than one frame
        check(resized.observe(backAtTop.cells, image: backAtTop.image, atTop: true) == 0,
              "After a resize, scrolling back to the top restores the count without reopening the browser")
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
        // Panels as rectangles: a 1200x800 window, grey panels (30) split by black lines (0) four pixels
        // thick: a title bar, a left panel full height, two stacked on the right. The left panel holds a big
        // black "video" with a thin gap through it, and black beside a line that continues the right-hand
        // divider; neither may cut it in two.
        do {
            let layout = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            func fill(_ gray: CGFloat, _ x: CGFloat, _ yTop: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                layout.setFillColor(CGColor(gray: gray, alpha: 1)); layout.fill(CGRect(x: x, y: 800 - yTop - h, width: w, height: h))
            }
            fill(30 / 255, 0, 0, 1200, 800)
            fill(0, 0, 40, 1200, 4)          // under the title bar
            fill(0, 400, 44, 4, 756)         // left | right
            fill(0, 404, 420, 796, 4)        // right: top / bottom
            fill(0, 20, 120, 360, 560)       // black video in the left panel...
            fill(30 / 255, 20, 400, 360, 3)  // ...with a thin grey stripe through it, and black meeting y 420 there
            let rects = Desktop.panelRects(in: layout.makeImage()!)
            func has(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Bool {
                rects.contains { abs($0.minX - x0) < 0.01 && abs($0.minY - y0) < 0.01 && abs($0.maxX - x1) < 0.01 && abs($0.maxY - y1) < 0.01 }
            }
            check(rects.count == 4 && has(0, 0, 1, 0.05) && has(0, 0.055, 0.333, 1) && has(0.337, 0.055, 1, 0.525) && has(0.337, 0.53, 1, 1),
                  "Panels: cut along thin black lines with grey on both sides, not through black video (\(rects.map { String(format: "%.3f,%.3f-%.3f,%.3f", $0.minX, $0.minY, $0.maxX, $0.maxY) }))")
        }
        // A project saved before graphics had their own progress (no graphics keys) still loads, keeps its
        // font size step, and starts graphics progress at nothing.
        do {
            let old = #"{"id":"6F1B2A1E-0000-4000-8000-000000000001","name":"Old","app":"Premiere Pro","script":"","style":"","instruction":"","routine":"","messages":[],"fontSizeStep":5,"completed":[0,1],"styledWords":{"a":1}}"#
            let project = try JSONDecoder().decode(Project.self, from: Data(old.utf8))
            check(project.fontSizeStep == 5 && project.completed(graphics: false) == [0, 1] && project.completed(graphics: true).isEmpty
                  && project.styledWords(graphics: true).isEmpty, "Projects saved by older versions load, with graphics progress apart")
            check(Project().fontSizeStep == 0, "A new project's font size step is 0 (size left as it is)")
        }
        // The script editor shows highlights instead of ** marks and saves the marks back: shown and saved,
        // a script must come back the same and give the same phrases.
        do {
            let scripts = [
                "**After 65**, I thought **tummy control **meant squeezing my waist - until I found **these jeans.**\nThe **high-rise, ultra-stretch waistband **gently smooths",
                "No highlights here at all", "", "a literal \\* star and a \\\\ backslash, then **bold \\* star**",
                "**whole line**", "**one** **two**\n\n**three**",
            ]
            var same = true
            for script in scripts {
                let back = ScriptText.marked(ScriptText.attributed(script))
                let before = (try? ScriptParser.parse(script))?.map { $0.highlights.map(\.text) }, after = (try? ScriptParser.parse(back))?.map { $0.highlights.map(\.text) }
                if back != script || before != after { same = false; print("  differs: \(script.debugDescription) -> \(back.debugDescription)") }
            }
            check(same, "The script editor shows highlights and saves the same script back")
            // Pasting over a selection that starts on a highlight: the pasted plain text must stay plain (it once
            // took the highlight from the text it replaced, and a whole pasted sheet turned bold and green).
            let editor = RichScriptTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            editor.isRichText = true; editor.isEditable = true
            editor.textStorage?.setAttributedString(ScriptText.attributed("**After 65**, I thought"))
            editor.selectAll(nil)
            editor.insertText(ScriptText.attributed("I can just **pull on** and look"), replacementRange: editor.selectedRange())
            check(ScriptText.marked(editor.textStorage!) == "I can just **pull on** and look", "Pasting over a highlight keeps the pasted plain text plain")
        }
        // A click is held only for a real window in front: the Dock's screen-sized window (Dock always shown)
        // held a tester's run "Waiting for Dock" with the Dock nowhere near the caption.
        do {
            func row(_ id: Int, _ owner: String, _ rect: CGRect, layer: Int = 0) -> [String: Any] {
                [kCGWindowNumber as String: NSNumber(value: id), kCGWindowOwnerName as String: owner, kCGWindowLayer as String: layer,
                 kCGWindowAlpha as String: 1.0, kCGWindowBounds as String: rect.dictionaryRepresentation]
            }
            let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117), caption = CGPoint(x: 240, y: 660)
            let dock = row(7, "Dock", screen, layer: 20), premiere = row(42, "Adobe Premiere Pro 2025", screen)
            check(Desktop.blocker(at: caption, of: 42, in: [dock, premiere], ignoring: []) == nil, "The Dock's screen-sized window does not hold a click")
            let player = row(9, "Opera", CGRect(x: 100, y: 600, width: 400, height: 200), layer: 3)
            check(Desktop.blocker(at: caption, of: 42, in: [player, dock, premiere], ignoring: []) == "Opera", "A real window over the caption still holds it")
            let overlayApp = row(11, "UltraViewer", screen, layer: 101)
            check(Desktop.blocker(at: caption, of: 42, in: [overlayApp, premiere], ignoring: [], screen: screen.size) == nil, "A see-through full-screen overlay does not hold a click")
            let locked = row(3, "loginwindow", screen, layer: 2000)
            check(Desktop.blocker(at: caption, of: 42, in: [locked, premiere], ignoring: [], screen: screen.size) == "loginwindow", "A locked screen still holds every click")
        }
        // One lookalike letter in one word of a longer phrase is tolerated; nothing looser.
        check(Desktop.sameWords(["closes", "ih", "front"], ["closes", "in", "front"]), "A phrase is found with one lookalike letter misread (ih for in)")
        check(!Desktop.sameWords(["ih"], ["in"]), "A lone word must match exactly")
        check(!Desktop.sameWords(["after", "66"], ["after", "65"]), "A number must match exactly")
        check(!Desktop.sameWords(["clases", "ih", "front"], ["closes", "in", "front"]), "Only one word may be loose")
        check(!Desktop.sameWords(["closes", "ix", "front"], ["closes", "in", "front"]), "Only known lookalike letters are tolerated")
        // Flip in the script editor: highlighted and plain swap; punctuation-only stretches and line breaks stay plain.
        do {
            let flipper = RichScriptTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            flipper.isRichText = true; flipper.isEditable = true
            flipper.textStorage?.setAttributedString(ScriptText.attributed("**After 65**, I thought **tummy control **meant it\n**Pull them on** and **look polished**"))
            flipper.flipHighlights()
            let flipped = ScriptText.marked(flipper.textStorage!)
            check(flipped == "After 65, **I thought** tummy control **meant it**\nPull them on **and** look polished",
                  "Flip swaps highlighted and plain in the script (\(flipped.debugDescription))")
        }
        // Each phrase gets: what a run does. Size only still steps Back out of a browser left open.
        do {
            var project = Project()
            check(project.effectiveRunParts == "style" && !project.runSteps.contains(OCRStep.increaseSize.rawValue),
                  "A step of 0 counts as Style only, and Apply shows it")
            project.fontSizeStep = 5
            check(project.effectiveRunParts == "both" && project.runSteps.count == OCRStep.allCases.count, "Style & size with a step runs every step")
            project.runParts = "style"
            check(!project.runSteps.contains(OCRStep.increaseSize.rawValue) && project.runSteps.contains(OCRStep.applyStyle.rawValue), "Style only skips the size step")
            project.runParts = "size"
            check(!project.runSteps.contains(OCRStep.applyStyle.rawValue) && !project.runSteps.contains(OCRStep.openStylePanel.rawValue)
                  && project.runSteps.contains(OCRStep.backFromStyle.rawValue) && project.runSteps.contains(OCRStep.increaseSize.rawValue),
                  "Size only skips the style steps but keeps Back")
        }
        // Bo: Drive's log errors by kind (made-up lines in Drive's format), and when clearing is worth it.
        do {
            func kind(_ message: String) -> BoWatcher.ErrorKind? { BoWatcher.kind(of: Substring(message)) }
            check(kind("[1:CurlWorker1] curl_api.cc:987:operator() No progress made for 3 seconds & we appear offline.") == .connection
                  && kind("[1:x] curl_api.cc:180:StatusFromCurlCode Remapped curl code 28 to TIMEOUT_EXCEEDED: Operation too slow.") == .connection
                  && kind("[1:x] file_provider_native_api.mm:242:UNKNOWN Error Domain=NSFileProviderErrorDomain Code=-1004 \"Your device couldn’t connect to the server.\"") == .connection,
                  "Bo: offline, timeouts and could-not-connect count as Connection")
            check(kind("[1:core_9] authenticated_transport.cc:166:DumpToLog Request 0x81788ff88: 429 transport: OK reader: OK url: https://example") == .server
                  && kind("[1:core_9] authenticated_transport.cc:166:DumpToLog Request 0x81788ff88: 500 transport: OK") == .server
                  && kind("[1:core_9] authenticated_transport.cc:166:DumpToLog Request 0x81788ff88: 403 transport: OK") == .access,
                  "Bo: a failed request counts by its status: 429 and 5xx are Google's servers, 403 is Access")
            check(kind("[1:core_9] authenticated_transport.cc:166:DumpToLog req.hdr 0x81788ff88: Content-Type=application/x-protobuf") == nil
                  && kind("[1:core_9] authenticated_transport.cc:166:DumpToLog Request 0x81788ff88: 0 transport: OK") == nil,
                  "Bo: a request's header lines, and a status of 0, are not counted again")
            check(kind("[1:core_9] change_handler.cc:1832:operator() NOT_FOUND: Can't access item in hidden shared drive") == .access
                  && kind("[1:core_9] upload_task.cc:10:Run Upload failed: quota exceeded") == .sync
                  && kind("[1:Main] drive_fs_main.cc:218:LogExistingCrashReports Crash reports from previous runs exist.") == .crash
                  && kind("[1:Main] message_loop.cc:232:ScheduleWork Tried to ScheduleWork on a disabled MessageLoop!") == .noise
                  && kind("[1:w] portable_clearcut_uploader.cc:90:UNKNOWN Failed to send to clearcut: Error sending request") == .noise
                  && kind("[1:w] phenotype_impl.cc:883:UNKNOWN Sync: Failed to sync response has status -1") == .noise
                  && kind("[1:Main] syncing_status_controller.cc:307:AccountHasSyncErrors Syncing status response not found for account: no_user") == .noise,
                  "Bo: access, uploads, crashes; Drive's housekeeping is background noise")
            let now = ISO8601DateFormatter().date(from: "2026-11-03T12:00:00Z")!
            var counts: [BoWatcher.ErrorKind: BoWatcher.ErrorCount] = [:]
            BoWatcher.countErrors(in: """
                2026-11-03T11:30:00.000ZE [1:w] curl_api.cc:987:operator() we appear offline
                2026-11-03T02:00:00.000ZE [1:w] curl_api.cc:987:operator() we appear offline again
                2026-11-01T02:00:00.000ZE [1:w] curl_api.cc:987:operator() two days ago, offline
                2026-11-03T11:40:00.000ZI [1:w] curl_api.cc:987:operator() offline, but only information
                """, now: now, into: &counts)
            check(counts[.connection]?.day == 2 && counts[.connection]?.hour == 1
                  && counts[.connection]?.example == "curl_api.cc:987:operator() we appear offline",
                  "Bo counts error lines of the last day and hour, newest as the example, without the thread")
            let lags = BoWatcher.finderLags(in: """
                2026-11-03T11:00:00.000ZI [1:core_111] activity_monitor.cc:9:X Slow working set change acknowledgment: 50 sec
                2026-11-03T11:00:00.000ZI [1:core_111] activity_monitor.cc:9:X Slow working set change acknowledged after 60 sec
                2026-11-03T11:50:00.000ZI [1:core_111] activity_monitor.cc:9:X Slow working set change acknowledgment: 90000 sec
                2026-11-03T09:00:00.000ZI [1:core_222][STRM] activity_monitor.cc:9:X Slow working set change acknowledgment: 30 sec
                2026-11-03T08:00:00.000ZI [1:core_333] activity_monitor.cc:9:X Slow working set change acknowledgment: 99999 sec
                2026-11-03T08:10:00.000ZI [1:core_333] activity_monitor.cc:9:X Slow working set change acknowledged after 100000 sec
                """, now: now)
            check(lags == ["111": 90600, "222": 10830], "Bo: still waiting, Finder's wait keeps growing after Drive goes quiet; taken, it is gone")
            await MainActor.run {
                let saved = UserDefaults.standard.array(forKey: "boRestarts")
                BoWatcher.recordRestart(at: now)
                check(BoWatcher.restarts.last == now.timeIntervalSince1970, "Bo saves when he restarted Drive (as a property list)")
                UserDefaults.standard.set(saved, forKey: "boRestarts")
            }
            check(BoWatcher.quittingSince(in: """
                2026-11-03T07:45:03.870ZI [1:core_111] activity_monitor.cc:9:X Slow working set change acknowledgment: 95805 sec
                2026-11-03T07:40:00.000ZI [1:Main] client.cc:4203:Quit Quit initiated from DFSAppDelegate.mm:162 (you cancelled it)
                2026-11-03T07:48:10.214ZI [1:Main] client.cc:4254:StopAllAccounts StopAllAccounts with APP_RESTART_REQUESTED initiated from client.cc:3122
                2026-11-03T09:27:43.042ZE [1:Main] client.cc:4248:StopAllAccounts Dropping Quit request since we are already quitting.
                """) == ISO8601DateFormatter().date(from: "2026-11-03T07:48:10Z")!.addingTimeInterval(0.214)
                  && BoWatcher.quittingSince(in: "2026-11-03T07:45:03.870ZI [1:core_111] x.cc:9:X all fine") == nil,
                  "Bo sees when Drive began quitting")
            check(BoWatcher.settingsShown(in: """
                2026-11-03T09:57:13.098ZI [1:Main] dialog.cc:87:UpdateViewViaDifferencer [UpdateViewDiff: additions="preferences_dialog {
                    sign_out_button: "Disconnect account"
                2026-11-03T10:01:00.000ZI [1:Main] dialog.cc:87:UpdateViewViaDifferencer [UpdateViewDiff: additions="
                    title: "Preparing to disconnect account"
                2026-11-03T10:02:00.000ZI [1:core_1] x.cc:1:Y something else
                """) == ISO8601DateFormatter().date(from: "2026-11-03T10:01:00Z")
                  && BoWatcher.settingsShown(in: "2026-11-03T10:02:00.000ZI [1:core_1] x.cc:1:Y something else") == nil,
                  "Bo sees when Drive's settings or its disconnect dialog were last on screen")
            let preparing = """
                2026-11-03T10:00:00.000ZI [1:Main] dialog.cc:87:UpdateViewViaDifferencer [UpdateViewDiff: additions="preferences_dialog {
                2026-11-03T10:01:00.000ZI [1:Main] dialog.cc:87:UpdateViewViaDifferencer [UpdateViewDiff: additions="
                    title: "Preparing to disconnect account"
                2026-11-03T10:01:00.100ZI [1:Main] dialog.cc:87:UpdateViewViaDifferencer [UpdateViewDiff: additions="preferences_dialog {
                2026-11-03T10:05:00.000ZI [1:core_1] x.cc:1:Y still working
                """
            check(BoWatcher.disconnectWaiting(in: preparing) == ISO8601DateFormatter().date(from: "2026-11-03T10:01:00Z")
                  && BoWatcher.disconnectWaiting(in: preparing + "2026-11-03T10:06:00.000ZI [1:Main] dialog.cc:87:UpdateViewViaDifferencer [UpdateViewDiff: removals=\"x\"]") == nil,
                  "Bo sees a disconnect still preparing, and that it moved on once Drive's windows change")
            check(BoWatcher.duration(94474) == "26 hours" && BoWatcher.duration(1800) == "30 minutes", "Bo says how long in hours or minutes")
            let gaps = BoWatcher.gaps(account: "1", email: "a@b.c",
                                      drive: ["Team 02": 160, "Team 03": 22, "Not loaded": 0, "Slow": 204, "Small": 5, "Same": 7, "Big": 1000],
                                      finder: ["Team 02": 117, "Team 03": 19, "Not loaded": 35, "Slow": Int?.none, "Small": 4, "Same": 7, "Big": 960] as [String: Int?])
            check(gaps.map(\.drive) == ["Team 02", "Big", "Team 03"] && gaps.first?.gap == 43,
                  "Bo: Finder missing 3+ items and 2% of a drive counts; drives Drive has not loaded, unfinished listings and small gaps do not")
            // This Mac: projects idle for a month are archive candidates; drag copies a week old and a big Premiere cache.
            let day = 86_400.0
            func folder(_ name: String, _ kind: BoWatcher.Folder.Kind, _ gb: Int64, daysAgo: Double) -> BoWatcher.Folder {
                .init(url: URL(fileURLWithPath: "/tmp/" + name), name: name, bytes: gb * 1_000_000_000, lastUsed: now.addingTimeInterval(-daysAgo * day), kind: kind)
            }
            let disk = [folder("Old", .project, 90, daysAgo: 40), folder("Fresh", .project, 7, daysAgo: 2), folder("Docs", .folder, 97, daysAgo: 150),
                        folder("Drags", .dragCopies, 60, daysAgo: 85), folder("Cache", .mediaCache, 23, daysAgo: 0)]
            check(BoWatcher.idleProjects(disk, now: now).map(\.name) == ["Old"], "Bo: only projects untouched for a month are archive candidates")
            let roomy = BoWatcher.Storage(accounts: [], free: 300_000_000_000)
            check(BoWatcher.advice(roomy, restartsToday: 0, folders: disk, now: now).map(\.id) == ["archive", "drags", "media-cache"],
                  "Bo recommends archiving idle projects, clearing week-old drag copies and a big Premiere cache")
            check(BoWatcher.advice(roomy, restartsToday: 0, folders: [folder("Fresh", .project, 7, daysAgo: 2), folder("Drags", .dragCopies, 2, daysAgo: 1)], now: now).isEmpty,
                  "Bo leaves recent projects and fresh drag copies alone")
            let settings = BoWatcher.DriveLog()
            settings.read("""
                2026-11-03T10:21:42.382ZI [1:Main] dialog.cc:87:UpdateViewViaDifferencer [UpdateViewDiff: additions="preferences_dialog {
                      email: "a@b.c"
                      quota_details: "Using 11.0 GB of 15.0 GB"
                      sign_out_button_aria_label: "Disconnect account"
                """)
            check(settings.quotas["a@b.c"]?.text == "Using 11.0 GB of 15.0 GB", "Bo reads each account's Drive space from Drive's settings")
            typealias Account = BoWatcher.Storage.Account
            let small = BoWatcher.Storage(accounts: [Account(id: "1", email: "a@b.c", bytes: 900_000_000)], logBytes: 100_000_000, logFiles: 5,
                                          free: 300_000_000_000)
            check(BoWatcher.advice(small, restartsToday: 0).isEmpty, "Bo: a cache under 2 GB on a roomy Mac needs no clearing")
            check(BoWatcher.advice(small, restartsToday: 3) == [.clearCache(small.accounts[0], .stuck(3))],
                  "Bo: Drive stuck three times in a day: clear the cache")
            var big = small; big.accounts = [Account(id: "1", email: nil, bytes: 2_500_000_000)]; big.logBytes = 600_000_000
            big.unuploadedFiles = 4; big.unuploadedBytes = 1_000
            check(BoWatcher.advice(big, restartsToday: 0).map(\.id) == ["cache-1", "unuploaded", "logs"],
                  "Bo: a big cache, files not uploaded and old logs are each recommended")
            var full = small; full.free = 5_000_000_000
            check(BoWatcher.advice(full, restartsToday: 0).map(\.id) == ["cache-1", "space"], "Bo: a Mac short of room: clear a cache over 500 MB")
        }
        // Penny reads Grafana's answers as Grafana 11 gives them (2026-11-05).
        do {
            check(Grafana.user(from: Data(#"{"id":7,"login":"duc","email":"d@x.com","name":"Duc"}"#.utf8)) == Grafana.User(name: "Duc", email: "d@x.com", login: "duc")
                  && Grafana.user(from: Data(#"{"message":"Unauthorized"}"#.utf8)) == nil, "Penny reads who is signed in")
            let found = Grafana.found(from: Data(#"[{"uid":"a","title":"PMKT","type":"dash-db","folderTitle":"Ops","url":"/d/a/pmkt","isStarred":true},{"uid":"f","title":"Ops","type":"dash-folder"}]"#.utf8))
            check(found.map(\.uid) == ["a"] && found[0].starred && found[0].folder == "Ops", "Penny lists dashboards, not folders")
            let dashboard = Grafana.dashboard(from: Data(#"{"meta":{"folderTitle":"Ops"},"dashboard":{"uid":"b","title":"Ops","version":4,"time":{"from":"now/d","to":"now/d"},"templating":{"list":[{"name":"team","type":"query","multi":true,"includeAll":true,"current":{"value":["$__all"]},"query":"select team from publisher","datasource":{"type":"grafana-postgresql-datasource","uid":"pg"}},{"name":"Provider","type":"custom","multi":true,"includeAll":true,"current":{"value":"$__all"},"query":"Facebook, Tiktok,A\\,B, Shown : google"}]},"panels":[{"id":9,"type":"row","title":"Later","collapsed":true,"gridPos":{"x":0,"y":20,"w":24,"h":1},"panels":[{"id":3,"type":"table","gridPos":{"x":0,"y":21,"w":24,"h":8}}]},{"id":6,"type":"stat","title":"  PO","gridPos":{"x":3,"y":0,"w":3,"h":3}},{"id":5,"type":"stat","title":"RE","gridPos":{"x":0,"y":0,"w":3,"h":3}},{"id":8,"type":"row","title":"Dashboards","collapsed":false,"gridPos":{"x":0,"y":3,"w":24,"h":1}},{"id":7,"type":"table","gridPos":{"x":0,"y":4,"w":30,"h":9}}]}}"#.utf8))
            check(dashboard?.sections.map(\.title) == ["", "Dashboards", "Later"] && dashboard?.sections.map { $0.tiles.map(\.id) } == [[5, 6], [7], [3]]
                  && dashboard?.sections[2].collapsed == true && dashboard?.sections[0].tiles[1].title == "PO" && dashboard?.sections[1].tiles[0].w == 24
                  && dashboard?.version == 4 && dashboard?.span == Grafana.Span(from: "now/d", to: "now/d"),
                  "Penny lays a dashboard out in its rows, panels in grid order, a closed row's panels kept inside it")
            check(dashboard?.variables.map(\.name) == ["team", "Provider"] && dashboard?.variables[1].options == ["Facebook", "Tiktok", "A,B", "google"]
                  && dashboard?.variables[0].source == Grafana.Source(uid: "pg", type: "grafana-postgresql-datasource") && dashboard?.variables[1].isAll == true,
                  "Penny reads a dashboard's filters: a custom list split on commas, \"text : value\" keeping the value")
            var team = Grafana.Variable(name: "team"); team.multi = true; team.includeAll = true; team.current = ["Ann's", "Bo"]
            var provider = Grafana.Variable(name: "Provider"); provider.multi = true; provider.includeAll = true; provider.current = [Grafana.Variable.all]; provider.options = ["Facebook", "Tiktok"]
            var everyone = Grafana.Variable(name: "who"); everyone.includeAll = true; everyone.current = [Grafana.Variable.all]; everyone.allValue = "ALL"
            let sql = Grafana.interpolate("team in ($team) and p in (SELECT detect(ARRAY[${Provider}])) and $__timeFilter(time) and w = '$who' and ${Provider:csv} [[team]] $teams", with: [team, provider, everyone])
            check(sql == "team in ('Ann''s','Bo') and p in (SELECT detect(ARRAY['Facebook','Tiktok'])) and $__timeFilter(time) and w = 'ALL' and Facebook,Tiktok 'Ann''s','Bo' $teams",
                  "Penny writes filters into SQL as Grafana does: quoted, All as every value or the all-value, macros left to Grafana (\(sql))")
            check(Grafana.interpolate("By $team", with: [team], display: true) == "By Ann's + Bo" && Grafana.mentions("where x in ($team)", "team")
                  && !Grafana.mentions("where x in ($teams)", "team") && Grafana.mentions("${team:csv}", "team"), "Penny titles with filters and knows which filter a query uses")
            team.settle(["Bo", "Cy"]); check(team.current == ["Bo"], "A chosen value Grafana no longer has is let go")
            team.settle(["Cy"]); check(team.current == [Grafana.Variable.all], "With none left the filter goes back to All")
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
            let now = Date(timeIntervalSince1970: 1_793_874_600)  // 2026-11-05 10:30 UTC
            func at(_ text: String, _ end: Bool) -> String { Grafana.moment(text, end: end, now: now, calendar: utc).map { ISO8601DateFormatter().string(from: $0) } ?? "nil" }
            check(at("now/d", false) == "2026-11-05T00:00:00Z" && at("now/d", true) == "2026-11-05T23:59:59Z" && at("now-1d/d", false) == "2026-11-04T00:00:00Z"
                  && at("now-7d", false) == "2026-10-29T10:30:00Z" && at("now-1M/M", true) == "2026-10-31T23:59:59Z" && at("now", true) == "2026-11-05T10:30:00Z",
                  "Penny reads Grafana's times: now/d is the day, now-1M/M last month")
            let alaska = Grafana.zone([nil, "", "America/Anchorage", "utc"])
            var anchorage = utc; anchorage.timeZone = alaska
            check(alaska.identifier == "America/Anchorage" && Grafana.zone(["browser", "utc"]) == .current && Grafana.zone([nil]) == .current
                  && Grafana.moment("now/d", end: false, now: now, calendar: anchorage).map { ISO8601DateFormatter().string(from: $0) } == "2026-11-05T09:00:00Z"
                  && Grafana.preferredZone(from: Data(#"{"theme":"","timezone":"America/Anchorage","weekStart":""}"#.utf8)) == "America/Anchorage",
                  "Penny counts the day in Grafana's timezone (the dashboard's, yours, your team's, the company's), not this Mac's")
            check(Grafana.pageZone(from: Data(#"<script nonce="">window.grafanaBootData = {"settings":{"note":"a } in {text","dateFormats":{"defaultTimezone":"utc"}},"user":{"isSignedIn":true,"timezone":"America/Anchorage"}};</script>"#.utf8)) == "America/Anchorage"
                  && Grafana.pageZone(from: Data("<html>no boot data</html>".utf8)) == nil
                  && Grafana.serverZone(from: Data(#"{"dateFormats":{"defaultTimezone":"America/Anchorage"}}"#.utf8)) == "America/Anchorage",
                  "Penny takes the timezone Grafana's own page settled on for you, and the server's default")
            let clocked = Grafana.dashboard(from: Data(#"{"dashboard":{"uid":"r","panels":[{"id":2,"type":"grafana-clock-panel","options":{"timezone":"America/Anchorage"},"gridPos":{"x":21,"y":2,"w":3,"h":3}}]}}"#.utf8))
            let business = clocked?.clock.flatMap(TimeZone.init(identifier:)) ?? .current
            check(clocked?.clock == "America/Anchorage" && Grafana.zone(["", nil, "browser"], fallback: business).identifier == "America/Anchorage"
                  && Grafana.zone(["Europe/Paris", "browser"], fallback: business).identifier == "Europe/Paris" && Grafana.zone([nil], fallback: business) == business,
                  "With no timezone set in Grafana, Penny counts the company's day: the dashboard clock's zone, not this Mac's")
            let replies = Grafana.replies(from: Data(#"{"results":{"A":{"status":200,"frames":[{"schema":{"fields":[{"name":"time","type":"time"},{"name":"po_today","type":"number"},{"name":"who","type":"string"}]},"data":{"values":[[1000,2000],[5,null],["a","b"]],"entities":[null,{"NaN":[1]},null]}}]},"B":{"status":400,"error":"pq: column \"x\" does not exist","frames":[]}}}"#.utf8))
            let answer = replies["A"]?.frames.first
            check(answer?.columns.map(\.kind) == ["time", "number", "string"] && answer?.columns[1].cells[0] == .number(5) && answer?.columns[1].cells[1].number?.isNaN == true
                  && replies["B"]?.error == #"pq: column "x" does not exist"#, "Penny reads Grafana's frames, NaN included, and a query's error")
            check(Grafana.message(in: Data(#"{"results":{"A":{"error":"db query error"}}}"#.utf8)) == "db query error", "A refused query says why")
            func numbers(_ name: String, _ values: [Double?], kind: String = "number") -> Grafana.Column {
                Grafana.Column(name: name, kind: kind, cells: values.map { $0.map(Grafana.Cell.number) ?? .none })
            }
            let today = Grafana.Frame(columns: [numbers("po_today", [110])]), yesterday = Grafana.Frame(columns: [numbers("po_yesterday", [100])])
            let change = Grafana.transform([today, yesterday], [
                ["id": "concatenate", "options": [:]],
                ["id": "calculateField", "options": ["alias": "a", "mode": "binary", "binary": ["left": "po_today", "operator": "-", "right": "po_yesterday"]]],
                ["id": "calculateField", "options": ["alias": "b", "mode": "binary", "binary": ["left": "a", "operator": "/", "right": "po_yesterday"]]],
                ["id": "calculateField", "options": ["mode": "binary", "binary": ["left": "b", "operator": "*", "right": "100"], "replaceFields": true]]])
            check(change.count == 1 && change[0].columns.map(\.name) == ["b * 100"] && change[0].columns[0].cells == [.number(10)], "Penny works out %PO against yesterday the way the panel does")
            let joined = Grafana.transform([Grafana.Frame(columns: [numbers("time", [1, 2], kind: "time"), numbers("total_re", [200, 400])]),
                                            Grafana.Frame(columns: [numbers("time", [2], kind: "time"), numbers("loss", [8])])],
                                           [["id": "calculateField", "options": ["alias": "RAL", "mode": "binary", "binary": ["left": "loss", "operator": "/", "right": "total_re"]]]])
            check(joined.count == 1 && joined[0].columns.map(\.name) == ["time", "total_re", "loss", "RAL"] && joined[0].columns[3].cells == [.number(0), .number(0.02)],
                  "Two queries' series are joined by time before a field is worked out from both, a missing value counting as 0")
            let organized = Grafana.organize(Grafana.Frame(columns: [numbers("total_po", [1]), numbers("publisher", [2]), numbers("tax", [3]), numbers("cbh", [4])]),
                                             ["excludeByName": ["tax": true], "indexByName": ["publisher": 0, "total_po": 1], "renameByName": ["total_po": "PO", "cbh": ""]])
            check(organized.columns.map(\.name) == ["publisher", "PO", "cbh"], "Penny hides, orders and renames columns as the panel's organize step says")
            check(Grafana.show(702_920, unit: "currencyUSD", decimals: 2).full == "$702.92K" && Grafana.show(-1234.5, unit: "currencyUSD", decimals: 2).full == "-$1.23K"
                  && Grafana.show(3_100_000, unit: "currencyUSD", decimals: 2) == Grafana.Shown(prefix: "$", text: "3.10", suffix: "M")
                  && Grafana.show(0.0869, unit: "percentunit", decimals: 2).full == "8.69%" && Grafana.show(-12.334, unit: "percent", decimals: 2).full == "-12.33%"
                  && Grafana.show(13251, unit: nil, decimals: nil).full == "13251" && Grafana.show(49.32, unit: nil, decimals: nil).full == "49.3"
                  && Grafana.show(13251, unit: "locale", decimals: nil).full == "13,251" && Grafana.show(.nan, unit: "percent", decimals: 2).full == "–"
                  && Grafana.show(.infinity, unit: "percentunit", decimals: 2).full == "∞%" && Grafana.show(-0.001, unit: nil, decimals: 2).full == "0.00",
                  "Penny writes values the way Grafana does: $702.92K, 8.69%, 13251")
            let fieldConfig: [String: Any] = ["defaults": ["unit": "currencyUSD", "thresholds": ["mode": "absolute", "steps": [["color": "light-green", "value": NSNull()], ["color": "red", "value": -20000], ["color": "light-green", "value": 0]]], "custom": ["cellOptions": ["type": "color-background"]]],
                                              "overrides": [["matcher": ["id": "byRegexp", "options": "(RE|ME|PC)"], "properties": [["id": "decimals", "value": 2]]],
                                                            ["matcher": ["id": "byRegexp", "options": ".*/.*"], "properties": [["id": "unit", "value": "percentunit"]]],
                                                            ["matcher": ["id": "byName", "options": "Product"], "properties": [["id": "color", "value": ["mode": "fixed", "fixedColor": "dark-blue"]], ["id": "custom.width", "value": 113]]]]]
            let ratio = Grafana.look(for: numbers("ME/RE", []), in: fieldConfig), product = Grafana.look(for: Grafana.Column(name: "Product", kind: "string", cells: []), in: fieldConfig)
            check(ratio.unit == "percentunit" && ratio.decimals == 2 && ratio.cell == "color-background" && product.color(for: nil) == "dark-blue" && product.width == 113,
                  "Penny takes a field's look from the defaults and every override that matches it, later ones winning")
            check(ratio.color(for: 5) == "light-green" && ratio.color(for: -500) == "red" && ratio.color(for: -30000) == "light-green" && ratio.color(for: nil) == "light-green",
                  "Penny colours a value by the threshold step it reaches")
            let stat = Grafana.Tile(["id": 1, "type": "stat", "options": ["reduceOptions": ["calcs": ["sum"], "fields": "/^PO$/"]], "fieldConfig": [:]])
            let figures = Grafana.figures(of: stat, [Grafana.Frame(columns: [numbers("time", [1, 2], kind: "time"), numbers("PO", [3, 4]), numbers("POS", [9])])])
            check(figures.map(\.name) == ["PO"] && figures.first?.number == 7, "A stat sums the field its pattern picks")
            let gauge = Grafana.Tile(["id": 2, "type": "bargauge", "options": ["reduceOptions": ["calcs": ["mean"], "values": true]]])
            check(Grafana.figures(of: gauge, [Grafana.Frame(columns: [Grafana.Column(name: "Age", kind: "string", cells: [.text("18-24"), .text("25-34")]), numbers("CPM", [2, 3])])]).map(\.name) == ["18-24", "25-34"],
                  "A bar gauge with every value shows a bar per row, named by its text")
            check(Grafana.values(from: [Grafana.Frame(columns: [Grafana.Column(name: "email", kind: "string", cells: [.text("b@x"), .text("a@x"), .text("b@x"), .none])])], regex: "", sort: 1) == ["a@x", "b@x"]
                  && Grafana.values(from: [Grafana.Frame(columns: [Grafana.Column(name: "x", kind: "string", cells: [.text("p_1"), .text("q")])])], regex: "/p_(\\d)/", sort: 0) == ["1"],
                  "A filter's values: sorted, no repeats, its regex keeping the first group")
            check(Grafana.plainText(fromHTML: "<ul>\nFor ads:\n<li>Data from 17/03 &amp; on</li>\n<li>PO = Ads + Organic</li></ul>") == "For ads:\n• Data from 17/03 & on\n• PO = Ads + Organic",
                  "A text panel's HTML reads as plain lines")
            check(Grafana.dateFormat("HH:mm MMM-DD") == "HH:mm MMM-dd" && Grafana.interval(span: 86_400_000, points: 1000) == 300_000, "Grafana's clock format and step read right")
            let rotated = HTTPURLResponse(url: Grafana.base, statusCode: 200, httpVersion: nil,
                                          headerFields: ["Set-Cookie": "grafana_session=abc123; Path=/; Max-Age=2592000; HttpOnly; Secure; SameSite=Lax"])!
            check(Grafana.sessionCookie(in: rotated) == "abc123", "Penny takes the renewed session Grafana sends")
            // Penny's own copy of the ads' numbers, by product (2026-11-05).
            let day = Ledger.bounds(of: "2026-11-04")
            check(day?.from == Date(timeIntervalSince1970: 1_793_782_800) && abs((day?.to.timeIntervalSince1970 ?? 0) - (1_793_869_200 - 0.001)) < 0.000_01,
                  "Penny's copy counts the company's Alaska-time day, first millisecond to last")
            let nov5 = Date(timeIntervalSince1970: 1_793_869_200 + 3 * 3600)  // Nov 5, 3 AM in Alaska
            var copied = Ledger.Summary()
            copied.copied["2026-11-03"] = Date(timeIntervalSince1970: 1_793_869_200 - 3600)   // long after Nov 3 ended: settled
            copied.copied["2026-11-04"] = Date(timeIntervalSince1970: 1_793_869_200 - 3600)   // before Nov 4 ended: copied again
            copied.copied["2026-11-05"] = nov5.addingTimeInterval(-10)                        // just copied: not yet
            check(Ledger.wanted(now: nov5, summary: copied, kept: 4) == ["2026-11-04", "2026-11-02"],
                  "Penny copies the days he hasn't and the ones not yet settled, newest first")
            check(Ledger.state(of: "2026-11-03", in: copied) == .final(copied: copied.copied["2026-11-03"]!)
                  && Ledger.state(of: "2026-11-04", in: copied) == .live(copied: copied.copied["2026-11-04"]!, until: Ledger.bounds(of: "2026-11-04")!.to.addingTimeInterval(Ledger.settles))
                  && Ledger.state(of: "2026-11-02", in: copied) == .missing,
                  "Penny's data shows each day as final, still coming in, or not copied")
            let old = try JSONDecoder().decode(Ledger.Summary.self, from: Data(#"{"copied":{},"products":{"P":{"2026-11-04":[1,0,0,0,0,0,0,0,0]}}}"#.utf8))
            check(old.products["P"]?["2026-11-04"]?.spent == 1 && old.latest.isEmpty, "A summary saved before the last hour was kept still reads")
            let ads = Grafana.Frame(columns: [Grafana.Column(name: "product", kind: "string", cells: [.text("ComfyJeans"), .text("")]),
                                              Grafana.Column(name: "ad_id", kind: "string", cells: [.text("a1"), .text("a2")]),
                                              Grafana.Column(name: "campaign_id", kind: "string", cells: [.text("c1"), .text("c2")]),
                                              Grafana.Column(name: "campaign", kind: "string", cells: [.text("1_X_ComfyJeans"), .text("2_Y")]),
                                              Grafana.Column(name: "ad", kind: "string", cells: [.text("X_v1.1"), .text("Y_v1")]),
                                              numbers("budget", [500, nil])])
            let hours = Grafana.Frame(columns: [Grafana.Column(name: "product", kind: "string", cells: [.text("ComfyJeans"), .text("ComfyJeans"), .text("ComfyJeans"), .text("")]),
                                                Grafana.Column(name: "ad_id", kind: "string", cells: [.text("a1"), .text("a1"), .text("a3"), .text("a2")]),
                                                numbers("hour", [19, 20, 19, 1]), numbers("spent", [10, 30, 5, 2]), numbers("views", [20, 10, 4, 1]),
                                                numbers("orders", [2, 0, 1, 0]), numbers("revenue", [60, 0, 25, 0])])
            let products = Ledger.products(from: [ads, hours], day: "2026-11-04", copied: nov5)
            let chapter = products["ComfyJeans"]
            check(Set(products.keys) == ["ComfyJeans", "NA"] && chapter?.ads.map { $0.id } == ["a1", "a3"] && chapter?.ads.first?.budget == 500
                  && chapter?.numbers == Ledger.Numbers([45, 0, 0, 0, 34, 0, 0, 3, 85]),
                  "Penny sorts each ad and its hours under its product; an ad seen only in the hours keeps its id")
            check(Ledger.latest(products) == 20, "Penny knows the last hour Grafana has numbers for")
            let saved = try JSONEncoder().encode(Ledger.Numbers([1, 2, 3, 4, 5, 6, 7, 8, 9]))
            check(String(decoding: saved, as: UTF8.self) == "[1,2,3,4,5,6,7,8,9]" && (try? JSONDecoder().decode(Ledger.Numbers.self, from: saved))?.orders == 8,
                  "An hour's numbers are saved as a plain list")
            let text = Data(String(repeating: "Penny's copy ", count: 200).utf8)
            check((try? Ledger.gunzip(Ledger.gzip(text))) == text && Ledger.crc32(Data("123456789".utf8)) == 0xcbf4_3926,
                  "A day's file is gzip, read back as written")
            var second = chapter!
            second.ads = [Ledger.Ad(id: "b1", campaignID: "c9", name: "X_v1.1")]
            second.hours = [Ledger.Hour(ad: "b1", hour: 19, numbers: Ledger.Numbers([5, 0, 0, 0, 2, 0, 0, 1, 30]))]
            let creatives = Ledger.creatives([chapter!, second])
            check(creatives.map { $0.name } == ["X_v1.1", "a3"] && creatives[0].count == 2 && creatives[0].numbers.orders == 3 && creatives[0].bestHours() == [19],
                  "The same creative in two campaigns is one line, with the hours it sold in")
            check(Ledger.hours([chapter!])[19].spent == 15 && Ledger.campaigns([chapter!]).map { $0.name } == ["1_X_ComfyJeans", "a3"],
                  "Penny adds a product's numbers up by hour and by campaign")
            check(Ledger.days(from: "2026-11-04", to: "2026-11-02") == ["2026-11-04", "2026-11-03", "2026-11-02"] && Ledger.days(from: "2026-11-02", to: "2026-11-02") == ["2026-11-02"]
                  && Ledger.days(from: "2026-10-31", to: "2026-11-01") == ["2026-11-01", "2026-10-31"] && Ledger.days(from: "x", to: "2026-11-01").isEmpty,
                  "Picked dates are every day from one to the other, either way round")
            check(Ledger.hourName(23) == "11 PM-12 AM" && Ledger.hourName(11) == "11 AM-12 PM" && Ledger.hourName(0) == "12 AM-1 AM",
                  "Hours are written as the dashboards write them")
            check(Ledger.folder(of: "Activa Bra 2.0") == "Activa Bra 2.0" && Ledger.folder(of: "A/B") == "A-B" && Ledger.folder(of: " ") == "NA",
                  "Each product gets a folder of its own name")
            var waste = chapter!
            waste.ads = [Ledger.Ad(id: "z1", campaignID: "c8", name: "Z_v1")]
            waste.hours = [Ledger.Hour(ad: "z1", hour: 3, numbers: Ledger.Numbers([100, 0, 0, 0, 9, 0, 0, 0, 0]))]
            let read = Ledger.report([chapter!, waste], before: Ledger.Numbers([40, 0, 0, 0, 0, 0, 0, 1, 80]))
            check(read.first?.contains("$145.00") == true && read.contains { $0.contains("down") } && read.contains { $0.contains("No orders: **Z_v1**") },
                  "Penny's read gives the totals, the change on the days before and the creatives that spend without selling")
            // CBH and the hours as a media buyer reads them (2026-11-06).
            let cbhFrame = Grafana.Frame(columns: [Grafana.Column(name: "product", kind: "string", cells: [.text("MeadowEase"), .text("")]),
                                                   numbers("po", [20, 1]), numbers("re", [1000, 50]), numbers("pc", [300, 10]), numbers("tax", [40, 2]),
                                                   numbers("me", [400, 0]), numbers("cbh", [180, 30]), numbers("cbh_before_ads", [580, 30])])
            let margins = Ledger.margins(from: [cbhFrame])
            check(margins["MeadowEase"] == Ledger.Margin([20, 1000, 300, 40, 400, 180, 580]) && margins["NA"]?.revenue == 50, "Penny reads each product's CBH, a blank product as NA")
            let profit = Ledger.Profit(margins["MeadowEase"]!)!
            check(abs(profit.kept - 0.58) < 1e-9 && abs(profit.cost - 1) < 1e-9 && abs(profit.breakeven - 1 / 0.58) < 1e-9 && abs(profit.profitable - 1 / 0.53) < 1e-9,
                  "Breakeven comes from CBH: what the product keeps before ads, and what an ad dollar takes")
            check(Ledger.Profit(Ledger.Margin([0, 0, 0, 0, 10, -10, 0])) == nil && abs(Ledger.Profit.usual.breakeven - 1.8) < 1e-9 && abs(Ledger.Profit.usual.profitable - 2) < 0.03,
                  "Without CBH Penny uses the usual 1.8× line, and about 2.0× for profitable")
            func spentDay(_ name: String, _ hours: [(Int, Double, Double)]) -> Ledger.Day {
                Ledger.Day(product: "P", day: name, copied: nov5, ads: [], hours: hours.map { Ledger.Hour(ad: "a", hour: $0.0, numbers: Ledger.Numbers([$0.1, 0, 0, 0, 0, 0, 0, 1, $0.2])) })
            }
            let week = ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04"].enumerated().map { index, name in
                spentDay(name, [(19, 30, 90), (3, 60, 30), (9, 60, 90), (12, 30, index == 2 ? 15 : 90)] + (index < 2 ? [(14, 10, 50)] : []))
            }
            let reads = Ledger.hourReads(week, profit: profit)
            check(reads[19].verdict == .reliable && reads[3].verdict == .dead && reads[9].verdict == .costly && reads[12].verdict == .volatile
                  && reads[14].verdict == .few && reads[0].verdict == .idle, "Each hour gets the dashboard's verdict, with breakeven from CBH")
            check(reads[12].floor == 0.5 && reads[12].ceiling == 3 && reads[19].spentPerDay == 30 && abs(reads[9].cbh - (0.58 * 360 - 240)) < 1e-9,
                  "An hour's bad and good days are the 10th and 90th percentile of its days' ROAS; its CBH is what revenue keeps less spend")
            let parts = Ledger.efficiency(reads, profit: profit)
            check(parts.losing.hours == [3, 9] && parts.profitable.hours == [12, 14, 19] && parts.losing.numbers.spent == 480,
                  "The budget splits into hours below breakeven and profitable hours")
            let hoursRead = Ledger.report(week, profit: profit)
            check(hoursRead.contains { $0.contains("Breakeven ROAS **1.72**") } && hoursRead.contains { $0.hasPrefix("Put more in: 7 PM-8 PM") }
                  && hoursRead.contains { $0.hasPrefix("Cut back: 3 AM-4 AM") }, "Penny's read names breakeven, the hours to put more in and the ones to cut")
            var priced = Ledger.Summary()
            priced.margins = ["P": ["2026-11-04": Ledger.Margin([1, 100, 0, 0, 10, 40, 50])], "Q": ["2026-11-04": Ledger.Margin([1, 100, 0, 0, 0, 50, 50])]]
            check(priced.margin(of: "P", on: ["2026-11-04", "2026-11-03"]).days == 1 && (try? JSONDecoder().decode(Ledger.Summary.self, from: JSONEncoder().encode(priced))) == priced,
                  "Each product's CBH is kept by day in the summary")
        }
        // Pix's chat history (2026-11-06): boards saved before it still read, each earlier chat titled by your first message.
        do {
            let before = try JSONDecoder().decode(PixBoard.self, from: Data(#"{"jobs":[],"chat":[{"id":"8D3F1C2A-0000-4000-8000-000000000001","fromPix":false,"text":"Make the CTA red\nplease","pictures":[],"proposals":[],"taken":[],"date":0}],"ctaFrom":"x"}"#.utf8))
            check(before.chat.count == 1 && before.past.isEmpty && before.ctaFrom == "x", "Pix's boards saved before the chat history still load")
            check(PixChat(messages: before.chat).title == "Make the CTA red" && PixChat(messages: [PixMessage(fromPix: false, text: "", pictures: ["a.jpg"])]).title == "",
                  "An earlier chat with Pix is titled by your first message")
        }
        // Sage, the research helper (Basil, the recipe helper, before): YouTube's answers, the recipe a page publishes, and notes in the vault (2026-11-06).
        do {
            check(Study.duration("PT1M15S") == "1:15" && Study.duration("PT1H2M3S") == "1:02:03" && Study.duration("PT45S") == "0:45" && Study.duration("P0D") == "",
                  "Sage writes a video's length as a clock")
            let search = Data(#"{"items":[{"id":{"kind":"youtube#video","videoId":"v1"}},{"id":{"videoId":"v2"}}]}"#.utf8)
            let details = Data(#"{"items":[{"id":"v2","snippet":{"title":"Mac &amp; Cheese","channelTitle":"Cook","publishedAt":"2026-01-02T03:04:05Z","description":"Recipe: https://example.com/mac https://youtu.be/x https://www.instagram.com/cook","thumbnails":{"medium":{"url":"https://i.ytimg.com/m.jpg"}}},"contentDetails":{"duration":"PT9M"},"statistics":{"viewCount":"1200"}}]}"#.utf8)
            let video = Study.videos(in: details).first
            check(Study.ids(inSearch: search) == ["v1", "v2"] && video?.title == "Mac & Cheese" && video?.duration == "9:00" && video?.views == 1200
                  && video?.published == "2026-01-02" && video?.thumbnail?.lastPathComponent == "m.jpg",
                  "Sage reads YouTube's search and video answers")
            check(Study.links(in: video?.description ?? "").map(\.absoluteString) == ["https://example.com/mac"], "Only links that could hold the recipe are read")
            check(Study.failure(in: Data(#"{"error":{"message":"quota","errors":[{"reason":"quotaExceeded"}]}}"#.utf8)) == "quotaExceeded",
                  "Sage knows when the day's searches are used up")
            let html = #"<script type="application/ld+json">{"@type":"WebSite"}</script><script type='application/ld+json'>{"@context":"https://schema.org","@graph":[{"@type":"Person"},{"@type":["Recipe","NewsArticle"],"name":"Adobo","recipeIngredient":["1 kg chicken"]}]}</script>"#
            check(Study.recipeData(inHTML: html)?["name"] as? String == "Adobo" && Study.recipeData(inHTML: "<p>no recipe</p>") == nil,
                  "Sage finds the Recipe a page publishes, inside a graph or under several types")
            var recipe = Study.recipe(from: ["title": " Adobo ", "tags": ["#Filipino Food", "chicken"], "steps": ["1. Brown the chicken", "2) Simmer"], "ingredients": ["1 kg chicken", " "]])
            check(recipe.title == "Adobo" && recipe.tags == ["filipino-food", "chicken"] && recipe.steps == ["Brown the chicken", "Simmer"] && recipe.ingredients == ["1 kg chicken"],
                  "Sage's answer is tidied: tags Obsidian takes, steps without their numbers")
            recipe.source = "https://www.youtube.com/watch?v=v2"; recipe.channel = "Cook \"Pro\""
            let note = Study.note(recipe, added: "2026-11-06")
            let header = Study.header(of: note)
            check(header["title"] == ["Adobo"] && header["status"] == ["to try"] && header["channel"] == ["Cook \"Pro\""] && header["tags"] == ["recipe", "filipino-food", "chicken"]
                  && note.contains("![](https://www.youtube.com/watch?v=v2)") && note.contains("2. Simmer") && header["servings"] == nil,
                  "A recipe note has its header, the video, and numbered steps")
            let made = Study.setting("status", to: "made", in: note)
            check(Study.header(of: made)["status"] == ["made"] && made.components(separatedBy: "status:").count == 2 && made.contains("## Steps"),
                  "Changing a recipe's status changes only that line")
            check(Study.header(of: Study.setting("tags", to: "[a]", in: note))["tags"] == ["a"] && Study.header(of: Study.setting("status", to: "made", in: "Just text"))["status"] == ["made"],
                  "A list value is replaced whole; a note with no header gets one")
            check(Study.fileName(for: "Mac & Cheese: The Best?", taken: ["mac & cheese the best.md"]) == "Mac & Cheese The Best 2.md" && Study.fileName(for: " .. ", taken: []) == "Recipe.md",
                  "A recipe's file name suits Windows too and never takes an existing note's")
            let vault = FileManager.default.temporaryDirectory.appendingPathComponent("sage-check-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: vault.appendingPathComponent("Soups"), withIntermediateDirectories: true)
            try Data(note.utf8).write(to: vault.appendingPathComponent("Adobo.md"))
            try Data("---\ntags: [soup]\nstatus: Favourite\n---\nPho".utf8).write(to: vault.appendingPathComponent("Soups/Pho.md"))
            try Data("{}".utf8).write(to: vault.appendingPathComponent(".obsidian/app.md"))
            let entries = Study.entries(in: vault)
            check(Set(entries.map(\.title)) == ["Adobo", "Pho"] && entries.first { $0.title == "Pho" }?.status == "favourite" && entries.first { $0.title == "Pho" }?.tags == ["soup"],
                  "Sage reads every note in the recipes folder and the folders in it, Obsidian's own left out")
            let reply = Study.reply(from: ["reply": " Looking ", "youtube": "pho recipe", "notes": ["pho", " "], "show": []])
            check(reply.text == "Looking" && reply.notes == ["pho"] && reply.looksUp && !Study.reply(from: ["reply": "Hi"]).looksUp, "Sage's chat answer says what he looks up")
            check(Study.named(["PHO", "adobo!", "Nothing"], in: entries).map(\.title) == ["Pho", "Adobo"], "Notes the chat names are found by title, case and marks aside")
            let asked = [Study.Message(fromSage: false, text: "What's in my pho?")]
            let withNotes = Study.chatPrompt(chat: asked, recipes: entries, folder: true, canSearch: false, found: [video!], searched: "mac",
                                               read: [("Pho", "Pho text")], last: true)
            check(withNotes.contains("- Pho | favourite | - | soup") && withNotes.contains("Me: What's in my pho?") && withNotes.contains("id v2 | Mac & Cheese")
                  && withNotes.contains("My note \"Pho\":\nPho text") && withNotes.contains("Answer now") && withNotes.contains("no API key"),
                  "Sage's chat gets your notes list, the chat, what he looked up, and what he can't do")
            check(Study.chatPrompt(chat: asked, recipes: [], folder: false, canSearch: true, found: nil, searched: "", read: [], last: false).contains("not chosen yet"),
                  "Without a recipes folder Sage still chats, and says where to choose one")
            check(Study.recipeSearch(" chicken ") == "chicken recipe" && Study.recipeSearch("how to make pho") == "how to make pho" && Study.recipeSearch("Adobo Recipe") == "Adobo Recipe",
                  "Sage searches for recipes, not anything with the word in it")
            let picked = Study.picks(from: ["picks": [["id": "v2", "why": " Clear method "], ["id": "zz", "why": "not shown"], ["id": "v2", "why": "twice"]]], among: [video!], count: 5)
            check(picked == [Study.Pick(id: "v2", why: "Clear method")] && Study.pickPrompt("mac recipe", videos: [video!], count: 5).contains("id v2 | Mac & Cheese"),
                  "Sage's picks are only videos he was shown, once each")
            let kept = Study.Saved(video: video!, why: "Clear method")
            let back = try? JSONDecoder().decode([Study.Saved].self, from: JSONEncoder().encode([kept]))
            check(back?.first?.video?.title == "Mac & Cheese" && back?.first?.why == "Clear method" && back?.first?.written == "",
                  "A saved video is kept in the app, unwritten until you ask")
            let old = Date(timeIntervalSince1970: 1_000_000)
            let first = Study.Conversation(messages: [Study.Message(fromSage: true, text: "Hi"), Study.Message(fromSage: false, text: "Quick pho for two\nwith beef")], updated: old)
            let second = Study.Conversation(messages: [Study.Message(fromSage: false, text: String(repeating: "adobo ", count: 20))], updated: old.addingTimeInterval(60))
            check(first.title == "Quick pho for two" && second.title.count == 58 && second.title.hasSuffix("…") && Study.Conversation().title == "",
                  "A chat is titled by your first message")
            check(Study.find("", in: [first, second]).map(\.id) == [second.id, first.id] && Study.find("BEEF", in: [first, second]).map(\.id) == [first.id],
                  "Chats list newest first and are found by any message's words")
            check(Study.ago(old, now: old.addingTimeInterval(30)) == "now" && Study.ago(old, now: old.addingTimeInterval(8 * 60)) == "8m"
                  && Study.ago(old, now: old.addingTimeInterval(3 * 3600)) == "3h" && Study.ago(old, now: old.addingTimeInterval(2 * 86_400)) == "2d"
                  && Study.ago(old, now: old.addingTimeInterval(15 * 86_400)) == "2w",
                  "Each chat shows how long ago it was")
            check(Study.thumbnail(of: "https://www.youtube.com/watch?v=wwapBsT0oc8&t=3")?.absoluteString == "https://i.ytimg.com/vi/wwapBsT0oc8/mqdefault.jpg"
                  && Study.thumbnail(of: "https://youtu.be/abc_-1")?.lastPathComponent == "mqdefault.jpg" && Study.thumbnail(of: "https://youtube.com/shorts/xyz") != nil
                  && Study.thumbnail(of: "https://example.com/watch?v=x") == nil && Study.thumbnail(of: "") == nil,
                  "A recipe card shows its video's picture")
            let md = Study.markdown("## Steps\n\n1. Brown **chicken**\n2. Add `soy`\n   - nested *one*\n\n- [x] done\n- [ ] todo\n\n> [!tip] Swap\n> Use ==thighs==\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nSee [[Pho|my pho]] and #soup <b>")
            check(md.contains("<h2>Steps</h2>") && md.contains("<ol><li>Brown <strong>chicken</strong>") && md.contains("<code>soy</code>") && md.contains("<ul><li>nested <em>one</em>")
                  && md.contains("task-list-item is-checked") && md.contains("data-callout=\"tip\"") && md.contains("<mark>thighs</mark>") && md.contains("<td>2</td>")
                  && md.contains("href=\"sage-note:Pho\">my pho</a>") && md.contains("class=\"tag\" href=\"#soup\"") && md.contains("&lt;b&gt;") && !md.contains("<b>"),
                  "Sage draws a note's Markdown as Obsidian's reading view does")
            let page = Study.page(note: note, look: Study.Look(dark: true, accent: "#ff8800", fontSize: 18, css: ".theme-dark{--x:1}"), dark: true)
            check(page.contains("theme-dark") && page.contains("metadata-container") && page.contains("multi-select-pill\">#filipino-food") && page.contains("--accent: #ff8800")
                  && page.contains("--font-text-size: 18px") && page.contains(".theme-dark{--x:1}") && page.contains("class=\"video-embed\"") && page.contains("<h2>Steps</h2>"),
                  "A note's page has its properties, the video, your accent, size and theme")
            let obsidian = vault.appendingPathComponent(".obsidian")
            try FileManager.default.createDirectory(at: obsidian.appendingPathComponent("themes/Minimal"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: obsidian.appendingPathComponent("snippets"), withIntermediateDirectories: true)
            try Data(##"{"theme":"moonstone","accentColor":"#3366ff","baseFontSize":17,"cssTheme":"Minimal","enabledCssSnippets":["wide"]}"##.utf8).write(to: obsidian.appendingPathComponent("appearance.json"))
            try Data("/* minimal */".utf8).write(to: obsidian.appendingPathComponent("themes/Minimal/theme.css"))
            try Data("/* wide */".utf8).write(to: obsidian.appendingPathComponent("snippets/wide.css"))
            let look = Study.look(vault: vault)
            check(Study.vault(of: vault.appendingPathComponent("Soups"))?.standardizedFileURL.path == vault.standardizedFileURL.path && look.dark == false && look.accent == "#3366ff"
                  && look.fontSize == 17 && look.css.contains("minimal") && look.css.contains("wide"),
                  "Sage reads your vault's Obsidian look: light or dark, accent, size, theme and snippets")
            // Sage researches any topic (2026-11-06): topics, web pages, research notes.
            let editing = Study.Topic(name: "Editing techniques"), cooking = Study.Topic(name: "Recipes", kind: .recipes)
            check(editing.statuses == ["to read", "read", "key"] && cooking.statuses == ["to try", "made", "favourite"]
                  && Study.search("speed ramp", in: editing) == "speed ramp" && Study.search("pho", in: cooking) == "pho recipe",
                  "Each topic has its own statuses, and only recipe topics search for recipes")
            check(Study.link("https://example.com/a?b=1")?.host == "example.com" && Study.link("www.example.com/x")?.scheme == "https"
                  && Study.link("chicken adobo") == nil && Study.link("adobo.") == nil && Study.videoID(of: "https://youtu.be/abc_-1") == "abc_-1",
                  "A link in Find is told apart from words to search")
            let article = #"<html><head><title>Ignored</title><meta property="og:title" content="Speed ramps &amp; you"><meta name="description" content="How to ramp"><meta property="og:image" content="/pic.jpg"><script>var x = "<p>no</p>";</script></head><body><nav>Menu Home</nav><article><h1>Speed ramps</h1><p>First, set &#8220;time remapping&#8221;.</p><ul><li>Add keyframes</li><li>Ease them</li></ul>"# + String(repeating: "<p>More words here.</p>", count: 40) + "</article><footer>Footer</footer></body></html>"
            let read = Study.page(fromHTML: article, url: URL(string: "https://www.cuts.example/guide")!)
            check(read.title == "Speed ramps & you" && read.site == "cuts.example" && read.description == "How to ramp" && read.image?.absoluteString == "https://www.cuts.example/pic.jpg"
                  && read.text.hasPrefix("Speed ramps\nFirst, set “time remapping”.") && read.text.contains("• Add keyframes") && !read.text.contains("Menu") && !read.text.contains("no</p>"),
                  "Sage reads a web page: its title, site, picture and readable text, menus and scripts left out")
            var brief = Study.brief(from: ["title": "Speed ramps", "summary": "How to ramp.", "points": ["Use keyframes"], "details": [], "quotes": ["“Ease in”"], "questions": ["Optical flow?"], "tags": ["Premiere Pro"]])
            brief.source = "https://www.cuts.example/guide"; brief.channel = "cuts.example"; brief.image = "https://www.cuts.example/pic.jpg"
            let research = Study.note(brief, topic: "Editing techniques", added: "2026-11-06")
            let researchHeader = Study.header(of: research)
            check(researchHeader["status"] == ["to read"] && researchHeader["topic"] == ["Editing techniques"] && researchHeader["tags"] == ["research", "premiere-pro"]
                  && research.contains("![](https://www.cuts.example/pic.jpg)") && research.contains("## Key points\n\n- Use keyframes") && research.contains("> Ease in")
                  && research.contains("## Open questions") && !research.contains("## Details") && research.contains("## Sources\n\n- https://www.cuts.example/guide")
                  && Study.entry(URL(fileURLWithPath: "/x/Speed.md"), text: research, modified: Date()).picture?.lastPathComponent == "pic.jpg",
                  "A research note has its header, the page's picture, and only the sections with something in them")
            let older = try JSONDecoder().decode([Study.Saved].self, from: JSONEncoder().encode([Study.Saved(video: video!)]))
            let pageSaved = Study.Saved(page: read, topic: editing.id)
            check(older.first?.topic == nil && older.first?.id == "v2" && pageSaved.id == "https://www.cuts.example/guide" && pageSaved.title == "Speed ramps & you"
                  && pageSaved.origin == "cuts.example" && pageSaved.thumbnail?.lastPathComponent == "pic.jpg"
                  && Study.pickPrompt("speed ramp", videos: [video!], count: 5, topic: editing).contains("researching \"Editing techniques\""),
                  "Saved holds videos and pages, each in its topic")
            try? FileManager.default.removeItem(at: vault)
        }
        // Don's brief and Pix's jobs (2026-11-04).
        do {
            let brief = try DonBrief(answer: ["product": " Jeans ", "vibe": "Warm", "voice": "", "music": "", "graphicStyle": "Denim blue", "cta": "GET YOURS NOW!",
                                              "ctaLook": "65% OFF badge", "videoShots": [["line": "Pull them on", "idea": "Quick pull-on"], ["line": " ", "idea": "x"]]],
                                     from: "a\nb", project: "P", script: "Script 1")
            check(brief.product == "Jeans" && brief.videoShots.map(\.line) == ["Pull them on"], "Don's brief keeps the lines that need AI video, trimmed")
            check((try? DonBrief(answer: ["vibe": "", "graphicStyle": ""], from: "", project: "", script: "")) == nil, "An answer with no brief in it is refused")
            check(DonBrief.lines("**65% OFF**\n\n**GET YOURS** NOW!") == ["65% OFF", "GET YOURS NOW!"], "Don reads the script's words without the bold marks")
            check(!brief.outdated(by: "a\nb") && brief.outdated(by: "a\nc"), "Don's brief knows when the script changed after")
            // The script sheet (2026-11-05), as the CraftyHold working file lays it out.
            let link = DonSheet.address("https://docs.google.com/spreadsheets/d/1HGTHRZbMbwVFYx0HRW6iM4aQvILoP8tgIu3GFEETmA0/edit?gid=1658507630#gid=1658507630")
            check(link?.id == "1HGTHRZbMbwVFYx0HRW6iM4aQvILoP8tgIu3GFEETmA0" && link?.tab == 1658507630, "Don finds the sheet and its tab in the link")
            check(DonSheet.address("https://docs.google.com/spreadsheets/d/1HGTHRZbMbwVFYx0HRW6iM4aQvILoP8tgIu3GFEETmA0/edit")?.tab == nil
                  && DonSheet.address("https://example.com/a") == nil, "A link without a tab reads the first; anything else is not a sheet")
            check(DonSheet.column("Khoảng cut từ source") == .cut && DonSheet.column("Source") == .source && DonSheet.column("Cảnh") == .scene
                  && DonSheet.column("Text/Voiceover") == .text && DonSheet.column("Hiệu ứng ") == .effect && DonSheet.column("Extra Notes") == .notes,
                  "Don reads the sheet's headers in Vietnamese or English, the cut range before the source")
            let rows = [["Version", "Cảnh", "Text/Voiceover", "Hiệu ứng ", "Khoảng cut từ source", "Source", "Comment ", "Extra Notes"],
                        ["v1.0\nUtility demo", "1", "Pens\nGlasses", "", "1-2", "H8 open.mp4", "", "nhanh hơn", "ref videos"],
                        ["", "2", "Cards"],
                        ["", "", "", "", "", ""],
                        ["v1.1\n\nGifting + Lifestyle", "1", "THE gift", "", "0-2", "H22 full clip.mp4\n"],
                        ["v1.1\nGifting + Lifestyle", "1", "Again", "", "", "H1.mp4"]]
            let versions = DonSheet.versions(rows, tab: "Video")
            check(versions.map(\.name) == ["v1.0 · Utility demo", "v1.1 · Gifting + Lifestyle", "v1.1 · Gifting + Lifestyle (2)"],
                  "A filled Version cell starts a version, named on one line, never twice the same")
            check(versions.first?.lines.map(\.text) == ["Pens\nGlasses", "Cards"] && versions.first?.unfilmed == 1 && versions[1].lines.first?.source == "H22 full clip.mp4",
                  "Each version keeps its lines and their source; empty rows are skipped")
            check(DonSheet.described(versions[0].lines[0]) == "Pens / Glasses [media: H8 open.mp4] [editor notes: nhanh hơn]"
                  && DonSheet.described(versions[0].lines[1]) == "Cards [no media]", "Don is told each line's footage, or that it has none")
            check(DonSheet.versions([["Name", "Price"], ["A", "1"]], tab: "Pricing").isEmpty, "A tab with no words column holds no script")
            var sheet = DonSheet(link: "x", versions: versions)
            check(sheet.version(for: ScriptTab(name: "v1.1"))?.name == "v1.1 · Gifting + Lifestyle" && sheet.version(for: ScriptTab(name: "Script 1"))?.name == "v1.0 · Utility demo"
                  && sheet.version(for: ScriptTab(name: "Script 1", script: "Hello")) == nil, "A script is read from the version named like its tab, or the first when nothing is pasted")
            let tab = ScriptTab(name: "v1.1")
            sheet.picks[tab.id.uuidString] = ""
            check(sheet.version(for: tab) == nil, "Choosing the project's script over the sheet sticks")
            let stream = [#"{"type":"system","subtype":"init","mcp_servers":[{"name":"claude.ai Google Sheets","status":"connected"}]}"#,
                          #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"mcp__claude_ai_Google_Sheets__get_spreadsheet","input":{}}]}}"#,
                          #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"{\"properties\":{\"title\":\"CraftyHold - Working File\"}}"}]}}"#,
                          #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"mcp__claude_ai_Google_Sheets__get_values","input":{}}]}}"#,
                          #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"{\"range\":\"'Image Script'!A1:B2\",\"values\":[[\"Text\"],[\"Hi\"]]}"}]}]}}"#]
            let read = try SheetsConnector.cells(in: Data(stream.joined(separator: "\n").utf8))
            check(read.title == "CraftyHold - Working File" && read.tab == "Image Script" && read.rows == [["Text"], ["Hi"]],
                  "The cells come from the connector's own answer, the tab from its range")
            let unconnected = #"{"type":"system","subtype":"init","mcp_servers":[{"name":"claude.ai Google Sheets","status":"needs-auth"}]}"#
            check((try? SheetsConnector.cells(in: Data(unconnected.utf8))) == nil, "No cells without the Sheets connector")
            check(PixJob(kind: .schematic, title: "", detail: "", state: .queued, project: "", script: "").waitsForPictures
                  && !PixJob(kind: .cta, title: "", detail: "", state: .queued, project: "", script: "").waitsForPictures, "Only a schematic waits for product pictures")
            check(PixDesk.isSVG("<svg xmlns=\"http://www.w3.org/2000/svg\"><text>A</text></svg>") && !PixDesk.isSVG("<svg><text>A</svg>") && !PixDesk.isSVG("<html/>"),
                  "Pix keeps only a CTA that is well-formed SVG")
            check(PixDesk.embed(#"<image href="PICTURE1"/><image href="PICTURE12"/>"#, pictures: [Data([1, 2])]) == #"<image href="data:image/jpeg;base64,AQI="/><image href="PICTURE12"/>"#,
                  "Pix puts each product picture in for its name, and only that name")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pix-check-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let first = PixDesk.file(project: "Easy/shapes", script: "Script 1", what: "CTA", ext: "svg", in: folder)
            try Data().write(to: first)
            check(first.lastPathComponent == "Easy-shapes - Script 1 - CTA.svg"
                  && PixDesk.file(project: "Easy/shapes", script: "Script 1", what: "CTA", ext: "svg", in: folder).lastPathComponent == "Easy-shapes - Script 1 - CTA 2.svg",
                  "Pix names a file after the project and script, never over an earlier one")
            try? FileManager.default.removeItem(at: folder)
            check(OpenAIImages.newestModel(in: Data(#"{"data":[{"id":"gpt-image-1"},{"id":"gpt-image-1.5"},{"id":"gpt-image-1-mini"},{"id":"gpt-5"},{"id":"gpt-image-1.10"}]}"#.utf8)) == "gpt-image-1.10"
                  && OpenAIImages.newestModel(in: Data(#"{"data":[{"id":"dall-e-3"}]}"#.utf8)) == nil, "Pix picks the newest full GPT Image model the key has")
            check((try? OpenAIImages.png(from: Data(#"{"data":[{"b64_json":"AQI="}]}"#.utf8))) == Data([1, 2]), "Pix reads GPT Image's picture")
            check(OpenAIImages.message(in: Data(#"{"error":{"message":"Incorrect API key provided"}}"#.utf8)) == "Incorrect API key provided", "Pix shows OpenAI's reason for a refusal")
            let schema = PixDesk.chatSchema
            let items = ((schema["properties"] as? [String: Any])?["proposals"] as? [String: Any])?["items"] as? [String: Any]
            check(schema["required"] as? [String] == ["attachPicturesTo", "proposals", "reply"] && items?["additionalProperties"] as? Bool == false,
                  "Pix's chat schema is strict, as Codex needs")
            let claude = Data((#"{"type":"system"}"# + "\n" + #"{"type":"result","is_error":false,"result":"```json\n{\"reply\":\"hi\"}\n```"}"#).utf8)
            check((try? HelperBrain.answer(claude, provider: .claude))?["reply"] as? String == "hi", "The helper brain reads Claude's answer, fenced or not")
            check((try? HelperBrain.answer(Data(#"{"reply":"yo"}"#.utf8), provider: .codex))?["reply"] as? String == "yo", "The helper brain reads Codex's last message")
        }
        // Tala reads ElevenLabs' answers as its API documents them (2026-11-04).
        do {
            let plan = try ElevenLabs.account(from: Data(#"{"tier":"creator","character_count":12000,"character_limit":100000,"next_character_count_reset_unix":1767225600,"status":"active"}"#.utf8))
            check(plan.tier == "creator" && plan.left == 88_000 && plan.resets == Date(timeIntervalSince1970: 1767225600), "Tala reads the plan and its credits left")
            let page = try ElevenLabs.voices(from: Data(#"{"voices":[{"voice_id":"a1","name":"Rachel","category":"premade","labels":{"accent":"american","gender":"female","use_case":"narration"},"preview_url":"https://x.y/a.mp3"},{"name":"no id"}],"has_more":true,"next_page_token":"t2"}"#.utf8))
            check(page.voices.map(\.id) == ["a1"] && page.voices[0].labels == ["american", "female", "narration"] && page.next == "t2",
                  "Tala lists voices with their labels and follows to the next page")
            let last = try ElevenLabs.voices(from: Data(#"{"voices":[],"has_more":false,"next_page_token":"t3"}"#.utf8))
            check(last.next == nil, "Tala stops at the last page of voices")
            let models = try ElevenLabs.models(from: Data(#"[{"model_id":"eleven_flash_v2_5","name":"Flash","can_do_text_to_speech":true,"maximum_text_length_per_request":40000,"model_rates":{"character_cost_multiplier":0.5}},{"model_id":"eleven_multilingual_sts_v2","can_do_text_to_speech":false},{"model_id":"alpha","can_do_text_to_speech":true,"requires_alpha_access":true}]"#.utf8))
            check(models.map(\.id) == ["eleven_flash_v2_5"] && models[0].maxCharacters == 40_000 && models[0].creditsPerCharacter == 0.5,
                  "Tala offers only the text-to-speech models the account can use, with their limits and cost")
            check(ElevenLabs.message(in: Data(#"{"detail":{"status":"invalid_api_key","message":"Invalid API key"}}"#.utf8)) == "Invalid API key",
                  "Tala shows ElevenLabs' reason for refusing a key")
            // A real answer, 2026-11-04: the key was known but restricted without Voices.
            let restricted = Data(#"{"detail":{"status":"missing_permissions","message":"The API key you used is missing the permission voices_read to execute this operation."}}"#.utf8)
            do { try ElevenLabs.check(401, restricted); check(false, "A key missing a permission is told apart from a wrong key") }
            catch ElevenLabs.Failure.missing(let permission) { check(permission == "voices_read", "A key missing a permission is told apart from a wrong key") }
            catch { check(false, "A key missing a permission is told apart from a wrong key") }
            do { try ElevenLabs.check(401, Data(#"{"detail":{"status":"invalid_api_key","message":"Invalid API key"}}"#.utf8)); check(false, "A wrong key is refused") }
            catch ElevenLabs.Failure.rejected(let reason) { check(reason == "Invalid API key", "A wrong key is refused") }
            catch { check(false, "A wrong key is refused") }
            check(ElevenLabs.permissionName("voices_read") == "Voices (Read)" && ElevenLabs.permissionName("text_to_speech") == "Text to Speech"
                  && ElevenLabs.permissionName("user_read") == "User (Read)", "Tala names a permission as ElevenLabs' key screen does")
            check(ElevenLabs.spoken("Hello **world**\n\nBuy **now**") == "Hello world\nBuy now", "Tala voices the script's words without bold marks")
            let tagged = "[excited] Meet the bra. It lifts [whispers] like magic [laughs]\n[array] no"
            check(ElevenLabs.tags(in: tagged).map { String(tagged[$0]) } == ["[excited]", "[whispers]", "[laughs]", "[array]"],
                  "Tala finds the [tags] in her copy")
            check(ElevenLabs.understandsTags("eleven_v4") && ElevenLabs.understandsTags("eleven_v3")
                  && !ElevenLabs.understandsTags("eleven_multilingual_v2") && !ElevenLabs.understandsTags("eleven_flash_v2_5"),
                  "Tala knows only Eleven v3 and v4 follow tags")
            check(ElevenLabs.parts("short", max: 100) == ["short"], "A script the model takes at once is one part")
            check(ElevenLabs.parts("One line here\nTwo line here\nThree", max: 27) == ["One line here\nTwo line here", "Three"],
                  "Tala cuts a long script between lines")
            check(ElevenLabs.parts("First sentence. Second sentence. Third one.", max: 20) == ["First sentence.", "Second sentence.", "Third one."],
                  "Tala cuts a line too long for one part between sentences")
            let long = String(repeating: "word ", count: 50).trimmingCharacters(in: .whitespaces)
            let split = ElevenLabs.parts(long, max: 23)
            check(split.allSatisfy { $0.count <= 23 } && split.joined(separator: " ") == long, "Tala never cuts mid-word or loses a word")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tala-check-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let first = ElevenLabs.file(project: "Bra: launch", script: "Script 1", in: folder)
            try Data().write(to: first)
            check(first.lastPathComponent == "Bra- launch - Script 1 - voice-over.mp3"
                  && ElevenLabs.file(project: "Bra: launch", script: "Script 1", in: folder).lastPathComponent == "Bra- launch - Script 1 - voice-over 2.mp3",
                  "Tala names the voice-over after the project and script, never replacing an earlier one")
            let older = folder.appendingPathComponent("older.wav"), notes = folder.appendingPathComponent("notes.txt")
            try Data().write(to: older); try Data().write(to: notes)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: older.path)
            check(ElevenLabs.audioFiles(in: folder).map(\.url.lastPathComponent) == ["Bra- launch - Script 1 - voice-over.mp3", "older.wav"],
                  "Tala's file browser lists the folder's sound files, newest first")
            try? FileManager.default.removeItem(at: folder)
            var copy = TalaCopy(script: "Hello **world**")
            copy.text = "[excited] Hello world"
            check(!copy.outdated(by: "**Hello** world") && copy.outdated(by: "Hello there"),
                  "Tala's copy is outdated only when the script's words change, not its bold marks or her tags")
        }
        // Kino groups a batch's files by shot code and works out what each shot would send (2026-11-04).
        do {
            check(KinoCode.parse("K1.1 front")! == ("K1", "K1.1", "front") && KinoCode.parse("k03")! == ("K3", "K3", "")
                  && KinoCode.parse("K9 ref")! == ("K9", "K9", "ref") && KinoCode.parse("1.2")! == ("1", "1.2", ""),
                  "Kino reads the shot code at the start of a file's name, and the words after it")
            check(KinoCode.parse("hf_20260911_103632") == nil && KinoCode.parse("IMG_1234") == nil && KinoCode.parse("20260911_take") == nil
                  && KinoCode.parse("Product hero") == nil, "A date, a camera number or a plain name is not a shot code")
            let folder = URL(fileURLWithPath: "/batch", isDirectory: true)
            let files = KinoCode.files(["K10.png", "K2.mp4", "K1.1.jpg", "K1.png", "K9 ref.mp4", "K9.png", "K1.mov", "notes.txt", "hf_2026.mp4"]
                .map { folder.appendingPathComponent($0) })
            check(files.map(\.handle) == ["hf-2026", "K1", "K1-video", "K1.1", "K2", "K9", "K9-ref", "K10"]
                  && files.first { $0.handle == "K1.1" }?.shot == "K1" && files.first { $0.handle == "hf-2026" }?.shot == nil,
                  "K1, K1.1 and K1's video go into shot K1, each with a tag of its own; a name without a code is in no shot")
            check(KinoPrompt.tags(in: "Use @K1.1. Then @k2, mail@x").map(\.handle) == ["K1.1", "k2", "x"]
                  && KinoPrompt.replacing("@K1.1 and @K7", { $0 == "K1.1" ? "image 1" : nil }) == "image 1 and @K7",
                  "Kino finds the @tags in a prompt, without a full stop after them, and rewrites only the ones it sends")
            func shot(_ names: [String]) -> [KinoFile] { KinoCode.files(names.map { folder.appendingPathComponent($0) }) }
            var o3 = KinoSettings(); o3.model = "kling-o3"
            let edit = KinoRequest.plan(files: shot(["K2.png", "K2.1.png", "K2.2.mp4"]), roles: ["K2.2": .edit], prompt: "Replace the pants in @K2.2 with @K2",
                                        shared: "", settings: o3, durations: [folder.appendingPathComponent("K2.2.mp4").path: 6])
            check(edit.endpoint.hasSuffix("kling-video/o3/video-edit") && edit.problems.isEmpty && edit.seconds == nil
                  && edit.prompt.hasPrefix("Image 1 is a look reference") && edit.prompt.contains("Edit video 1: change only")
                  && edit.prompt.contains("Replace the pants in video 1 with image 1"),
                  "A video given the role Video to edit goes to Kling O3's edit endpoint, its length from the video, with each file's role said")
            let follow = KinoRequest.plan(files: shot(["K3.png", "K3.1.mp4"]), roles: [:], prompt: "She turns", shared: "Easyshape jeans",
                                          settings: o3, durations: [:])
            check(follow.endpoint.hasSuffix("video-reference") && follow.prompt.contains("Follow only the camera path and pacing of video 1; do not carry over its people, speech")
                  && follow.prompt.contains("Easyshape jeans\n\nShe turns") && follow.prompt.hasSuffix("No subtitles, no background music."),
                  "A video follows by default, keeping out its people and their talking; the words for every shot come before the shot's")
            check(KinoRequest.plan(files: shot(["K4.png", "K4.1.png", "K4.2.png", "K4.3.png", "K4.4.png", "K4.5.mp4"]), roles: [:], prompt: "x", shared: "",
                                   settings: o3, durations: [:]).problems.contains { $0.contains("4") },
                  "Kling O3 with a video takes four pictures, and says so before running")
            var seedance = KinoSettings(); seedance.model = "seedance-2.5"
            let mixed = KinoRequest.plan(files: shot(["K5.png", "K5.1.png"]), roles: ["K5": .start], prompt: "x", shared: "", settings: seedance, durations: [:])
            check(mixed.endpoint.hasSuffix("reference-to-video") && mixed.notes.contains { $0.contains("K5") } && mixed.inputs.allSatisfy { $0.slot == "image_urls" },
                  "Seedance with looks and a start frame sends the start frame as a look and says so")
            check(KinoRequest.plan(files: shot(["K5.png"]), roles: ["K5": .start], prompt: "", shared: "", settings: seedance, durations: [:]).endpoint.hasSuffix("image-to-video"),
                  "A start frame alone goes to Seedance's image-to-video, which needs no prompt")
            let stray = KinoRequest.plan(files: shot(["K6.png", "K6.1.png"]), roles: ["K6.1": .unused], prompt: "@K6.1 and @K8", shared: "", settings: o3, durations: [:])
            check(stray.problems.count == 2, "A tag for a file left out, or for no file of the shot, stops the shot")
            let long = KinoRequest.plan(files: shot(["K7.mp4"]), roles: ["K7": .edit], prompt: "x", shared: "", settings: o3,
                                        durations: [folder.appendingPathComponent("K7.mp4").path: 22])
            check(long.problems.contains { $0.contains("15.5") }, "A video too long for Kling O3 to edit is caught before running")
            var kling = KinoSettings(); kling.model = "kling-4.0"
            let direct = KinoRequest.plan(files: shot(["K8.png", "K8.1.png", "K8.2.mp4"]), roles: ["K8": .start], prompt: "@K8.1 walks", shared: "",
                                          settings: kling, durations: [:])
            check(direct.inputs.map(\.slot) == ["first_frame", "refer_image", "feature_video"] && direct.prompt.contains("@refA walks"),
                  "Kling 4.0 gets each file in its own slot, named by the id Kino gives it")
            var fit = KinoSettings(); fit.model = "seedance-2.5"; fit.quality = "1080p"; fit.seconds = 30; fit.aspect = "21:9"
            let fitted = fit.fitted(to: KinoModel.named("kling-o3"))
            check(fitted.quality == "pro" && fitted.seconds == 15 && fitted.aspect == "9:16", "Switching model keeps the picture size and fits the length and shape")
            // The media you put in (2026-11-05): nothing read unless dropped; coded names file themselves, any file goes anywhere.
            await MainActor.run {
                let desk = KinoDesk()
                func at(_ name: String) -> URL { folder.appendingPathComponent(name) }
                desk.add([at("K1.png"), at("K1.1.png"), at("K9 ref.mp4"), at("7.png"), at("IMG_1234.jpg"), at("notes.txt")])
                check(desk.media.count == 5 && desk.shots == ["K1", "K9"] && desk.files(in: "K1").map(\.handle) == ["K1", "K1.1"]
                      && desk.files(in: "K9").map(\.handle) == ["K9"], "Dropped files with a shot code go into their shot; a bare number and other names stay in the media")
                desk.add([at("IMG_1234.jpg"), at("K1.png")], into: "K9")
                check(desk.files(in: "K9").map(\.handle) == ["K9", "K9.1", "K9.2"] && desk.files(in: "K1").count == 2
                      && desk.shots(using: at("K1.png").path) == ["K1", "K9"], "A file dragged onto a shot gets that shot's next tag, and can be in many shots")
                let made = desk.newShot(with: [at("7.png")])
                check(made == "K10" && desk.shots.last == "K10" && desk.files(in: "K10").map(\.handle) == ["K10"], "New shot comes after the last, with what was dropped on it")
                desk.takeOut(desk.files(in: "K9")[1], of: "K9")
                desk.remove(at("K1.png").path)
                check(desk.files(in: "K9").map(\.handle) == ["K9"] && desk.files(in: "K1").map(\.handle) == ["K1.1"] && desk.media.count == 4,
                      "Taking a file out of a shot keeps it in the media; removing it takes it out of every shot")
                desk.add([at("clip.mp4")], into: "K1", as: .edit)
                desk.add([at("hero.png")], into: "K1", as: .start)
                check(desk.role(of: desk.files(in: "K1").first { $0.url.lastPathComponent == "clip.mp4" }!, in: "K1") == .edit
                      && desk.role(of: desk.files(in: "K1").first { $0.url.lastPathComponent == "hero.png" }!, in: "K1") == .start,
                      "A file dropped on a shot's empty place takes that place's role")
                desk.add([at("K12.png"), at("K12.1.png")])
                let twelve = desk.files(in: "K12")
                check(desk.given("K12").isEmpty && desk.role(of: twelve[0], in: "K12") == .look && desk.role(of: twelve[1], in: "K12") == .look,
                      "A shot's pictures have no role until you give one: each goes as a reference (no start frame made by Kino)")
                desk.setPrompt("/start @K12 She turns. /end @K12.1", for: "K12")
                check(desk.given("K12") == ["K12": .start, "K12.1": .end] && desk.plan("K12").prompt.contains("She turns.")
                      && !desk.plan("K12").prompt.contains("/start") && !desk.plan("K12").prompt.contains("/end"),
                      "Commands in the prompt give roles (/start @K12) and are not sent to the model")
                desk.setRole(.start, of: twelve[1], in: "K12")
                check(desk.given("K12") == ["K12.1": .start] && desk.shot("K12").prompt == "She turns. /start @K12.1",
                      "A role picked on the file rewrites its command in the prompt; the start frame before it loses its command")
                desk.setPrompt("She turns.", for: "K12")
                desk.add([at("K12 Size.png")], into: "K12", as: .end)
                check(desk.shot("K12").prompt == "/end @K12-size She turns.", "A role picked for a file with no command writes one at the start of the prompt")
                desk.add([at("K12.2.png")], into: "K12", as: .end)
                check(desk.files(in: "K12").filter { desk.role(of: $0, in: "K12") == .end }.map(\.name) == ["K12.2"]
                      && desk.shot("K12").prompt == "/end @K12.2 She turns.", "A shot keeps one end frame; the one before loses its command")
                desk.setRole(nil, of: desk.files(in: "K12").first { $0.name == "K12.2" }!, in: "K12")
                check(desk.given("K12").isEmpty && desk.shot("K12").prompt == "She turns.", "No role: the file's command leaves the prompt")
                desk.setPrompt("/start @K12 She turns.", for: "K12")
                desk.takeOut(twelve[0], of: "K12")
                check(desk.shot("K12").prompt == "She turns.", "A file taken out of a shot takes its command with it")
                var old = KinoShot(); old.roles = ["K12.1": .start]
                check(old.roles.count == 1 && desk.given("K12")["K12.1"] == nil, "Roles kept beside the prompt before are not read: a role is only a command you can see")
                check(KinoPrompt.withoutCommands("/start @K1 She walks. /out @K2") == "She walks. " && KinoPrompt.commands(in: "and/or @K1").isEmpty
                      && KinoPrompt.commands(in: "/hello @K1").isEmpty, "Only a / starting a word with a role's name is a command")
                desk.add([at("K4.png"), at("K4.1.mp4")])
                check(desk.role(of: desk.files(in: "K4")[0], in: "K4") == .look, "With a video in the shot, its picture is a look, not a start frame")
                check(desk.media(sorted: .name).map(\.name).prefix(4) == ["7", "clip", "hero", "IMG_1234"]
                      && desk.media(sorted: .name).map(\.name).suffix(5) == ["K9 ref", "K12", "K12 Size", "K12.1", "K12.2"]
                      && desk.media(sorted: .added).first?.name == "K4.1"
                      && desk.media(sorted: .shot).map(\.name).prefix(3) == ["clip", "hero", "K1.1"],
                      "The media sorts by name as a person reads it (K2 before K10, K12 before K12 Size and K12.1), by shot, or newest first")
                let inMedia = desk.media.count
                desk.addTakes([at("K12.1 O1.mp4"), at("K12 O2.mp4"), at("K77 O1.mp4"), at("still.png")])
                desk.addTakes([at("final.mp4")], to: "K4")
                let outputs = desk.takes(of: "K12")
                check(outputs.map { desk.number(of: $0) } == [1, 2] && desk.takes.first?.shot == "K4" && desk.takes.count == 4
                      && desk.takes.first { $0.path.hasSuffix("K77 O1.mp4") }?.shot == nil && desk.media.count == inMedia,
                      "Videos dropped on the outputs go with the shot their name has (K12.1 O1 with K12) or the one dropped on, numbered in order; they stay out of the media")
                check(KinoRole.commanded("StartFrame") == .start && KinoRole.commanded("last") == .end && KinoRole.commanded("out") == .unused
                      && KinoRole.commanded("startx") == nil && Set(KinoRole.allCases.map(\.command)).count == KinoRole.allCases.count,
                      "Each role has its own / command in the prompt, called by its usual words (/startframe is /start)")
                desk.watch(outputs[1].path)
                check(desk.takes(of: "K12")[1].seen && !desk.takes(of: "K12")[0].seen, "A take played counts as watched")
            }
            func slots(_ model: String, _ names: [String], _ roles: [String: KinoRole] = [:]) -> [String] {
                KinoSlot.all(model: model, files: shot(names), roles: roles).map { slot in
                    switch slot { case .file(let file): file.handle; case .empty(let role): "+" + role.rawValue }
                }
            }
            check(slots("kling-o3", []) == ["+start", "+end", "+look", "+motion", "+edit"]
                  && slots("kling-o3", ["K1.png", "K1.1.png", "K1.2.png", "K1.3.png", "K1.4.mp4"]) == ["K1", "K1.1", "K1.2", "K1.3", "K1.4"]
                  && slots("kling-o3", ["K1.png", "K1.1.mp4"]) == ["K1", "+look", "K1.1"],
                  "An empty Kling O3 shot shows a place for each role; with its video it has no place for frames, and with 4 pictures no room left")
            check(slots("kling-motion", ["K2.png"]) == ["K2", "+motion"] && slots("seedance-2.5", ["K3.mp3"]) .suffix(2) == ["K3", "+sound"],
                  "Motion Control has a place for the person and the performance; Seedance has places for sounds")
        }
        // Script tabs: each script keeps its own text and progress; the open one is the project's script, as runs read it.
        do {
            var project = Project(name: "Tabs", script: "**one**")
            project.completed = [0]; project.graphicsCompleted = [0]
            let first = project.openScript.id
            check(project.scriptTabs.map(\.name) == ["Script 1"] && first == project.id, "A project saved before tabs is one tab, Script 1")
            project.addScript()
            check(project.scriptTabs.map(\.name) == ["Script 1", "Script 2"] && project.script.isEmpty && project.completed.isEmpty
                  && project.graphicsCompleted == nil, "A new script opens empty, with no progress")
            project.script = "**two**"; project.completed = [0]
            let second = project.openScript.id
            project.openScript(first)
            check(project.script == "**one**" && project.completed == [0] && project.graphicsCompleted == [0] && project.scriptTabs.count == 2,
                  "Opening a script brings back its text and progress")
            check(project.scriptTabs.first { $0.id == second }?.script == "**two**", "The script left keeps what was typed in it")
            project.renameScript(second, to: "  V2 ")
            check(project.scriptTabs.map(\.name) == ["Script 1", "V2"], "A script is renamed in place, trimmed")
            project.addScript()
            check(project.scriptTabs.map(\.name) == ["Script 1", "V2", "Script 3"], "New scripts go at the end, numbered")
            let third = project.openScript.id
            project.moveScript(third, to: 0)
            check(project.scriptTabs.map(\.name) == ["Script 3", "Script 1", "V2"] && project.openScript.id == third && project.scriptPosition == 0,
                  "Dragging the open script to the front keeps it open")
            project.moveScript(first, to: 2)
            check(project.scriptTabs.map(\.name) == ["Script 3", "V2", "Script 1"] && project.script.isEmpty
                  && project.scriptTabs.last?.script == "**one**", "Dragging another script moves it with its text")
            project.moveScript(first, to: 0); project.moveScript(third, to: 2)
            check(project.scriptTabs.map(\.name) == ["Script 1", "V2", "Script 3"], "Dragging back restores the order")
            project.removeScript(second)
            check(project.scriptTabs.map(\.name) == ["Script 1", "Script 3"] && project.scriptName == "Script 3", "Removing another script keeps the open one")
            project.removeScript(project.openScript.id)
            check(project.scriptTabs.map(\.name) == ["Script 1"] && project.script == "**one**", "Removing the open script opens its neighbour")
            project.removeScript(project.openScript.id)
            check(project.scriptTabs.count == 1, "The last script cannot be removed")
            let round = try? JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
            check(round?.scriptTabs.map(\.name) == project.scriptTabs.map(\.name) && round?.script == "**one**", "Script tabs are saved and load back")
        }
        // Interface language: English passes through; Vietnamese by exact text, by number pattern, with values filled in.
        do {
            let saved = UserDefaults.standard.string(forKey: "appLanguage")
            UserDefaults.standard.set("en", forKey: "appLanguage")
            check(L("Run from playhead") == "Run from playhead", "English shows the English text")
            UserDefaults.standard.set("vi", forKey: "appLanguage")
            check(L("Run from playhead") == "Chạy từ playhead", "Vietnamese by exact text")
            check(L("Starting in 3…") == "Bắt đầu sau 3…", "Vietnamese with the numbers kept (\(L("Starting in 3…")))")
            check(L("%@ of %@ done", 8, 10) == "Xong 8 / 10", "Vietnamese with values filled in")
            check(L("Something never translated") == "Something never translated", "Untranslated text shows as it is")
            if let saved { UserDefaults.standard.set(saved, forKey: "appLanguage") } else { UserDefaults.standard.removeObject(forKey: "appLanguage") }
        }
        // The caption track's name misread (2026-10-22: "Sulotitle") still gives the click that focuses the Timeline.
        do {
            let header = TextHit(text: "Sulotitle", rect: CGRect(x: 0.41, y: 0.613, width: 0.023, height: 0.005))
            check(Desktop.trackHeader(in: [header]) != nil, "A misread caption track name is still found")
            check(Desktop.trackHeader(in: [TextHit(text: "Subtle", rect: header.rect), TextHit(text: "C1:Subtitle here", rect: header.rect)]) == nil,
                  "Only one-word names of about the track name's length count")
            check(Desktop.trackHeader(in: [TextHit(text: "Subtitel", rect: CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.03))]) == nil,
                  "Caption-sized text is never taken for the track name")
            check(Desktop.trackHeader(in: [TextHit(text: "Settings", rect: header.rect)]) == nil, "Other one-word labels are not the track")
            check(Desktop.letterDistance("sulotitle", "subtitle") == 2 && Desktop.letterDistance("", "ab") == 2, "Letter distance")
        }
        // A style applied through its right-click menu is remembered and found again.
        do {
            let old = #"{"row":4,"column":2,"positionKnown":true,"appearance":[1,2,3]}"#
            let decoded = try? JSONDecoder().decode(RememberedStyle.self, from: Data(old.utf8))
            check(decoded != nil && decoded?.menu == nil, "A style saved before menus still loads, with no menu")
            var saved = decoded!
            saved.menu = StyleMenuChoice(item: "Apply Style without Font", position: CGPoint(x: 0.4, y: 0.62), keys: [])
            let again = try? JSONDecoder().decode(RememberedStyle.self, from: JSONEncoder().encode(saved))
            check(again?.menu == saved.menu, "The menu choice is saved with the style")
            let items = ["Set as Track Style", "Apply Style without Font", "Duplicate", "Delete"].enumerated().map {
                TextHit(text: $0.element, rect: CGRect(x: 500, y: 300 + Double($0.offset) * 22, width: 160, height: 16))
            }
            check(Desktop.menuItem("Apply Style without Font", in: items)?.text == "Apply Style without Font", "The menu item is found by its text")
            check(Desktop.menuItem("apply style without font", in: [TextHit(text: "Apply Style without Font ⌘", rect: .zero)]) != nil, "A shortcut beside the item does not hide it")
            check(Desktop.menuItem("Apply Style without Font", in: items.filter { !$0.text.hasPrefix("Apply") }) == nil, "A missing item is not guessed")
            check(!rejects(action("rightClick")), "Right-click is an allowed action")
            check(Desktop.menuItem(Desktop.withoutFontItem, in: [TextHit(text: "Apply style wlthout font", rect: .zero)]) != nil, "A misread letter does not hide the item (2026-10-26)")
            check(Desktop.menuItem(Desktop.withoutFontItem, in: [TextHit(text: "Set as Track Style", rect: .zero), TextHit(text: "Apply Style", rect: .zero)]) == nil,
                  "Other items are never taken for Apply Style without Font")
            check(Desktop.withoutFontLine(in: [TextHit(text: "l Appty Style wlthoth font", rect: .zero)]) != nil,
                  "A badly read Apply Style without Font is still the item (2026-11-02: your pick was taken for a misclick)")
            check(Desktop.withoutFontLine(in: items)?.text == "Apply Style without Font", "Among the menu's items, it is the one found")
            check(Desktop.withoutFontLine(in: [TextHit(text: "Apply Style", rect: .zero), TextHit(text: "Set as Track Style", rect: .zero),
                                               TextHit(text: "Font Size", rect: .zero), TextHit(text: "Delete", rect: .zero)]) == nil,
                  "Apply Style, Font Size and other lines are never it")
        }
        // Bold that starts or ends inside a word is widened to the whole word (2026-10-22: "oft stretch", "his much lift").
        do {
            let line = try ScriptParser.parse("Fabric has this really s**oft stretch** that, t**his much lift **from it, **hug**s and **plain** words")[0]
            let phrases = line.highlights.map { Store.wholeWords($0, in: line.text) }
            check(phrases == ["soft stretch", "this much lift ", "hugs", "plain"], "Mid-word bold covers whole words (\(phrases))")
            let spaced = try ScriptParser.parse("My bust sits** higher, rounder,**")[0]
            check(spaced.highlights.map { Store.wholeWords($0, in: spaced.text) } == [" higher, rounder,"], "Bold starting at a space is left as it is")
        }
        // Captions placed in the script: the bold words of that very part are styled, in order (2026-10-28: "Fabric" was
        // styled inside "Soft fabric", and "wire" twice on one word, when phrases were matched anywhere on screen).
        do {
            let lines = try ScriptParser.parse("""
            Wait, my whole hand **fits between the cup** and **wire**, and I still **get this much lift?**!
            **Soft fabric** sits against my skin instead.
            **Fabric** is **super smooth** with so **much stretch**
            With the brand, **wire** stays outside, it **perks right up**
            """)
            let map = ScriptMap(lines: lines)
            let same: (String, String) -> Bool = { ScriptMap.same($0, $1, lookalikes: Desktop.lookalikes) }
            func tags(_ caption: [String], near: Int = 0) -> [Int?]? {
                guard let at = map.locate(caption, near: near, same: same) else { return nil }
                return caption.indices.map { at + $0 < map.words.count ? map.words[at + $0].phrase : nil }
            }
            // Phrases by index: 0 fits between the cup, 1 wire, 2 get this much lift?, 3 Soft fabric, 4 Fabric,
            // 5 super smooth, 6 much stretch, 7 wire (again), 8 perks right up.
            check(tags(["soft", "fabric", "sits"]) == [3, 3, nil], "\"Soft fabric sits\" is Soft fabric only, not Fabric")
            check(tags(["fabric", "is", "super", "smooth"]) == [4, nil, 5, 5], "\"Fabric is super smooth\" is Fabric and super smooth")
            check(tags(["wait", "my", "whole", "hand", "fits"]) == [nil, nil, nil, nil, 0], "A phrase starting at a caption's last word is placed")
            check(tags(["between", "the", "cup", "and", "wire"]) == [0, 0, 0, nil, 1], "Its rest on the next caption, then the first wire")
            check(tags(["and", "still", "get", "this", "much", "lift3"]) == [nil, nil, 2, 2, 2, 2], "A misread last word (lift3) still lines up")
            check(tags(["with", "the", "brand", "wire", "stays", "outside"])?[3] == 7, "The second wire is its own phrase, by its place")
            check(map.split("rightup") == ["right", "up"] && map.split("outside") == nil, "Two words read as one are split back")
            check(tags(["completely", "unrelated", "words"]) == nil, "A caption not in the script is not placed")
            // Ties go forward from the last place: "wire stays" after the first lines is the second wire.
            let near = map.locate(["wire"], near: 20, same: same)
            check(near.map { map.words[$0].phrase } == 7, "A one-word caption is the next one in the script")
        }
        // A step past captions is seen in the script: Shift+Down stops only at video cuts, and went from "See that curved
        // wire?" straight to "Giving me that round", past "heavy lifting from below" (2026-10-28).
        do {
            let lines = try ScriptParser.parse("""
            See that **curved wire?** It's doing all the **heavy lifting from below**
            Giving me that **round, push-up effect**
            """)
            let map = ScriptMap(lines: lines)
            let same: (String, String) -> Bool = { ScriptMap.same($0, $1, lookalikes: Desktop.lookalikes) }
            let before = ["see", "that", "curved", "wire"], after = ["giving", "me", "that", "round"]
            let end = (map.locate(before, near: 0, same: same) ?? -99) + before.count
            let landed = map.locate(after, near: end, same: same) ?? -1
            let todo: (Int) -> Int? = { $0 == 0 ? nil : 0 }   // curved wire? done
            check(map.unstyled(from: end, to: landed, styled: todo).map { map.words[$0].text } == ["heavy", "lifting", "from", "below"],
                  "The bold words passed over between two captions are found")
            check(map.unstyled(from: end, to: landed, styled: { _ in nil }).isEmpty, "Nothing passed over once those are styled")
            let next = map.locate(["push", "up", "effect"], near: landed, same: same) ?? -1
            check(map.unstyled(from: landed + after.count, to: next, styled: todo).isEmpty, "The next caption right after is no gap")
        }
        // The playhead's time is the timeline's own display above its ruler, not a clip list's times higher up (2026-10-28).
        do {
            let list = [TextHit(text: "00:00:00:00", rect: CGRect(x: 0.203, y: 0.218, width: 0.036, height: 0.012)),
                        TextHit(text: "00:00:01:10", rect: CGRect(x: 0.262, y: 0.217, width: 0.035, height: 0.013))]
            let timeline = [TextHit(text: "00:00:05:02", rect: CGRect(x: 0.054, y: 0.537, width: 0.047, height: 0.012)),
                            TextHit(text: "00:00:05:00", rect: CGRect(x: 0.308, y: 0.56, width: 0.036, height: 0.012)),
                            TextHit(text: "00:00:10:00", rect: CGRect(x: 0.471, y: 0.56, width: 0.036, height: 0.012)),
                            TextHit(text: "00:00:15:00", rect: CGRect(x: 0.634, y: 0.56, width: 0.036, height: 0.012)),
                            TextHit(text: "Subtitle", rect: CGRect(x: 0.122, y: 0.613, width: 0.025, height: 0.012))]
            let monitor = [TextHit(text: "00:00:05:02", rect: CGRect(x: 0.732, y: 0.849, width: 0.048, height: 0.015)),
                           TextHit(text: "00:00:51:19", rect: CGRect(x: 0.933, y: 0.852, width: 0.048, height: 0.012))]
            let time = Desktop.playheadTime(in: list + timeline + monitor)
            check(time.map { abs($0 - 5.067) < 0.01 } == true, "The timeline's time is read, not a clip list's (\(time ?? -1))")
        }
        // Inside the Program Monitor's picture a caption with no tall or hanging letters is still a caption (2026-10-26:
        // "on the outside?" at 0.0234 against interface text 0.0139); outside the picture the bar stays.
        do {
            let interface = (0 ..< 9).map { TextHit(text: "Panel \($0)", rect: CGRect(x: 0.7, y: 0.1 + Double($0) * 0.03, width: 0.05, height: 0.0139)) }
            let picture = CGRect(x: 0.02, y: 0.07, width: 0.26, height: 0.75)
            let low = TextHit(text: "on the outside?", rect: CGRect(x: 0.093, y: 0.613, width: 0.116, height: 0.0234))
            check(Desktop.captionBlocks(in: interface + [low], area: picture).count == 1, "A low caption inside the picture is a caption")
            check(Desktop.captionBlocks(in: interface + [low]).isEmpty, "Without the picture, the bar for interface text stays")
            check(Desktop.captionStarts(with: ["on", "the", "outside"], in: interface + [low], area: picture), "The rest of a split phrase on a low caption is seen")
            // A two-tone line read as two pieces, the styled one listed second: still "a bra with the wire".
            let styled = TextHit(text: "a bra", rect: CGRect(x: 0.081, y: 0.611, width: 0.04, height: 0.026))
            let plain = TextHit(text: "with the wire", rect: CGRect(x: 0.124, y: 0.612, width: 0.097, height: 0.025))
            check(Desktop.headAtCaptionEnd("wire", in: interface + [plain, styled], area: picture) != nil, "The last word is taken in reading order")
        }
        // A highlighted word's outline swallowing the space: "perks rightup" is still "perks right up" (2026-10-26).
        do {
            let interface = (0 ..< 6).map { TextHit(text: "Panel \($0)", rect: CGRect(x: 0.7, y: 0.1 + Double($0) * 0.03, width: 0.05, height: 0.012)) }
            let picture = CGRect(x: 0, y: 0.05, width: 0.3, height: 0.85)
            let line = TextHit(text: "perks rightup", rect: CGRect(x: 0.097, y: 0.61, width: 0.111, height: 0.034),
                               words: [("perks", CGRect(x: 0.097, y: 0.61, width: 0.045, height: 0.034)), ("rightup", CGRect(x: 0.146, y: 0.61, width: 0.062, height: 0.034))])
            let match = Desktop.selection(forTokens: ["perks", "right", "up"], in: interface + [line], area: picture)
            check(match?.matched == 3 && abs((match?.span.end.x ?? 0) - 0.208) < 0.002, "Two phrase words read joined still match, to the end of the joined word")
            check(Desktop.selection(forTokens: ["perks", "rightly"], in: interface + [line], area: picture) == nil, "A joined word is only split into the phrase's own words")
            check(!Desktop.captionStarts(with: ["up"], in: interface + [line], area: picture), "The rest of a split phrase at the end of a caption does not start it")
        }
        // A phrase split over two caption clips, only its first word on the first (2026-10-20/22: "secure." / "No bounce around").
        do {
            let interface = (0 ..< 6).map { TextHit(text: "Panel \($0)", rect: CGRect(x: 0.7, y: 0.1 + Double($0) * 0.03, width: 0.05, height: 0.012)) }
            let picture = CGRect(x: 0, y: 0.05, width: 0.3, height: 0.85)
            let first = TextHit(text: "it keeps everything secure.", rect: CGRect(x: 0.05, y: 0.61, width: 0.2, height: 0.03))
            let second = TextHit(text: "No bounce around", rect: CGRect(x: 0.08, y: 0.61, width: 0.15, height: 0.03))
            let middle = TextHit(text: "secure and soft", rect: CGRect(x: 0.08, y: 0.61, width: 0.15, height: 0.03))
            check(Desktop.headAtCaptionEnd("secure", in: interface + [first], area: picture) != nil, "A phrase's first word ending a caption is a split candidate")
            check(Desktop.headAtCaptionEnd("secure", in: interface + [middle], area: picture) == nil, "Not when the word is not the caption's last")
            check(Desktop.headAtCaptionEnd("on", in: interface + [TextHit(text: "carry on", rect: first.rect)], area: picture) == nil, "Not a short common word")
            check(Desktop.headAtCaptionEnd("65", in: interface + [TextHit(text: "After 65", rect: first.rect)], area: picture) == nil, "Not a number")
            check(Desktop.captionStarts(with: ["no", "bounce", "around"], in: interface + [second], area: picture), "The next clip starting with the rest is seen")
            check(!Desktop.captionStarts(with: ["no", "bounce", "around"], in: interface + [TextHit(text: "There is no bounce around", rect: second.rect)], area: picture),
                  "A clip with the rest in its middle does not count")
            check(Desktop.captionStarts(with: ["rounder"], in: interface + [TextHit(text: "rounder, and fuller", rect: second.rect)], area: picture), "A one-word rest at the start counts")
            check(!Desktop.captionStarts(with: ["no", "bounce"], in: interface + [TextHit(text: "No bounce", rect: CGRect(x: 0.72, y: 0.4, width: 0.04, height: 0.012))], area: picture),
                  "Interface text is never a caption")
        }
        // A caption track too short to read is made taller; one of normal height is left alone.
        do {
            let v1 = TextHit(text: "V1", rect: CGRect(x: 0.368, y: 0.762, width: 0.010, height: 0.0139))
            let v4 = TextHit(text: "V4", rect: CGRect(x: 0.368, y: 0.650, width: 0.010, height: 0.0139))
            let ruler = [TextHit(text: "00:01:20:00", rect: CGRect(x: 0.48, y: 0.578, width: 0.04, height: 0.012)),
                         TextHit(text: "00:01:25:00", rect: CGRect(x: 0.59, y: 0.578, width: 0.04, height: 0.012))]
            let squashed = TextHit(text: "Sulotitle", rect: CGRect(x: 0.41, y: 0.613, width: 0.023, height: 0.0046))
            let normal = TextHit(text: "Subtitle", rect: CGRect(x: 0.41, y: 0.608, width: 0.03, height: 0.0125))
            check(Desktop.captionTrackTooSmall(in: [v1, v4, squashed]), "A squashed caption track name is too small")
            check(!Desktop.captionTrackTooSmall(in: [v1, v4, normal]), "A caption track of normal height is left alone")
            check(Desktop.captionTrackTooSmall(in: [v1, v4] + ruler), "No caption track name read, with the timeline in view, is too small")
            check(!Desktop.captionTrackTooSmall(in: [normal]), "No timeline in view: nothing to make taller")
            check(Desktop.captionTrackHeaderPoint(in: [v1, v4, squashed]).map { abs($0.y - squashed.rect.midY) < 0.001 } == true, "Taller from over its name when read")
            check(Desktop.captionTrackHeaderPoint(in: [v1, v4] + ruler).map { $0.y > 0.59 && $0.y < 0.65 && $0.x < 0.45 } == true,
                  "Without a name, over the header column between the ruler and the top video track")
            check(Desktop.trackLabels(in: [TextHit(text: "Va", rect: v1.rect), TextHit(text: "A12", rect: v1.rect), v1]).count == 2, "Track labels are V or A with a number")
        }
        // Your pick's row, checked from the top before it is remembered (2026-10-22: counted R1, really R2).
        check(Store.confirmedStyleRow(reported: 0, differences: [0: 240, 1: 12, 2: 260, 3: 255]) == 1, "A picked row counted one short is corrected")
        check(Store.confirmedStyleRow(reported: 1, differences: [0: 240, 1: 12, 2: 9, 3: 255]) == 1, "A twin a few closer does not move the counted row")
        check(Store.confirmedStyleRow(reported: 1, differences: [0: 20, 1: 240, 2: 22, 3: 255]) == 0 || Store.confirmedStyleRow(reported: 1, differences: [0: 20, 1: 240, 2: 22, 3: 255]) == 2,
              "With yours not at the counted row, the nearest close row is taken")
        check(Store.confirmedStyleRow(reported: 4, differences: [2: 72, 3: 563, 4: 600, 5: 590]) == 2, "A dark tile under the hover tint is still found when plainly the best")
        check(Store.confirmedStyleRow(reported: 2, differences: [0: 90, 1: 95, 2: 100]) == nil, "Nothing clear keeps the counted row")
        // Every guide line has a Vietnamese text (a missing one would show in English mid-guide).
        do {
            let missing = (EditFunction.allCases.flatMap { Guide.steps(for: $0) }.flatMap { [$0.title, $0.lead, $0.tip] + $0.points }
                           + EditFunction.allCases.flatMap(\.points))
                .filter { !$0.isEmpty && Vietnamese.text[$0] == nil }
            check(missing.isEmpty, "Every guide line is translated (missing: \(Set(missing)))")
        }
        print("\(count) checks passed. No desktop input was sent.")
        // Exit explicitly: AppKit objects created by the checks keep the process alive after main
        // returns, which left finished runs hanging and made ./test.sh appear to time out.
        exit(0)
    }
}
