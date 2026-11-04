import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple
import GraphiteTestSupport

/// The author written into a PDF for what Graphite adds (`/T`): the name chosen in Settings, else the Mac owner's name, else
/// none. PDFKit's own author, "Mobile User" on an iPad or iPhone, is never left in the file. The files are written as saving
/// writes them, read back by PDFKit and, for the key itself, by CoreGraphics.
final class PDFAnnotationAuthorTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var savedFolder: TemporaryVault!

    override func setUp() {
        suiteName = "PDFAnnotationAuthorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedFolder = try? TemporaryVault(prefix: "PDFAnnotationAuthorTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        savedFolder?.remove()
        savedFolder = nil
    }

    private func author(chosen: String?, owner: String? = nil) -> PDFAnnotationAuthor {
        if let chosen { defaults.set(chosen, forKey: PDFAnnotationAuthor.preferenceKey) } else { defaults.removeObject(forKey: PDFAnnotationAuthor.preferenceKey) }
        return PDFAnnotationAuthor(defaults: defaults, ownerName: { owner })
    }

    private func pixelData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private func stroke(named name: String, hasOutline: Bool, at height: CGFloat = 400) -> PortableInkStroke {
        let segment = [CGPoint(x: 100, y: height), CGPoint(x: 200, y: height + 50)]
        let outline = hasOutline ? [[CGPoint(x: 95, y: height - 5), CGPoint(x: 205, y: height - 5), CGPoint(x: 205, y: height + 55), CGPoint(x: 95, y: height + 55)]] : nil
        return PortableInkStroke(name: name, segments: [segment], width: 2, red: 0, green: 0, blue: 0, alpha: 1, outline: outline)
    }

    private func inkEdit(_ strokes: [PortableInkStroke], removal: PDFInkUpdate.Removal = .strokes([])) -> PDFEdit {
        .updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: removal, addedStrokes: strokes, editableRecord: nil))
    }

    /// The file as saving leaves it, written and compacted, and read back.
    private func saved(_ document: PDFDocument) throws -> (reloaded: PDFDocument, data: Data) {
        let file = try XCTUnwrap(savedFolder).root.appendingPathComponent("\(UUID().uuidString).pdf")
        XCTAssertTrue(PDFFileService.write(document, to: file))
        return (try XCTUnwrap(PDFDocument(url: file)), try Data(contentsOf: file))
    }

    private func authors(of reloaded: PDFDocument) throws -> [String: String?] {
        let page = try XCTUnwrap(reloaded.page(at: 0))
        var authorsByKind: [String: String?] = [:]
        for annotation in page.annotations { authorsByKind[(annotation.type ?? "?") + (annotation.persistentName.map { "/" + $0 } ?? "")] = annotation.userName }
        return authorsByKind
    }

    private func makeDocument() throws -> PDFDocument { try PDFTextBoxTestDocuments.writtenDocument(from: PDFTextBoxTestDocuments.blankPageData()) }

    /// Every kind of annotation Graphite creates, added in one document by one author.
    private func addEveryKind(to document: PDFDocument, as author: PDFAnnotationAuthor) throws {
        let edits: [PDFEdit] = [
            inkEdit([stroke(named: "outlined-ink", hasOutline: true), stroke(named: "plain-ink", hasOutline: false, at: 300)]),
            .addMarkup(page: 0, markup: PDFMarkup(name: "marker", kind: .highlight, color: .yellow, lineBounds: [CGRect(x: 60, y: 500, width: 200, height: 20)])),
            .addMarkup(page: 0, markup: PDFMarkup(name: "underline", kind: .underline, color: .green, lineBounds: [CGRect(x: 60, y: 450, width: 200, height: 20)])),
            .addMarkup(page: 0, markup: PDFMarkup(name: "strike", kind: .strikeOut, color: .red, lineBounds: [CGRect(x: 60, y: 420, width: 200, height: 20)])),
            .addPicture(page: 0, picture: PDFPicture(name: "picture", imageData: try pixelData(), bounds: CGRect(x: 20, y: 100, width: 100, height: 50), quarterTurns: 0)),
            .addTextBox(page: 0, textBox: PDFTextBoxTestDocuments.sampleBox(name: "box", link: URL(string: "https://example.org/")))
        ]
        for edit in edits { try PDFPageManager.apply(edit, to: document, drawsInkOutlines: true, author: author) }
    }

    // MARK: The name and where it is kept

    func testNoNameIsChosenUntilOneIsTypedAndItIsKeptUnderItsKey() {
        XCTAssertEqual(PDFAnnotationAuthor.preferenceKey, "GraphiteAnnotationAuthorName")
        XCTAssertEqual(PDFAnnotationAuthor.chosenName(in: defaults), "", "Nothing is chosen by default.")
        defaults.set("  Ada Lovelace \n", forKey: "GraphiteAnnotationAuthorName")
        XCTAssertEqual(PDFAnnotationAuthor.chosenName(in: defaults), "Ada Lovelace", "Spaces around the name are not part of it.")
    }

    func testTheChosenNameWinsThenTheOwnersNameThenNone() {
        XCTAssertEqual(author(chosen: "Ada", owner: "Mac Owner").name, "Ada")
        XCTAssertEqual(author(chosen: nil, owner: "Mac Owner").name, "Mac Owner", "Where the system offers a name without asking.")
        XCTAssertEqual(author(chosen: "   ", owner: "Mac Owner").name, "Mac Owner", "A blank name is no name.")
        XCTAssertNil(author(chosen: nil, owner: nil).name, "An iPad or iPhone offers none: no author is written.")
        XCTAssertNil(author(chosen: "", owner: "  ").name)
    }

    func testOnlyAMacOffersTheOwnersNameWithoutAsking() {
        #if os(macOS)
        XCTAssertEqual(PDFAnnotationAuthor.deviceOwnerName, NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
        #else
        XCTAssertNil(PDFAnnotationAuthor.deviceOwnerName, "On an iPad or iPhone the full user name is “Mobile User”, which names nobody.")
        #endif
    }

    // MARK: Every kind, after a save and a reload

    func testEveryKindOfAnnotationNamesTheChosenAuthorInTheSavedFile() throws {
        let document = try makeDocument()
        try addEveryKind(to: document, as: author(chosen: "Ada Lovelace"))

        let (reloaded, data) = try saved(document)

        let written = try authors(of: reloaded)
        XCTAssertEqual(written.count, 8, "Two ink strokes, three markups, a picture, a text box and the link over its text: \(written.keys.sorted())")
        // PDFKit writes no author on a link, so the link over the box's text has none to name.
        for (annotation, name) in written where !annotation.hasPrefix("Link/") { XCTAssertEqual(name, "Ada Lovelace", annotation) }
        // By a second reader, the key itself.
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: data) { dictionaries in
            XCTAssertEqual(dictionaries.count, written.count)
            for dictionary in dictionaries where PDFAnnotationDictionaryReading.name("Subtype", in: dictionary) != "Link" {
                XCTAssertEqual(PDFAnnotationDictionaryReading.string("T", in: dictionary), "Ada Lovelace", PDFAnnotationDictionaryReading.name("Subtype", in: dictionary) ?? "?")
            }
        }
    }

    func testAnEmptyNameWritesNoAuthorAtAllAndNeverMobileUser() throws {
        let document = try makeDocument()
        try addEveryKind(to: document, as: author(chosen: nil, owner: nil))

        let (reloaded, data) = try saved(document)

        for (annotation, name) in try authors(of: reloaded) { XCTAssertNil(name, annotation) }
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: data) { dictionaries in
            XCTAssertFalse(dictionaries.isEmpty)
            for dictionary in dictionaries {
                XCTAssertFalse(PDFAnnotationDictionaryReading.hasKey("T", in: dictionary), "No /T: \(PDFAnnotationDictionaryReading.name("Subtype", in: dictionary) ?? "?")")
            }
        }
        XCTAssertNil(String(decoding: data, as: UTF8.self).range(of: "Mobile User"))
    }

    func testTheOwnersNameIsWrittenWhenNoNameIsChosen() throws {
        let document = try makeDocument()
        try addEveryKind(to: document, as: author(chosen: nil, owner: "Mac Owner"))

        for (annotation, name) in try authors(of: try saved(document).reloaded) where !annotation.hasPrefix("Link/") { XCTAssertEqual(name, "Mac Owner", annotation) }
    }

    // MARK: What is in the file keeps its author

    func testAnnotationsMadeBeforeKeepTheirAuthorWhateverTheNameIsNow() throws {
        let document = try makeDocument()
        try addEveryKind(to: document, as: author(chosen: "Ada Lovelace"))
        let first = try saved(document).reloaded
        PDFPageManager.prepareForWriting(first)

        // New ink and a new picture under another name, beside the old annotations.
        let later = author(chosen: "Grace Hopper")
        try PDFPageManager.apply(inkEdit([stroke(named: "new-ink", hasOutline: true, at: 200)]), to: first, drawsInkOutlines: true, author: later)
        try PDFPageManager.apply(.addPicture(page: 0, picture: PDFPicture(name: "new-picture", imageData: try pixelData(), bounds: CGRect(x: 200, y: 100, width: 50, height: 50), quarterTurns: 0)),
                                 to: first, drawsInkOutlines: true, author: later)

        let written = try authors(of: try saved(first).reloaded)
        XCTAssertEqual(written["Ink/new-ink"] ?? nil, "Grace Hopper")
        XCTAssertEqual(written["Stamp/new-picture"] ?? nil, "Grace Hopper")
        XCTAssertEqual(written["Ink/outlined-ink"] ?? nil, "Ada Lovelace")
        XCTAssertEqual(written["Highlight/marker"] ?? nil, "Ada Lovelace")
        XCTAssertEqual(written["Stamp/picture"] ?? nil, "Ada Lovelace")
        XCTAssertEqual(written["FreeText/box"] ?? nil, "Ada Lovelace")
    }

    func testAMovedPictureAndAnEditedTextBoxKeepTheirAuthor() throws {
        let document = try makeDocument()
        try addEveryKind(to: document, as: author(chosen: "Ada Lovelace"))
        let later = author(chosen: "Grace Hopper")

        let picture = try XCTUnwrap(PDFPageManager.pictures(on: try XCTUnwrap(document.page(at: 0))).first)
        try PDFPageManager.apply(.movePicture(picture.reference(onPageAt: 0), to: CGRect(x: 40, y: 150, width: 100, height: 50)), to: document, drawsInkOutlines: true, author: later)
        let box = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(document.page(at: 0))).first)
        var edited = box
        edited.origin = CGPoint(x: 80, y: 480)
        try PDFPageManager.apply(.replaceTextBox(box.reference(onPageAt: 0), with: edited), to: document, drawsInkOutlines: true, author: later)

        let written = try authors(of: try saved(document).reloaded)
        XCTAssertEqual(written["Stamp/picture"] ?? nil, "Ada Lovelace")
        XCTAssertEqual(written["FreeText/box"] ?? nil, "Ada Lovelace")
        XCTAssertEqual(written.filter { _, name in name == "Grace Hopper" }.count, 0, "Nothing was added, so the later name is written nowhere.")
    }

    func testInkWrittenAgainAsAWholeGroupKeepsEachStrokesAuthorAndAnAnonymousOneStaysAnonymous() throws {
        let document = try makeDocument()
        try PDFPageManager.apply(inkEdit([stroke(named: "by-ada", hasOutline: true)]), to: document, drawsInkOutlines: true, author: author(chosen: "Ada Lovelace"))
        try PDFPageManager.apply(inkEdit([stroke(named: "anonymous", hasOutline: true, at: 300)]), to: document, drawsInkOutlines: true, author: author(chosen: nil, owner: nil))

        let later = author(chosen: "Grace Hopper")
        let everyStroke = [stroke(named: "by-ada", hasOutline: true), stroke(named: "anonymous", hasOutline: true, at: 300), stroke(named: "added", hasOutline: true, at: 200)]
        try PDFPageManager.apply(inkEdit(everyStroke, removal: .entireGroup), to: document, drawsInkOutlines: true, author: later)

        let written = try authors(of: try saved(document).reloaded)
        XCTAssertEqual(written["Ink/by-ada"] ?? nil, "Ada Lovelace")
        XCTAssertTrue(written.keys.contains("Ink/anonymous"))
        XCTAssertNil(written["Ink/anonymous"] ?? nil, "An annotation without an author is not given one by being written again.")
        XCTAssertEqual(written["Ink/added"] ?? nil, "Grace Hopper")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
