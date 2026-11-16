/**
 * File: PDFFormFieldPagesTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The pages of a PDF file with form fields are found from the file's own page dictionaries, and a page of
 *              another PDF is looked at by its own dictionary, so handwritten pages are not read to find fields.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
import XCTest
import PDFKit
@testable import GraphiteUI

#if os(macOS)
import GraphiteTestSupport

@MainActor
final class PDFFormFieldPagesTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() async throws {
        temporaryDirectory = try TemporaryVault.make(prefix: "PDFFormFieldPages", for: self).root
    }

    func testOnlyThePagesWithAFormFieldAreFoundAndInkIsNotAField() throws {
        let location = try writeWorksheet(named: "Worksheet.pdf", fieldPageIndices: [1], inkPageIndices: [0, 2])
        XCTAssertEqual(PDFFormFieldPages.pageNumbers(at: location), [2])
    }

    func testAFileWithoutFieldsHasNoPagesWithFieldsAndAnUnreadableFileIsUnknown() throws {
        let location = try writeWorksheet(named: "Handwritten.pdf", fieldPageIndices: [], inkPageIndices: [0, 1, 2])
        XCTAssertEqual(PDFFormFieldPages.pageNumbers(at: location), [])
        let unreadable = temporaryDirectory.appendingPathComponent("Unreadable.pdf")
        try Data("not a PDF".utf8).write(to: unreadable)
        XCTAssertNil(PDFFormFieldPages.pageNumbers(at: unreadable))
    }

    func testAPageOfTheFileIsLookedAtByItsNumberAndAPageFromAnotherPDFByItsOwnDictionary() throws {
        let location = try writeWorksheet(named: "Worksheet.pdf", fieldPageIndices: [1], inkPageIndices: [0])
        let document = try XCTUnwrap(PDFDocument(url: location))
        let pageNumbers = PDFFormFieldPages.pageNumbers(at: location)
        XCTAssertFalse(PDFFormFieldPages.mayHaveFormField(try XCTUnwrap(document.page(at: 0)), in: document, pageNumbers: pageNumbers))
        XCTAssertTrue(PDFFormFieldPages.mayHaveFormField(try XCTUnwrap(document.page(at: 1)), in: document, pageNumbers: pageNumbers))
        XCTAssertFalse(PDFFormFieldPages.mayHaveFormField(try XCTUnwrap(document.page(at: 0)), in: document, pageNumbers: nil),
                       "With the file's pages unknown, each page is looked at by its own dictionary.")
        XCTAssertTrue(PDFFormFieldPages.mayHaveFormField(try XCTUnwrap(document.page(at: 1)), in: document, pageNumbers: nil))

        let otherLocation = try writeWorksheet(named: "Other.pdf", fieldPageIndices: [0], inkPageIndices: [1])
        let other = try XCTUnwrap(PDFDocument(url: otherLocation))
        document.insert(try XCTUnwrap(other.page(at: 0)), at: 0)
        document.insert(try XCTUnwrap(other.page(at: 1)), at: 1)
        XCTAssertTrue(PDFFormFieldPages.mayHaveFormField(try XCTUnwrap(document.page(at: 0)), in: document, pageNumbers: pageNumbers),
                      "A page put in from another PDF with a field.")
        XCTAssertFalse(PDFFormFieldPages.mayHaveFormField(try XCTUnwrap(document.page(at: 1)), in: document, pageNumbers: pageNumbers),
                       "A page put in from another PDF with ink only.")
    }

    /// Three pages, a text field on each of `fieldPageIndices` and forty ink strokes on each of `inkPageIndices`.
    private func writeWorksheet(named name: String, fieldPageIndices: Set<Int>, inkPageIndices: Set<Int>) throws -> URL {
        let document = PDFDocument()
        for pageIndex in 0..<3 {
            let page = PDFPage()
            if fieldPageIndices.contains(pageIndex) {
                let field = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 200, height: 24), forType: .widget, withProperties: nil)
                field.widgetFieldType = .text
                field.fieldName = "Field \(pageIndex)"
                page.addAnnotation(field)
            }
            if inkPageIndices.contains(pageIndex) {
                for strokeIndex in 0..<40 {
                    let ink = PDFAnnotation(bounds: CGRect(x: 40 + strokeIndex * 10, y: 300, width: 8, height: 20), forType: .ink, withProperties: nil)
                    let path = NSBezierPath()
                    path.move(to: CGPoint(x: 1, y: 1))
                    path.line(to: CGPoint(x: 6, y: 18))
                    ink.add(path)
                    page.addAnnotation(ink)
                }
            }
            document.insert(page, at: pageIndex)
        }
        let location = temporaryDirectory.appendingPathComponent(name)
        XCTAssertTrue(document.write(to: location))
        return location
    }
}
#endif
