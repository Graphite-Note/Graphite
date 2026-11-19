/**
 * File: PDFCombinedInkGroup.swift
 * -------------------------------
 * Layer: Apple
 * Description: An ink group a shown page holds as one annotation: its strokes' names, authors and order, the strokes
 *              erased since the file was read, and the picture of the rest the group's one annotation draws.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */
import Foundation
import CoreGraphics
import PDFKit
import Synchronization

/// An ink group of a page of the file as read that the shown page holds as its first stroke only
/// (`PDFShownInkCombining`); that annotation draws the picture of the group here (`PDFShownInkAnnotation`).
///
/// What the shown document's edits need of each stroke left out of the page is kept here: its name, by which erasing
/// and undo remove it, its author, which a stroke written again keeps, and whether it multiplies over the page. An
/// erased stroke is only noted, and the picture is drawn again without it; strokes written since are annotations of
/// the page of their own, as before. The file is never changed: saving, export and sharing replay the edits on the
/// file, one `/Ink` annotation per stroke.
///
/// The picture is drawn off the main thread from a separate copy of the file and may be drawn on any thread, so the
/// state is behind a lock.
public final class PDFCombinedInkGroup: Sendable {
    /// The group's picture of the page as shown, its crop box and quarter turns, for the group's strokes as they were.
    public struct Picture: Sendable {
        public let image: CGImage
        public let cropBox: CGRect
        /// Clockwise, in degrees.
        public let rotation: Int
        /// The group's `version` the picture was drawn for.
        public let version: Int

        public init(image: CGImage, cropBox: CGRect, rotation: Int, version: Int) {
            self.image = image
            self.cropBox = cropBox
            self.rotation = rotation
            self.version = version
        }
    }

    private struct Fields {
        var removedNames = Set<String>()
        var version = 0
        var picture: Picture?
    }

    public let group: String
    /// The file the shown document was read from, mapped as it was read and never changed, from which the picture is
    /// drawn; shared by every group of the document.
    public let fileData: Data
    /// The file's page count, by which a renderer knows its copy is that file.
    public let filePageCount: Int
    /// The page's zero-based index in that file, which a page keeps when pages are moved.
    public let filePageIndex: Int
    /// Every stroke of the group in the page's order, as the file has them.
    public let strokes: [PDFShownInkCombining.Stroke]
    private let fields = Mutex(Fields())

    public init(group: String, fileData: Data, filePageCount: Int, filePageIndex: Int, strokes: [PDFShownInkCombining.Stroke]) {
        self.group = group
        self.fileData = fileData
        self.filePageCount = filePageCount
        self.filePageIndex = filePageIndex
        self.strokes = strokes
    }

    /// The same group for another page, as when a page is duplicated, with the same strokes erased.
    public func copy() -> PDFCombinedInkGroup {
        let copy = PDFCombinedInkGroup(group: group, fileData: fileData, filePageCount: filePageCount, filePageIndex: filePageIndex, strokes: strokes)
        let removedNames = self.removedNames
        copy.fields.withLock { fields in fields.removedNames = removedNames }
        return copy
    }

    /// The names of the strokes erased since the file was read.
    public var removedNames: Set<String> { fields.withLock { fields in fields.removedNames } }

    /// Counts the changes of the strokes drawn; a picture drawn for another count is not drawn.
    public var version: Int { fields.withLock { fields in fields.version } }

    /// The strokes the group still draws, in the page's order.
    public var remainingStrokes: [PDFShownInkCombining.Stroke] {
        let removedNames = self.removedNames
        guard !removedNames.isEmpty else { return strokes }
        return strokes.filter { stroke in stroke.name.map { name in !removedNames.contains(name) } ?? true }
    }

    /// Notes the strokes of these names as erased. Returns whether any of the group's strokes was.
    @discardableResult
    public func remove(named names: Set<String>) -> Bool {
        let erased = Set(strokes.compactMap(\.name)).intersection(names)
        return fields.withLock { fields in
            let added = erased.subtracting(fields.removedNames)
            guard !added.isEmpty else { return false }
            fields.removedNames.formUnion(added)
            fields.version += 1
            return true
        }
    }

    /// The picture last drawn, of any version.
    public var picture: Picture? { fields.withLock { fields in fields.picture } }

    /// Keeps the picture, unless it was drawn for strokes that have changed since.
    public func show(_ picture: Picture?) {
        fields.withLock { fields in
            guard picture.map({ picture in picture.version == fields.version }) ?? true else { return }
            fields.picture = picture
        }
    }

    /// Draws the picture in an annotation's drawing context, which is the page as shown for `box`, as PDFKit's own
    /// strokes draw into it; nothing while the picture is missing, out of date, or of another crop box or turn.
    func drawPicture(of page: PDFPage, box: PDFDisplayBox, in context: CGContext) {
        let cropBox = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        guard let picture = fields.withLock({ fields in fields.picture.flatMap { picture in picture.version == fields.version ? picture : nil } }),
              picture.cropBox == cropBox, picture.rotation == rotation, box == .cropBox || page.bounds(for: box) == cropBox else { return }
        let shownSize = rotation % 180 == 0 ? cropBox.size : CGSize(width: cropBox.height, height: cropBox.width)
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(picture.image, in: CGRect(origin: .zero, size: shownSize))
        context.restoreGState()
    }
}
