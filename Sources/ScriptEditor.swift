import AppKit
import SwiftUI

final class ScriptTextView: NSTextView {
    var onPasteImage: ((NSImage) -> Void)?
    override func paste(_ sender: Any?) {
        if let onPasteImage, let image = NSImage(pasteboard: .general) { onPasteImage(image); return }
        guard let text = RichScript.paste() else { return }
        insertText(text, replacementRange: selectedRange())
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "b" { markSelection(); return true }
        return super.performKeyEquivalent(with: event)
    }
    func markSelection() {
        let range = selectedRange()
        guard range.length > 0 else { return }
        let value = (string as NSString).substring(with: range)
        let replacement = value.hasPrefix("**") && value.hasSuffix("**") && value.count >= 4 ? String(value.dropFirst(2).dropLast(2)) : "**" + value + "**"
        insertText(replacement, replacementRange: range)
    }
}

struct ScriptEditor: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool
    var onPasteImage: ((NSImage) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = ScriptTextView()
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.drawsBackground = false
        editor.textColor = .labelColor
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.onPasteImage = onPasteImage
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? ScriptTextView else { return }
        view.isEditable = editable
        view.onPasteImage = onPasteImage
        if view.string != text { view.string = text }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptEditor
        init(_ parent: ScriptEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
}

// MARK: The script, shown as it reads

extension NSAttributedString.Key {
    /// Marks a highlighted phrase in the script editor (true), or plain text (false); saved as **…** around a
    /// highlight. Every run carries it, true or false: text pasted over a highlight takes any attribute it does
    /// not carry from the text it replaces, and a plain run without it turned into a highlight.
    static let scriptHighlight = NSAttributedString.Key("EditAssistScriptHighlight")
}

/// The script with its highlights shown as bold green text instead of ** marks, like a document. The
/// project still stores the marks (ScriptParser reads them), so this converts on the way in and out:
/// `**` toggles a highlight, `\*` and `\\` are a literal star and backslash, as in ScriptParser.
enum ScriptText {
    static let font = NSFont.systemFont(ofSize: 14)
    static let bold = NSFont.systemFont(ofSize: 14, weight: .bold)
    static let green = NSColor(red: 0.43, green: 0.88, blue: 0.73, alpha: 1)
    static var paragraph: NSParagraphStyle { let style = NSMutableParagraphStyle(); style.lineSpacing = 4; return style }

    static func isHighlight(_ value: Any?) -> Bool { (value as? Bool) == true }

    static func attributes(highlighted: Bool) -> [NSAttributedString.Key: Any] {
        [.font: highlighted ? bold : font, .foregroundColor: highlighted ? green : NSColor.labelColor,
         .paragraphStyle: paragraph, .scriptHighlight: highlighted]
    }

    static func attributed(_ marked: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var on = false, run = ""
        func flush() { if !run.isEmpty { result.append(NSAttributedString(string: run, attributes: attributes(highlighted: on))); run = "" } }
        let chars = Array(marked)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, ["*", "\\"].contains(chars[i + 1]) { run.append(chars[i + 1]); i += 2; continue }
            if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "*" { flush(); on.toggle(); i += 2; continue }
            run.append(chars[i]); i += 1
        }
        flush()
        return result
    }

    static func marked(_ attributed: NSAttributedString) -> String {
        var result = ""
        attributed.enumerateAttribute(.scriptHighlight, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            let text = (attributed.string as NSString).substring(with: range)
                .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "*", with: "\\*")
            result += isHighlight(value) ? "**\(text)**" : text
        }
        return result
    }
}

final class RichScriptTextView: NSTextView {
    var onPasteImage: ((NSImage) -> Void)?
    override func paste(_ sender: Any?) {
        if let onPasteImage, let image = NSImage(pasteboard: .general) { onPasteImage(image); return }
        guard let marked = RichScript.paste() else { return }
        // Bold in what you copied (Google Docs, Sheets, Word) arrives as highlights.
        insertText(ScriptText.attributed(marked), replacementRange: selectedRange())
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "b": toggleHighlight(); return true
        case "z": undoManager?.undo(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
    override func keyDown(with event: NSEvent) {
        // ⇧⌘Z redoes, as in every editor.
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "z" {
            undoManager?.redo(); return
        }
        super.keyDown(with: event)
    }

    /// ⌘B: highlight the selection, or remove the highlight when all of it already is one. With nothing
    /// selected it switches what you type next, like bold in a document. Undoable.
    func toggleHighlight() {
        let range = selectedRange()
        guard let storage = textStorage else { return }
        guard range.length > 0 else {
            let on = ScriptText.isHighlight(typingAttributes[.scriptHighlight])
            typingAttributes = ScriptText.attributes(highlighted: !on)
            return
        }
        var all = true
        storage.enumerateAttribute(.scriptHighlight, in: range) { value, _, _ in if !ScriptText.isHighlight(value) { all = false } }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.setAttributes(ScriptText.attributes(highlighted: !all), range: range)
        storage.endEditing()
        didChangeText()
        undoManager?.setActionName(all ? "Remove Highlight" : "Highlight")
    }
}

/// The project's script, edited as it reads: highlights bold and green, ⌘B to highlight, ⌘Z to undo.
struct RichScriptEditor: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool
    var onPasteImage: ((NSImage) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = RichScriptTextView()
        // Rich text so a highlight can show; what may be in it is kept to plain text and highlights.
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.drawsBackground = false
        editor.typingAttributes = ScriptText.attributes(highlighted: false)
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.onPasteImage = onPasteImage
        editor.textStorage?.setAttributedString(ScriptText.attributed(text))
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? RichScriptTextView, let storage = view.textStorage else { return }
        view.isEditable = editable
        view.onPasteImage = onPasteImage
        // Only when the script changed elsewhere (Paste formatted text, a new project): replacing it while
        // you type would move the caret.
        if ScriptText.marked(storage) != text {
            storage.setAttributedString(ScriptText.attributed(text))
            view.undoManager?.removeAllActions(withTarget: storage)
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichScriptEditor
        init(_ parent: RichScriptEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, let storage = view.textStorage else { return }
            // Whatever arrived (typed, dropped, pasted), it reads as plain text or a highlight, nothing else.
            storage.beginEditing()
            storage.enumerateAttribute(.scriptHighlight, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                storage.setAttributes(ScriptText.attributes(highlighted: ScriptText.isHighlight(value)), range: range)
            }
            storage.endEditing()
            parent.text = ScriptText.marked(storage)
        }
    }
}
