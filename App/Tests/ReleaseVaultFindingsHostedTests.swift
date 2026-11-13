/**
 * File: ReleaseVaultFindingsHostedTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The defects the release test vault's checks found on the iPad on 2026-11-12 (Docs/Bug-hunt-todo.md
 *              section 15) that only UIKit shows: where touches go, and how a picture is fitted.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import Textual
import GraphiteCore
@testable import GraphiteUI

/// Section 15 of the bug hunt, on the iPad: each test fails before its fix.
@MainActor
final class ReleaseVaultFindingsHostedTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try ReleaseVaultFindingsHosting.setAccessibilityRuntimeEnabled(false)
    }

    /// HUNT-328: the strip along a table's right edge took no tap while a cell was edited: it lies
    /// outside the table, where the text selection's overlay of the block took every touch.
    func testATouchOnTheRightStripReachesTheStripRatherThanTheTextSelection() async throws {
        try ReleaseVaultFindingsHosting.setAccessibilityRuntimeEnabled(true)
        var source = "| Left | Right |\n| --- | --- |\n| a | b |\n"
        let editor = LivePreviewTableEditor()
        func viewUpdates() {
            editor.update(source: source, textSize: 17, sourceEditing: RenderedBlockSourceEditing(replaceSource: { _, transform in
                source = transform(source) ?? source
                viewUpdates()
            }, setIsEditingInView: { _, _ in }))
        }
        viewUpdates()
        editor.beginEditing(TableCellPosition(row: 1, column: 0))
        let table = StructuredText(source, parser: ObsidianMarkdownParser(baseURL: nil, textSize: 17))
            .textual.tableStyle(ObsidianTableStyle())
            .textual.textSelection(.enabled)
            .environment(\.livePreviewTableEditor, editor)
            .frame(width: 600, alignment: .topLeading)
            .coordinateSpace(.named(LivePreviewTableEditor.blockCoordinateSpaceName))
        let host = try show(AnyView(table.padding(40)))

        var columnStrip: NSObject?
        try await waitUntil("the strips are shown") {
            columnStrip = ReleaseVaultFindingsHosting.accessibilityElements(in: host.view).first { element in
                element.accessibilityLabel == "Add column to the right"
            }
            return columnStrip != nil
        }
        let stripFrame = try XCTUnwrap(columnStrip).accessibilityFrame
        let touchedView = try XCTUnwrap(window?.hitTest(CGPoint(x: stripFrame.midX, y: stripFrame.midY), with: nil))
        let touchedClasses = sequence(first: touchedView, next: \.superview).map { view in String(describing: type(of: view)) }
        XCTAssertFalse(touchedClasses.contains { name in name.contains("TextInteraction") }, "The strip's touch went to \(touchedClasses)")
    }

    /// HUNT-331: the zoom over a note drew a 480 by 270 picture at its pixel size, smaller than the
    /// note drew it. It is fitted to the window, less its margins.
    func testTheZoomFitsASmallPictureToTheWindow() async throws {
        let folder = try TemporaryVault.make(prefix: "ZoomFit", for: self)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 270), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let pngData = renderer.pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 480, height: 270))
        }
        let location = try folder.writeFile("Small.png", data: pngData)
        let host = try show(AnyView(ImageZoomOverlay(location: location, title: "Small.png", close: {})))

        var scrollView: ZoomingImageScrollView?
        try await waitUntil("the picture is shown") {
            host.view.layoutIfNeeded()
            scrollView = Self.descendants(of: host.view).compactMap { view in view as? ZoomingImageScrollView }.first { view in
                view.image != nil && view.bounds.width > 0
            }
            return scrollView != nil
        }
        let shown = try XCTUnwrap(scrollView)
        shown.layoutIfNeeded()
        let shownSize = CGSize(width: 480 * shown.zoomScale, height: 270 * shown.zoomScale)
        XCTAssertGreaterThan(shownSize.width, 480, "A picture smaller than the window is enlarged.")
        XCTAssertTrue(abs(shownSize.width - (shown.bounds.width - 48)) < 2 || abs(shownSize.height - (shown.bounds.height - 48)) < 2,
                      "Fitted to the window less its margins: \(shownSize) in \(shown.bounds.size)")
    }

    /// Docs/Editor-scrolling-todo.md, found by the release pass: in `Pictures.md` the picture blocks low on Live
    /// Preview's fourth page stayed blank, their source hidden and no view over them, until the next scroll. Scrolled
    /// to in code, a page kept the viewport TextKit had laid out for the page before; the editor saw the shortfall
    /// but let it go while its last relayout was a moment old, and nothing looked again. The pass's own steps over the
    /// note now find every block of every page with its view.
    func testEveryPictureBlockOfThePicturesNoteHasItsViewOnEveryPageAsThePassScrollsIt() async throws {
        // Another app's SVG never decodes, a deliberate failure of the vault, which the pass waits for in vain.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { issue in issue.compactDescription.contains("every picture on screen is decoded") }
        XCTExpectFailure("The vault's SVG of another app is not drawn", options: options)
        let pass = try await ReleaseVaultPass.open(for: self)
        try await pass.runNotes([try VaultPath("Pictures.md")])
        pass.printReport()
        let blocksLeftBlank = pass.findings.filter { finding in
            if case .blockLeftAsSource = finding.problem { true } else { false }
        }
        XCTAssertEqual(blocksLeftBlank, [], "Each finding is printed on a GRAPHITE-RELEASE-FINDING line.")
        // Docs/Editor-scrolling-todo.md: in about a third of these runs the switch from the reading view to source mode
        // left the reading view on screen with no editor. The pane was drawn from inside Observation's notice of the
        // switch, before the session stored the new mode, read the mode it was leaving, and was not drawn again.
        let viewsNotShown = pass.findings.filter { finding in
            if case .notShown = finding.problem { true } else { false }
        }
        XCTAssertEqual(viewsNotShown, [], "Every view of the note shows, source mode after the reading view too.")
    }

    private static func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { child in [child] + descendants(of: child) }
    }

    private func show(_ view: AnyView) throws -> UIHostingController<AnyView> {
        let host = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        return host
    }
}

/// Finding SwiftUI's controls as VoiceOver finds them.
@MainActor
enum ReleaseVaultFindingsHosting {
    static func accessibilityElements(in object: NSObject) -> [NSObject] {
        var elements: [NSObject] = object.isAccessibilityElement ? [object] : []
        let count = object.accessibilityElementCount()
        if let children = object.accessibilityElements {
            elements += children.compactMap { child in child as? NSObject }.flatMap(accessibilityElements)
        } else if count != NSNotFound, count > 0 {
            elements += (0..<count).compactMap { elementIndex in object.accessibilityElement(at: elementIndex) as? NSObject }.flatMap(accessibilityElements)
        } else if let view = object as? UIView {
            elements += view.subviews.flatMap(accessibilityElements)
        }
        return elements
    }

    /// SwiftUI builds its accessibility elements only while an assistive technology asks for them.
    static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }
}
#endif
