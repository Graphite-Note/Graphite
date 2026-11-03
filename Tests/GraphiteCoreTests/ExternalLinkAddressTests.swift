/**
 * File: ExternalLinkAddressTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Which link targets are web or app addresses and not names of vault files.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteCore

final class ExternalLinkAddressTests: XCTestCase {
    func testWebAndAppAddressesAreExternal() {
        for target in ["https://example.com/page", "http://example.com/a/b#top", "mailto:a@b.c", "obsidian://open?vault=V", "https%3A//example.com/x"] {
            XCTAssertTrue(WikiLinkResolver.isExternalAddress(target, isWiki: false), target)
        }
    }

    func testNamesOfFilesAreNot() {
        for target in ["Note", "Folder/Note.md", "../Up/Note#Heading", "Note%20Two.md", "#Heading", "Homework 2.1"] {
            XCTAssertFalse(WikiLinkResolver.isExternalAddress(target, isWiki: false), target)
            XCTAssertNil(WikiLinkResolver.externalLocation(of: target, isWiki: false), target)
        }
    }

    func testTheLocationKeepsItsFragment() {
        XCTAssertEqual(WikiLinkResolver.externalLocation(of: "https://example.com/a#top", isWiki: false)?.absoluteString, "https://example.com/a#top")
    }

    func testAWikilinkIsNotReadPercentDecoded() {
        XCTAssertFalse(WikiLinkResolver.isExternalAddress("https%3A//example.com", isWiki: true), "A Wikilink is written as the file is named.")
    }
}
