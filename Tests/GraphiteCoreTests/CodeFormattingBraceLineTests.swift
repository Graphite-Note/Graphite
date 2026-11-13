/**
 * File: CodeFormattingBraceLineTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: HUNT-355: code with braces on lines of their own keeps its lines when a block is formatted, with either
 *              line ending, and formatting it again changes nothing, in C, Swift, Python and JavaScript.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
@testable import GraphiteCore

final class CodeFormattingBraceLineTests: XCTestCase {
    private func formatted(_ code: String, _ languageName: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let language = try XCTUnwrap(CodeLanguage.named(languageName), file: file, line: line)
        return try XCTUnwrap(CodeFormatter.formatted(code, language: language), "\(languageName) is formatted", file: file, line: line)
    }

    /// The owner's block of 2026-11-13: `int main()`, then `{` on a line of its own.
    func testABraceOnItsOwnLineStaysUnderItsLineWithNoBlankLineBetween() throws {
        let code = "int main()\n{\n    return 0;\n}\n"
        XCTAssertEqual(try formatted(code, "c"), code)
        XCTAssertEqual(try formatted("int main()\n{\nreturn 0;\n}\n", "c"), code, "Only the indentation is changed.")
    }

    func testWindowsLineEndingsAreKeptOnceEach() throws {
        let code = "int main()\r\n{\r\n    return 0;\r\n}\r\n"
        XCTAssertEqual(try formatted(code, "c"), code)
        XCTAssertEqual(try formatted("int main()\r\n{\r\nreturn 0;\r\n}\r\n", "c"), code)
    }

    func testFormattingTwiceGivesTheSameText() throws {
        let samples: [(language: String, code: String)] = [
            ("c", "#include <stdio.h>\nint main(void)\n{\nint values[] = {1,2,3};\nif(values[0]>0)\n{\nprintf(\"%d\\n\",values[0]);\n}\nelse\n{\nreturn 1;\n}\n\n\nreturn 0;\n}\n"),
            ("swift", "struct Point\n{\nvar x: Int\nfunc moved(by distance: Int) -> Point\n{\nPoint(x: x+distance)\n}\n}\n"),
            ("python", "def main():\n    values = [1,2,3]\n\n\n\n    for value in values:\n        print(value)\n"),
            ("javascript", "function main()\n{\nconst values = [1,2,3];\nif(values.length){\nconsole.log(values);\n}\n}\n"),
        ]
        for sample in samples {
            for lineBreak in ["\n", "\r\n"] {
                let code = sample.code.replacingOccurrences(of: "\n", with: lineBreak)
                let once = try formatted(code, sample.language)
                XCTAssertEqual(try formatted(once, sample.language), once, "\(sample.language) with \(lineBreak.debugDescription)")
                XCTAssertFalse(once.contains(lineBreak + lineBreak + "{"), "No blank line before a brace in \(sample.language): \(once)")
                XCTAssertEqual(once.components(separatedBy: lineBreak).count, once.components(separatedBy: "\n").count,
                               "Every line ends as the code's lines do in \(sample.language)")
            }
        }
    }
}
