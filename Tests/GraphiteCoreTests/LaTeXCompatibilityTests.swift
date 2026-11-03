/**
 * File: LaTeXCompatibilityTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: What Graphite rewrites in a formula before the typesetter reads it: commands
 *              it knows under another name, and declarations that last to the end of a group.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteCore

final class LaTeXCompatibilityTests: XCTestCase {
    private func assertRewrites(_ latex: String, to expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(LaTeXCompatibility.normalized(latex), expected, file: file, line: line)
    }

    func testCommandsKnownUnderAnotherNameAreRenamed() {
        assertRewrites(#"\boldsymbol{x} + \pmb{y}"#, to: #"\bm{x} + \bm{y}"#)
        assertRewrites(#"\lvert x \rvert \lVert y \rVert"#, to: #"\vert x \vert \Vert y \Vert"#)
        assertRewrites(#"\left\lvert x \right\rvert"#, to: #"\left\vert x \right\vert"#)
        assertRewrites(#"\mathscr{L}"#, to: #"\mathcal{L}"#)
        assertRewrites(#"a \bmod b"#, to: #"a \mathbin{\mathrm{mod}} b"#)
        assertRewrites(#"\varDelta"#, to: #"\mathit{\Delta}"#)
        assertRewrites(#"a \: b"#, to: #"a \> b"#)
        assertRewrites(#"\small x"#, to: " x")
    }

    func testCommandsWithLettersAfterThemAreNotJoined() {
        assertRewrites(#"\leqslant x"#, to: #"\leqslant x"#)
        assertRewrites(#"\boldsymbol x"#, to: #"\bm x"#)
    }

    func testDotsAreLowOrCenteredByWhatComesNext() {
        let low = #"{.\,.\,.}"#
        assertRewrites(#"1, \dots, n"#, to: "1, \(low), n")
        assertRewrites(#"a_1 \dots a_n"#, to: "a_1 \(low) a_n")
        assertRewrites(#"\dots"#, to: low)
        assertRewrites(#"\ldots"#, to: low)
        assertRewrites(#"a + \dots + b"#, to: #"a + \cdots + b"#)
        assertRewrites(#"a = \dots = b"#, to: #"a = \cdots = b"#)
        assertRewrites(#"a \cdot \dots \cdot b"#, to: #"a \cdot \cdots \cdot b"#)
        assertRewrites(#"\dots \leq b"#, to: #"\cdots \leq b"#)
        assertRewrites(#"\dotsc \dotsb \dotsm \dotsi \dotso"#, to: "\(low) \\cdots \\cdots \\cdots \(low)")
    }

    func testFontDeclarationsLastToTheEndOfTheirGroup() {
        assertRewrites(#"{\sf H}_2{\sf O}"#, to: #"{\mathsf{ H}}_2{\mathsf{ O}}"#)
        assertRewrites(#"{\bf x y} z"#, to: #"{\mathbf{ x y}} z"#)
        assertRewrites(#"\rm a b"#, to: #"\mathrm{ a b}"#)
        assertRewrites(#"{\rm a \bf b} c"#, to: #"{\mathrm{ a \mathbf{ b}}} c"#)
        assertRewrites(#"\begin{matrix} \it a & b \end{matrix}"#, to: #"\begin{matrix} \mathit{ a }& b \end{matrix}"#)
    }

    /// `\color` used to close only at a brace, so a colored cell swallowed the cell's end and
    /// the formula could not be typeset, or crashed the parser (SwiftUIMath patch 9).
    func testColorDeclarationsEndWithTheirCell() {
        assertRewrites(#"\begin{matrix} \color{red} a & b \end{matrix}"#, to: #"\begin{matrix} \textcolor{red}{ a }& b \end{matrix}"#)
        assertRewrites(#"\begin{matrix} \color{red} a \\ b \end{matrix}"#, to: #"\begin{matrix} \textcolor{red}{ a }\\ b \end{matrix}"#)
        assertRewrites(#"\begin{matrix} a \color{red} \end{matrix} b"#, to: #"\begin{matrix} a \textcolor{red}{ }\end{matrix} b"#)
        assertRewrites(#"\left( \color{red} x \right) y"#, to: #"\left( \textcolor{red}{ x }\right) y"#)
    }

    func testColorDeclarationsOutsideAnEnvironmentHoldAllOfIt() {
        assertRewrites(#"\color{red} \begin{matrix} a & b \\ c \end{matrix} d"#, to: #"\textcolor{red}{ \begin{matrix} a & b \\ c \end{matrix} d}"#)
        assertRewrites(#"\color{red} \left( a \right) b"#, to: #"\textcolor{red}{ \left( a \right) b}"#)
        assertRewrites(#"{\color{red} a} b"#, to: #"{\textcolor{red}{ a}} b"#)
        assertRewrites(#"\color{red} a \color{blue} b"#, to: #"\textcolor{red}{ a \textcolor{blue}{ b}}"#)
    }

    func testRowBreaksAndAmpersandsInBracesDoNotEndACell() {
        assertRewrites(#"\begin{matrix} \color{red} \substack{a \\ b} & c \end{matrix}"#, to: #"\begin{matrix} \textcolor{red}{ \substack{a \\ b} }& c \end{matrix}"#)
        assertRewrites(#"\begin{array}{l|c} \color{red} a & b \end{array}"#, to: #"\begin{array}{l|c} \textcolor{red}{ a }& b \end{array}"#)
    }

    func testEscapedSymbolsAreNotGroupsOrCellEnds() {
        assertRewrites(#"\begin{matrix} \color{red} a \& b \{ c \end{matrix}"#, to: #"\begin{matrix} \textcolor{red}{ a \& b \{ c }\end{matrix}"#)
    }

    func testMalformedGroupsAreLeftForTheTypesetterToReject() {
        assertRewrites(#"{\color{red} a"#, to: #"{\textcolor{red}{ a"#)
        assertRewrites(#"\left( \color{red} a"#, to: #"\left( \textcolor{red}{ a"#)
        assertRewrites(#"a \right) b"#, to: #"a \right) b"#)
        assertRewrites(#"a \end{matrix} b"#, to: #"a \end{matrix} b"#)
        assertRewrites(#"\begin{matrix"#, to: #"\begin{matrix"#)
    }

    func testStarredOperatorNamesAreLeftForTheTypesetter() {
        assertRewrites(#"\operatorname*{max}_x"#, to: #"\operatorname*{max}_x"#)
        assertRewrites(#"\operatorname{tr}"#, to: #"\mathrm{tr}"#)
    }
}
