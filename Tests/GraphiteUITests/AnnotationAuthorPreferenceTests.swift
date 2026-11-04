import XCTest
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// The name written as the author of what is added to a PDF (invariant ST-31): kept on this device, empty by default, read by
/// the writer of annotations from the same key and the same store.
@MainActor
final class AnnotationAuthorPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = try IsolatedDeviceState.make(prefix: "AnnotationAuthorPreferenceTests", for: self).preferences
    }

    override func tearDown() async throws {
        defaults = nil
    }

    func testTheNameIsEmptyByDefaultAndSettingsStoresItUnderTheKeyTheWriterReads() {
        let preferences = GraphitePreferences(defaults: defaults)
        XCTAssertEqual(preferences.annotationAuthorName, "")
        XCTAssertNil(defaults.object(forKey: "GraphiteAnnotationAuthorName"))

        preferences.annotationAuthorName = "Ada Lovelace"

        XCTAssertEqual(defaults.string(forKey: "GraphiteAnnotationAuthorName"), "Ada Lovelace")
        XCTAssertEqual(PDFAnnotationAuthor(defaults: defaults, ownerName: { nil }).name, "Ada Lovelace", "What the writer of annotations reads is what Settings stored.")
    }

    func testTheNameIsKeptForTheNextLaunch() {
        GraphitePreferences(defaults: defaults).annotationAuthorName = "Ada Lovelace"

        XCTAssertEqual(GraphitePreferences(defaults: defaults).annotationAuthorName, "Ada Lovelace")
    }

    func testClearingTheNameRemovesTheKeyAndABlankNameIsNotStored() {
        let preferences = GraphitePreferences(defaults: defaults)
        preferences.annotationAuthorName = "Ada Lovelace"

        preferences.annotationAuthorName = "   "
        XCTAssertNil(defaults.object(forKey: "GraphiteAnnotationAuthorName"), "Blank spaces are no name.")

        preferences.annotationAuthorName = "Ada"
        preferences.annotationAuthorName = ""
        XCTAssertNil(defaults.object(forKey: "GraphiteAnnotationAuthorName"))
        XCTAssertEqual(GraphitePreferences(defaults: defaults).annotationAuthorName, "")
    }

    func testTheNameIsNotPartOfAnyVaultOrPerVaultKey() {
        GraphitePreferences(defaults: defaults).annotationAuthorName = "Ada Lovelace"

        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { key in key.contains("GraphiteAnnotationAuthorName.") }, "One name for the device, not for a vault.")
    }
}
