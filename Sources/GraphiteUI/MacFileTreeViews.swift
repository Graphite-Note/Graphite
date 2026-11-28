/**
 * File: MacFileTreeViews.swift
 * ----------------------------
 * Layer: UI
 * Description: The Mac file tree's outline view and its rows, with the field a row shows while its name is typed.
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

/// The images of the notes' icons the Mac file tree draws, made once per icon, as rows are reused while the tree
/// scrolls. Bounded: past `maximumImageCount` icons it starts again empty.
@MainActor
final class NoteIconImages {
    private var imagesByIcon: [NoteIcon: NSImage] = [:]
    static let maximumImageCount = 512
    private static let iconPointSize: CGFloat = 12
    /// The window's icons, whose pictures a picture icon is drawn from; nil while icons are off.
    weak var catalog: NoteIconCatalog?

    /// The picture of a picture icon, read once by the window's `NoteIconPictures`; nil for another icon or a picture
    /// that cannot be read.
    func loadedPicture(of icon: NoteIcon) async -> NSImage? {
        guard case .picture(let source) = icon, let catalog, let location = catalog.pictureLocation(of: source),
              let picture = try? await catalog.pictures.picture(at: location) else { return nil } // Unreadable: no icon.
        let image = NSImage(cgImage: picture.image, size: NSSize(width: Self.iconPointSize + 2, height: Self.iconPointSize + 2))
        if imagesByIcon.count >= Self.maximumImageCount { imagesByIcon.removeAll() }
        imagesByIcon[icon] = image
        return image
    }

    func image(of icon: NoteIcon) -> NSImage? {
        if let image = imagesByIcon[icon] { return image }
        guard let image = Self.makeImage(of: icon) else { return nil }
        if imagesByIcon.count >= Self.maximumImageCount { imagesByIcon.removeAll() }
        imagesByIcon[icon] = image
        return image
    }

    /// An SF Symbol tinted as secondary text, or the emoji drawn into an image.
    private static func makeImage(of icon: NoteIcon) -> NSImage? {
        switch icon {
        case .symbol(let systemName):
            let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
            return symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)))
        case .emoji(let emoji):
            let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: iconPointSize)])
            return NSImage(size: text.size(), flipped: false) { rectangle in
                text.draw(in: rectangle)
                return true
            }
        case .picture:
            // Read off the main actor by `loadedPicture(of:)`.
            return nil
        }
    }
}

/// A row of the file tree: the name, the extension muted after it, and a mark for a file
/// that has other versions. Laid out by hand rather than with constraints, as NetNewsWire's
/// sidebar cells are: there is one per visible row, and they are laid out as the list scrolls.
final class FileTreeCellView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let conflictMarker = NSImageView()
    /// The note's icon before its name; made when a row first shows one.
    private var iconView: NSImageView?
    private var icon: NoteIcon?
    private var title = ""
    private var extensionSuffix: String?
    /// The part of the title and extension the file tree's filter matched, marked.
    private var highlightedRange: NSRange?
    private var font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    /// The field naming the row's item, shown over its title while the name is typed.
    private weak var nameField: NSTextField?
    /// A renamed file's extension, muted after the field, as the rename keeps it.
    private let nameFieldSuffix = NSTextField(labelWithString: "")

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
        nameFieldSuffix.textColor = .secondaryLabelColor
        nameFieldSuffix.isHidden = true
        addSubview(nameFieldSuffix)
    }

    /// Shows the field over the title, the kept extension after it.
    func showNameField(_ field: NSTextField, extensionSuffix: String?) {
        // A reused cell may still hold the field of an earlier name.
        if let earlierField = nameField, earlierField !== field, earlierField.superview === self { earlierField.removeFromSuperview() }
        if field.superview !== self { addSubview(field) }
        nameField = field
        titleField.isHidden = true
        nameFieldSuffix.stringValue = extensionSuffix ?? ""
        nameFieldSuffix.font = field.font
        nameFieldSuffix.isHidden = extensionSuffix == nil
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    /// The title again, once the name is no longer typed or the cell shows another row.
    func removeNameField() {
        guard let nameField else { return }
        if nameField.superview === self { nameField.removeFromSuperview() }
        self.nameField = nil
        titleField.isHidden = false
        nameFieldSuffix.isHidden = true
        needsLayout = true
    }

    /// Whether the row shows its name field, which a test reads.
    var showsNameField: Bool { nameField?.superview === self }

    /// The kept extension shown after the name field, with where it is in the cell, which a test reads; nil when none shows.
    var shownNameFieldSuffix: (text: String, frame: NSRect, color: NSColor?)? {
        guard showsNameField, !nameFieldSuffix.isHidden else { return nil }
        return (nameFieldSuffix.stringValue, nameFieldSuffix.frame, nameFieldSuffix.textColor)
    }

    /// The name fields in the cell, which a test counts: one while a name is typed, none after.
    var nameFieldCount: Int { subviews.filter { subview in subview is FileTreeNameField }.count }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameter icon: The note's icon and the window's images of icons, nil for a row without one.
    func configure(title: String, extensionSuffix: String?, highlightedRange: NSRange? = nil, icon: (NoteIcon, NoteIconImages)? = nil,
                   hasConflictVersions: Bool, font: NSFont) {
        if icon?.0 != self.icon { show(icon?.0, images: icon?.1 ?? NoteIconImages()) }
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

    private func show(_ newIcon: NoteIcon?, images: NoteIconImages) {
        icon = newIcon
        let image = newIcon.flatMap(images.image(of:))
        if image != nil, iconView == nil {
            let createdView = NSImageView()
            createdView.setAccessibilityElement(false)
            addSubview(createdView)
            iconView = createdView
        }
        iconView?.image = image
        iconView?.isHidden = image == nil
        needsLayout = true
        if image == nil, let newIcon, case .picture = newIcon {
            Task { [weak self] in
                guard await images.loadedPicture(of: newIcon) != nil, let self, self.icon == newIcon else { return }
                self.show(newIcon, images: images)
            }
        }
    }

    /// The icon's slot before the name, the width of the iPad tree's marker slot.
    private static let iconSlotWidth: CGFloat = 18

    override func layout() {
        super.layout()
        let markerWidth: CGFloat = conflictMarker.isHidden ? 0 : 18
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        var titleOrigin: CGFloat = 2
        if let iconView, !iconView.isHidden {
            let iconFrame = NSRect(x: 2, y: floor((bounds.height - 16) / 2), width: 16, height: 16)
            if iconView.frame != iconFrame { iconView.frame = iconFrame }
            titleOrigin += Self.iconSlotWidth
        }
        let titleFrame = NSRect(x: titleOrigin, y: floor((bounds.height - titleHeight) / 2),
                                width: max(0, bounds.width - titleOrigin - 2 - markerWidth), height: titleHeight)
        if titleField.frame != titleFrame { titleField.frame = titleFrame }
        if let nameField, nameField.superview === self {
            let suffixWidth = nameFieldSuffix.isHidden ? 0 : ceil(nameFieldSuffix.intrinsicContentSize.width) + 2
            let fieldHeight = min(bounds.height, ceil(nameField.intrinsicContentSize.height))
            let fieldWidth = max(0, bounds.width - suffixWidth - markerWidth)
            nameField.frame = NSRect(x: 0, y: floor((bounds.height - fieldHeight) / 2), width: fieldWidth, height: fieldHeight)
            if !nameFieldSuffix.isHidden {
                let suffixHeight = ceil(nameFieldSuffix.intrinsicContentSize.height)
                let suffixOrigin = NSPoint(x: nameField.frame.maxX + 2, y: floor((bounds.height - suffixHeight) / 2))
                nameFieldSuffix.frame = NSRect(origin: suffixOrigin, size: NSSize(width: suffixWidth - 2, height: suffixHeight))
            }
        }
        if !conflictMarker.isHidden {
            let markerFrame = NSRect(x: bounds.width - markerWidth, y: floor((bounds.height - 16) / 2), width: 16, height: 16)
            if conflictMarker.frame != markerFrame { conflictMarker.frame = markerFrame }
        }
    }
}
#endif
