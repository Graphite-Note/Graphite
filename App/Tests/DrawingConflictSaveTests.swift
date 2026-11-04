/**
 * File: DrawingConflictSaveTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A drawing whose file changed elsewhere while it was open is never written over, and its
 *              strokes can go to a new file beside it, from the editor's own alert; and strokes go to the
 *              drawing's draft once they pause. Hosted, since saving a drawing is iOS code.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */

import XCTest
import SwiftUI
import PencilKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class DrawingConflictSaveTests: XCTestCase {
    func testADrawingThatChangedElsewhereSavesAsANewFileBesideIt() async throws {
        let vault = try TemporaryVault.make(prefix: "DrawingConflict", for: self).root.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Sketches"), withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)

        let original = try VaultPath("Sketches/Drawing.svg")
        let location = vault.appendingPathComponent(original.rawValue)
        let content = DrawingContent(strokeData: PKDrawing().dataRepresentation(), canvasWidth: 800, background: .white)
        _ = try await DrawingFileService(writer: AtomicFileWriter()).save(content, format: .svg, to: location, expecting: .absent)
        let request = DrawingEditorRequest(target: .existingDrawing(path: original, location: location, revision: try FileRevision.read(location)),
                                           title: original.name, initialStrokeData: PKDrawing().dataRepresentation(), canvasWidth: 800, background: .white, format: .svg)
        try Data("<svg/>".utf8).write(to: location)

        do {
            try await workspace.saveDrawing(content, format: .svg, for: request)
            XCTFail("The newer file is not overwritten.")
        } catch { XCTAssertEqual(error as? GraphiteError, .conflict) }
        try await workspace.saveDrawingAsNewFile(content, format: .svg, for: request)

        XCTAssertEqual(try String(contentsOf: location, encoding: .utf8), "<svg/>")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Sketches/Drawing Graphite edits.svg").path))
        XCTAssertTrue(workspace.notice?.contains("Drawing Graphite edits.svg") == true)
    }

    /// HUNT-092 in the editor: Done on a drawing changed elsewhere shows an alert that offers Save as New Drawing
    /// and Use Other Version, says only what it offers, and its Save as New Drawing keeps the strokes beside the file.
    func testDoneOnADrawingChangedElsewhereOffersANewDrawingOrTheOtherVersionAndKeepsTheStrokes() async throws {
        try Self.setAccessibilityRuntimeEnabled(true)
        defer { try? Self.setAccessibilityRuntimeEnabled(false) } // Left on, it slows later tests and changes nothing they check.
        let vault = try TemporaryVault.make(prefix: "DrawingConflictAlert", for: self).root.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Sketches"), withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        let original = try VaultPath("Sketches/Drawing.svg")
        let location = vault.appendingPathComponent(original.rawValue)
        let content = DrawingContent(strokeData: PKDrawing().dataRepresentation(), canvasWidth: 800, background: .white)
        _ = try await DrawingFileService(writer: AtomicFileWriter()).save(content, format: .svg, to: location, expecting: .absent)
        let request = DrawingEditorRequest(target: .existingDrawing(path: original, location: location, revision: try FileRevision.read(location)),
                                           title: original.name, initialStrokeData: PKDrawing().dataRepresentation(), canvasWidth: 800, background: .white, format: .svg)
        let editor = DrawingEditor(request: request,
                                   save: { content, format in try await workspace.saveDrawing(content, format: format, for: request) },
                                   saveAsNewDrawing: { content, format in try await workspace.saveDrawingAsNewFile(content, format: format, for: request) },
                                   exportCopy: { _, _ in throw CocoaError(.featureUnsupported) }, preserveDraft: { _ in }, removeDraft: {})
        let controller = UIHostingController(rootView: AnyView(editor))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the drawing's canvas shows") { !self.descendants(of: controller.view, matching: InfiniteCanvasView.self).isEmpty }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: InfiniteCanvasView.self).first)
        let points = (0...10).map { step in
            PKStrokePoint(location: CGPoint(x: 100 + CGFloat(step) * 20, y: 200), timeOffset: Double(step) / 60, size: CGSize(width: 4, height: 4),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        // Another app writes the file while the drawing is open.
        try Data("<svg/>".utf8).write(to: location)

        let done = try await element(in: controller, "the editor's Done") { element in element.accessibilityLabel == "Done" && element.accessibilityTraits.contains(.button) }
        XCTAssertTrue(done.accessibilityActivate())
        try await waitUntil("the alert shows") { controller.presentedViewController is UIAlertController }
        let alert = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
        attachScreenshot(of: window, named: "Alert for a drawing changed elsewhere")
        XCTAssertEqual(Set(alert.actions.compactMap(\.title)), ["Save as New Drawing", "Use Other Version", "Cancel"])
        let message = (alert.title ?? "") + " " + (alert.message ?? "")
        XCTAssertTrue(message.contains("new drawing") && message.contains("other version"), "It says only what it offers: \(message)")
        XCTAssertFalse(message.contains("Reload"), "It names no option it does not offer: \(message)")

        let saveAsNew = try await element(in: alert, "Save as New Drawing in the alert") { element in element.accessibilityLabel == "Save as New Drawing" }
        XCTAssertTrue(saveAsNew.accessibilityActivate())
        let copy = vault.appendingPathComponent("Sketches/Drawing Graphite edits.svg")
        try await waitUntil("the strokes go to a new drawing beside the file") { FileManager.default.fileExists(atPath: copy.path) }
        XCTAssertEqual(try String(contentsOf: location, encoding: .utf8), "<svg/>", "The other version is not written over")
    }

    /// HUNT-086: a crash or a forced end gives no notice, so the editor keeps its strokes in the draft once they pause
    /// for 5 seconds, without the app leaving the screen; each new stroke starts the pause again.
    func testStrokesGoToTheDraftOnceTheyPauseWhileTheEditorStaysOpen() async throws {
        let clock = HostedControlledClock()
        var drafts: [DrawingContent] = []
        let request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil, background: .white, format: .png)
        let editor = DrawingEditor(request: request, clock: clock, save: { _, _ in }, exportCopy: { _, _ in throw CocoaError(.featureUnsupported) },
                                   preserveDraft: { content in drafts.append(content) }, removeDraft: {})
        let controller = UIHostingController(rootView: AnyView(editor))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the drawing's canvas shows") { !self.descendants(of: controller.view, matching: InfiniteCanvasView.self).isEmpty }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: InfiniteCanvasView.self).first)
        func stroke(atHeight height: CGFloat) -> PKStroke {
            let points = (0...10).map { step in
                PKStrokePoint(location: CGPoint(x: 100 + CGFloat(step) * 20, y: height), timeOffset: Double(step) / 60, size: CGSize(width: 4, height: 4),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        XCTAssertTrue(clock.requestedDurations.isEmpty, "Nothing waits before anything is drawn")

        canvas.drawing = PKDrawing(strokes: [stroke(atHeight: 200)])
        try await waitUntil("the pause after the stroke is timed") { clock.requestedDurations == [.seconds(5)] }
        XCTAssertTrue(drafts.isEmpty, "Nothing is written while the pause runs")
        clock.endSleeps()
        try await waitUntil("the draft is kept after the pause") { drafts.count == 1 }
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(drafts.last).strokeData).strokes.count, 1)

        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [stroke(atHeight: 300)])
        try await waitUntil("a new stroke starts the pause again") { clock.requestedDurations == [.seconds(5)] }
        XCTAssertEqual(drafts.count, 1)
        clock.endSleeps()
        try await waitUntil("the draft is kept again") { drafts.count == 2 }
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(drafts.last).strokeData).strokes.count, 2, "The draft has every stroke")
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The first accessibility element of the controller or what it presents, once there is one.
    private func element(in controller: UIViewController, _ description: String, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        var found: NSObject?
        try await waitUntil(description, timeoutSeconds: 10) {
            var shown: UIViewController? = controller
            while let current = shown, found == nil {
                found = self.accessibilityElements(in: current.view).first(where: matches)
                shown = current.presentedViewController
            }
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    private func accessibilityElements(in object: NSObject) -> [NSObject] {
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

    /// SwiftUI builds its accessibility elements only while an assistive technology asks for them; this switches the
    /// accessibility runtime on, as VoiceOver or UI automation would.
    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }
}
