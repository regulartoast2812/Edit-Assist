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
