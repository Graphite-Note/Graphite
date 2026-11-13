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

    /// The main queue's work dispatched so far, run: the block's formatting is dispatched there
    /// when the selection leaves it.
    private func runMainQueueTurnsAndItsDispatches() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            await runMainQueueTurns()
        }
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

    /// The paths the owner's block may have taken, tried on 2026-11-13: typed key by key then
    /// left, pasted then left, undone and done again, in Live Preview and Source mode. At every step `{` stays right under `int main()`, with no blank line between.
    func testABlockTypedOrPastedThenLeftUndoneAndRedoneKeepsItsBraceUnderItsLine() async throws {
        let note = "Intro\n\n```c\nx\n```\n\nAfter the block.\n"
        let formattedNote = "Intro\n\n```c\nint main()\n{\n    return 0;\n}\n```\n\nAfter the block.\n"
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("GraphiteHUNT355-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        for mode in [EditingMode.livePreview, .source] {
            for pastes in [false, true] {
                let label = "\(mode), \(pastes ? "pasted" : "typed")"
                let (coordinator, textView) = try await makeEditor(text: note, mode: mode)
                defer { withExtendedLifetime(coordinator) {} }
                // In a window as its first responder, as when typing in Graphite: otherwise the
                // text view ends editing after each change, and the block is formatted there.
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = textView.enclosingScrollView
                window.showInvisibly()
                window.makeFirstResponder(textView)
                defer { window.orderOut(nil); window.contentView = nil }
                func select(_ range: NSRange) async throws {
                    textView.setSelectedRange(range)
                    coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
                    await runMainQueueTurnsAndItsDispatches()
                }
                func assertBraceUnderItsLine(_ step: String) {
                    XCTAssertTrue(textView.string.contains("int main()\n{\n"), "\(step), \(label): \(textView.string.debugDescription)")
                }
                try await select(NSRange(location: (note as NSString).range(of: "x\n```").location, length: 1))
                if pastes {
                    pasteboard.clearContents()
                    pasteboard.setString("int main()\n{\nreturn 0;\n}", forType: .string)
                    XCTAssertTrue(textView.readSelection(from: pasteboard, type: .string), label)
                    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
                    await runMainQueueTurns()
                } else {
                    await typeLines(["int main()", "{", "return 0;", "}"], in: textView, coordinator: coordinator)
                }
                assertBraceUnderItsLine("Written")
                try await select(NSRange(location: (textView.string as NSString).range(of: "After").location, length: 0))
                XCTAssertEqual(textView.string, formattedNote, "Formatted on leaving the block, \(label)")
                textView.undoManager?.undo()
                await runMainQueueTurnsAndItsDispatches()
                assertBraceUnderItsLine("Undone")
                textView.undoManager?.redo()
                await runMainQueueTurnsAndItsDispatches()
                XCTAssertEqual(textView.string, formattedNote, "Redone, \(label)")
            }
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
