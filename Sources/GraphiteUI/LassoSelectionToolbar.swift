/**
 * File: LassoSelectionToolbar.swift
 * ---------------------------------
 * Layer: UI
 * Description: The floating toolbar beside the lasso's selection on the iPad and the iPhone (`FloatingSelectionToolbar`):
 *              Take Screenshot, colour swatches one tap away, Cut, Copy and Duplicate, Bring Items to Front and Send
 *              Items to Back on a PDF page, and Delete, with the rest behind "…". It replaces the system's edit menu,
 *              to which iOS adds Ask Siri (Docs/Lasso-todo.md section 4).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */

#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore

/// The lasso's floating toolbar, beside the selection's frame. Its host is not scaled: the PDF
/// view holding a page's canvas, or the view holding a drawing's canvas, so the bar keeps its
/// size however far the page or the drawing is zoomed. Nothing is made until a selection first
/// shows it.
@MainActor
final class LassoSelectionToolbar {
    private unowned let canvas: UIView
    private let frameView: () -> SelectionFrameView?
    private let commands: (_ availableWidth: CGFloat) -> LassoToolbarCommands
    private(set) var toolbar: FloatingSelectionToolbar?
    /// Whether the selection's bar is to be shown: it stays wanted while the selection is
    /// scrolled out of view or dragged, and shows again once the selection is back or let go.
    private(set) var isWanted = false
    private var scrollObservations: [NSKeyValueObservation] = []
    private weak var observedHost: UIView?

    init(canvas: UIView, frameView: @escaping () -> SelectionFrameView?, commands: @escaping (_ availableWidth: CGFloat) -> LassoToolbarCommands) {
        self.canvas = canvas
        self.frameView = frameView
        self.commands = commands
    }

    var isShown: Bool { toolbar?.isShown ?? false }

    /// The view the bar stands in: the PDF view around a page's canvas, or the canvas's own superview.
    static func host(of canvas: UIView) -> UIView? {
        var ancestor = canvas.superview
        while let view = ancestor {
            if view is PDFView { return view }
            ancestor = view.superview
        }
        return canvas.superview
    }

    /// Shows the bar beside the selection with the commands it has now.
    func present() {
        isWanted = true
        guard let host = Self.host(of: canvas), let target = targetRect(in: host) else { return toolbar?.hide() ?? () }
        let commands = commands(host.bounds.inset(by: host.safeAreaInsets).width - 2 * FloatingSelectionToolbar.margin)
        guard !commands.items.isEmpty else { return toolbar?.hide() ?? () }
        let bar = toolbar ?? FloatingSelectionToolbar()
        toolbar = bar
        bar.show(commands.items, moreMenuElements: commands.moreMenuElements, pointingAt: target, in: host)
        observeScrolling(between: canvas, and: host)
    }

    /// Shows the bar again with the commands of a selection that changed, if it is shown.
    func refresh() {
        if isShown { present() }
    }

    /// A tap on the selection: shows its bar, or hides it if it was showing.
    func toggle() {
        if isShown { dismiss() } else { present() }
    }

    /// Hides the bar while the selection is dragged; `present` shows it where the drag ends.
    func suspend() {
        toolbar?.hide()
    }

    func dismiss() {
        isWanted = false
        toolbar?.hide()
    }

    /// Keeps the bar beside the selection as the page or the drawing scrolls or zooms. A
    /// selection scrolled out of view takes its bar away, and back once it is in view again.
    func follow() {
        guard isWanted, let toolbar, let host = toolbar.superview else { return }
        guard let target = targetRect(in: host) else { return toolbar.hide() }
        if toolbar.isShown { toolbar.follow(target) } else if !isFrameDragged { present() }
    }

    private var isFrameDragged: Bool {
        frameView()?.dragRecognizers.contains { recognizer in recognizer.state == .began || recognizer.state == .changed } ?? false
    }

    func stop() {
        isWanted = false
        scrollObservations = []
        observedHost = nil
        toolbar?.removeFromSuperview()
        toolbar = nil
    }

    /// The selection's box with its handles in the host; nil when there is none or it is out of view.
    private func targetRect(in host: UIView) -> CGRect? {
        guard let frameView = frameView(), frameView.window != nil, frameView.superview != nil else { return nil }
        let rect = canvas.convert(frameView.boxWithHandlesInSuperview, to: host)
        return rect.intersects(host.bounds) ? rect : nil
    }

