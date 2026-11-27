/**
 * File: NotePresentationTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: A note presented as slides: its slides built by the reading view's builder, moves between them,
 *              ending, the note left as it was; the keys, taps and swipes, the time, the slide number, the canvas
 *              mapping of the Pencil's marks, the shrinking of a tall slide and the Mac's screens.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class NotePresentationTests: XCTestCase {
    private var vault: TemporaryVault!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "NotePresentationVault", for: self)
        index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault.cacheDirectory) // Best-effort removal of a temporary folder.
    }

    private static let lecture = """
    ---
    course: Signals
    ---
    # Sampling

    A signal is sampled every $T$ seconds.

    ---

    ## The theorem

    $$
    f_s > 2 f_{max}
    $$

    ---

    > [!note] Aliasing
    > Too slow, and frequencies fold over.

    """

    private func presentation(of text: String, clock: ManualClock = ManualClock()) throws -> NotePresentation {
        let path = try VaultPath("Lectures/Sampling.md")
        _ = try vault.writeFile(path.rawValue, text: text)
        let source = NotePresentationSource(text: text, path: path, vault: try XCTUnwrap(ReadingVault(vault.root, index)), configuration: ReadingConfiguration())
        return NotePresentation.started(from: source, clock: clock,
                                        pencil: PresentationPencilChoices(tool: .laser, inkColor: .red, laserStyle: .dot))
    }

    private func waitForEverySlide(of presentation: NotePresentation) async throws {
        try await waitUntil("every slide is built") {
            presentation.slides.allSatisfy { content in if case .building = content { false } else { true } }
        }
    }

    func testEachSlideIsBuiltAsTheReadingViewBuildsItsText() async throws {
        let presentation = try presentation(of: Self.lecture)
        XCTAssertEqual(presentation.slides.count, 3)
        XCTAssertEqual(presentation.title, "Sampling")
        try await waitForEverySlide(of: presentation)
        guard case .built(let first) = presentation.slides[0], case .built(let second) = presentation.slides[1],
              case .built(let third) = presentation.slides[2] else { return XCTFail("Every slide is built: \(presentation.slides)") }
        XCTAssertFalse(first.contains { block in if case .properties = block { true } else { false } }, "No properties on a slide.")
        XCTAssertTrue(first.contains { block in
            if case .heading(_, 1, let text, _) = block { text.trimmingCharacters(in: .whitespaces) == "Sampling" } else { false }
        }, "\(first)")
        XCTAssertTrue(second.contains { block in if case .displayMath = block { true } else { false } }, "\(second)")
        XCTAssertTrue(third.contains { block in if case .callout(_, "note", _, _, _) = block { true } else { false } }, "\(third)")
    }

    func testMovingChangesTheSlideAndCountsTheMoves() throws {
        let presentation = try presentation(of: Self.lecture)
        presentation.move(.previous)
        XCTAssertEqual(presentation.moveCount, 0, "Nothing before the first slide.")
        presentation.move(.next)
        presentation.move(.last)
        XCTAssertEqual(presentation.position.index, 2)
        XCTAssertNil(presentation.nextSlide)
        XCTAssertEqual(presentation.moveCount, 2)
        presentation.move(.first)
        XCTAssertEqual(presentation.position.index, 0)
        XCTAssertNotNil(presentation.nextSlide)
    }

    func testEndingReleasesTheSlidesAndLeavesTheNoteAsItWas() async throws {
        let presentation = try presentation(of: Self.lecture)
        try await waitForEverySlide(of: presentation)
        presentation.move(.next)
        presentation.end()
        XCTAssertTrue(presentation.hasEnded)
        XCTAssertTrue(presentation.slides.isEmpty)
        presentation.move(.next)
        XCTAssertEqual(presentation.moveCount, 1, "An ended presentation does not move.")
        XCTAssertEqual(try vault.readText(at: "Lectures/Sampling.md"), Self.lecture, "Presenting writes nothing.")
    }

    func testTheTimeCountsFromTheStartOnTheInjectedClock() throws {
        let clock = ManualClock(startingAt: .seconds(100))
        let presentation = try presentation(of: Self.lecture, clock: clock)
        clock.advance(by: .seconds(65))
        XCTAssertEqual(PresentationElapsedTime.text(for: presentation.clock.now - presentation.startedAt), "01:05")
        XCTAssertEqual(PresentationElapsedTime.text(for: .seconds(3_725)), "1:02:05")
        XCTAssertEqual(PresentationElapsedTime.text(for: .seconds(-3)), "00:00")
    }

    func testASlideIsBuiltWithoutPropertiesTitleOrPluginsAtTheSlidesTextSize() {
        var noteConfiguration = ReadingConfiguration()
        noteConfiguration.inlineTitle = "Sampling"
        noteConfiguration.runsPluginPostProcessors = true
        noteConfiguration.usesStrictLineBreaks = true
        let configuration = NotePresentation.slideConfiguration(from: noteConfiguration)
        XCTAssertFalse(configuration.showsProperties)
        XCTAssertNil(configuration.inlineTitle)
        XCTAssertFalse(configuration.runsPluginPostProcessors)
        XCTAssertTrue(configuration.usesStrictLineBreaks, "The vault's own reading settings stay.")
        XCTAssertEqual(configuration.textSize, NotePresentation.slideTextSize)
    }

    func testTheKeysAreThoseOfObsidiansSlides() {
        let forward: [KeyEquivalent] = [.rightArrow, .downArrow, .pageDown, .return, .space, "n", "N"]
        for key in forward { XCTAssertEqual(PresentationKeys.request(for: key, modifiers: []), .move(.next), "\(key)") }
        let back: [KeyEquivalent] = [.leftArrow, .upArrow, .pageUp, .delete, "p"]
        for key in back { XCTAssertEqual(PresentationKeys.request(for: key, modifiers: []), .move(.previous), "\(key)") }
        XCTAssertEqual(PresentationKeys.request(for: .space, modifiers: .shift), .move(.previous))
        XCTAssertEqual(PresentationKeys.request(for: .home, modifiers: []), .move(.first))
        XCTAssertEqual(PresentationKeys.request(for: .end, modifiers: []), .move(.last))
        XCTAssertEqual(PresentationKeys.request(for: .escape, modifiers: []), .end)
        XCTAssertNil(PresentationKeys.request(for: "x", modifiers: []))
    }

    func testATapOnTheLeftQuarterGoesBackAndASwipeLeftGoesForward() {
        XCTAssertEqual(PresentationTouches.move(forTapAtX: 100, width: 1_000), .previous)
        XCTAssertEqual(PresentationTouches.move(forTapAtX: 260, width: 1_000), .next)
        XCTAssertEqual(PresentationTouches.move(forTapAtX: 10, width: 0), .next)
        XCTAssertEqual(PresentationTouches.move(forSwipeDistance: -80), .next)
        XCTAssertEqual(PresentationTouches.move(forSwipeDistance: 80), .previous)
    }

    func testTheSlideNumberSaysWhichSlideOfHowMany() {
        XCTAssertEqual(PresentationSlideNumber.text(for: SlidePosition(slideCount: 12, index: 2)), "3 of 12")
        XCTAssertEqual(PresentationSlideNumber.text(for: SlidePosition(slideCount: 0)), "No slides")
    }

    func testAPointOfTheSlideIsTheSameCanvasPointOnEveryScreen() {
        // The device in landscape, and a 1080p external display: both keep the canvas's shape.
        let device = PresentationCanvasMapping(viewSize: CGSize(width: 1_194, height: 834))
        let display = PresentationCanvasMapping(viewSize: CGSize(width: 1_920, height: 1_080))
        XCTAssertEqual(display.canvasFrame, CGRect(x: 0, y: 0, width: 1_920, height: 1_080))
        XCTAssertEqual(device.canvasFrame.width / device.canvasFrame.height, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(device.canvasFrame.midY, 417, accuracy: 0.001, "Centred, with bars above and below.")
        let touched = CGPoint(x: 600, y: 400)
        let canvasPoint = device.canvasPoint(fromViewPoint: touched)
        let roundTrip = device.viewPoint(fromCanvasPoint: canvasPoint)
        XCTAssertEqual(roundTrip.x, touched.x, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, touched.y, accuracy: 0.001)
        let onDisplay = display.viewPoint(fromCanvasPoint: canvasPoint)
        XCTAssertEqual(onDisplay.x / 1_920, (touched.x - device.canvasFrame.minX) / device.canvasFrame.width, accuracy: 0.001)
        XCTAssertEqual(onDisplay.y / 1_080, (touched.y - device.canvasFrame.minY) / device.canvasFrame.height, accuracy: 0.001)
    }

    func testATallSlideShrinksToTheColumnAndAShortOneDoesNot() {
        XCTAssertEqual(NoteSlideCanvas.fittingScale(contentHeight: 300, columnHeight: 624), 1)
        XCTAssertEqual(NoteSlideCanvas.fittingScale(contentHeight: 1_248, columnHeight: 624), 0.5)
        XCTAssertEqual(NoteSlideCanvas.fittingScale(contentHeight: 0, columnHeight: 624), 1)
    }

    func testThePencilsChoicesAreReadFromTheDevicesPreferences() throws {
        let suiteName = "NotePresentationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(PresentationPencilChoices.stored(in: defaults), PresentationPencilChoices(tool: .laser, inkColor: .red, laserStyle: .dot))
        defaults.set("fadingInk", forKey: "GraphitePresentationPencilTool")
        defaults.set("blue", forKey: "GraphitePresentationInkColor")
        defaults.set("line", forKey: LaserPointerStyle.preferenceKey)
        XCTAssertEqual(PresentationPencilChoices.stored(in: defaults), PresentationPencilChoices(tool: .fadingInk, inkColor: .blue, laserStyle: .line))
        defaults.set("chalk", forKey: "GraphitePresentationPencilTool")
        XCTAssertEqual(PresentationPencilTool.stored(in: defaults), .laser, "A tool this build does not know reads as the laser.")
    }

    #if os(macOS)
    func testTheMacPutsThePresenterOnGraphitesScreenAndTheSlideOnAnother() {
        XCTAssertNil(MacPresentationScreenPlan(screenCount: 0, mainScreenIndex: nil))
        XCTAssertEqual(MacPresentationScreenPlan(screenCount: 1, mainScreenIndex: 0)?.audienceScreenIndex, nil)
        let twoScreens = MacPresentationScreenPlan(screenCount: 2, mainScreenIndex: 1)
        XCTAssertEqual(twoScreens?.presenterScreenIndex, 1)
        XCTAssertEqual(twoScreens?.audienceScreenIndex, 0)
        XCTAssertEqual(MacPresentationScreenPlan(screenCount: 3, mainScreenIndex: nil)?.presenterScreenIndex, 0)
        XCTAssertEqual(MacPresentationScreenPlan(screenCount: 3, mainScreenIndex: 7)?.audienceScreenIndex, 1)
    }
    #endif
}
