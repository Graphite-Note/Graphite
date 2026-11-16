/**
 * File: MacPDFPageToolHarness.swift
 * ---------------------------------
 * Layer: Tests
 * Description: A one-page PDF open in a Mac PDF view with its markup interaction and row, and the pointer's and
 *              keyboard's events on it, for the tests of the markup row's page tools.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
@testable import GraphiteUI
import GraphiteTestSupport

/// A one-page PDF of `pageSize` open in a PDF view in an invisible window, with the markup
/// row's model and the interaction that makes the page tools.
@MainActor
struct MacPDFPageToolHarness {
    static let pageSize = CGSize(width: 400, height: 600)

    let location: URL
    let session: PDFSession
    let view: GraphiteMacPDFView
    let window: NSWindow
    let interaction: MacPDFMarkupInteraction
    let toolbar: PDFMarkupToolbar
    let page: PDFPage
    var tools: MacPDFPageTools? { interaction.pageTools }

    /// Opens the fixture for `testCase`, which takes it down when it ends.
    static func open(for testCase: XCTestCase, prefix: String, currentDate: @escaping () -> Date = Date.init) async throws -> MacPDFPageToolHarness {
        let directory = try TemporaryVault.make(prefix: prefix, for: testCase).root
        let location = directory.appendingPathComponent("Worksheet.pdf")
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()

        let session = try await PDFSession.open(location)
        session.undoManager.groupsByEvent = false
        let view = GraphiteMacPDFView(frame: CGRect(origin: .zero, size: pageSize))
        view.documentUndoManager = session.undoManager
        view.document = session.document
        view.autoScales = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        window.showInvisibly()
        view.layoutSubtreeIfNeeded()
        session.pdfView = view
        let toolbar = PDFMarkupToolbar()
        let interaction = MacPDFMarkupInteraction(session: session, view: view)
        let suiteName = "\(prefix)-\(UUID().uuidString)"
        interaction.pageToolPreferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        interaction.currentDate = currentDate
        testCase.addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        interaction.toolbar = toolbar
        view.markupInteraction = interaction
        interaction.input = PDFAnnotationInput(isEnabled: true, drawsWithFinger: false, showsToolPicker: false)
        testCase.addTeardownBlock {
            interaction.stopObservingSelection()
            window.orderOut(nil)
        }
        return MacPDFPageToolHarness(location: location, session: session, view: view, window: window, interaction: interaction, toolbar: toolbar,
                                     page: try XCTUnwrap(session.document.page(at: 0)))
    }

    func choose(_ tool: PDFMarkupTool) {
        interaction.input.markupTool = tool
    }

    func event(_ type: NSEvent.EventType, at pagePoint: CGPoint, clickCount: Int = 1, time: TimeInterval = 0) throws -> NSEvent {
        let viewPoint = view.convert(pagePoint, from: page)
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(viewPoint, to: nil), modifierFlags: [], timestamp: time,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1))
    }

    func key(_ characters: String, keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    /// The Delete key, which removes what a page tool has selected.
    func pressDelete() throws -> Bool {
        try XCTUnwrap(tools).handleKeyDown(try key(String(UnicodeScalar(UInt8(NSDeleteCharacter))), keyCode: 51))
    }

    /// A press, drag and release through the points of the page, as one user action closing its undo group.
    func drag(through pagePoints: [CGPoint]) throws {
        guard let first = pagePoints.first, let last = pagePoints.last else { return }
        session.undoManager.beginUndoGrouping()
        tools?.mouseDown(try event(.leftMouseDown, at: first))
        for (index, point) in pagePoints.dropFirst().enumerated() {
            tools?.mouseDragged(try event(.leftMouseDragged, at: point, time: Double(index + 1) / 60))
        }
        tools?.mouseUp(try event(.leftMouseUp, at: last, time: Double(pagePoints.count) / 60))
        session.undoManager.endUndoGrouping()
    }

    /// Runs `operation` as one user action, closing its undo group.
    func step(_ operation: () throws -> Void) rethrows {
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try operation()
    }
}
#endif
