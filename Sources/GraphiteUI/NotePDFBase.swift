/**
 * File: NotePDFBase.swift
 * -----------------------
 * Layer: UI
 * Description: A base in a printed note, drawn as the reading view shows it: its view run over the vault's index
 *              before drawing, its card covers decoded beforehand, and its rows divided into the parts a page may
 *              end between (a row of cards, a list item, a table row).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import SwiftUI
import GraphiteCore
import GraphiteApple

/// A base's view as it prints: its results, its covers, and where its parts start.
struct PrintedBase: Sendable {
    let result: BaseQueryResult
    /// Card covers decoded before drawing, as a drawing runs no task to load them.
    let covers: [BaseImageReference: ReadingThumbnail]
    /// The first displayed row of each part, then the row count: part `i` is the rows from
    /// `partStarts[i]` up to `partStarts[i + 1]`.
    let partStarts: [Int]
    let vaultRoot: URL

    var unitCount: Int { max(1, partStarts.count - 1) }

    /// The displayed rows of a run of parts.
    func rows(forUnits units: Range<Int>) -> Range<Int> {
        guard partStarts.count > 1 else { return 0..<0 }
        let lastPart = partStarts.count - 1
        return partStarts[min(units.lowerBound, lastPart)]..<partStarts[min(units.upperBound, lastPart)]
    }
}

/// A base inside a callout or an embedded note, by what it runs. Such a base is drawn by
/// the reading view's own block views (`BaseCodeBlockView`, `BaseFileEmbedView`), which on
/// paper look it up by this key.
struct PrintedBaseKey: Hashable, Sendable {
    let source: BaseSource
    let viewName: String?
}

extension EnvironmentValues {
    /// The bases inside a printed block's callouts and embedded notes, run before drawing;
    /// nil on screen, where each base runs itself. One missing from it prints as its name.
    @Entry var printedNestedBases: [PrintedBaseKey: PrintedBase]? = nil
}

enum NotePDFBases {
    /// The views a page can show; a map or kanban prints as the base's name.
    private static let printedViewTypes: Set<BaseViewType> = [.cards, .list, .table]
    /// Cover pixels per point of a card's width: sharp on paper without holding full-size pictures.
    private static let coverPixelsPerPoint: CGFloat = 2

    /// The base run over the vault as the reading view runs it, with `note` as `this`; nil
    /// when the vault cannot run it here, it fails, or its view cannot be printed.
    @MainActor
    static func printed(_ source: BaseSource, viewName: String?, note: VaultPath, vault: ReadingVault, layoutWidth: CGFloat) async -> PrintedBase? {
        guard let store = vault.store else { return nil }
        let model = BaseDocumentModel(source: source, contextPath: note, store: store, index: vault.index, preferredViewName: viewName)
        await model.reload()
        guard let result = model.result, printedViewTypes.contains(result.view.type) else { return nil }
        let cardWidth = result.view.cards.cardSize.map { size in CGFloat(size) } ?? BaseCardsView.defaultCardWidth
        let covers = await decodedPictures(of: result, root: store.root, coverPixelDimension: Int(cardWidth * coverPixelsPerPoint))
        let cardMetrics = BaseCardGridMetrics(availableWidth: layoutWidth, preferredCardWidth: cardWidth, isPrinted: true)
        let rowsPerPart = result.view.type == .cards ? cardMetrics.columnCount : 1
        return PrintedBase(result: result, covers: covers, partStarts: partStarts(of: result, rowsPerPart: rowsPerPart), vaultRoot: store.root)
    }

    /// The bases inside the callouts and embedded notes of `block`, at any depth, each run
    /// with the note it is written in as `this`. A base the paper cannot show is left out
    /// and prints as its name. The same base in two embedded notes is run once, with the
    /// first note as `this`, as the lookup has only what the block says.
    @MainActor
    static func nested(in block: RenderedBlock, note: VaultPath, vault: ReadingVault, layoutWidth: CGFloat) async -> [PrintedBaseKey: PrintedBase] {
        var bases: [PrintedBaseKey: PrintedBase] = [:]
        var tried: Set<PrintedBaseKey> = []
        for (key, baseNote) in nestedBaseKeys(in: block, note: note) where tried.insert(key).inserted {
            guard !Task.isCancelled else { return bases }
            bases[key] = await printed(key.source, viewName: key.viewName, note: baseNote, vault: vault, layoutWidth: layoutWidth)
        }
        return bases
    }

    /// The bases inside a callout's or an embedded note's blocks, with the note each is in.
    static func nestedBaseKeys(in block: RenderedBlock, note: VaultPath) -> [(key: PrintedBaseKey, note: VaultPath)] {
        switch block {
        case .callout(_, _, _, _, let body): body.flatMap { inner in baseKeys(in: inner, note: note) }
        case .transclusion(_, let path, _, let body): body.flatMap { inner in baseKeys(in: inner, note: path) }
        case .properties, .markdown, .displayMath, .heading, .video, .audio, .pdf, .base, .baseFile, .missingEmbed, .missingSection, .image,
             .footnotes, .pluginCodeBlock, .pluginSection, .diagram:
            []
        }
    }

    private static func baseKeys(in block: RenderedBlock, note: VaultPath) -> [(key: PrintedBaseKey, note: VaultPath)] {
        switch block {
        case .base(_, let yaml): [(PrintedBaseKey(source: .inline(yaml), viewName: nil), note)]
        case .baseFile(_, let path, let viewName): [(PrintedBaseKey(source: .file(path), viewName: viewName), note)]
        case .callout, .transclusion: nestedBaseKeys(in: block, note: note)
        case .properties, .markdown, .displayMath, .heading, .video, .audio, .pdf, .missingEmbed, .missingSection, .image, .footnotes,
             .pluginCodeBlock, .pluginSection, .diagram:
            []
        }
    }

    /// Where each part starts: each group's rows in runs of `rowsPerPart`, a run never
    /// spanning two groups, then the row count.
    static func partStarts(of result: BaseQueryResult, rowsPerPart: Int) -> [Int] {
        var starts: [Int] = []
        var groupStart = 0
        for group in result.groups {
            starts.append(contentsOf: stride(from: groupStart, to: groupStart + group.rows.count, by: max(1, rowsPerPart)))
            groupStart += group.rows.count
        }
        return starts + [groupStart]
    }

    /// The pictures the view shows from files and the web, each decoded once at the size it
    /// prints: the cards' covers, then the `image()` values of its cells. One that cannot be
    /// read is left out and prints as an empty photo.
    private static func decodedPictures(of result: BaseQueryResult, root: URL, coverPixelDimension: Int) async -> [BaseImageReference: ReadingThumbnail] {
        var pictures: [BaseImageReference: ReadingThumbnail] = [:]
        for (reference, maximumPixelDimension) in pictureReferences(of: result, coverPixelDimension: coverPixelDimension) {
            guard !Task.isCancelled else { return pictures }
            guard let picture = await decodedCover(reference, root: root, maximumPixelDimension: maximumPixelDimension) else { continue }
            pictures[reference] = ReadingThumbnail(image: picture, aspectRatio: CGFloat(picture.width) / CGFloat(max(picture.height, 1)),
                                                   isEditableDrawing: false)
        }
        return pictures
    }

    /// Each picture of the view once, with the longest side in pixels it is decoded at: a
    /// card's cover at `coverPixelDimension`, a cell's `image()` at the size of its cell.
    static func pictureReferences(of result: BaseQueryResult, coverPixelDimension: Int) -> [(reference: BaseImageReference, maximumPixelDimension: Int)] {
        var references: [(reference: BaseImageReference, maximumPixelDimension: Int)] = []
        var listed: Set<BaseImageReference> = []
        func list(_ reference: BaseImageReference, maximumPixelDimension: Int) {
            if case .color = reference { return }
            if listed.insert(reference).inserted { references.append((reference, maximumPixelDimension)) }
        }
        if result.view.type == .cards, result.view.cards.imageProperty != nil {
            for row in result.rows { if let cover = row.presentation.coverImage { list(cover, maximumPixelDimension: coverPixelDimension) } }
        }
        let cellPixelDimension = Int(BaseImageValueView.frameSize.width * coverPixelsPerPoint)
        for row in result.rows {
            for target in row.cells.flatMap({ cell in cell.value.map(imageTargets(in:)) ?? [] }) {
                if let reference = BaseImageValueView.reference(for: target) { list(reference, maximumPixelDimension: cellPixelDimension) }
            }
        }
        return references
    }

    /// The targets of the `image()` values in a cell's value, also inside a list.
    private static func imageTargets(in value: BaseValue) -> [String] {
        switch value {
        case .image(let target): [target]
        case .list(let elements): elements.flatMap(imageTargets(in:))
        case .null, .boolean, .number, .string, .date, .duration, .link, .file, .object, .regularExpression, .icon, .html: []
        }
    }

    /// A cover from a file or the web; nil for a colour, or a picture that cannot be read,
    /// which prints as an empty photo as the screen shows it.
    private static func decodedCover(_ reference: BaseImageReference, root: URL, maximumPixelDimension: Int) async -> CGImage? {
        switch reference {
        case .color:
            return nil
        case .remote(let location):
            return try? await BaseThumbnailStore.downloadedThumbnail(at: location, maximumDimension: maximumPixelDimension) // Unreadable: an empty photo.
        case .vaultFile(let path):
            guard let location = try? path.url(in: root) else { return nil } // A path outside the vault: an empty photo.
            return try? await ImageFileService().displayImage(at: location, maximumPixelDimension: maximumPixelDimension) // Unreadable: an empty photo.
        }
    }
}

/// A run of a printed base's parts, drawn by the base's own cards, list or table view, with
/// the view's name above its first part as the base's toolbar shows it.
struct NotePDFBaseView: View {
    let base: PrintedBase
    let units: Range<Int>

    var body: some View {
        let result = base.result.keepingRows(at: base.rows(forUnits: units))
        VStack(alignment: .leading, spacing: 4) {
            if units.lowerBound == 0 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.view.name).font(.headline)
                    Text(base.result.displayedCount == 1 ? "1 result" : "\(base.result.displayedCount) results").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            switch result.view.type {
            case .cards: BaseCardsView(result: result, actions: actions)
            case .list: BaseListView(result: result, actions: actions)
            case .table: BaseTableView(result: result, sortKeys: result.view.sort, actions: actions, sort: { _, _ in })
            case .map, .kanban, .unsupported: EmptyView()
            }
        }
        .environment(\.basesScrollVertically, false)
        .environment(\.baseRowLimit, nil)
        .environment(\.printedBaseCovers, base.covers)
    }

    /// Paper is not tapped: nothing opens or edits.
    private var actions: BaseViewActions {
        BaseViewActions(openPath: { _ in }, openLink: { _ in }, editRequest: { _, _, _ in nil }, beginEditing: { _ in },
                        toggleCheckbox: { _, _ in }, requestedCheckboxValue: { _ in nil }, thumbnails: BaseThumbnailStore(),
                        vaultRoot: base.vaultRoot, contentVersion: 0)
    }
}

/// A base inside a callout or an embedded note on paper: drawn whole as the base draws it,
/// or as its name when it could not be run for paper.
struct NotePDFNestedBaseView: View {
    let base: PrintedBase?
    let name: String

    var body: some View {
        if let base {
            NotePDFBaseView(base: base, units: 0..<base.unitCount)
        } else {
            Label(name, systemImage: "tablecells").foregroundStyle(.secondary)
        }
    }
}
