/**
 * File: MacPDFMarkupInteraction.swift
 * -----------------------------------
 * Layer: UI
 * Description: The Mac PDF view's pointer and keyboard handling of text markup: marking a selection with the
 *              highlighter, selecting, recolouring and removing a mark, and the markup items of the right-click menu.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import GraphiteApple

/// The Mac PDF view's handling of text markup. The view (`GraphiteMacPDFView`) hands it
/// each mouse and key event first; an event it does not take goes on to PDFKit.
///
/// - A click on a mark selects it: its text shows selected, Delete removes it, and the
///   mouse let go does not mark the text again.
/// - With the highlighter chosen, letting go of the mouse after selecting text marks it.
/// - A right-click on a mark offers its colours and Remove; on selected text, the
///   markup styles and the links to the page, before PDFKit's own items.
@MainActor
final class MacPDFMarkupInteraction: NSObject {
    private weak var session: PDFSession?
    private weak var view: PDFView?
    /// The pane's markup row, told when the text selection comes and goes for the menu bar.
    weak var toolbar: PDFMarkupToolbar? {
        didSet { reportTextSelection() }
    }
    var input = PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)
    var linkActions: PDFLinkActions?
    private var selectedMark: (annotation: PDFAnnotation, page: PDFPage)?
    private var mouseDownChoseMark = false

    init(session: PDFSession, view: PDFView) {
        self.session = session
        self.view = view
        super.init()
        // PDFKit posts the change on the main thread, where the view's selection changes.
        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: view)
    }

    /// Ends the observation of the view's selection; called when the view is taken down.
    func stopObservingSelection() {
        NotificationCenter.default.removeObserver(self, name: .PDFViewSelectionChanged, object: nil)
    }

    @objc private func selectionChanged() { reportTextSelection() }

    private var selectionHasText: Bool { !(view?.currentSelection?.string ?? "").isEmpty }

    private func reportTextSelection() {
        toolbar?.textSelectionChanged(hasText: selectionHasText)
    }

    // MARK: Events

    /// Takes a plain click on a mark, which selects the mark.
    func handleMouseDown(_ event: NSEvent) -> Bool {
        mouseDownChoseMark = false
        selectedMark = nil
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, event.clickCount == 1,
              let view, let mark = mark(at: event) else { return false }
        selectedMark = mark
        mouseDownChoseMark = true
        view.currentSelection = Self.textSelection(of: mark.annotation, on: mark.page)
        return true
    }

    /// After PDFKit has finished the selection: marks it if the highlighter is chosen.
    func mouseUpFinished() {
        guard input.isEnabled, let view, let session,
              let style = input.markupTool.styleToApplyOnMouseUp(style: input.markupStyle, selectionHasText: selectionHasText,
                                                                clickChoseExistingMark: mouseDownChoseMark) else { return }
        PDFSelectionMarking.markSelection(of: view, in: session, as: style)
    }

    /// Takes Delete and Forward Delete while a mark is selected, which remove it.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let selectedMark, let session, let key = event.charactersIgnoringModifiers?.unicodeScalars.first,
              Self.deletionKeys.contains(Int(key.value)) else { return false }
        self.selectedMark = nil
        view?.clearSelection()
        PDFSelectionMarking.remove(selectedMark.annotation, on: selectedMark.page, in: session)
        return true
    }

    private static let deletionKeys: Set<Int> = [NSBackspaceCharacter, NSDeleteCharacter, NSDeleteFunctionKey]

    /// The right-click menu: a mark's menu, or PDFKit's menu with the markup items first when text is selected.
    func menu(for event: NSEvent, defaultMenu: NSMenu?) -> NSMenu? {
        if let mark = mark(at: event) { return markMenu(for: mark) }
        guard input.isEnabled, let view, let session, let selection = view.currentSelection,
              let selectedText = selection.string, !selectedText.isEmpty else { return defaultMenu }
        let menu = defaultMenu ?? NSMenu()
        var items = PDFMarkupStyle.choices.map { style in
            MacPDFMarkupMenuItem(title: style.kind == .highlight ? "Highlight \(style.title)" : style.title, image: Self.image(for: style)) {
                [weak view, weak session] in
                guard let view, let session else { return }
                PDFSelectionMarking.markSelection(of: view, in: session, as: style)
            } as NSMenuItem
        }
        if let linkActions, let page = selection.pages.first, session.document.index(for: page) != NSNotFound {
            items.append(.separator())
            items += Self.linkItems(linkActions, pageIndex: session.document.index(for: page), text: selectedText)
        }
        items.append(.separator())
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        return menu
    }

    // MARK: Marks

    private func mark(at event: NSEvent) -> (annotation: PDFAnnotation, page: PDFPage)? {
        guard input.isEnabled, let view else { return nil }
        let viewPoint = view.convert(event.locationInWindow, from: nil)
        guard let page = view.page(for: viewPoint, nearest: false) else { return nil }
        return page.markupAnnotation(at: view.convert(viewPoint, to: page)).map { annotation in (annotation, page) }
    }

    private func markMenu(for mark: (annotation: PDFAnnotation, page: PDFPage)) -> NSMenu? {
        guard let kind = PDFMarkupKind(annotationType: mark.annotation.type), let session else { return nil }
        let menu = NSMenu()
        let currentColor = PDFMarkup(annotation: mark.annotation)?.color
        for color in PDFSelectionMarking.colors(for: kind) {
            let item = MacPDFMarkupMenuItem(title: color.title, image: Self.swatch(color.platformColor)) { [weak session] in
                guard let session else { return }
                PDFSelectionMarking.recolor(mark.annotation, on: mark.page, to: color, in: session)
            }
            item.state = color == currentColor ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(MacPDFMarkupMenuItem(title: "Remove \(kind.title)", image: NSImage(systemSymbolName: "trash", accessibilityDescription: nil)) {
            [weak session] in
            guard let session else { return }
            PDFSelectionMarking.remove(mark.annotation, on: mark.page, in: session)
        })
        return menu
    }

    /// The marked text as a selection, from the start of its first line to the end of its
    /// last, so a selected mark shows as exactly its text selected. A rectangle's selection
    /// took in whole lines of text around it.
    private static func textSelection(of mark: PDFAnnotation, on page: PDFPage) -> PDFSelection? {
        let lineRectangles = PDFMarkup.lineRectangles(of: mark)
        guard let firstLine = lineRectangles.first, let lastLine = lineRectangles.last else { return nil }
        return page.selection(from: CGPoint(x: firstLine.minX + markEdgeInset, y: firstLine.midY),
                              to: CGPoint(x: lastLine.maxX - markEdgeInset, y: lastLine.midY))
    }

    /// How far inside a marked line its first and last characters are looked for, in points.
    private static let markEdgeInset: CGFloat = 1

    private static func linkItems(_ linkActions: PDFLinkActions, pageIndex: Int, text: String) -> [NSMenuItem] {
        var items = [
            MacPDFMarkupMenuItem(title: "Copy Link to Page", image: NSImage(systemSymbolName: "link", accessibilityDescription: nil)) {
                linkActions.copyLink(pageIndex)
            },
            MacPDFMarkupMenuItem(title: "Copy as Quote", image: NSImage(systemSymbolName: "text.quote", accessibilityDescription: nil)) {
                linkActions.copyQuote(pageIndex, text)
            },
        ]
        if let quoteInNote = linkActions.quoteInNote, let noteName = linkActions.noteName {
            let image = NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: nil)
            items.append(MacPDFMarkupMenuItem(title: "Quote in “\(noteName)”", image: image) {
                quoteInNote(pageIndex, text)
            })
        }
        return items
    }

    // MARK: Images

    /// The swatch of a highlight colour, or the symbol of an underline or strikethrough.
    static func image(for style: PDFMarkupStyle) -> NSImage? {
        switch style {
        case .highlight(let color): swatch(color.platformColor)
        case .underline, .strikeOut: NSImage(systemSymbolName: style.symbolName, accessibilityDescription: style.title)
        }
    }

    private static let swatchSide: CGFloat = 12
    private static let swatchCornerRadius: CGFloat = 3
    /// A faint edge, so a light swatch shows on a light menu.
    private static let swatchEdgeOpacity: CGFloat = 0.25

    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: swatchSide, height: swatchSide), flipped: false) { rectangle in
            color.setFill()
            NSBezierPath(roundedRect: rectangle, xRadius: swatchCornerRadius, yRadius: swatchCornerRadius).fill()
            NSColor.black.withAlphaComponent(swatchEdgeOpacity).setStroke()
            NSBezierPath(roundedRect: rectangle.insetBy(dx: 0.25, dy: 0.25), xRadius: swatchCornerRadius, yRadius: swatchCornerRadius).stroke()
            return true
        }
    }
}

/// A menu item that runs a closure.
private final class MacPDFMarkupMenuItem: NSMenuItem {
    private let perform: () -> Void

    init(title: String, image: NSImage?, perform: @escaping () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(MacPDFMarkupMenuItem.performAction), keyEquivalent: "")
        target = self
        self.image = image
    }

    required init(coder: NSCoder) {
        perform = {}
        super.init(coder: coder)
    }

    @objc private func performAction() { perform() }
}
#endif
