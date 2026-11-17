/**
 * File: LassoSelectionKindsTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The Lasso panel's "Included in Selection" switches: what each lets the lasso take, that the last one
 *              on stays on, and how they are kept on the device.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */
import XCTest
@testable import GraphiteUI

final class LassoSelectionKindsTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suiteName = "LassoSelectionKindsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testEveryKindIsOnUntilOneIsSwitchedOffAndTheChoiceIsKept() throws {
        let defaults = try defaults()
        XCTAssertEqual(LassoSelectionKinds.stored(in: defaults), .all)
        LassoSelectionKinds.all.setting(.images, included: false).store(in: defaults)
        XCTAssertEqual(LassoSelectionKinds.stored(in: defaults), [.handwriting, .textBoxes])
    }

    func testAKeptValueWithNoKnownKindReadsAsEveryKind() throws {
        let defaults = try defaults()
        defaults.set(1 << 9, forKey: LassoSelectionKinds.preferenceKey)
        XCTAssertEqual(LassoSelectionKinds.stored(in: defaults), .all)
    }

    func testTheLastKindOnCannotBeSwitchedOff() {
        let handwritingOnly: LassoSelectionKinds = [.handwriting]
        XCTAssertFalse(handwritingOnly.canExclude(.handwriting))
        XCTAssertEqual(handwritingOnly.setting(.handwriting, included: false), handwritingOnly)
        XCTAssertTrue(LassoSelectionKinds.all.canExclude(.handwriting))
        XCTAssertFalse(handwritingOnly.canExclude(.images), "a kind that is off has nothing to switch off")
    }

    func testTextBoxesAndImagesAreToldApartByTheTextBoxPrefix() {
        let textBox = LassoSelectionKinds.textBoxIdentifierPrefix + "Box 1"
        let imagesOnly: LassoSelectionKinds = [.images]
        XCTAssertTrue(imagesOnly.takesPicture(identifiedAs: "Picture 1"))
        XCTAssertFalse(imagesOnly.takesPicture(identifiedAs: textBox))
        let textBoxesOnly: LassoSelectionKinds = [.textBoxes]
        XCTAssertTrue(textBoxesOnly.takesPicture(identifiedAs: textBox))
        XCTAssertFalse(textBoxesOnly.takesPicture(identifiedAs: "Picture 1"))
    }
}