    /// A PDF scrolls its pages, not the canvas on one of them, so the canvas is not told: the
    /// bar watches the scroll views between the canvas and its host. A drawing's canvas is its
    /// own scroll view, which tells the lasso (`HistoryCanvasView.layoutSubviews`).
    private func observeScrolling(between canvas: UIView, and host: UIView) {
        guard observedHost !== host else { return }
        observedHost = host
        scrollObservations = []
        var ancestor = canvas.superview
        while let view = ancestor, view !== host.superview {
            if let scrollView = view as? UIScrollView {
                scrollObservations.append(scrollView.observe(\.contentOffset, options: []) { [weak self] _, _ in
                    // Reported on the main thread that scrolls; the bar moves on the main actor.
                    Task { @MainActor [weak self] in self?.follow() }
                })
            }
            ancestor = view.superview
        }
    }
}

/// What the lasso's bar shows: the items on the bar and in its "…" menu, and the colours the
/// bar had no room for, as a palette in that menu.
struct LassoToolbarCommands {
    var items: [FloatingToolbarItem]
    var moreMenuElements: [UIMenuElement]
}

/// How the lasso's bar is laid out: how many swatches it shows and which commands it puts in
/// "…" because it is too narrow.
struct LassoToolbarLayout {
    enum Command { case duplicate, cut, arrange }
    var swatchCount: Int
    var inMoreMenu: Set<Command> = []

    /// Makes the bar narrower by one step: a swatch less, then Duplicate, Cut and the arranging
    /// into "…"; false when there is nothing left to take off the bar.
    mutating func narrow() -> Bool {
        if swatchCount > 0 {
            swatchCount -= 1
            return true
        }
        guard let next = [Command.duplicate, .cut, .arrange].first(where: { command in !inMoreMenu.contains(command) }) else { return false }
        inMoreMenu.insert(next)
        return true
    }
}

extension InkSelectionController {
    /// The most swatches the bar shows; the other colours are in its "…" menu.
    static let maximumSwatchesOnToolbar = 6

    /// The bar's commands for the selection, as many as fit in `availableWidth` points: Take
    /// Screenshot; the colours of Settings › Colors after black, for ink; Cut, Copy and
    /// Duplicate (Copy alone with pictures, which Graphite pastes as ink would lose); Bring Items
    /// to Front and Send Items to Back on a PDF page, dimmed where they would move nothing; Delete.
    /// In "…": the colours left out, Bring Items Forward and Send Items Backward, Straighten (for a
    /// line of writing that runs uphill or downhill) and Smooth. Where the bar is still too wide
    /// with no swatch, Duplicate, Cut and the arranging go into "…" in that order.
    func selectionToolbarCommands(palette: [PaletteColor] = GraphitePreferences.storedColorPalette(),
                                  availableWidth: CGFloat = .greatestFiniteMagnitude) -> LassoToolbarCommands {
        let colors = selectedStrokeIndices.isEmpty ? [] : Self.swatchColors(palette: palette)
        var layout = LassoToolbarLayout(swatchCount: min(colors.count, Self.maximumSwatchesOnToolbar))
        while true {
            let commands = LassoToolbarCommands(items: toolbarItems(colors: colors, layout: layout),
                                                moreMenuElements: Self.colorMenu(of: Array(colors.dropFirst(layout.swatchCount))) { [weak self] color in
                                                    self?.recolorSelection(color)
                                                })
            if Self.width(of: commands) <= availableWidth || !layout.narrow() { return commands }
        }
    }

    /// The bar's items in order, those in "…" included, for one way of laying the bar out.
    private func toolbarItems(colors: [(title: String, color: UIColor)], layout: LassoToolbarLayout) -> [FloatingToolbarItem] {
        let hasPictures = !selectedPictureIdentifiers.isEmpty
        var items = [FloatingToolbarItem(title: "Take Screenshot", systemImageName: "camera.viewfinder") { [weak self] in self?.takeScreenshot() }]
        items += colors.prefix(layout.swatchCount).map { color in
            FloatingToolbarItem(title: color.title, systemImageName: "circle.fill", symbolColor: color.color, group: 1) { [weak self] in
                self?.recolorSelection(color.color)
            }
        }
        if !hasPictures {
            items.append(FloatingToolbarItem(title: "Cut", systemImageName: "scissors",
                                             isInMoreMenu: layout.inMoreMenu.contains(.cut), group: 2) { [weak self] in
                self?.cutSelection()
            })
        }
        items.append(FloatingToolbarItem(title: "Copy", systemImageName: "doc.on.doc", group: 2) { [weak self] in self?.copySelection() })
        if !hasPictures {
            items.append(FloatingToolbarItem(title: "Duplicate", systemImageName: "plus.square.on.square",
                                             isInMoreMenu: layout.inMoreMenu.contains(.duplicate), group: 2) { [weak self] in
                self?.duplicateSelection()
            })
        }
        items += arrangementItems(onBar: !layout.inMoreMenu.contains(.arrange))
        items.append(FloatingToolbarItem(title: "Delete", systemImageName: "trash", isDestructive: true, group: 4) { [weak self] in self?.deleteSelection() })
        return items + tidyingItems()
    }

