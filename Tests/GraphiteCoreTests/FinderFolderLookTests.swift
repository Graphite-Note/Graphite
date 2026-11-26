import XCTest
@testable import GraphiteCore

final class FinderFolderLookTests: XCTestCase {
    /// The bytes macOS 27's Finder wrote on a folder given a "Green" tag and the nerd-face
    /// emoji (read from a real folder with `xattr -px`).
    private let finderTagsBytes: [UInt8] = [
        0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30, 0xA1, 0x01, 0x57, 0x47, 0x72, 0x65, 0x65, 0x6E,
        0x0A, 0x31, 0x08, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x12
    ]
    private let finderIconBytes = Data(#"{"emoji":"🥸"}"#.utf8)
    private let finderInformationBytes: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0x04, 0x02] + [UInt8](repeating: 0, count: 22)

    func testReadsWhatFinderWrote() {
        let look = FinderFolderLook(tagsData: Data(finderTagsBytes), iconData: finderIconBytes,
                                    finderInformationData: Data(finderInformationBytes), hasCustomIconFile: false, colorTagNames: [:])
        XCTAssertEqual(look.tags, [FinderTag(name: "Green", color: .green, storedColor: .gray)])
        XCTAssertEqual(look.mark, .emoji("🥸"))
        XCTAssertTrue(look.isCustomized)
        // The tag is named Green but carries color 1, as iCloud Drive leaves every tag: Finder
        // draws it green, the system's icon gray.
        XCTAssertEqual(look.style, FolderStyle(color: .green, mark: .emoji("🥸")))
        XCTAssertFalse(look.systemIconMatchesFinder)
    }

    /// A shared folder on 2026-11-19: Finder showed it red, Graphite gray.
    func testAColorTagShowsTheColorItIsNamedAfterWhateverItsNumber() {
        XCTAssertEqual(FinderTag(storedText: "Red\n1", colorTagNames: [:]).color, .red)
        XCTAssertEqual(FinderTag(storedText: "Rot\n1", colorTagNames: [.red: "Rot"]).color, .red)
        XCTAssertEqual(FinderTag(storedText: "Blue\n4", colorTagNames: [:]), FinderTag(name: "Blue", color: .blue))
        // Other names show their number's color; a tag stored without a color shows none.
        XCTAssertEqual(FinderTag(storedText: "Work\n1", colorTagNames: [:]).color, .gray)
        XCTAssertNil(FinderTag(storedText: "Orange", colorTagNames: [:]).color)
        XCTAssertNil(FinderTag(storedText: "Orange\n0", colorTagNames: [:]).color)
    }

    func testARewrittenNumberIsKeptWhenTheTagsAreWrittenBack() throws {
        let tags = FinderFolderLook.tags(from: try PropertyListSerialization.data(fromPropertyList: ["Red\n1", "Work"], format: .binary, options: 0),
                                         colorTagNames: [:])
        let tagsData = try XCTUnwrap(FinderFolderLook.tagsAttributeData(for: tags))
        XCTAssertEqual(try PropertyListSerialization.propertyList(from: tagsData, format: nil) as? [String], ["Red\n1", "Work"])
    }

