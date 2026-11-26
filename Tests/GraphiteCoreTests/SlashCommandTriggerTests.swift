/**
 * File: SlashCommandTriggerTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Where a typed `/` opens the slash commands and what its query is, by Obsidian's rule, and where
 *              Graphite opens nothing (code, display math, the frontmatter).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class SlashCommandTriggerTests: XCTestCase {
    /// The query before the end of `text`, where the cursor is.
    private func queryAtEnd(of text: String) -> SlashCommandQuery? {
        SlashCommandTrigger.query(in: text as NSString, cursor: (text as NSString).length)
    }

    func testASlashAtTheStartOfALineOrAfterASpaceOpensWithTheLettersAfterIt() {
        XCTAssertEqual(queryAtEnd(of: "/"), SlashCommandQuery(text: "", replacementRange: NSRange(location: 0, length: 1)))
        XCTAssertEqual(queryAtEnd(of: "/tab"), SlashCommandQuery(text: "tab", replacementRange: NSRange(location: 0, length: 4)))
        XCTAssertEqual(queryAtEnd(of: "First line\n/h2"), SlashCommandQuery(text: "h2", replacementRange: NSRange(location: 11, length: 3)))
        XCTAssertEqual(queryAtEnd(of: "Notes /call"), SlashCommandQuery(text: "call", replacementRange: NSRange(location: 6, length: 5)))
        XCTAssertEqual(queryAtEnd(of: "Notes\t/call")?.text, "call", "A tab is a space, as JavaScript's \\s reads it.")
        XCTAssertEqual(queryAtEnd(of: "Notes\u{00A0}/call")?.text, "call", "So is a no-break space.")
        XCTAssertEqual(queryAtEnd(of: "- [ ] /task")?.text, "task", "In a list item, after its marker.")
        XCTAssertEqual(queryAtEnd(of: "/é")?.text, "é")
    }

    func testASlashInsideAWordOrAfterAnotherSlashOpensNothing() {
        XCTAssertNil(queryAtEnd(of: "and/or"))
        XCTAssertNil(queryAtEnd(of: "1/2"))
        XCTAssertNil(queryAtEnd(of: "https://example.com"))
        XCTAssertNil(queryAtEnd(of: "/usr/bin"), "A second / ends the query, as [^\\s/]* says.")
        XCTAssertNil(queryAtEnd(of: "//"))
    }

    func testASpaceAfterTheQueryClosesIt() {
        XCTAssertNil(queryAtEnd(of: "/table "))
        XCTAssertNil(queryAtEnd(of: "/table\n"), "The cursor on the next line has no / before it.")
    }

    func testTheCursorInTheMiddleOfAQueryReadsUpToTheCursor() {
        let text = "Intro /callout" as NSString
        XCTAssertEqual(SlashCommandTrigger.query(in: text, cursor: 9), SlashCommandQuery(text: "ca", replacementRange: NSRange(location: 6, length: 3)))
        XCTAssertNil(SlashCommandTrigger.query(in: text, cursor: 0))
        XCTAssertNil(SlashCommandTrigger.query(in: text, cursor: 5), "Before the /.")
    }

    func testAVeryLongRunAfterTheSlashIsNotAQuery() {
        XCTAssertNotNil(queryAtEnd(of: "/" + String(repeating: "a", count: SlashCommandTrigger.maximumQueryLength)))
        XCTAssertNil(queryAtEnd(of: "/" + String(repeating: "a", count: SlashCommandTrigger.maximumQueryLength + 1)))
    }

    func testNothingOpensInCodeMathOrTheFrontmatter() {
        XCTAssertNil(queryAtEnd(of: "```\n/usr"), "In a fenced code block.")
        let inlineCode = "Run `ls /tm` later" as NSString
        XCTAssertNil(SlashCommandTrigger.query(in: inlineCode, cursor: inlineCode.range(of: "/tm").location + 3), "In inline code.")
        XCTAssertNotNil(queryAtEnd(of: "Run `ls /tm"), "An unclosed backtick is a backtick, not code.")
        XCTAssertNil(queryAtEnd(of: "$$\nx /y"), "In display math.")
        let frontmatter = "---\ntitle: /x\n---\nBody" as NSString
        XCTAssertNil(SlashCommandTrigger.query(in: frontmatter, cursor: frontmatter.range(of: "/x").location + 2), "In the frontmatter.")
        XCTAssertNotNil(queryAtEnd(of: "```\ncode\n```\n/tab"), "After a closed fence.")
        XCTAssertNotNil(queryAtEnd(of: "$$\nx\n$$\n/tab"), "After closed display math.")
        XCTAssertNotNil(queryAtEnd(of: "$$x$$ then /tab"), "Display math opened and closed on its line.")
        XCTAssertNotNil(queryAtEnd(of: "```\n$$\n```\n/tab"), "A $$ inside code opens no math.")
        XCTAssertNotNil(queryAtEnd(of: "---\ntitle: A\n---\n/tab"), "After the frontmatter.")
    }

    func testTheSlashCommandContextComesOnlyFromTheTrigger() {
        XCTAssertNil(LinkCompletion.context(in: "/tab" as NSString, cursor: 4), "Links and tags do not read slashes; the editors ask the trigger.")
    }

    /// Each key typed in a query asks for the block of its line, which an editor answers from
    /// the checkpoints it keeps for styling; with the answer at hand, a query at the end of a
    /// 5,000-line note reads only its own line.
    func testAQueryAtTheEndOfALongNoteReadsOnlyItsLine() {
        var lines: [String] = ["---", "title: Long", "---", "$$", "x = 1", "$$"]
        for lineIndex in 0..<5_000 {
            lines.append(lineIndex % 50 == 0 ? "```swift\nlet value = \(lineIndex) // $$ not math\n```" : "A line of prose \(lineIndex), with $x$ and a [[link]].")
        }
        let text = (lines.joined(separator: "\n") + "\n/tab") as NSString
        let lineStart = text.lineRange(for: NSRange(location: text.length, length: 0)).location
        let checkpoint = MarkdownStyleScanner.blockCheckpoint(atLineStart: lineStart, in: text, resumingFrom: nil)
        XCTAssertEqual(checkpoint.context, .normal)
        var askedLineStarts: [Int] = []
        let start = ContinuousClock.now
        let repetitionCount = 100
        for _ in 0..<repetitionCount {
            XCTAssertNotNil(SlashCommandTrigger.query(in: text, cursor: text.length) { lineStart in
                askedLineStarts.append(lineStart)
                return MarkdownStyleScanner.blockCheckpoint(atLineStart: lineStart, in: text, resumingFrom: checkpoint).context
            })
        }
        let elapsed = ContinuousClock.now - start
        let millisecondsPerQuery = (Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15) / Double(repetitionCount)
        print("SLASH-TRIGGER \(text.length) characters: \(String(format: "%.3f", millisecondsPerQuery)) ms a query")
        XCTAssertEqual(Set(askedLineStarts), [lineStart], "Only the cursor's line is asked about.")
        XCTAssertLessThan(millisecondsPerQuery, 1)
        XCTAssertNil(SlashCommandTrigger.query(in: "and/or" as NSString, cursor: 6) { _ in
            XCTFail("No / that opens the commands: the block is not asked for.")
            return .normal
        })
    }
}
