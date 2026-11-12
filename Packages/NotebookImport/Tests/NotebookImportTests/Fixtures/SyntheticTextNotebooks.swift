/**
 * File: SyntheticTextNotebooks.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The two synthetic notebooks with typed text checked in under Tests/SyntheticNotebooks, built from the
 *              documented formats: a Goodnotes page with text boxes, a turned box, a sticky note and an older RTF box,
 *              and a Notability note whose typed text flows onto a second page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import Foundation

/// The synthetic notebooks with typed text that the app's import tests read from `Tests/SyntheticNotebooks`. They are
/// built here, field by field as `Docs/Goodnotes-format.md` and `Docs/Notability-format.md` describe the formats, so
/// nothing in them comes from a real notebook; `SyntheticTextNotebooksTests` checks that the checked-in files are
/// exactly what these builders make. The text boxes' sizes are Goodnotes' own for the same text: the text's width and
/// height in Helvetica Neue 24 or Georgia 36, rounded up to whole units, as the made-for-purpose samples store them.
enum SyntheticTextNotebooks {
    static let goodnotesFileName = "Synthetic text boxes.goodnotes"
    static let notabilityFileName = "Synthetic typed note.note"

    static let headingText = "Graphite one"
    static let headingLink = "https://example.com/graphite"
    static let turnedText = "Red two"
    static let stickyNoteText = "Sticky one"
    static let olderBoxText = "Older box"
    /// Goodnotes' "Standard" paper, 455.04 × 588.45 points.
    static let standardPaperSizeInUnits = (width: Float(834.24), height: Float(1_078.82))
    static let turnedAngleRadians = Float.pi / 6
    static let turnedScale = Float(2)

    static let typedHeading = "Synthetic typed note"
    /// Enough lines of 12-unit text to fill the first letter page and flow onto a second one.
    static let typedLineCount = 70

    // MARK: Goodnotes

    static func goodnotesNotebook() -> GoodnotesNotebookBuilder {
        var builder = GoodnotesNotebookBuilder()
        builder.schemaVersion = 35
        let size = standardPaperSizeInUnits
        builder.addAttachment("TEMPLATE", fileIdentifier: "TEMPLATEFILE",
                              contents: SyntheticPDF.gridPage(width: Double(size.width) * 6 / 11, height: Double(size.height) * 6 / 11), pdfPageCount: 1)
        builder.addPaper("PAPER", attachment: "TEMPLATE", width: size.width, height: size.height, template: "SYNTHETIC_standard_1_2 - White")
        let page = "5E1F7E57-0000-0000-0000-0000000000A1"
        builder.addPage(page, position: "a", paper: "PAPER")
        let layer = "5E1F7E57-0000-0000-0000-0000000000A2"
        let underline = GoodnotesRecord.constantWidthPath(width: 3, subpaths: [(start: (100, 150), curves: [(300, 150, 500, 150)])])
        builder.layers[layer] = [
            GoodnotesRecord.header("INK"), GoodnotesRecord.stroke("INK", path: underline, position: (1, 1)),
            GoodnotesRecord.header("HEADING"), textBox("HEADING", position: 2, origin: (100, 100), angle: 0, scale: 1, size: (140, 29),
                                                       text: headingText, run: runAttributes(color: (0.118, 0.106, 0.106, 1), link: headingLink)),
            GoodnotesRecord.header("TURNED"), textBox("TURNED", position: 3, origin: (420, 560), angle: turnedAngleRadians, scale: turnedScale,
                                                      size: (131, 41), text: turnedText,
                                                      run: runAttributes(color: (0.953, 0.247, 0.247, 1), fontName: "Georgia", size: 36)),
            GoodnotesRecord.header("STICKY"), stickyNote("STICKY", position: 4, origin: (520, 220)),
            GoodnotesRecord.header("OLDER"), olderTextBox("OLDER", position: 5, frame: (100, 880, 150, 49)),
        ]
        return builder
    }

    /// A text box (body field 21): placement, then the layout with its rich text, size, defaults and insets.
    private static func textBox(_ identifier: String, position: UInt64, origin: (Float, Float), angle: Float, scale: Float, size: (Float, Float),
                                text: String, run: ProtocolBufferWriter) -> [UInt8] {
        GoodnotesRecord.body(kind: 21, ProtocolBufferWriter.message { box in
            box.string(1, identifier)
            box.message(7, GoodnotesRecord.position(counter: position, replica: 1))
            box.message(20, ProtocolBufferWriter.message { placement in
                placement.message(1, GoodnotesRecord.point(origin.0, origin.1))
                if angle != 0 { placement.float(2, angle) }
                if scale != 1 { placement.float(3, scale) }
            })
            box.message(32, richTextLayout(text: text, run: run) { layout in
                layout.message(2, GoodnotesRecord.point(size.0, size.1))
                layout.message(10, ProtocolBufferWriter.message { insets in for side in 1...4 { insets.float(side, 10) } })
            })
        })
    }

    /// A sticky note (body field 20), 256 units square on Goodnotes' yellow, its text in the defaults' look.
    private static func stickyNote(_ identifier: String, position: UInt64, origin: (Float, Float)) -> [UInt8] {
        GoodnotesRecord.body(kind: 20, ProtocolBufferWriter.message { note in
            note.string(1, identifier)
            note.message(7, GoodnotesRecord.position(counter: position, replica: 1))
            note.message(20, ProtocolBufferWriter.message { placement in placement.message(1, GoodnotesRecord.point(origin.0, origin.1)) })
            note.message(21, ProtocolBufferWriter.message { size in size.message(2, GoodnotesRecord.point(256, 256)) })
            note.message(30, GoodnotesRecord.color(0.98, 0.906, 0.471, 1))
            note.message(31, richTextLayout(text: stickyNoteText, run: runAttributes(color: (0.193, 0.166, 0.007, 1))) { _ in })
            note.string(33, "Synthetic Author")
        })
    }

    /// An older text box (body field 8): its frame, the text area 10 units inside it, and its text as an iPad's Cocoa RTF,
    /// 24 half-points of Helvetica in blue.
    private static func olderTextBox(_ identifier: String, position: UInt64, frame: (Float, Float, Float, Float)) -> [UInt8] {
        let rtf = "{\\rtf1\\ansi\\ansicpg1252\\cocoartf2822\n\\cocoatextscaling1\\cocoaplatform1{\\fonttbl\\f0\\fswiss\\fcharset0 Helvetica;}\n"
            + "{\\colortbl;\\red255\\green255\\blue255;\\red0\\green0\\blue255;}\n{\\*\\expandedcolortbl;;\\cssrgb\\c0\\c0\\c100000;}\n"
            + "\\pard\\pardirnatural\\partightenfactor0\n\n\\f0\\fs24 \\cf2 \(olderBoxText)}"
        return GoodnotesRecord.body(kind: 8, ProtocolBufferWriter.message { box in
            box.string(1, identifier)
            box.message(2, rectangle(frame.0, frame.1, frame.2, frame.3))
            box.message(3, rectangle(frame.0 + 10, frame.1 + 10, frame.2 - 20, frame.3 - 20))
            box.message(5, GoodnotesRecord.position(counter: position, replica: 1))
            box.string(6, rtf)
        })
    }

    private static func rectangle(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> ProtocolBufferWriter {
        ProtocolBufferWriter.message { rectangle in
            rectangle.message(1, GoodnotesRecord.point(x, y))
            rectangle.message(2, GoodnotesRecord.point(width, height))
        }
    }

    /// A run's attributes: 3 colour, 4 link, 30 font name, 40 size in units; an unset font or size takes the defaults'.
    private static func runAttributes(color: (Float, Float, Float, Float), link: String? = nil, fontName: String? = nil,
                                      size: Float? = nil) -> ProtocolBufferWriter {
        ProtocolBufferWriter.message { attributes in
            attributes.message(3, GoodnotesRecord.color(color.0, color.1, color.2, color.3))
            if let link { attributes.string(4, link) }
            if let fontName { attributes.string(30, fontName) }
            attributes.float(40, size ?? -404)
        }
    }

    /// `{1: {2: LZ4 rich text}, 5: {1: default attributes}}`, the defaults black Helvetica Neue 24 as in the samples.
    private static func richTextLayout(text: String, run: ProtocolBufferWriter, extra: (inout ProtocolBufferWriter) -> Void) -> ProtocolBufferWriter {
        let richText = ProtocolBufferWriter.message { container in
            container.message(1, ProtocolBufferWriter.message { body in
                body.string(1, text)
                body.message(2, run)
            })
        }
        return ProtocolBufferWriter.message { layout in
            layout.message(1, ProtocolBufferWriter.message { content in content.lengthDelimited(2, appleLZ4StoredPayload(richText.bytes)) })
            layout.message(5, ProtocolBufferWriter.message { defaults in
                defaults.message(1, ProtocolBufferWriter.message { attributes in
                    attributes.message(3, GoodnotesRecord.color(0, 0, 0, 1))
                    attributes.string(30, "Helvetica Neue")
                    attributes.float(40, 24)
                })
            })
            extra(&layout)
        }
    }

    // MARK: Notability

    /// A reflowable note (no stored page width, as the typed-text sample): a red bold heading, an underlined line, then
    /// numbered lines enough for two pages, and one pen curve at the right of the first page.
    static func notabilityNote() -> NotabilityNoteBuilder {
        var builder = NotabilityNoteBuilder()
        builder.folderName = "Synthetic typed note"
        builder.reflowStateClassName = "NBReflowStateReflowable"
        builder.storedPageWidth = nil
        builder.paperFields = [("paperIdentifier", "Legacy:13"), ("paperSize", "letter"), ("paperOrientation", "portrait"),
                               ("paperSizingBehavior", "deviceBasedWidth"), ("lineStyle2", "No Lines")]
        let underlined = "Underlined line\n"
        let numbered = (1...typedLineCount).map { number in "Line \(number) of the synthetic typed note." }.joined(separator: "\n")
        let heading = typedHeading + "\n"
        builder.text = heading + underlined + numbered + "\n\n\n"
        let headingLength = heading.utf16.count, underlinedLength = underlined.utf16.count
        builder.textRuns = [
            SyntheticNotabilityTextRun(range: "{0, \(headingLength)}", fontName: "HelveticaNeue-Bold", fontSize: 20, color: "0.93,0.21,0.14,1.0"),
            SyntheticNotabilityTextRun(range: "{\(headingLength), \(underlinedLength)}",
                                       otherAttributes: [("NSUnderline", .integer(1)), ("NSStrikethrough", .integer(0)), ("line-spacing", .real(1)),
                                                         ("NSBaselineOffset", .real(0))]),
            SyntheticNotabilityTextRun(range: "{\(headingLength + underlinedLength), \(builder.text.utf16.count - headingLength - underlinedLength)}"),
        ]
        builder.curves = [.pen([(420, 60), (460, 40), (500, 80), (540, 60)], uuidByte: 0x51)]
        return builder
    }
}

/// A one-page PDF written byte by byte, so that it is the same at every build: a light blue grid every 20 points,
/// as Goodnotes' template paper is a one-page vector PDF of the page's size.
enum SyntheticPDF {
    static func gridPage(width: Double, height: Double) -> [UInt8] {
        var drawing = "0.75 0.85 0.95 RG 0.5 w\n"
        for x in stride(from: 20.0, to: width, by: 20) { drawing += String(format: "%.2f 0 m %.2f %.2f l S\n", x, x, height) }
        for y in stride(from: 20.0, to: height, by: 20) { drawing += String(format: "0 %.2f m %.2f %.2f l S\n", y, width, y) }
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            String(format: "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] /Contents 4 0 R /Resources << >> >>", width, height),
            "<< /Length \(drawing.utf8.count) >>\nstream\n\(drawing)endstream",
        ]
        var file = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(file.utf8.count)
            file += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = file.utf8.count
        file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { file += String(format: "%010d 00000 n \n", offset) }
        file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        return Array(file.utf8)
    }
}
