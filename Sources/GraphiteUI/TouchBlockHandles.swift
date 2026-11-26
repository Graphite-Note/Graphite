/**
 * File: TouchBlockHandles.swift
 * -----------------------------
 * Layer: UI
 * Description: The block handle of Live Preview on the iPad and the iPhone: a finger's long press in the left margin
 *              lifts the block beside it, a drag moves it, and lifting without moving opens the block's menu.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if canImport(UIKit)
import UIKit
import GraphiteCore

/// The block handle of one iPad or iPhone note editor (Docs/Slash-menu-and-block-handles-todo.md,
/// section 3). Only a finger in the left margin starts it: Apple Pencil never does, and a press
/// on the text still selects text. Its views are made the first time a press lifts a block.
@MainActor
// UIKit calls the edit menu's delegate on the main thread; its protocol is not marked so.
final class TouchBlockHandles: NSObject, UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
    /// What the handles act on: the note's text and its revision, or nil outside Live Preview.
    var noteState: () -> (source: NSString, revision: Int)? = { nil }
    /// Makes an edit as one step Undo takes back; set by the coordinator.
    var perform: (MarkdownTextEdit) -> Void = { _ in }

    private weak var textView: UITextView?
    private(set) var pressRecognizer: UILongPressGestureRecognizer?
    private var handleView: TouchBlockHandleView?
    private var insertionLine: UIView?
    private var editMenu: UIEditMenuInteraction?
    private var blocks: (revision: Int, blocks: [HandleBlock])?
    /// The block lifted by the press, or whose menu is open.
    private(set) var liftedBlock: HandleBlock?
    /// Where the block would go if the finger lifted now; nil until it moves.
    private(set) var dragDestination: Int?
    private var pressStart: CGPoint?
    /// Where the finger touched down, which picks the block even if it slid a little before
    /// the press began.
    private var touchDownPoint: CGPoint?

    /// The fold chevron's touch target, whose place the handle takes while a block is lifted.
    static let handleSize = CGSize(width: 28, height: 28)
    /// How long a finger rests before the block lifts.
    private static let pressDuration: TimeInterval = 0.35
    /// How far the finger moves before the press becomes a drag.
    private static let dragThreshold: CGFloat = 8

    var isShown: Bool { handleView?.isHidden == false }

    func attach(to textView: UITextView) {
        guard pressRecognizer == nil else { return }
        self.textView = textView
        pressRecognizer = watchPresses(on: textView)
    }

    /// Lets a long press on `view`, the text view or a fold chevron in its margin (a button,
    /// which keeps its touches from the text view's recognizers), lift the block beside it.
    @discardableResult
    func watchPresses(on view: UIView) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        recognizer.minimumPressDuration = Self.pressDuration
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
        return recognizer
    }

    /// Hides the handle, as typing does.
    func hide() {
        handleView?.isHidden = true
        insertionLine?.isHidden = true
        liftedBlock = nil
        dragDestination = nil
    }

    // MARK: Gesture

    /// Only a touch in the left margin, beside a block, in Live Preview.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let textView, touch.type == .direct, noteState() != nil else { return false }
        let point = touch.location(in: textView)
        guard point.x < textView.textContainerInset.left + textView.textContainer.lineFragmentPadding else { return false }
        touchDownPoint = point
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let textView else { return false }
        return block(atHeightOf: touchDownPoint ?? gestureRecognizer.location(in: textView)) != nil
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        guard let textView else { return }
        let point = recognizer.location(in: textView)
        switch recognizer.state {
        case .began: lift(at: touchDownPoint ?? point, in: textView)
        case .changed: drag(to: point, in: textView)
        case .ended: drop(in: textView)
        case .cancelled, .failed: hide()
        case .possible, .recognized: break
        @unknown default: hide()
        }
    }

    private func lift(at point: CGPoint, in textView: UITextView) {
        guard let block = block(atHeightOf: point), let frame = handleFrame(for: block, in: textView) else { return }
        let handleView = handleView ?? {
            let view = TouchBlockHandleView()
            textView.addSubview(view)
            self.handleView = view
            return view
        }()
        handleView.frame = frame
        handleView.isHidden = false
        liftedBlock = block
        cancelTextViewPresses(in: textView)
        pressStart = point
        dragDestination = nil
    }

    /// The text view's own long presses (the loupe, the selection) also see a press in the
    /// margin; once a block is lifted they are cancelled, as turning a recognizer off and on
    /// cancels it, so the cursor stays where it was. Making them wait for this press instead
    /// held it back until the finger moved, as the text view makes it wait for them in turn.
    private func cancelTextViewPresses(in textView: UITextView) {
        for recognizer in textView.gestureRecognizers ?? [] where recognizer is UILongPressGestureRecognizer && !(recognizer.delegate is TouchBlockHandles) {
            guard recognizer.isEnabled else { continue }
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
    }

    private func drag(to point: CGPoint, in textView: UITextView) {
        guard let block = liftedBlock, let state = noteState(), let pressStart else { return }
        guard dragDestination != nil || hypot(point.x - pressStart.x, point.y - pressStart.y) >= Self.dragThreshold else { return }
        let destinations = BlockHandleEditing.destinations(for: block, in: currentBlocks(for: state), textLength: state.source.length)
        guard let nearest = BlockHandleDrop.nearest(destinations, to: point.y, heightOf: { destination in
            destinationHeight(destination, source: state.source, in: textView)
        }) else { return }
        dragDestination = nearest.destination
        showInsertionLine(at: nearest.height, in: textView)
        handleView?.center.y = point.y
    }

    private func drop(in textView: UITextView) {
        guard let block = liftedBlock, let state = noteState() else { return hide() }
        if let destination = dragDestination {
            if let edit = BlockHandleEditing.moving(block, to: destination, in: state.source) { perform(edit) }
            hide()
            return
        }
        insertionLine?.isHidden = true
        showMenu(for: block, in: textView)
    }

    // MARK: Menu

    private func showMenu(for block: HandleBlock, in textView: UITextView) {
        let interaction = editMenu ?? {
            let interaction = UIEditMenuInteraction(delegate: self)
            textView.addInteraction(interaction)
            editMenu = interaction
            return interaction
        }()
        let sourcePoint = handleView.map { view in CGPoint(x: view.frame.maxX, y: view.frame.midY) } ?? .zero
        interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: sourcePoint))
    }

    /// The block's menu: Turn Into its other kinds, then Duplicate and Delete, as on the Mac.
    func menu(for block: HandleBlock) -> UIMenu {
        let actions = BlockHandleAction.actions(for: block.kind)
        let turnInto = actions.filter(\.turnsIntoAnotherKind).map { action in element(for: action, block: block) }
        var children: [UIMenuElement] = []
        if !turnInto.isEmpty { children.append(UIMenu(title: "Turn Into", image: UIImage(systemName: "arrow.triangle.2.circlepath"), children: turnInto)) }
        children += actions.filter { action in !action.turnsIntoAnotherKind }.map { action in element(for: action, block: block) }
        return UIMenu(children: children)
    }

    private func element(for action: BlockHandleAction, block: HandleBlock) -> UIAction {
        UIAction(title: action.title, image: UIImage(systemName: action.systemImage), attributes: action == .delete ? .destructive : []) { [weak self] _ in
            guard let self, let state = self.noteState(), let edit = action.edit(for: block, in: state.source) else { return }
            self.perform(edit)
            self.hide()
        }
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        liftedBlock.map { block in menu(for: block) }
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration,
                             animator: any UIEditMenuInteractionAnimating) {
        animator.addCompletion { [weak self] in self?.hide() }
    }

    // MARK: Geometry

    private func currentBlocks(for state: (source: NSString, revision: Int)) -> [HandleBlock] {
        if let blocks, blocks.revision == state.revision { return blocks.blocks }
        let found = BlockHandleEditing.blocks(in: state.source as String)
        blocks = (state.revision, found)
        return found
    }

    private func block(atHeightOf point: CGPoint) -> HandleBlock? {
        guard let textView, let state = noteState(), let location = characterOffset(atHeightOf: point, in: textView) else { return nil }
        return BlockHandleEditing.block(at: location, in: currentBlocks(for: state))
    }

    private func characterOffset(atHeightOf point: CGPoint, in textView: UITextView) -> Int? {
        guard let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager else { return nil }
        let containerPoint = CGPoint(x: 1, y: point.y - textView.textContainerInset.top)
        guard let fragment = textLayoutManager.textLayoutFragment(for: containerPoint) else { return nil }
        let fragmentStart = contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
        let localY = containerPoint.y - fragment.layoutFragmentFrame.minY
        let line = fragment.textLineFragments.first { line in line.typographicBounds.minY <= localY && localY < line.typographicBounds.maxY }
        return fragmentStart + (line?.characterRange.location ?? 0)
    }

    private func lineRect(at location: Int, in textView: UITextView) -> CGRect? {
        guard let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager,
              let textLocation = contentManager.location(contentManager.documentRange.location, offsetBy: location) else { return nil }
        textLayoutManager.ensureLayout(for: NSTextRange(location: textLocation))
        guard let fragment = textLayoutManager.textLayoutFragment(for: textLocation), let firstLine = fragment.textLineFragments.first else { return nil }
        let bounds = firstLine.typographicBounds
        return CGRect(x: textView.textContainerInset.left + fragment.layoutFragmentFrame.minX + textView.textContainer.lineFragmentPadding,
                      y: textView.textContainerInset.top + fragment.layoutFragmentFrame.minY + bounds.minY, width: bounds.width, height: bounds.height)
    }

    /// In the left margin, at the height of the block's first line, where a fold chevron is.
    private func handleFrame(for block: HandleBlock, in textView: UITextView) -> CGRect? {
        guard let firstLine = lineRect(at: block.range.location, in: textView) else { return nil }
        let size = Self.handleSize
        return CGRect(x: max(2, firstLine.minX - size.width - 4), y: firstLine.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func destinationHeight(_ destination: Int, source: NSString, in textView: UITextView) -> CGFloat? {
        if destination < source.length { return lineRect(at: destination, in: textView)?.minY }
        guard source.length > 0 else { return nil }
        return lineRect(at: source.lineRange(for: NSRange(location: source.length - 1, length: 0)).location, in: textView)?.maxY
    }

    private func showInsertionLine(at height: CGFloat, in textView: UITextView) {
        let line = insertionLine ?? {
            let line = UIView()
            line.backgroundColor = textView.tintColor
            line.layer.cornerRadius = 1
            line.isUserInteractionEnabled = false
            textView.addSubview(line)
            insertionLine = line
            return line
        }()
        let left = textView.textContainerInset.left
        line.frame = CGRect(x: left, y: height - 1, width: textView.bounds.width - left - textView.textContainerInset.right, height: 2)
        line.isHidden = false
    }
}

extension NativeMarkdownEditor.Coordinator {
    /// The handle a finger's long press in the margin lifts, in Live Preview only; its moves
    /// and menu items are edits Undo takes back.
    func connectBlockHandles(of textView: UITextView) {
        blockHandles.noteState = { [weak self, weak textView] in
            guard let self, let textView, self.configuration.mode == .livePreview, self.hasSettledText else { return nil }
            return (self.currentSource(of: textView), self.textRevision)
        }
        blockHandles.perform = { [weak self, weak textView] edit in
            guard let self, let textView else { return }
            self.perform(edit, in: textView)
        }
        blockHandles.attach(to: textView)
    }
}

/// Six dots in two columns, drawn where a lifted block's handle is.
final class TouchBlockHandleView: UIView {
    private static let dotDiameter: CGFloat = 3.4
    private static let dotSpacing: CGFloat = 6.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        // The page's colour behind the dots covers a heading's fold chevron while its block is lifted.
        backgroundColor = .systemBackground
        layer.cornerRadius = 6
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "Block handle"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("The block handle is made in code.") }

    override func draw(_ rect: CGRect) {
        UIColor.secondaryLabel.setFill()
        for column in 0..<2 {
            for row in 0..<3 {
                let center = CGPoint(x: bounds.midX + (CGFloat(column) - 0.5) * Self.dotSpacing, y: bounds.midY + CGFloat(row - 1) * Self.dotSpacing)
                UIBezierPath(ovalIn: CGRect(x: center.x - Self.dotDiameter / 2, y: center.y - Self.dotDiameter / 2,
                                            width: Self.dotDiameter, height: Self.dotDiameter)).fill()
            }
        }
    }
}
#endif
