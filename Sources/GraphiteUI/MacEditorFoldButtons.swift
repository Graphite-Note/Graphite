/**
 * File: MacEditorFoldButtons.swift
 * --------------------------------
 * Layer: UI
 * Description: The chevrons beside what folds in the Mac's note editor, and the "…" after what is folded, as on the iPad.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

#if os(macOS)
import AppKit
import GraphiteCore

@MainActor
final class MacEditorFoldButtons {
    private var buttons: [String: (chevron: NSButton, ellipsis: NSButton)] = [:]
    /// What each chevron shows now, so a scroll step that changes neither leaves the button alone.
    private var shownStates: [String: ShownState] = [:]
    private static let foldedChevron = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    private static let unfoldedChevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)

    /// The fold and the header line a chevron was last set for.
    private struct ShownState: Equatable {
        let isFolded: Bool
        let header: String
    }
    /// Folds or unfolds the section with this key; set by the coordinator.
    var toggle: (String) -> Void = { _ in }
    private static let chevronSize: CGFloat = 18

    /// How many sections show a button now, for tests.
    var shownCount: Int { buttons.count }

    /// Places the buttons of the lines TextKit has laid out on screen, and takes away the others.
    func place(regionsByStart: [Int: FoldableRegion], foldedKeys: Set<String>, source: NSString, in textView: NSTextView) {
        guard !regionsByStart.isEmpty, let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager,
              let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange else {
            removeAll()
            return
        }
        let origin = textView.textContainerOrigin
        let documentStart = contentManager.documentRange.location
        var keysInUse = Set<String>()
        textLayoutManager.enumerateTextLayoutFragments(from: viewportRange.location, options: []) { fragment in
            let fragmentStart = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
            if let region = regionsByStart[fragmentStart], NSMaxRange(region.headerRange) <= source.length {
                keysInUse.insert(region.key)
                let pair = buttons[region.key] ?? makeButtons(for: region.key, in: textView)
                buttons[region.key] = pair
                position(pair, of: region, isFolded: foldedKeys.contains(region.key), on: fragment, origin: origin, source: source)
            }
            return fragment.rangeInElement.location.compare(viewportRange.endLocation) == .orderedAscending
        }
        for (key, pair) in buttons where !keysInUse.contains(key) {
            pair.chevron.removeFromSuperview()
            pair.ellipsis.removeFromSuperview()
            buttons[key] = nil
            shownStates[key] = nil
        }
    }

    private func position(_ pair: (chevron: NSButton, ellipsis: NSButton), of region: FoldableRegion, isFolded: Bool, on fragment: NSTextLayoutFragment,
                          origin: CGPoint, source: NSString) {
        guard let firstLine = fragment.textLineFragments.first, let lastLine = fragment.textLineFragments.last else { return }
        let fragmentOrigin = CGPoint(x: origin.x + fragment.layoutFragmentFrame.minX, y: origin.y + fragment.layoutFragmentFrame.minY)
        let header = source.substring(with: region.headerRange)
        let indentLength = (header.prefix { character in character == " " || character == "\t" } as Substring).utf16.count
        let textStartX = firstLine.locationForCharacter(at: min(indentLength, max(0, firstLine.characterRange.length - 1))).x
        let firstLineBounds = firstLine.typographicBounds
        pair.chevron.frame = CGRect(x: max(2, fragmentOrigin.x + textStartX - Self.chevronSize - 4),
                                    y: fragmentOrigin.y + firstLineBounds.minY + (firstLineBounds.height - Self.chevronSize) / 2,
                                    width: Self.chevronSize, height: Self.chevronSize)
        // Set when the fold or the header changes, not on every step of a scroll: a new image redraws the button.
        let shownState = ShownState(isFolded: isFolded, header: header)
        if shownStates[region.key] != shownState {
            shownStates[region.key] = shownState
            pair.chevron.image = isFolded ? Self.foldedChevron : Self.unfoldedChevron
            pair.chevron.alphaValue = isFolded ? 1 : 0.4
            let headerText = header.trimmingCharacters(in: .whitespaces).drop { character in character == "#" }.trimmingCharacters(in: .whitespaces)
            pair.chevron.setAccessibilityLabel(isFolded ? "Unfold \(headerText)" : "Fold \(headerText)")
            pair.ellipsis.isHidden = !isFolded
        }
        guard isFolded else { return }
        let lastLineBounds = lastLine.typographicBounds
        pair.ellipsis.frame = CGRect(x: fragmentOrigin.x + lastLineBounds.maxX + 6,
                                     y: fragmentOrigin.y + lastLineBounds.minY + (lastLineBounds.height - Self.chevronSize) / 2,
                                     width: 28, height: Self.chevronSize)
    }

    func removeAll() {
        for pair in buttons.values {
            pair.chevron.removeFromSuperview()
            pair.ellipsis.removeFromSuperview()
        }
        buttons.removeAll()
        shownStates.removeAll()
    }

    private func makeButtons(for key: String, in textView: NSTextView) -> (chevron: NSButton, ellipsis: NSButton) {
        let chevron = KeyedFoldButton(foldKey: key, owner: self)
        chevron.isBordered = false
        chevron.imagePosition = .imageOnly
        chevron.contentTintColor = .secondaryLabelColor
        let ellipsis = KeyedFoldButton(foldKey: key, owner: self)
        ellipsis.title = "…"
        ellipsis.isBordered = false
        ellipsis.setAccessibilityLabel("Unfold")
        textView.addSubview(chevron)
        textView.addSubview(ellipsis)
        return (chevron, ellipsis)
    }

    fileprivate func buttonWasPressed(_ key: String) {
        toggle(key)
    }
}

/// A fold button that knows its section.
private final class KeyedFoldButton: NSButton {
    private let foldKey: String
    private weak var owner: MacEditorFoldButtons?

    init(foldKey: String, owner: MacEditorFoldButtons) {
        self.foldKey = foldKey
        self.owner = owner
        super.init(frame: .zero)
        target = self
        action = #selector(wasPressed)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func wasPressed() {
        owner?.buttonWasPressed(foldKey)
    }
}
#endif
