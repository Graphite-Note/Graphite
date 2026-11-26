/**
 * File: MacBlockHandles.swift
 * ---------------------------
 * Layer: UI
 * Description: The handle beside the block under the pointer in the Mac's Live Preview: dragged, it moves the block;
 *              clicked, it opens the block's menu.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(macOS)
import AppKit
import GraphiteCore

/// The block handle of one Mac note editor (Docs/Slash-menu-and-block-handles-todo.md,
/// section 2). It shows only while the pointer is over a block in Live Preview, beside the
/// fold chevron; nothing is made until the pointer first rests on a block.
@MainActor
final class MacBlockHandles {
    /// What the handles act on: the note's text and its revision, or nil when the editor does
    /// not show handles (Source mode, the editor without keyboard focus to give).
    var noteState: () -> (source: NSString, revision: Int)? = { nil }
    /// Makes an edit as one step Undo takes back; set by the coordinator.
    var perform: (MarkdownTextEdit) -> Void = { _ in }
    /// Whether the editor shows Live Preview, the only mode with handles; the text view
    /// watches the pointer for them only then.
    var isInLivePreview: () -> Bool = { false }
    var watchesPointer: Bool { isInLivePreview() }

    private weak var textView: NSTextView?
    private var handleView: MacBlockHandleView?
    private var insertionLine: NSView?
    /// The note's blocks, found once per text revision while the pointer moves over the note.
    private var blocks: (revision: Int, blocks: [HandleBlock])?
    /// The block the handle shows for.
    private(set) var shownBlock: HandleBlock?
    /// While a drag is on: where the block would go if it were let go now.
    private(set) var dragDestination: Int?
    private var escapeMonitor: Any?

    static let handleSize = CGSize(width: 14, height: 18)
    /// The fold chevron's width and gap, which the handle sits left of.
    private static let chevronRoom: CGFloat = 24
    /// How far the pointer moves before a press on the handle becomes a drag.
    private static let dragThreshold: CGFloat = 4

    func attach(to textView: NSTextView) {
        self.textView = textView
    }

    var isShown: Bool { handleView?.isHidden == false }

    // MARK: Pointer

    /// The pointer moved over the note, at a point of its window.
    func pointerMoved(to windowPoint: CGPoint) {
        guard dragDestination == nil, handleView?.isTracking != true, let textView else { return }
        let point = textView.convert(windowPoint, from: nil)
        if let handleView, !handleView.isHidden, handleView.frame.insetBy(dx: -4, dy: -4).contains(point) { return }
        guard let state = noteState(), let location = characterOffset(atHeightOf: point, in: textView),
              let block = BlockHandleEditing.block(at: location, in: currentBlocks(for: state)) else {
            hide()
            return
        }
        show(for: block, source: state.source, in: textView)
    }

    func pointerLeft() {
        guard dragDestination == nil, handleView?.isTracking != true else { return }
        hide()
    }

    /// Hides the handle, as typing does.
    func hide() {
        handleView?.isHidden = true
        shownBlock = nil
    }

    private func currentBlocks(for state: (source: NSString, revision: Int)) -> [HandleBlock] {
        if let blocks, blocks.revision == state.revision { return blocks.blocks }
        let found = BlockHandleEditing.blocks(in: state.source as String)
        blocks = (state.revision, found)
        return found
    }

    private func show(for block: HandleBlock, source: NSString, in textView: NSTextView) {
        guard let frame = handleFrame(for: block, source: source, in: textView) else { return hide() }
        let handleView = handleView ?? makeHandleView(in: textView)
        handleView.frame = frame
        handleView.isHidden = false
        handleView.setAccessibilityLabel("Move or change this block")
        shownBlock = block
    }

    private func makeHandleView(in textView: NSTextView) -> MacBlockHandleView {
        let handleView = MacBlockHandleView(owner: self)
        textView.addSubview(handleView)
        self.handleView = handleView
        return handleView
    }

    // MARK: Geometry

    /// The character the line at the point's height starts with, wherever the point is across.
    private func characterOffset(atHeightOf point: CGPoint, in textView: NSTextView) -> Int? {
        guard let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager else { return nil }
        let origin = textView.textContainerOrigin
        let containerPoint = CGPoint(x: 1, y: point.y - origin.y)
        guard let fragment = textLayoutManager.textLayoutFragment(for: containerPoint) else { return nil }
        let fragmentStart = contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
        // Within a paragraph of several lines, the line under the pointer.
        let localY = containerPoint.y - fragment.layoutFragmentFrame.minY
        let line = fragment.textLineFragments.first { line in line.typographicBounds.minY <= localY && localY < line.typographicBounds.maxY }
        return fragmentStart + (line?.characterRange.location ?? 0)
    }

    /// Left of the fold chevron, at the height of the block's first line.
    private func handleFrame(for block: HandleBlock, source: NSString, in textView: NSTextView) -> CGRect? {
        guard let firstLine = lineRect(at: block.range.location, in: textView) else { return nil }
        let size = Self.handleSize
        return CGRect(x: max(0, firstLine.minX - Self.chevronRoom - size.width), y: firstLine.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The rectangle of the line `location` starts, in the text view's coordinates.
    private func lineRect(at location: Int, in textView: NSTextView) -> CGRect? {
        guard let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager,
              let textLocation = contentManager.location(contentManager.documentRange.location, offsetBy: location) else { return nil }
        textLayoutManager.ensureLayout(for: NSTextRange(location: textLocation))
        guard let fragment = textLayoutManager.textLayoutFragment(for: textLocation), let firstLine = fragment.textLineFragments.first else { return nil }
        let origin = textView.textContainerOrigin
        let bounds = firstLine.typographicBounds
        return CGRect(x: origin.x + fragment.layoutFragmentFrame.minX + (textView.textContainer?.lineFragmentPadding ?? 0),
                      y: origin.y + fragment.layoutFragmentFrame.minY + bounds.minY, width: bounds.width, height: bounds.height)
    }

    /// The top of the line a destination starts, or the bottom of the note's last line.
    private func destinationHeight(_ destination: Int, source: NSString, in textView: NSTextView) -> CGFloat? {
        if destination < source.length { return lineRect(at: destination, in: textView)?.minY }
        guard source.length > 0 else { return nil }
        return lineRect(at: source.lineRange(for: NSRange(location: source.length - 1, length: 0)).location, in: textView)?.maxY
    }

    // MARK: Dragging

    /// A press on the handle moved past the threshold: the block is being dragged.
    func dragMoved(to windowPoint: CGPoint, pressStart: CGPoint) {
        guard let textView, let block = shownBlock, let state = noteState() else { return }
        let point = textView.convert(windowPoint, from: nil)
        guard dragDestination != nil || hypot(point.x - pressStart.x, point.y - pressStart.y) >= Self.dragThreshold else { return }
        if dragDestination == nil { startWatchingEscape() }
        let destinations = BlockHandleEditing.destinations(for: block, in: currentBlocks(for: state), textLength: state.source.length)
        guard let nearest = BlockHandleDrop.nearest(destinations, to: point.y, heightOf: { destination in
            destinationHeight(destination, source: state.source, in: textView)
        }) else { return }
        dragDestination = nearest.destination
        showInsertionLine(at: nearest.height, in: textView)
    }

    /// The press ended: a drag drops the block, a click opens its menu under the handle.
    func pressEnded() {
        defer { endDrag() }
        guard let block = shownBlock, let state = noteState() else { return }
        if let destination = dragDestination {
            if let edit = BlockHandleEditing.moving(block, to: destination, in: state.source) { perform(edit) }
            hide()
            return
        }
        showMenu(for: block)
    }

    func showMenu(for block: HandleBlock) {
        guard let handleView else { return }
        menu(for: block).popUp(positioning: nil, at: CGPoint(x: 0, y: handleView.bounds.height + 2), in: handleView)
    }

    /// Ends a drag without moving anything, as Escape does.
    func cancelDrag() {
        endDrag()
    }

    private func endDrag() {
        dragDestination = nil
        insertionLine?.isHidden = true
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private func startWatchingEscape() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode, let self, self.dragDestination != nil else { return event }
            self.cancelDrag()
            self.handleView?.cancelTracking()
            return nil
        }
    }

    private static let escapeKeyCode: UInt16 = 53

    private func showInsertionLine(at height: CGFloat, in textView: NSTextView) {
        let line = insertionLine ?? {
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            line.layer?.cornerRadius = 1
            textView.addSubview(line)
            insertionLine = line
            return line
        }()
        let origin = textView.textContainerOrigin
        let width = textView.textContainer?.size.width ?? textView.bounds.width
        line.frame = CGRect(x: origin.x, y: height - 1, width: min(width, textView.bounds.width - origin.x), height: 2)
        line.isHidden = false
    }

    // MARK: Menu

    /// The block's menu: Turn Into its other kinds, then Duplicate and Delete.
    func menu(for block: HandleBlock) -> NSMenu {
        let menu = NSMenu()
        let actions = BlockHandleAction.actions(for: block.kind)
        let turnInto = actions.filter(\.turnsIntoAnotherKind)
        if !turnInto.isEmpty {
            let submenu = NSMenu()
            for action in turnInto { submenu.addItem(item(for: action, block: block)) }
            let turnIntoItem = NSMenuItem(title: "Turn Into", action: nil, keyEquivalent: "")
            turnIntoItem.submenu = submenu
            menu.addItem(turnIntoItem)
            menu.addItem(.separator())
        }
        for action in actions where !action.turnsIntoAnotherKind { menu.addItem(item(for: action, block: block)) }
        return menu
    }

    private func item(for action: BlockHandleAction, block: HandleBlock) -> NSMenuItem {
        let item = BlockHandleMenuItem(title: action.title) { [weak self] in
            guard let self, let state = self.noteState(), let edit = action.edit(for: block, in: state.source) else { return }
            self.perform(edit)
        }
        item.image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: nil)
        return item
    }
}

/// A menu item that runs its closure.
private final class BlockHandleMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(choose), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("Block handle menu items are made in code.") }

    @objc private func choose() { run() }
}

/// The handle itself: six dots, a press that drags or opens the menu.
final class MacBlockHandleView: NSView {
    private weak var owner: MacBlockHandles?
    private var pressStart: CGPoint?
    private(set) var isTracking = false
    /// The dots' diameter and the distance between their centres, in points.
    private static let dotDiameter: CGFloat = 2.6
    private static let dotSpacing: CGFloat = 5

    init(owner: MacBlockHandles) {
        self.owner = owner
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        toolTip = "Drag to move, click for the block's menu"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("The block handle is made in code.") }

    /// Six dots in two columns, as Notion's handle has them.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.6).setFill()
        for column in 0..<2 {
            for row in 0..<3 {
                let center = CGPoint(x: bounds.midX + (CGFloat(column) - 0.5) * Self.dotSpacing, y: bounds.midY + CGFloat(row - 1) * Self.dotSpacing)
                NSBezierPath(ovalIn: CGRect(x: center.x - Self.dotDiameter / 2, y: center.y - Self.dotDiameter / 2,
                                            width: Self.dotDiameter, height: Self.dotDiameter)).fill()
            }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        pressStart = superview.map { view in view.convert(event.locationInWindow, from: nil) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTracking, let pressStart else { return }
        owner?.dragMoved(to: event.locationInWindow, pressStart: pressStart)
    }

    override func mouseUp(with event: NSEvent) {
        guard isTracking else { return }
        isTracking = false
        pressStart = nil
        owner?.pressEnded()
    }

    /// Escape ended the drag: the rest of the press does nothing.
    func cancelTracking() {
        isTracking = false
        pressStart = nil
    }

    override func accessibilityPerformPress() -> Bool {
        guard let owner, let block = owner.shownBlock else { return false }
        owner.showMenu(for: block)
        return true
    }
}
#endif
