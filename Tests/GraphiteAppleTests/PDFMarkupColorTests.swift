/**
 * File: PDFMarkupColorTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: A text mark of any colour: its hex text, the names of Graphite's colours, and the `/C` written to the
 *              file, read back by Core Graphics' own PDF parser and by PDFKit as the same colour.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import PDFKit
import GraphiteApple
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

final class PDFMarkupColorTests: XCTestCase {
    func testAColourIsKeptAsHexTextOrAsGraphitesName() throws {
        let orange = try XCTUnwrap(PDFMarkupColor(hex: "ff8000"))
        XCTAssertEqual(orange.hex, "#FF8000")
        XCTAssertEqual(orange.storedName, "#FF8000")
        XCTAssertNil(orange.name)
        XCTAssertEqual(PDFMarkupColor.yellow.storedName, "yellow")
        XCTAssertEqual(PDFMarkupColor.yellow.title, "Yellow")
        XCTAssertEqual(PDFMarkupColor(storedName: "purple"), .purple)
        XCTAssertEqual(PDFMarkupColor(storedName: "#FF8000"), orange)
        for text in ["", "#FF80", "#GG8000", "orange", "#FF80000"] { XCTAssertNil(PDFMarkupColor(storedName: text), text) }
        XCTAssertEqual(PDFMarkupColor(red: 2, green: -1, blue: .nan), PDFMarkupColor(redLevel: 255, greenLevel: 0, blueLevel: 0))
    }

    func testAMarkOfAnyColourIsWrittenAsItsColourAndReadBackTheSame() throws {
        let location = try TemporaryVault.make(prefix: "PDFMarkupColor", for: self).location(of: "Marked.pdf")
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: output)), mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(data: output as Data))
        let teal = PDFMarkupColor(redLevel: 0x12, greenLevel: 0x9A, blueLevel: 0x8B)
        try PDFPageManager.apply(.addMarkup(page: 0, markup: PDFMarkup(name: "Teal", kind: .underline, color: teal,
                                                                         lineBounds: [CGRect(x: 40, y: 500, width: 200, height: 18)])), to: document)
        XCTAssertTrue(document.write(to: location))

        // Core Graphics' own parser, not PDFKit, reads the /C array.
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try Data(contentsOf: location)) { dictionaries in
            XCTAssertEqual(dictionaries.count, 1)
            let components = try XCTUnwrap(dictionaries.first.flatMap { dictionary in PDFAnnotationDictionaryReading.numbers("C", in: dictionary) })
            XCTAssertEqual(components.count, 3, "Device RGB.")
            for (written, expected) in zip(components, [teal.red, teal.green, teal.blue]) { XCTAssertEqual(written, expected, accuracy: 0.002) }
        }

        let reread = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0)?.annotations.compactMap(PDFMarkup.init(annotation:)).first)
        XCTAssertEqual(reread.color, teal, "Read back, the colour is the same to eight bits a component.")
    }
}
