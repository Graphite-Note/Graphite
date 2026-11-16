/**
 * File: MacFileTreeViews.swift
 * ----------------------------
 * Layer: UI
 * Description: The Mac file tree's outline view and its rows.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 11/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import GraphiteCore

/// The file tree's outline view, which asks its controller for the clicked row's menu.
final class FileTreeOutlineView: NSOutlineView {
    weak var controller: FileTreeController?
    /// Times every row was reloaded, which a test counts.
    private(set) var fullReloadCount = 0

    override func reloadData() {
        fullReloadCount += 1
        super.reloadData()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // The outline view records the clicked row, and draws its outline, while finding its own menu.
        _ = super.menu(for: event)
        guard clickedRow >= 0 else { return nil }
        return controller?.menu(forRow: clickedRow)
    }
}

/// A row of the file tree: the name, the extension muted after it, and a mark for a file
/// that has other versions. Laid out by hand rather than with constraints, as NetNewsWire's
/// sidebar cells are: there is one per visible row, and they are laid out as the list scrolls.
final class FileTreeCellView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let conflictMarker = NSImageView()
    private var title = ""
    private var extensionSuffix: String?
    /// The part of the title and extension the file tree's filter matched, marked.
    private var highlightedRange: NSRange?
    private var font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.allowsDefaultTighteningForTruncation = false
        // Not the cell's `textField`: the table gives that field a single color, which drew
        // the muted extension in the name's color. The selected style is set here instead.
        titleField.allowsEditingTextAttributes = true
        addSubview(titleField)
        conflictMarker.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: ConflictVersionsText.markerDescription)
        conflictMarker.contentTintColor = .systemOrange
        conflictMarker.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        conflictMarker.isHidden = true
        addSubview(conflictMarker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, extensionSuffix: String?, highlightedRange: NSRange? = nil, hasConflictVersions: Bool, font: NSFont) {
        let changed = title != self.title || extensionSuffix != self.extensionSuffix || highlightedRange != self.highlightedRange || font != self.font
        self.title = title
        self.extensionSuffix = extensionSuffix
        self.highlightedRange = highlightedRange
        self.font = font
        if changed { updateTitle() }
        if conflictMarker.isHidden == hasConflictVersions {
            conflictMarker.isHidden = !hasConflictVersions
            needsLayout = true
        }
    }

    /// The title as drawn, name and extension.
    var drawnTitle: NSAttributedString { titleField.attributedStringValue }

    /// A selected row is drawn in the accent color, where the muted extension turns white too.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { if backgroundStyle != oldValue { updateTitle() } }
    }

    private func updateTitle() {
        let isEmphasized = backgroundStyle == .emphasized
        let attributedTitle = NSMutableAttributedString(string: title, attributes: [
            .font: font, .foregroundColor: isEmphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor,
        ])
        if let extensionSuffix {
            attributedTitle.append(NSAttributedString(string: extensionSuffix, attributes: [
                .font: font, .foregroundColor: isEmphasized ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75) : NSColor.secondaryLabelColor,
            ]))
        }
        if let highlightedRange, NSMaxRange(highlightedRange) <= attributedTitle.length {
            let highlight = NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.45 : 0.28)
            attributedTitle.addAttribute(.backgroundColor, value: highlight, range: highlightedRange)
        }
        titleField.attributedStringValue = attributedTitle
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let markerWidth: CGFloat = conflictMarker.isHidden ? 0 : 18
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        let titleFrame = NSRect(x: 2, y: floor((bounds.height - titleHeight) / 2), width: max(0, bounds.width - 4 - markerWidth), height: titleHeight)
        if titleField.frame != titleFrame { titleField.frame = titleFrame }
        if !conflictMarker.isHidden {
            let markerFrame = NSRect(x: bounds.width - markerWidth, y: floor((bounds.height - 16) / 2), width: 16, height: 16)
            if conflictMarker.frame != markerFrame { conflictMarker.frame = markerFrame }
        }
    }
}
#endif
