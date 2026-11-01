import XCTest
@testable import GraphiteCore

/// The editor options Obsidian keeps in `.obsidian/app.json`: readable line length, inline
/// title, spellcheck, default view and Live Preview. Graphite reads them where the file has
/// them and writes them as Obsidian does, leaving every other key and the layout alone.
final class ObsidianEditorSettingsKeysTests: XCTestCase {
    func testKeysTheFileLacksAreNilSoTheDeviceChoiceApplies() throws {
        let settings = try ObsidianSettings(applicationConfigurationData: Data("{\"vimMode\": true}".utf8))
        XCTAssertNil(settings.usesReadableLineLength)
        XCTAssertNil(settings.showsInlineTitle)
        XCTAssertNil(settings.usesSpellChecking)
        XCTAssertNil(settings.defaultViewMode)
        XCTAssertNil(settings.usesLivePreview)
    }

    func testTheKeysAreReadAsObsidianWritesThem() throws {
        let file = Data("{\"readableLineLength\": false, \"showInlineTitle\": true, \"spellcheck\": false, \"defaultViewMode\": \"preview\", \"livePreview\": false}".utf8)
        let settings = try ObsidianSettings(applicationConfigurationData: file)
        XCTAssertEqual(settings.usesReadableLineLength, false)
        XCTAssertEqual(settings.showsInlineTitle, true)
        XCTAssertEqual(settings.usesSpellChecking, false)
        XCTAssertEqual(settings.defaultViewMode, .preview)
        XCTAssertEqual(settings.usesLivePreview, false)
    }

    func testAValueGraphiteDoesNotKnowIsLeftAlone() throws {
        let file = Data("{\"defaultViewMode\": \"future\"}".utf8)
        var settings = try ObsidianSettings(applicationConfigurationData: file)
        XCTAssertNil(settings.defaultViewMode)
        settings.confirmsDeletion = false
        let merged = try settings.mergedApplicationConfigurationData(existingData: file)
        XCTAssertEqual(String(decoding: merged, as: UTF8.self), "{\n  \"defaultViewMode\": \"future\",\n  \"promptDelete\": false\n}")
    }

    func testUnrelatedChangesNeverAddTheKeys() throws {
        let file = Data("{\n  \"vimMode\": true\n}".utf8)
        var settings = try ObsidianSettings(applicationConfigurationData: file)
        settings.linkFormat = .absolute
        let merged = String(decoding: try settings.mergedApplicationConfigurationData(existingData: file), as: UTF8.self)
        XCTAssertEqual(merged, "{\n  \"vimMode\": true,\n  \"newLinkFormat\": \"absolute\"\n}")
    }

    func testChoosingAnOptionAddsOrReplacesOnlyThatKeyAndKeepsTheLayout() throws {
        let file = Data("{\n  \"zeta\": 0.1,\n  \"readableLineLength\": true,\n  \"nested\": {\"list\": [1, 2e3]},\n  \"vimMode\": true\n}".utf8)
        var settings = try ObsidianSettings(applicationConfigurationData: file)
        let loaded = settings
        settings.usesReadableLineLength = false
        settings.showsInlineTitle = false
        settings.usesSpellChecking = true
        settings.defaultViewMode = .source
        settings.usesLivePreview = true
        let merged = try settings.mergedApplicationConfigurationData(existingData: file, changedFrom: loaded)
        XCTAssertEqual(String(decoding: merged, as: UTF8.self),
                       "{\n  \"zeta\": 0.1,\n  \"readableLineLength\": false,\n  \"nested\": {\"list\": [1, 2e3]},\n  \"vimMode\": true,\n  \"showInlineTitle\": false,\n  \"spellcheck\": true,\n  \"defaultViewMode\": \"source\",\n  \"livePreview\": true\n}")
        XCTAssertEqual(try ObsidianSettings(applicationConfigurationData: merged), settings)
        XCTAssertEqual(try settings.mergedApplicationConfigurationData(existingData: merged), merged, "A save with nothing changed leaves the bytes alone.")
    }

    func testAnOptionObsidianChangedMeanwhileSurvivesAnUnrelatedSave() throws {
        let loadedFile = Data("{\"spellcheck\": true}".utf8)
        var settings = try ObsidianSettings(applicationConfigurationData: loadedFile)
        let loaded = settings
        settings.confirmsDeletion = false
        let fileNow = Data("{\"spellcheck\": false}".utf8)
        let merged = try settings.mergedApplicationConfigurationData(existingData: fileNow, changedFrom: loaded)
        XCTAssertEqual(String(decoding: merged, as: UTF8.self), "{\n  \"spellcheck\": false,\n  \"promptDelete\": false\n}")
    }
}
