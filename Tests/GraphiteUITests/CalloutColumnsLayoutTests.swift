/**
 * File: CalloutColumnsLayoutTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A multi-column callout's blocks sit side by side where the note is wide enough and stack under each
 *              other when it is narrow, measured by the size the layout asks for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class CalloutColumnsLayoutTests: XCTestCase {
    private static let blockHeightPoints: CGFloat = 40

    private func height(ofColumns count: Int, width: CGFloat) throws -> CGFloat {
        let columns = CalloutColumnsLayout {
            ForEach(0..<count, id: \.self) { _ in Color.gray.frame(height: Self.blockHeightPoints) }
        }
        let renderer = ImageRenderer(content: columns.frame(width: width))
        let image = try XCTUnwrap(renderer.cgImage)
        return CGFloat(image.height) / renderer.scale
    }

    func testThreeBlocksShareOneRowOfAWideNote() throws {
        XCTAssertEqual(try height(ofColumns: 3, width: 716), Self.blockHeightPoints)
    }

    func testTheyStackOnAPhonesWidth() throws {
        let gap = CalloutColumnArrangement.columnGapPoints
        XCTAssertEqual(try height(ofColumns: 3, width: 361), Self.blockHeightPoints * 3 + gap * 2)
    }

    func testTheLastWrapsWhereOnlyTwoFit() throws {
        XCTAssertEqual(try height(ofColumns: 3, width: 500), Self.blockHeightPoints * 2 + CalloutColumnArrangement.columnGapPoints)
    }
}
