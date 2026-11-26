/**
 * File: MacCourseDashboardInAppHostedTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: New Course and a course page inside the running Mac app: the starter made in a small demo vault, the
 *              course page with its embedded views, an assignment made through the view's New and marked done, and the
 *              course's rollup following it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// `Docs/Bases-relations-todo.md`, the Mac's check in the running app. The window's buttons are SwiftUI's, which a test
/// in the app cannot press (no accessibility tree in the process), so New is the model's `createNewItem` the button
/// calls, with the workspace's own services. Runs only with `TEST_RUNNER_GRAPHITE_MAC_COURSES` given to xcodebuild as a
/// folder, where it writes a picture of each step and the files made; a person looks at them.
@MainActor
final class MacCourseDashboardInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_COURSES"
    private var outputFolder: URL?
    private var pictureCount = 0

    func testANewCourseItsAssignmentAndItsProgressInTheRunningApp() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
        let vaultRoot = try TemporaryVault.make(prefix: "MacCourseDashboard", files: [
            "Welcome.md": "# Demo vault\n\nA small vault for checking course dashboards.\n",
            "Notes/Fourier series.md": "A periodic signal is a sum of sines and cosines.\n",
        ], for: self).root
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)

        await workspace.createCourse(named: "Digital Design", in: nil)
        XCTAssertNil(workspace.errorMessage)
        let course = try VaultPath("Courses/Digital Design.md")
        try await waitUntil("the course page is open", timeoutSeconds: 30) { workspace.markdownSession?.path == course }
        try await settle(window)
        try writePicture("course page", of: window)

        let services = try XCTUnwrap(workspace.baseNoteServices)
        let store = try XCTUnwrap(workspace.store)
        let index = try XCTUnwrap(workspace.index)
        let assignments = BaseDocumentModel(source: .file(try VaultPath("Courses/Assignments.base")), contextPath: course, store: store, index: index,
                                            preferredViewName: "This course")
        await assignments.reload()
        let created = await assignments.createNewItem(named: "Lab 1", services: services)
        let lab = try XCTUnwrap(created)
        XCTAssertEqual(lab.rawValue, "Courses/Assignments/Lab 1.md")
        try await waitUntil("the new note opens in a tab of its own", timeoutSeconds: 30) { workspace.markdownSession?.path == lab }
        try await settle(window)
        try writePicture("the new assignment", of: window)
        _ = await workspace.open(course, placement: .currentTab)
        try await waitUntil("the course page shows the assignment", timeoutSeconds: 30) { workspace.markdownSession?.path == course }
        try await settle(window)
        try writePicture("course page with its assignment", of: window)

        let labURL = vaultRoot.appendingPathComponent(lab.rawValue)
        let written = try String(contentsOf: labURL, encoding: .utf8)
        XCTAssertTrue(written.contains("  - \"[[Digital Design]]\""), written)
        try written.replacingOccurrences(of: "done:", with: "done: true").replacingOccurrences(of: "weight:", with: "weight: 20")
            .write(to: labURL, atomically: true, encoding: .utf8)
        workspace.filesSavedOutsideEditors([lab])
        try await waitUntil("the index has the change", timeoutSeconds: 30) { (try? await index.baseRecord(at: lab))?.properties.contains { entry in entry.key == "weight" } == true }
        try await settle(window)
        try writePicture("course page after the assignment is done", of: window)
        try Data(written.utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("Lab 1 as made.md"))

        // The relation picker of the assignment's course, read from the vault, and the rollup builder, as their sheets show them.
        let request = BaseEditRequest(path: lab, property: .note("course"), displayName: "course", kind: .list, currentValue: nil)
        let writtenCourse = await assignments.writtenPropertyNode(.note("course"), of: lab)
        let picker = BasePropertyEditorSheet(request: request, writtenNode: writtenCourse,
                                             relation: assignments.relationEditing(for: request, writtenNode: writtenCourse, services: services)) { _ in nil }
        try await writeSheetPicture("relation picker", picker)
        let courses = BaseDocumentModel(source: .file(try VaultPath("Courses/Courses.base")), contextPath: course, store: store, index: index)
        await courses.reload()
        let names = await courses.rollupPropertyNames(services: services)
        try await writeSheetPicture("rollup builder", BaseRollupBuilderSheet(vaultPropertyNames: names, rowPropertyNames: courses.availablePropertyKeys,
                                                                             noteFormulaNames: courses.noteListFormulaNames) { _ in nil })
    }

    /// A sheet in a window of its own, as large as the Mac shows it, after it settled.
    private func writeSheetPicture(_ name: String, _ sheet: some View) async throws {
        let window = NSWindow(contentViewController: NSHostingController(rootView: sheet.frame(width: 460, height: 560)))
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.showInvisibly()
        defer { window.close() }
        try await settle(window)
        try writePicture(name, of: window)
    }

    private func settle(_ window: NSWindow) async throws {
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 40).measure({}, until: { true })
    }

    private func writePicture(_ name: String, of window: NSWindow) throws {
        pictureCount += 1
        try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
            .write(to: try XCTUnwrap(outputFolder).appendingPathComponent(String(format: "%02d %@.png", pictureCount, name)))
    }
}
#endif
