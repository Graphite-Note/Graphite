/**
 * File: UiCodeBraceLineFormattingMacTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: HUNT-355 in the Mac editor: C typed with its braces on lines of their own, Return after each line, gets
 *              no blank line, and the box draws its `{` line as close to the line above as its other lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class UiCodeBraceLineFormattingMacTests: XCTestCase {
    private func makeEditor(text: String, mode: EditingMode) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = mode
        configuration.formatsCodeBlocks = true
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        return (coordinator, textView)
    }

    private func runMainQueueTurns() async {
        for _ in 0..<10 { await Task.yield() }
    }

    /// Typed key by key, Return after each line, as the owner wrote `int main()` then `{`.
    private func typeLines(_ lines: [String], in textView: MarkdownMacTextView, coordinator: NativeMarkdownEditor.Coordinator) async {
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                textView.insertNewline(nil)
                coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
                await runMainQueueTurns()
            }
            for character in line {
                textView.insertText(String(character), replacementRange: textView.selectedRange())
                coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            }
            await runMainQueueTurns()
        }
    }

    /// Typed key by key into a block with "Format Code Blocks" on; `CodeFormattingBraceLineTests` formats the same lines.
    func testCTypedWithItsBracesOnTheirOwnLinesAddsNoBlankLine() async throws {
        for mode in [EditingMode.livePreview, .source] {
            let note = "Intro\n\n```c\nx\n```\n\nAfter the block.\n"
            let (coordinator, textView) = try await makeEditor(text: note, mode: mode)
            let codeLine = (note as NSString).range(of: "x\n```").location
            textView.setSelectedRange(NSRange(location: codeLine, length: 1))
            await runMainQueueTurns()
            await typeLines(["int main()", "{", "return 0;", "}"], in: textView, coordinator: coordinator)
            XCTAssertEqual(textView.string, "Intro\n\n```c\nint main()\n{\nreturn 0;\n}\n```\n\nAfter the block.\n", "\(mode)")
            withExtendedLifetime(coordinator) {}
        }
    }

    /// The lines of the drawn box are as far apart as each other: a line of only `{` gets no
    /// room above it.
    func testTheBracesLineIsDrawnAsCloseToTheLineAboveAsTheOtherLines() async throws {
        let note = "Intro\n\n```c\nint main()\n{\n    return 0;\n}\n```\n\nAfter the block.\n"
        let (coordinator, textView) = try await makeEditor(text: note, mode: .livePreview)
        defer { withExtendedLifetime(coordinator) {} }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = textView.enclosingScrollView
        window.showInvisibly()
        defer { window.orderOut(nil); window.contentView = nil }
        let layoutManager = try XCTUnwrap(textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        func top(of fragment: String) throws -> CGFloat {
            let offset = (note as NSString).range(of: fragment).location
            let location = try XCTUnwrap(layoutManager.location(layoutManager.documentRange.location, offsetBy: offset))
            return try XCTUnwrap(layoutManager.textLayoutFragment(for: location)).layoutFragmentFrame.minY
        }
        let lineTops = try ["int main()", "{\n", "    return", "}\n```"].map(top(of:))
        let gaps = zip(lineTops.dropFirst(), lineTops).map { lower, upper in lower - upper }
        XCTAssertEqual(gaps.max() ?? 0, gaps.min() ?? 0, accuracy: 0.5, "Every code line is as far below the one above: \(gaps)")
    }
}
#endif
