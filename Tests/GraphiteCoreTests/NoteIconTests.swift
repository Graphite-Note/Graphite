/**
 * File: NoteIconTests.swift
 * -------------------------
 * Layer: Tests
 * Description: A note's `icon` property is read as Iconize and Pixel Banner write it (an emoji, a Lucide name of
 *              Iconize's built-in pack) or as an SF Symbol name, and is written back so Obsidian draws the same icon.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class NoteIconTests: XCTestCase {
    func testAnEmojiIsReadAsTheFirstEmojiOfTheText() {
        XCTAssertEqual(NoteIcon(propertyText: "📚"), .emoji("📚"))
        XCTAssertEqual(NoteIcon(propertyText: "  🧪 lab "), .emoji("🧪"), "Iconize keeps the first emoji of the text.")
        XCTAssertEqual(NoteIcon(propertyText: "❤️"), .emoji("❤️"), "A text-default scalar with its emoji variation selector.")
        XCTAssertEqual(NoteIcon(propertyText: "👩🏽‍🔬"), .emoji("👩🏽‍🔬"), "A joined sequence with a skin tone is one emoji.")
        XCTAssertEqual(NoteIcon(propertyText: "\"📝\""), .emoji("📝"), "Quotes kept from YAML are dropped.")
    }

    func testIconizeLucideNamesAreDrawnAsTheirPairedSymbol() {
        XCTAssertEqual(NoteIcon(propertyText: "LiBookOpen"), .symbol(systemName: "book"))
        XCTAssertEqual(NoteIcon(propertyText: "LiGraduationCap"), .symbol(systemName: "graduationcap"))
    }

    func testSymbolNamesAreReadAsTheyAreWritten() {
        XCTAssertEqual(NoteIcon(propertyText: "book.closed"), .symbol(systemName: "book.closed"))
        XCTAssertEqual(NoteIcon(propertyText: "testtube.2"), .symbol(systemName: "testtube.2"))
    }

    func testIconsGraphiteCannotDrawAreNone() {
        XCTAssertNil(NoteIcon(propertyText: ""))
        XCTAssertNil(NoteIcon(propertyText: "   "))
        XCTAssertNil(NoteIcon(propertyText: "FasBell"), "Font Awesome is a downloaded Iconize pack Graphite does not have.")
        XCTAssertNil(NoteIcon(propertyText: "LiSquirrel"), "A Lucide icon without a pairing.")
        XCTAssertNil(NoteIcon(propertyText: "Book Closed"), "Not a symbol name: capitals and a space.")
        XCTAssertNil(NoteIcon(propertyText: "book..closed"))
        XCTAssertNil(NoteIcon(propertyText: "7"), "A digit counts as an emoji only with its keycap.")
        XCTAssertNil(NoteIcon(propertyText: "#"))
    }

    func testAChosenSymbolIsWrittenAsIconizesLucideName() {
        XCTAssertEqual(NoteIcon.symbol(systemName: "book.closed").propertyText, "LiBook")
        XCTAssertEqual(NoteIcon.symbol(systemName: "wand.and.stars").propertyText, "wand.and.stars", "A symbol without a pairing keeps its own name.")
        XCTAssertEqual(NoteIcon.emoji("📚").propertyText, "📚")
    }

    func testEveryPairingReadsBackAsItsSymbolAndNamesAreUnique() {
        let pairings = NoteIconSymbols.pairings
        XCTAssertEqual(Set(pairings.map(\.systemName)).count, pairings.count, "Each SF Symbol is offered once.")
        XCTAssertEqual(Set(pairings.map(\.lucideName)).count, pairings.count, "Each Lucide icon is offered once.")
        for pairing in pairings {
            XCTAssertEqual(NoteIcon(propertyText: NoteIcon.symbol(systemName: pairing.systemName).propertyText),
                           .symbol(systemName: pairing.systemName), pairing.systemName)
        }
    }

    func testPictureIconsAreReadAsTheNotionImporterWritesThem() throws {
        XCTAssertEqual(NoteIcon(propertyText: "\"[[Icons/clock.gif]]\""), .picture(.vaultFile(linkTarget: "Icons/clock.gif")))
        XCTAssertEqual(NoteIcon(propertyText: "[[logo.svg]]"), .picture(.vaultFile(linkTarget: "logo.svg")))
        let notion = try XCTUnwrap(URL(string: "https://www.example.com/icons/clock_gray.svg"))
        XCTAssertEqual(NoteIcon(propertyText: notion.absoluteString), .picture(.webAddress(notion)))
        XCTAssertEqual(NoteIcon(propertyText: "Icons/clock.png"), .picture(.vaultFile(linkTarget: "Icons/clock.png")))
        XCTAssertNil(NoteIcon(propertyText: "[[Some note]]"), "A link to a note is no icon.")
        XCTAssertEqual(NoteIcon(propertyText: "photo"), .symbol(systemName: "photo"), "A symbol name is no path.")
        XCTAssertEqual(NoteIcon.picture(.webAddress(notion)).propertyText, notion.absoluteString)
        XCTAssertEqual(NoteIcon.picture(.vaultFile(linkTarget: "Icons/clock.gif")).propertyText, "[[Icons/clock.gif]]")
    }
}
