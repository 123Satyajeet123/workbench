import AppKit
import SwiftUI

/// A plain text view for a note. Each edit it makes, a typed key, a paste or an undo, goes to `edit` as a replaced range of
/// the text before it takes place, so the document never has to guess what changed.
final class NoteTextView: NSTextView {
    static let minimumHeight: CGFloat = 160
    var moveBlock: ((Int) -> Void)?

    /// The note is as tall as its text, and never shorter than a place to click into.
    override var intrinsicContentSize: NSSize {
        guard let layout = textLayoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: Self.minimumHeight)
        }
        layout.ensureLayout(for: layout.documentRange)
        let height = ceil(layout.usageBoundsForTextContainer.height)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, Self.minimumHeight))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    /// A pasted text is plain, and every kind of line break in it is a paragraph break.
    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let lines = text.replacing(/\r\n|\r|\u{2028}|\u{2029}/, with: "\n")
        if shouldChangeText(in: selectedRange(), replacementString: lines) {
            replaceCharacters(in: selectedRange(), with: lines)
            didChangeText()
        }
    }

    override func insertLineBreak(_ sender: Any?) { insertNewline(sender) }

    /// ⌃⌘ and an arrow move the paragraph under the caret.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let wanted: NSEvent.ModifierFlags = [.control, .command]
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: wanted) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.specialKey {
        case .upArrow: moveBlock?(-1)
        case .downArrow: moveBlock?(1)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

struct NoteTextEditor: NSViewRepresentable {
    let model: NoteEditorModel
    @Environment(\.uiScale) private var scale

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NoteTextView {
        let view = NoteTextView(usingTextLayoutManager: true)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.insertionPointColor = Palette.accent
        view.moveBlock = { [weak coordinator = context.coordinator] distance in coordinator?.moveBlock(by: distance) }
        context.coordinator.view = view
        view.textStorage.map(context.coordinator.watch)
        return view
    }

    func updateNSView(_ view: NoteTextView, context: Context) {
        context.coordinator.draw(scale: scale)
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: NoteEditorModel
        weak var view: NoteTextView?
        private var drawnRevision = -1
        private var drawnScale = 0.0
        private var isDrawing = false

        init(model: NoteEditorModel) { self.model = model }

        func watch(_ storage: NSTextStorage) {
            NotificationCenter.default.addObserver(
                self, selector: #selector(storageProcessedEditing(_:)),
                name: NSTextStorage.didProcessEditingNotification,
                object: storage)
        }

        static func attributes(scale: Double) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4 * scale
            style.paragraphSpacing = 10 * scale
            return [
                .font: NSFont.systemFont(ofSize: 14 * scale), .foregroundColor: Palette.text, .paragraphStyle: style,
            ]
        }

        /// Draws the document's text when it changed other than by typing, and the size when the zoom changed.
        func draw(scale: Double) {
            guard let view, drawnRevision != model.revision || drawnScale != scale else { return }
            isDrawing = true
            defer { isDrawing = false }
            let selection = view.selectedRange()
            let attributes = Self.attributes(scale: scale)
            view.typingAttributes = attributes
            if drawnRevision != model.revision || view.string != model.text {
                view.textStorage?.setAttributedString(NSAttributedString(string: model.text, attributes: attributes))
                let length = (model.text as NSString).length
                view.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            } else {
                view.textStorage?.addAttributes(
                    attributes, range: NSRange(location: 0, length: view.textStorage?.length ?? 0))
            }
            view.invalidateIntrinsicContentSize()
            drawnRevision = model.revision
            drawnScale = scale
        }

        func moveBlock(by distance: Int) {
            guard let view else { return }
            let caret = view.selectedRange().location
            model.moveBlock(atOffset: caret, by: distance)
            draw(scale: drawnScale)
            let block = model.document.blockID(at: caret)
            view.setSelectedRange(NSRange(location: model.document.offset(of: block), length: 0))
        }

        /// Every change of the characters, whoever made it: a key, a paste, an undo. The storage says which range was replaced
        /// and by what.
        @objc func storageProcessedEditing(_ note: Notification) {
            guard let storage = note.object as? NSTextStorage, !isDrawing,
                storage.editedMask.contains(.editedCharacters)
            else { return }
            let edited = storage.editedRange
            let replaced = edited.location..<(edited.location + edited.length - storage.changeInLength)
            model.edit(replaced, with: (storage.string as NSString).substring(with: edited))
            storage.addAttributes(Self.attributes(scale: drawnScale), range: edited)
            model.isComposing = view?.hasMarkedText() ?? false
        }
    }
}
