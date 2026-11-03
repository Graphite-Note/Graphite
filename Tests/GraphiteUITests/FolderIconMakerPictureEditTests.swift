/**
 * File: FolderIconMakerPictureEditTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A finished edit of the folder icon's picture never replaces a picture dropped meanwhile (HUNT-109).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import CoreGraphics
@testable import GraphiteUI

final class FolderIconMakerPictureEditTests: XCTestCase {
    private func bitmap(width: Int) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    func testTheEditedPictureIsShownWhenNothingReplacedTheOneItWasMadeFrom() throws {
        let source = try bitmap(width: 4), edited = try bitmap(width: 5)

        XCTAssertTrue(FolderIconMaker.picture(afterEditOf: source, resultingIn: edited, current: source) === edited)
    }

    /// Background removal runs for seconds; a picture dropped meanwhile was replaced by the old picture's result.
    func testAPictureDroppedMeanwhileStaysWhenTheEditFinishes() throws {
        let source = try bitmap(width: 4), edited = try bitmap(width: 5), dropped = try bitmap(width: 6)

        XCTAssertTrue(FolderIconMaker.picture(afterEditOf: source, resultingIn: edited, current: dropped) === dropped)
    }
}
