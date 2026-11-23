/**
 * File: ReadingDiagramThemeRepaintTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A theme change (light to dark, a vault theme's diagram colours) repaints a shown diagram, in a window, without
 *              laying it out or reading it again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import Synchronization
import GraphiteCore
import GraphiteTestSupport
import MermaidDiagrams
@testable import GraphiteUI

/// The colours a diagram is painted in come from the view's environment (`ReadingDiagramColors(theme:colorScheme:)`), the
/// scene from its preparation: a theme change paints the scene shown again in the new colours, and nothing lays it out
/// (no narrow layout is asked for) or reads it (the view holds the diagram prepared; only the note's builder reads).
@MainActor
final class ReadingDiagramThemeRepaintTests: XCTestCase {
    /// The column: narrower than the flowchart's regular scene at the readable scale, so the view shows its narrow scene and
    /// lays it out again for 496 points, the layout a theme change must not repeat.
    private let columnWidth: CGFloat = 500

    private func theme(background: ThemeColor, text: ThemeColor) -> NoteThemeStyle {
        var light = ThemeModeTokens(), dark = ThemeModeTokens()
        light.diagramColors = ["bg": background, "fg": text, "line": text]
        dark.diagramColors = ["bg": background, "fg": text, "line": text]
        return NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "repaint-\(background)", themeName: "Repaint", light: light, dark: dark))
    }

    func testAThemeChangeRepaintsTheShownDiagramWithoutLayingItOutOrReadingItAgain() async throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
        let diagram = ReadingDiagram(source: ReadingDiagramNarrowColumnTests.fourteenShapesInARow, typography: typography)
        guard case .drawn(let prepared, _) = diagram else { return XCTFail("The flowchart is drawn") }
        XCTAssertTrue(ReadingScaledDiagram<EmptyView>.showsNarrowScene(of: prepared, inColumnWidth: columnWidth, scaleAtNaturalWidth: 1))
        let layouts = NarrowLayoutCount()
        let countedLayout = ReadingDiagramNarrowLayout(name: "counted") { request in
            layouts.increment()
            return ReadingDiagramNarrowRequest.narrowScene(of: request)
        }
        let appearance = ThemeRepaintAppearance()
        let hostingView = host(ThemeRepaintHost(appearance: appearance, diagram: diagram, layout: countedLayout))
        try await waitUntil("the narrow scene is laid out for the column", timeoutSeconds: 10) { layouts.count == 1 }
        let light = try await settledPicture(of: hostingView)

        appearance.colorScheme = .dark
        let dark = try await picture(of: hostingView, differingFrom: light, "the diagram is painted dark")
        appearance.theme = theme(background: ThemeColor(red: 0.1, green: 0.1, blue: 0.4), text: ThemeColor(red: 1, green: 0.8, blue: 0))
        let themed = try await picture(of: hostingView, differingFrom: dark, "the diagram is painted in the theme's colours")
        appearance.theme = theme(background: ThemeColor(red: 0.3, green: 0, blue: 0), text: ThemeColor(red: 0, green: 1, blue: 0.6))
        let rethemed = try await picture(of: hostingView, differingFrom: themed, "the diagram is painted in the theme's new colours")

        XCTAssertEqual([dark.size, themed.size, rethemed.size], [light.size, light.size, light.size], "The same scene, at the same size")
        // A layout would start at once: no request is waiting for the column to settle.
        let anotherLayout = XCTestExpectation(description: "a layout after the theme changes")
        anotherLayout.isInverted = true
        layouts.onIncrement { anotherLayout.fulfill() }
        await fulfillment(of: [anotherLayout], timeout: 0.5)
        XCTAssertEqual(layouts.count, 1, "Laid out once, for the column, and never for a theme")
    }

    /// Hosts `view` in a window nobody sees, `columnWidth` wide.
    private func host<Content: View>(_ view: Content) -> NSHostingView<some View> {
        let hosting = NSHostingView(rootView: view.frame(width: columnWidth))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: columnWidth, height: 1_400), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.showInvisibly()
        addTeardownBlock { @MainActor in window.contentView = nil; window.orderOut(nil) }
        return hosting
    }

    private func picture(of hostingView: NSView) throws -> ThemeRepaintPicture {
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return ThemeRepaintPicture(bitmap: bitmap)
    }

    /// The picture once two in a row are the same: the narrow scene laid out has replaced the standard one.
    private func settledPicture(of hostingView: NSView) async throws -> ThemeRepaintPicture {
        var last = try picture(of: hostingView)
        try await waitUntil("the diagram stops changing", timeoutSeconds: 10) {
            let next = try picture(of: hostingView)
            defer { last = next }
            return next == last
        }
        return last
    }

    private func picture(of hostingView: NSView, differingFrom earlier: ThemeRepaintPicture, _ description: String) async throws -> ThemeRepaintPicture {
        var shown = earlier
        try await waitUntil(description, timeoutSeconds: 10) {
            shown = try picture(of: hostingView)
            return shown.share(differingFrom: earlier) > 0.01
        }
        return shown
    }
}

/// The appearance the host gives the diagram: what a vault's theme and the system's light or dark set in the app.
@MainActor @Observable
private final class ThemeRepaintAppearance {
    var colorScheme = ColorScheme.light
    var theme: NoteThemeStyle?
}

private struct ThemeRepaintHost: View {
    let appearance: ThemeRepaintAppearance
    let diagram: ReadingDiagram
    let layout: ReadingDiagramNarrowLayout

    var body: some View {
        ReadingDiagramView(diagram: diagram, textSize: 17, root: URL(filePath: "/"), navigate: { _, _ in }, scrollToHeading: { _ in })
            .environment(\.readingDiagramNarrowLayout, layout)
            .environment(\.noteTheme, appearance.theme)
            .environment(\.colorScheme, appearance.colorScheme)
    }
}

/// How many narrow layouts ran, counted from the threads that run them.
private final class NarrowLayoutCount: Sendable {
    private struct State {
        var count = 0
        var incremented: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    func increment() {
        let incremented = state.withLock { state in
            state.count += 1
            return state.incremented
        }
        incremented?()
    }

    func onIncrement(_ action: @escaping @Sendable () -> Void) {
        state.withLock { state in state.incremented = action }
    }

    var count: Int { state.withLock { state in state.count } }
}

/// A hosted view's pixels, compared byte by byte.
private struct ThemeRepaintPicture: Equatable {
    let size: CGSize
    private let bytes: [UInt8]

    init(bitmap: NSBitmapImageRep) {
        size = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        let count = bitmap.bytesPerRow * bitmap.pixelsHigh
        bytes = bitmap.bitmapData.map { data in Array(UnsafeBufferPointer(start: data, count: count)) } ?? []
    }

    /// The share of the bytes that differ from `other`'s by more than a little; all of them for another size.
    func share(differingFrom other: ThemeRepaintPicture) -> Double {
        guard other.size == size, other.bytes.count == bytes.count, !bytes.isEmpty else { return 1 }
        let differing = zip(bytes, other.bytes).reduce(0) { count, pair in abs(Int(pair.0) - Int(pair.1)) > 24 ? count + 1 : count }
        return Double(differing) / Double(bytes.count)
    }
}
#endif
