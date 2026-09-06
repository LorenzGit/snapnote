import SwiftUI

struct ArrowLabelField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Type your own phrase…"
        field.font = .systemFont(ofSize: 13)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Custom arrow label")
        field.toolTip = "Type your own arrow label · Shift+Return: new line · Return: apply"
        DispatchQueue.main.async { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ArrowLabelField
        init(_ parent: ArrowLabelField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let newline = selector == #selector(NSResponder.insertNewline(_:))
            let lineBreak = selector == NSSelectorFromString("insertLineBreak:")
                || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            if lineBreak || (newline && NSApp.currentEvent?.modifierFlags.contains(.shift) == true) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                parent.text = textView.string
                return true
            }
            if newline { parent.text = textView.string; parent.onSubmit(); return true }
            return false
        }
    }
}
