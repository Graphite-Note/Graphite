/**
 * File: SidebarAtKeyboardHostedTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Hosted test of an upright iPad window whose note takes the keyboard: the sidebar stays put away, as the
 *              keyboard does not turn the window sideways.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Found in the iPad simulator on 2026-11-12 and 2026-11-13 (Docs/Bug-hunt-todo.md, HUNT-353): a tap in a note, or in
/// a table's cell, showed the sidebar beside the note. The software keyboard took its room from the window's root view,
/// which measured the window's shape: 834 points wide and 1,194 tall less the keyboard is wider than tall, so the window
/// read as turned sideways, where the sidebar shows beside the documents. Nothing here plays sound.
@MainActor
final class SidebarAtKeyboardHostedTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.endEditing(true)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    func testTheKeyboardOfAnUprightWindowLeavesTheSidebarPutAway() async throws {
        let directory = try TemporaryVault.make(prefix: "SidebarAtKeyboard", for: self).root
        let note = "# A note\n\n" + String(repeating: "A line of the note to type in.\n\n", count: 20)
        try Data(note.utf8).write(to: directory.appendingPathComponent("Note.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Note.md"))

        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        controller.traitOverrides.verticalSizeClass = .regular
        let window = UIWindow(windowScene: try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first))
        window.frame = CGRect(origin: .zero, size: CGSize(width: 834, height: 1_194))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        try await waitUntil("the note's editor shows") { self.noteTextView(in: window) != nil }
        let textView = try XCTUnwrap(noteTextView(in: window))
        try await waitUntilSettled("the upright layout has settled") { textView.convert(textView.bounds, to: window) }
        let uprightFrame = textView.convert(textView.bounds, to: window)
        XCTAssertEqual(uprightFrame.width, window.bounds.width, accuracy: 1, "Upright the note has the window's width")

        // A tap in the note: the cursor, and the keyboard with it, whose room the keyboard's layout guide tells.
        textView.selectedRange = NSRange(location: 12, length: 0)
        textView.beginEditing()
        XCTAssertTrue(textView.isFirstResponder, "The note takes the cursor")
        let keyboardGuide = controller.view.keyboardLayoutGuide
        func keyboardHeight() -> CGFloat {
            controller.view.layoutIfNeeded()
            return keyboardGuide.layoutFrame.height
        }
        try await waitUntil("the software keyboard shows", timeoutSeconds: 10) { keyboardHeight() > 200 }
        print("SIDEBAR-AT-KEYBOARD keyboard \(keyboardHeight()) points high, window less it \(window.bounds.height - keyboardHeight())")
        XCTAssertLessThan(window.bounds.height - keyboardHeight(), window.bounds.width, "The window less its keyboard is wider than tall, as found")
        try await waitUntilSettled("the layout with the keyboard has settled") { textView.convert(textView.bounds, to: window) }
        let typingFrame = textView.convert(textView.bounds, to: window)
        XCTAssertEqual(typingFrame.minX, uprightFrame.minX, accuracy: 1, "No sidebar opened beside the note: \(typingFrame)")
        XCTAssertEqual(typingFrame.width, window.bounds.width, accuracy: 1, "The note keeps the window's width while typing")
    }

    private func noteTextView(in root: UIView) -> MarkdownTextView? {
        if let textView = root as? MarkdownTextView, textView.window != nil, !textView.isHidden { return textView }
        return root.subviews.lazy.compactMap { child in self.noteTextView(in: child) }.first
    }

    /// Waits until `measure` has given the same answer for 15 polls in a row.
    private func waitUntilSettled(_ description: String, _ measure: () -> CGRect) async throws {
        var lastAnswer = CGRect.null
        var unchangedPolls = 0
        try await waitUntil(description) {
            let answer = measure()
            unchangedPolls = answer == lastAnswer ? unchangedPolls + 1 : 0
            lastAnswer = answer
            return unchangedPolls >= 15
        }
    }
}
#endif
