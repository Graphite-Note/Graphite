/**
 * File: MacPDFTextBoxEditor.swift
 * -------------------------------
 * Layer: UI
 * Description: Typing in one text box over a Mac PDF view: a text view at the box's place and the PDF's zoom, whose
 *              text the document takes as the box when typing ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// Types in one text box over a Mac PDF view, as `PDFTextBoxEditor` does on the iPad. The
/// text view sits in the view's scrolling document, so it scrolls with the page; every size
/// is the box's times the zoom, and the box grows downward as lines are added. The box's
/// own annotation is hidden meanwhile, so its text is not shown twice. Typing keeps its own
/// undo history; the PDF's history takes the box as one step when typing ends.
@MainActor
final class MacPDFTextBoxEditor: NSObject, NSTextViewDelegate {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    let step: PDFTextBoxEditStep
    /// The box as typed so far.
    private(set) var box: PDFTextBox
    let textView = NSTextView(frame: .zero)
    private let typingUndoManager = UndoManager()
    /// The zoom the text view's sizes are at.
    private var scale: CGFloat = 1
    /// The looks new text takes where the box has none yet.
    private var typingLooks: PDFTextAttributes
    /// Told when the box changes size or looks, and when Escape ends typing.
    private weak var owner: MacPDFTextBoxTool?

    init(session: PDFSession, pdfView: PDFView, box: PDFTextBox, step: PDFTextBoxEditStep, typingLooks: PDFTextAttributes, owner: MacPDFTextBoxTool) {
        self.session = session
        self.pdfView = pdfView
        self.box = box
        self.step = step
        self.typingLooks = box.runs.last?.attributes ?? typingLooks
        self.owner = owner
        super.init()
        textView.delegate = self
        textView.isRichText = true
        textView.drawsBackground = box.style.fillColor != nil
        textView.backgroundColor = box.style.fillColor.map { fill in NSColor(cgColor: PDFTextBoxLayout.cgColor(fill)) ?? .clear } ?? .clear
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.allowsUndo = true
        // The page is white paper in every appearance.
        textView.appearance = NSAppearance(named: .aqua)
        textView.insertionPointColor = .black
        textView.wantsLayer = true
        textView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        textView.layer?.borderWidth = 1
        textView.setAccessibilityLabel("Text box")
    }

    // MARK: Showing

    /// Shows the text view over the box, with the caret at a point of the PDF view, or at the end of the text.
    func begin(caretAt viewPoint: CGPoint?) {
        guard let pdfView, let documentView = pdfView.documentView else { return }
        documentView.addSubview(textView)
        scale = max(pdfView.scaleFactor, 0.01)
        showText()
        place()
        setBoxAnnotationHidden(true)
        pdfView.window?.makeFirstResponder(textView)
        if let viewPoint {
            let characterIndex = textView.characterIndexForInsertion(at: textView.convert(viewPoint, from: pdfView))
            textView.setSelectedRange(NSRange(location: min(characterIndex, textView.string.utf16.count), length: 0))
        } else {
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        }
        session.registerPendingInkRecordWriter(for: self) { [weak self] in self?.commit(typingContinues: true) }
    }

    private func showText() {
        let selection = textView.selectedRange()
        textView.textStorage?.setAttributedString(PDFTextBoxTextConversion.attributedText(of: box.runs, style: box.style, scale: scale))
        textView.typingAttributes = PDFTextBoxTextConversion.textAttributes(of: typingLooks, style: box.style, scale: scale)
        let padding = CGFloat(box.style.padding) * scale
        textView.textContainerInset = NSSize(width: padding, height: padding)
        if NSMaxRange(selection) <= textView.string.utf16.count { textView.setSelectedRange(selection) }
    }

    /// Places the text view over the box as the PDF view shows it now; at another zoom its text is set again at that zoom.
    func place() {
        guard let pdfView, let documentView = pdfView.documentView, let page = step.page.page, page.document === session.document else { return }
        let zoom = max(pdfView.scaleFactor, 0.01)
        if abs(zoom - scale) > 0.001 {
            scale = zoom
            showText()
        }
        let geometry = MacPDFTextBoxGeometry(box: box, page: page, pdfView: pdfView)
        textView.frame = documentView.convert(geometry.unrotatedFrame, from: pdfView)
        textView.textContainer?.containerSize = NSSize(width: textView.frame.width - 2 * textView.textContainerInset.width,
                                                       height: .greatestFiniteMagnitude)
        textView.frameCenterRotation = geometry.counterclockwiseDegrees
    }

    /// Whether a point of the PDF view is on the text view, whose own clicks place the caret.
    func contains(viewPoint: CGPoint) -> Bool {
        guard let pdfView, textView.superview != nil else { return false }
        return textView.bounds.contains(textView.convert(viewPoint, from: pdfView))
    }

    // MARK: Typing

    func textDidChange(_ notification: Notification) {
        guard let textStorage = textView.textStorage else { return }
        box.runs = PDFTextBoxTextConversion.runs(of: textStorage, scale: scale, typingDefaults: typingLooks)
        let fittedHeight = PDFTextBoxLayout(box: box).fittedHeight
        if abs(fittedHeight - box.height) > 0.01 {
            box.height = fittedHeight
            place()
        }
        owner?.editedBoxDidChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        owner?.editedBoxDidChange()
    }

    func undoManager(for view: NSTextView) -> UndoManager? { typingUndoManager }

    /// Escape ends typing and leaves the box selected, as Preview does.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        owner?.endEditingLeavingBoxSelected()
        return true
    }

    /// The looks the row's text controls show: of the text at the caret or the start of the selection, or the typing looks.
    var currentLooks: PDFTextAttributes {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return typingLooks }
        let location = textView.selectedRange().location
        let index = min(max(location == 0 ? 0 : location - 1, 0), textStorage.length - 1)
        return PDFTextBoxTextConversion.runs(of: textStorage.attributedSubstring(from: NSRange(location: index, length: 1)),
                                             scale: scale, typingDefaults: typingLooks).first?.attributes ?? typingLooks
    }

    /// Changes the looks of the selected text, or, with none selected, of the text typed next;
    /// a change of the box (alignment, fill, border) changes the whole box.
    func apply(_ change: PDFTextBoxFormatChange) {
        let selection = textView.selectedRange()
        let changedStyle = change.applied(to: box.style, textColor: currentLooks.color)
        if changedStyle != box.style {
            box.style = changedStyle
            textView.drawsBackground = box.style.fillColor != nil
            textView.backgroundColor = box.style.fillColor.map { fill in NSColor(cgColor: PDFTextBoxLayout.cgColor(fill)) ?? .clear } ?? .clear
            showText()
        } else if selection.length > 0, let textStorage = textView.textStorage {
            let selected = textStorage.attributedSubstring(from: selection)
            let changedRuns = PDFTextBoxTextConversion.runs(of: selected, scale: scale, typingDefaults: typingLooks).map { run in
                PDFTextRun(text: run.text, attributes: change.applied(to: run.attributes))
            }
            textStorage.replaceCharacters(in: selection, with: PDFTextBoxTextConversion.attributedText(of: changedRuns, style: box.style, scale: scale))
            textView.setSelectedRange(selection)
        }
        typingLooks = change.applied(to: currentLooks)
        textView.typingAttributes = PDFTextBoxTextConversion.textAttributes(of: typingLooks, style: box.style, scale: scale)
        textDidChange(Notification(name: NSText.didChangeNotification))
    }

    // MARK: Ending

    /// Gives the document the box as typed, as the one step of this typing.
    /// - Parameter typingContinues: For a save while typing pauses (`PDFSession.commitTextBox`).
    func commit(typingContinues: Bool = false) {
        do { try session.commitTextBox(box, in: step, typingContinues: typingContinues) }
        catch { session.reportFailedChange(error) }
        // The commit put a new annotation in the box's place, which shows under the text view.
        if typingContinues { setBoxAnnotationHidden(true) }
    }

    /// Commits the box and takes the text view away.
    func end() {
        commit()
        session.unregisterPendingInkRecordWriter(for: self)
        setBoxAnnotationHidden(false)
        textView.delegate = nil
        if pdfView?.window?.firstResponder === textView { pdfView?.window?.makeFirstResponder(pdfView) }
        textView.removeFromSuperview()
    }

    /// Hides or shows the annotation that draws the box on the page, found by the box's name.
    private func setBoxAnnotationHidden(_ isHidden: Bool) {
        guard let page = step.page.page else { return }
        for annotation in page.annotations where PDFTextBox(annotation: annotation)?.name == box.name {
            if annotation.shouldDisplay == isHidden { annotation.shouldDisplay = !isHidden }
        }
    }
}

/// Where a text box is in a Mac PDF view: the rectangle it covers before it is turned,
/// about its middle, and its turn on screen, which is the box's own on a page shown turned
/// by quarter turns, as `PDFTextBoxSelectionFrame.geometry` finds it on the iPad.
struct MacPDFTextBoxGeometry {
    let unrotatedFrame: CGRect
    /// Clockwise on screen, in radians.
    let clockwiseRotation: CGFloat

    @MainActor
    init(box: PDFTextBox, page: PDFPage, pdfView: PDFView) {
        let scale = pdfView.scaleFactor
        let middle = pdfView.convert(box.middle, from: page)
        let size = CGSize(width: CGFloat(box.width) * scale, height: CGFloat(box.height) * scale)
        let quarterTurns = ((page.rotation / 90) % 4 + 4) % 4
        unrotatedFrame = CGRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height)
        clockwiseRotation = CGFloat(box.rotationRadians) + CGFloat(quarterTurns) * .pi / 2
    }

    /// The turn as AppKit's views take it, counterclockwise in degrees, nearest whole turn as 0.
    var counterclockwiseDegrees: CGFloat {
        let degrees = -clockwiseRotation * 180 / .pi
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return abs(remainder) < 0.01 || abs(abs(remainder) - 360) < 0.01 ? 0 : remainder
    }
}
#endif
