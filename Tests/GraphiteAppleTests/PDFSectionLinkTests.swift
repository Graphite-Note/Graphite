/**
 * File: PDFSectionLinkTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The picture of a note's section on a PDF page and the /Link over it: written as a stamp and a link
 *              any reader follows, read back, and kept in step when the picture moves or goes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

final class PDFSectionLinkTests: XCTestCase {
    private static let pageSize = CGSize(width: 200, height: 300)
    private static let address = "obsidian://open?vault=Study&file=Physics%2FLecture%201%23Entropy"

    private func imageData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private func blankDocument() throws -> PDFDocument {
        let pageData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let consumer = try XCTUnwrap(CGDataConsumer(data: pageData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: pageData as Data))
    }

    private func sectionPicture() throws -> PDFPicture {
        PDFPicture(name: "section-1", imageData: try imageData(), bounds: CGRect(x: 20, y: 200, width: 100, height: 50), quarterTurns: 0,
                   sectionLinkAddress: Self.address)
    }

    private func links(on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.sectionLinkOwnerKey) != nil }
    }

    /// A text string of a dictionary, decoded as PDF text (PDFDocEncoding or UTF-16).
    private func textString(_ key: String, in dictionary: CGPDFDictionaryRef) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dictionary, key, &value), let value, let text = CGPDFStringCopyTextString(value) else { return nil }
        return text as String
    }

    /// The `/URI` of a link's `/A` action, read with Core Graphics.
    private func uniformResourceIdentifier(ofLink dictionary: CGPDFDictionaryRef) -> String? {
        var action: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "A", &action), let action else { return nil }
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(action, "URI", &value), let value, let text = CGPDFStringCopyTextString(value) else { return nil }
        return text as String
    }

    func testASectionsPictureIsWrittenAsAStampWithALinkAnyReaderFollows() throws {
        let document = try blankDocument()
        try PDFPageManager.replay([.addPicture(page: 0, picture: try sectionPicture())], on: document)
        let data = try XCTUnwrap(document.dataRepresentation())
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: data) { dictionaries in
            XCTAssertEqual(dictionaries.count, 2)
            let stamp = try XCTUnwrap(dictionaries.first { dictionary in PDFAnnotationDictionaryReading.name("Subtype", in: dictionary) == "Stamp" })
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphiteSectionLink", in: stamp), Self.address)
            XCTAssertEqual(textString("Contents", in: stamp), "Lecture 1 › Entropy", "Read as a PDF reader reads text, UTF-16 included.")
            let link = try XCTUnwrap(dictionaries.first { dictionary in PDFAnnotationDictionaryReading.name("Subtype", in: dictionary) == "Link" })
            XCTAssertEqual(uniformResourceIdentifier(ofLink: link), Self.address)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphiteSectionLinkOwner", in: link), "section-1")
            XCTAssertEqual(PDFAnnotationDictionaryReading.numbers("Rect", in: link), [20, 200, 120, 250])
        }
        let reread = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        let picture = try XCTUnwrap(PDFPageManager.pictures(on: reread).first)
        XCTAssertEqual(picture.sectionLinkAddress, Self.address)
        XCTAssertEqual(reread.annotations.compactMap(PDFPageManager.sectionLink(of:)),
                       [SectionLink(note: "Physics/Lecture 1", subpath: "Entropy"), SectionLink(note: "Physics/Lecture 1", subpath: "Entropy")],
                       "The picture and its link both name the section.")
    }

    func testTheLinkFollowsThePictureAndGoesWithIt() throws {
        let document = try blankDocument()
        let picture = try sectionPicture()
        try PDFPageManager.replay([.addPicture(page: 0, picture: picture)], on: document)
        let page = try XCTUnwrap(document.page(at: 0))
        let moved = CGRect(x: 40, y: 100, width: 120, height: 60)
        try PDFPageManager.replay([.movePicture(picture.reference(onPageAt: 0), to: moved)], on: document)
        XCTAssertEqual(links(on: page).map(\.bounds), [moved], "One link, over the moved picture.")

        var unlinked = picture
        unlinked.bounds = moved
        unlinked.sectionLinkAddress = nil
        try PDFPageManager.replay([.replacePicture(unlinked.reference(onPageAt: 0), with: unlinked)], on: document)
        XCTAssertTrue(links(on: page).isEmpty, "A picture that no longer links has no link.")

        var relinked = unlinked
        relinked.sectionLinkAddress = Self.address
        try PDFPageManager.replay([.replacePicture(relinked.reference(onPageAt: 0), with: relinked),
                                   .removeAnnotation(relinked.reference(onPageAt: 0))], on: document)
        XCTAssertTrue(page.annotations.isEmpty, "Removing the picture removes its link: \(page.annotations.map(\.type))")
    }

    func testTheIndexReadsTheSectionsAPDFLinksTo() throws {
        let document = try blankDocument()
        try PDFPageManager.replay([.addPicture(page: 0, picture: try sectionPicture())], on: document)
        let written = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: try XCTUnwrap(document.dataRepresentation()) as CFData))))
        XCTAssertEqual(PDFTypedAnnotationText.sectionLinkTexts(of: written), ["Physics/Lecture 1#Entropy"])
        XCTAssertEqual(PDFTypedAnnotationText.indexedText(of: written), "[[Physics/Lecture 1#Entropy]]\n")
        XCTAssertEqual(try NoteSemantics.pdfText(PDFTypedAnnotationText.indexedText(of: written)).links.map(\.target), ["Physics/Lecture 1#Entropy"],
                       "The index records the PDF as linking to the note.")
    }

    func testOnlyTheSectionLinksARewriteNamesChange() throws {
        let document = try blankDocument()
        let ordinary = PDFPicture(name: "photo-1", imageData: try imageData(), bounds: CGRect(x: 0, y: 0, width: 10, height: 10), quarterTurns: 0)
        try PDFPageManager.replay([.addPicture(page: 0, picture: try sectionPicture()), .addPicture(page: 0, picture: ordinary)], on: document)
        let newAddress = "obsidian://open?vault=Study&file=Archive%2FThermodynamics%23Entropy"
        let edits = PDFPageManager.sectionLinkEdits(in: document) { address in address == Self.address ? newAddress : nil }
        XCTAssertEqual(edits.count, 1)
        try PDFPageManager.replay(edits, on: document)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(PDFPageManager.pictures(on: page).compactMap(\.sectionLinkAddress), [newAddress])
        XCTAssertEqual(page.annotations.filter { annotation in annotation.type == "Link" }.compactMap(\.url?.absoluteString), [newAddress])
        XCTAssertTrue(PDFPageManager.sectionLinkEdits(in: document) { _ in nil }.isEmpty)
    }

    func testAnOrdinaryPictureHasNoLink() throws {
        let document = try blankDocument()
        let picture = PDFPicture(name: "photo-1", imageData: try imageData(), bounds: CGRect(x: 0, y: 0, width: 10, height: 10), quarterTurns: 0)
        try PDFPageManager.replay([.addPicture(page: 0, picture: picture)], on: document)
        XCTAssertEqual(try XCTUnwrap(document.page(at: 0)).annotations.count, 1)
        XCTAssertNil(PDFPageManager.pictures(on: try XCTUnwrap(document.page(at: 0))).first?.sectionLinkAddress)
    }
}