    func testTheSystemIconMatchesFinderWhenEveryNumberIsItsTagsColor() {
        let rewritten = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red, storedColor: .gray)], iconMark: .symbol("frying.pan.fill"),
                                         hasCustomIconFlag: true, hasCustomIconFile: false)
        XCTAssertFalse(rewritten.systemIconMatchesFinder)
        let asWritten = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red), FinderTag(name: "Work", color: nil)], iconMark: .symbol("frying.pan.fill"),
                                         hasCustomIconFlag: true, hasCustomIconFile: false)
        XCTAssertTrue(asWritten.systemIconMatchesFinder)
        // A custom icon file carries its own colors.
        let picture = FinderFolderLook(tags: rewritten.tags, iconMark: nil, hasCustomIconFlag: true, hasCustomIconFile: true)
        XCTAssertTrue(picture.systemIconMatchesFinder)
    }

    func testTheMarkCountsOnlyWithTheCustomIconFlag() {
        let look = FinderFolderLook(tagsData: nil, iconData: Data(#"{"sym":"star.fill"}"#.utf8), finderInformationData: nil, hasCustomIconFile: false,
                                    colorTagNames: [:])
        XCTAssertNil(look.mark)
        XCTAssertFalse(look.isCustomized)
    }

    func testATagAloneDoesNotTintTheFolder() {
        let look = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red)], iconMark: nil, hasCustomIconFlag: false, hasCustomIconFile: false)
        XCTAssertFalse(look.isCustomized)
        XCTAssertEqual(look.style, FolderStyle(color: .red))
    }

    func testTheLastColoredTagIsTheColor() {
        let look = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red), FinderTag(name: "Green", color: .green), FinderTag(name: "Work", color: nil)],
                                    iconMark: .symbol("star.fill"), hasCustomIconFlag: true, hasCustomIconFile: false)
        XCTAssertEqual(look.color, .green)
    }

    func testFinderDrawsTheSymbolWhenBothAreThere() {
        XCTAssertEqual(FinderFolderLook.mark(from: Data(#"{"sym":"star.fill","emoji":"🥸"}"#.utf8)), .symbol("star.fill"))
        XCTAssertNil(FinderFolderLook.mark(from: Data(#"{"sym":""}"#.utf8)))
        XCTAssertNil(FinderFolderLook.mark(from: Data("not json".utf8)))
    }

    func testMalformedTagsAreNoTags() {
        XCTAssertEqual(FinderFolderLook.tags(from: Data("garbage".utf8), colorTagNames: [:]), [])
        XCTAssertEqual(FinderFolderLook.tags(from: Data(repeating: 0, count: FinderFolderLook.maximumTagsBytes + 1), colorTagNames: [:]), [])
        XCTAssertEqual(FinderTag(storedText: "Work\n9", colorTagNames: [:]), FinderTag(name: "Work", color: nil))
    }

    func testTheCustomIconFlagAndLabelKeepTheOtherBytes() throws {
        let existing = Data([UInt8](repeating: 0, count: 8) + [0x00, 0x05] + [UInt8](repeating: 0, count: 21) + [0x07])
        let set = try XCTUnwrap(FinderFolderLook.finderInformation(existing, settingCustomIconFlag: true, labelColor: .orange))
        XCTAssertEqual([UInt8](set)[8...9], [0x04, 0x0F])
        XCTAssertEqual([UInt8](set)[31], 0x07)
        let cleared = try XCTUnwrap(FinderFolderLook.finderInformation(set, settingCustomIconFlag: false, labelColor: nil))
        XCTAssertEqual([UInt8](cleared)[8...9], [0x00, 0x01])
        XCTAssertNil(FinderFolderLook.finderInformation(nil, settingCustomIconFlag: false, labelColor: nil))
    }

    func testTagsAreWrittenAsFinderWritesThem() throws {
        let tagsData = try XCTUnwrap(FinderFolderLook.tagsAttributeData(for: [FinderTag(name: "Work", color: nil), FinderTag(name: "Green", color: .green)]))
        XCTAssertEqual(FinderFolderLook.tags(from: tagsData, colorTagNames: [:]), [FinderTag(name: "Work", color: nil), FinderTag(name: "Green", color: .green)])
        XCTAssertEqual(try PropertyListSerialization.propertyList(from: tagsData, format: nil) as? [String], ["Work", "Green\n2"])
        XCTAssertNil(FinderFolderLook.tagsAttributeData(for: []))
    }

    func testTheIconAttributeIsWhatFinderWrites() {
        XCTAssertEqual(String(decoding: FinderFolderLook.iconAttributeData(for: .emoji("🥸")) ?? Data(), as: UTF8.self), #"{"emoji":"🥸"}"#)
        XCTAssertEqual(String(decoding: FinderFolderLook.iconAttributeData(for: .symbol("star.fill")) ?? Data(), as: UTF8.self), #"{"sym":"star.fill"}"#)
    }
}
