/**
 * File: GoodnotesTextPlanner.swift
 * --------------------------------
 * Layer: Planning
 * Description: Goodnotes text boxes, sticky notes and older RTF text boxes planned as text boxes in page points.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import CoreGraphics
import Foundation

/// Plans Goodnotes' typed text as text boxes (`Docs/Goodnotes-format.md`, "Text boxes", "Older text boxes" and
/// "Sticky notes"; design step 8). Everything in a text box is multiplied by its scale and by 6/11 point per unit: its
/// size, insets and font sizes. Its origin is its top-left corner, turned clockwise about it by its angle; the text
/// starts at the inset, its first baseline at the inset plus the font's ascent, as Graphite's text box draws it. The
/// stored size is the text's own, rounded up to whole units ("Link here" in Helvetica Neue 24 is 97.8 units wide and
/// stored as 98), with the insets outside it: the Graphite box is that width and an inset on each side, so its lines
/// break where Goodnotes' do.
enum GoodnotesTextPlanner {
    private static let black = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1)
    /// What Goodnotes draws when neither a run nor the defaults name a font or a size: "Modern" at 24 units.
    private static let defaultFamily = "Helvetica Neue"
    private static let defaultSizeInUnits = 24.0
    /// Goodnotes' inset of a text box when its record has none, in units.
    private static let defaultInsetInUnits = 10.0
    /// A sticky note's text starts this far inside the note, in units (measured on the export: 4.4 points).
    static let stickyNoteInsetInUnits = 8.0
    /// The room between an older text box's frame and its text area on every side (`Docs/Goodnotes-format.md`).
    static let olderTextBoxInsetInUnits = 10.0

    static func textBox(for textBox: GoodnotesTextBox, tally: inout ImportReportTally) -> ImportedTextBox? {
        let scale = textBox.scale
        guard scale.isFinite, scale > 0, let size = textBox.size else { return nil }
        let pointsPerBoxUnit = scale * GoodnotesPagePlanner.pointsPerUnit
        let inset = textBox.insets?.first ?? defaultInsetInUnits
        let runs = Self.runs(of: textBox.richText, pointsPerUnit: pointsPerBoxUnit, tally: &tally)
        return ImportedTextBox(content: .runs(runs), origin: point(textBox.origin), width: (Double(size.width) + 2 * inset) * pointsPerBoxUnit,
                               height: nil, rotationRadiansClockwise: textBox.rotationRadians, padding: inset * pointsPerBoxUnit, fillColor: nil)
    }

    /// A sticky note keeps its square and its colour as the box's fill; Goodnotes also prints its author's name at the
    /// bottom, which the box leaves out (the report says so).
    static func textBox(for stickyNote: GoodnotesStickyNote, tally: inout ImportReportTally) -> ImportedTextBox {
        tally.count(.stickyNote)
        let pointsPerUnit = GoodnotesPagePlanner.pointsPerUnit
        return ImportedTextBox(content: .runs(runs(of: stickyNote.richText, pointsPerUnit: pointsPerUnit, tally: &tally)),
                               origin: point(stickyNote.origin), width: Double(stickyNote.size.width) * pointsPerUnit,
                               height: Double(stickyNote.size.height) * pointsPerUnit, rotationRadiansClockwise: 0,
                               padding: stickyNoteInsetInUnits * pointsPerUnit, fillColor: stickyNote.paperColor)
    }

    /// An older text box: its text area (`textFrame`) and the 10 units Goodnotes keeps around it, and its RTF, which the
    /// writer reads. The text area places the text: in one of the owner's library notebooks a box's frame sits 36 units
    /// left of and 4 above its text area, where the frame's 10-unit inset would put the text over the drawing beside it
    /// and break its one line in two; the text area is the text's own width, as a newer box's size is.
    static func textBox(for textBox: GoodnotesRTFTextBox) -> ImportedTextBox {
        let pointsPerUnit = GoodnotesPagePlanner.pointsPerUnit
        let textArea = textBox.textFrame
        let origin = CGPoint(x: textArea.minX - olderTextBoxInsetInUnits, y: textArea.minY - olderTextBoxInsetInUnits)
        return ImportedTextBox(content: .rtf(textBox.rtf, pointsPerUnit: pointsPerUnit), origin: point(origin),
                               width: (Double(textArea.width) + 2 * olderTextBoxInsetInUnits) * pointsPerUnit, height: nil, rotationRadiansClockwise: 0,
                               padding: olderTextBoxInsetInUnits * pointsPerUnit, fillColor: nil)
    }

    /// The text in the look of its first run, completed by the defaults. How a text box with several runs marks their
    /// ranges is not known (`Docs/Goodnotes-format.md`), so the whole text takes the first run's look and the other runs
    /// are counted as styles not kept, as is a see-through colour.
    static func runs(of richText: GoodnotesRichText, pointsPerUnit: Double, tally: inout ImportReportTally) -> [ImportedTextRun] {
        guard !richText.text.isEmpty else { return [] }
        let first = richText.runs.first, defaults = richText.defaultAttributes
        for _ in richText.runs.dropFirst() { tally.count(.textStyle) }
        let color = first?.color ?? defaults?.color ?? black
        if color.alpha < 1 { tally.count(.textStyle) }
        let linkText = first?.link ?? defaults?.link
        return [ImportedTextRun(text: richText.text, font: .family(first?.fontName ?? defaults?.fontName ?? defaultFamily),
                                sizeInPoints: (first?.sizeInUnits ?? defaults?.sizeInUnits ?? defaultSizeInUnits) * pointsPerUnit,
                                color: color, isUnderlined: false, link: linkText.flatMap(URL.init(string:)))]
    }

    private static func point(_ unitPoint: CGPoint) -> CGPoint {
        CGPoint(x: Double(unitPoint.x) * GoodnotesPagePlanner.pointsPerUnit, y: Double(unitPoint.y) * GoodnotesPagePlanner.pointsPerUnit)
    }
}