    /// Bring Items to Front and Send Items to Back (on the bar unless it is too narrow), Bring
    /// Items Forward and Send Items Backward (in "…"), for pictures and text boxes on a PDF page.
    /// A PDF page arranges them; what would move none of them is dimmed, so the commands stay where
    /// they are. A drawing does not arrange.
    private func arrangementItems(onBar: Bool) -> [FloatingToolbarItem] {
        guard !selectedPictureIdentifiers.isEmpty, content is PDFPageCanvasView else { return [] }
        let identifiers = selectedPictureIdentifiers
        let possible = content?.possibleLassoPictureArrangements(identifiers) ?? []
        let textBoxCount = identifiers.filter { identifier in identifier.hasPrefix(LassoSelectionKinds.textBoxIdentifierPrefix) }.count
        let arranged = PDFArrangement.Objects.naming(pictureCount: identifiers.count - textBoxCount, otherObjectCount: textBoxCount)
        let places: [(PDFArrangement, Bool)] = [(.bringToFront, !onBar), (.sendToBack, !onBar), (.bringForward, true), (.sendBackward, true)]
        return places.map { arrangement, inMoreMenu in
            FloatingToolbarItem(title: arrangement.title(of: arranged), systemImageName: arrangement.systemImageName,
                                isEnabled: possible.contains(arrangement), isInMoreMenu: inMoreMenu, group: 3) { [weak self] in
                guard let self else { return }
                content?.arrangeLassoPictures(identifiers, arrangement)
                selectionToolbar.refresh()
            }
        }
    }

    /// Straighten, for a line of writing that runs uphill or downhill, and Smooth, in "…".
    private func tidyingItems() -> [FloatingToolbarItem] {
        guard !selectedStrokeIndices.isEmpty else { return [] }
        var items: [FloatingToolbarItem] = []
        if selectionSlant != nil {
            items.append(FloatingToolbarItem(title: "Straighten", systemImageName: "level", isInMoreMenu: true) { [weak self] in self?.straightenSelection() })
        }
        items.append(FloatingToolbarItem(title: "Smooth", systemImageName: "scribble.variable", isInMoreMenu: true) { [weak self] in self?.smoothSelection() })
        return items
    }

    /// The colours the bar has no room for, as a palette in "…".
    private static func colorMenu(of colors: [(title: String, color: UIColor)], recolor: @escaping (UIColor) -> Void) -> [UIMenuElement] {
        guard !colors.isEmpty else { return [] }
        let swatches = colors.map { color in
            UIAction(title: color.title, image: UIImage(systemName: "circle.fill")?.withTintColor(color.color, renderingMode: .alwaysOriginal)) { _ in
                recolor(color.color)
            }
        }
        return [UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"), options: [.displayInline, .displayAsPalette], children: swatches)]
    }

    /// Black, then the colours of Settings › Colors, each once.
    private static func swatchColors(palette: [PaletteColor]) -> [(title: String, color: UIColor)] {
        var seen: Set<String> = []
        return ([PaletteColor(name: "black", hex: PencilInk.pen.defaultColorHex)] + palette).compactMap { favorite in
            guard seen.insert(favorite.hex.lowercased()).inserted, let color = UIColor(graphiteHex: favorite.hex) else { return nil }
            return (favorite.name.prefix(1).uppercased() + favorite.name.dropFirst(), color)
        }
    }

    /// The width of the bar for these commands, as `FloatingSelectionToolbar` lays it out.
    static func width(of commands: LassoToolbarCommands) -> CGFloat {
        let onBar = commands.items.filter { item in !item.isInMoreMenu }
        let groupChanges = zip(onBar, onBar.dropFirst()).filter { pair in pair.0.group != pair.1.group }.count
        let hasMore = onBar.count < commands.items.count || !commands.moreMenuElements.isEmpty
        let buttonCount = onBar.count + (hasMore ? 1 : 0)
        let dividerCount = groupChanges + (hasMore && !onBar.isEmpty ? 1 : 0)
        return CGFloat(buttonCount) * 44 + CGFloat(dividerCount) * 9 + 12
    }

    /// The bar's commands for VoiceOver, on the frame itself: all but the colours, which the
    /// rotor would list one by one.
    func toolbarAccessibilityActions() -> [UIAccessibilityCustomAction] {
        selectionToolbarCommands().items.filter { item in item.isEnabled && item.symbolColor == nil }.map { item in
            UIAccessibilityCustomAction(name: item.title) { _ in
                item.action()
                return true
            }
        }
    }
}
#endif
