/**
 * File: FlowchartStyleTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Flowchart colors: classDef, class, style and linkStyle read, resolved, laid out and drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// `classDef`, `class`, `:::`, `style` and `linkStyle`: read, resolved in Mermaid's order, laid out and drawn.
final class FlowchartStyleTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    /// The flowchart `source` writes, with the keyword added when it has none.
    private func flowchart(_ source: String) throws -> FlowchartDiagram {
        try FlowchartReading.flowchart(source.hasPrefix("flowchart") ? source : "flowchart TD\n" + source)
    }

    private func laidOut(_ source: String) throws -> FlowchartLayout {
        try FlowchartLayoutEngine.layout(flowchart(source), typography: typography, limits: .standard)
    }

    private func color(_ hexadecimal: UInt32) -> DiagramColor {
        DiagramColor(red: Double(hexadecimal >> 16 & 0xFF) / 255, green: Double(hexadecimal >> 8 & 0xFF) / 255, blue: Double(hexadecimal & 0xFF) / 255)
    }

    // MARK: Colors and declarations

    func testColorsAreReadInEveryFormAStyleWritesThem() {
        XCTAssertEqual(DiagramColor(cssText: "#f9f"), color(0xFF99FF))
        XCTAssertEqual(DiagramColor(cssText: "#FF99FF"), color(0xFF99FF))
        XCTAssertEqual(DiagramColor(cssText: " #333 "), color(0x333333))
        XCTAssertEqual(DiagramColor(cssText: "#ff000080")?.alpha ?? 0, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(DiagramColor(cssText: "rgb(255, 0, 0)"), color(0xFF0000))
        XCTAssertEqual(DiagramColor(cssText: "rgba(0, 255, 0, 0.5)")?.alpha, 0.5)
        XCTAssertEqual(DiagramColor(cssText: "rgb(100%, 0%, 0%)"), color(0xFF0000))
        XCTAssertEqual(DiagramColor(cssText: "Red"), color(0xFF0000))
        XCTAssertEqual(DiagramColor(cssText: "none")?.alpha, 0, "No fill is a clear one")
        XCTAssertNil(DiagramColor(cssText: "#12"))
        XCTAssertNil(DiagramColor(cssText: "#ggg"))
        XCTAssertNil(DiagramColor(cssText: "rgb(1, 2)"))
        XCTAssertNil(DiagramColor(cssText: "notacolor"))
    }

    func testDeclarationsSetTheirPropertiesAndSayWhenOneIsNotApplied() {
        let all = DiagramElementStyle.reading("fill:#f9f,stroke:#333,stroke-width:4px,color:#fff,stroke-dasharray: 5 5")
        XCTAssertEqual(all.style, DiagramElementStyle(fill: color(0xFF99FF), stroke: color(0x333333), strokeWidth: 4, strokeDashLengths: [5, 5],
                                                      textColor: color(0xFFFFFF)))
        XCTAssertFalse(all.hasUnappliedDeclaration)
        let partial = DiagramElementStyle.reading("fill:#f9f,font-size:20px,stroke:nonsense")
        XCTAssertEqual(partial.style, DiagramElementStyle(fill: color(0xFF99FF)))
        XCTAssertTrue(partial.hasUnappliedDeclaration)
        XCTAssertEqual(DiagramElementStyle.reading("fill:rgb(255, 0, 0),stroke-width:2").style, DiagramElementStyle(fill: color(0xFF0000), strokeWidth: 2),
                       "A comma inside rgb() does not end the declaration")
        XCTAssertEqual(DiagramElementStyle.reading("fill:#fff !important").style.fill, color(0xFFFFFF))
        XCTAssertTrue(DiagramElementStyle.reading("").style.isEmpty)
    }

    // MARK: Reading

    func testAClassDefinitionStylesTheNodesGivenTheClassWhereverItIsWritten() throws {
        let diagram = try flowchart("""
        A[Start]:::warm --> B
        class B,C warm
        C --> D
        classDef warm fill:#f96,stroke:#333;
        """)
        let warm = DiagramElementStyle(fill: color(0xFF9966), stroke: color(0x333333))
        XCTAssertEqual(diagram.nodes.map(\.style), [warm, warm, warm, nil])
        XCTAssertEqual(diagram.unappliedStatementCount, 0)
    }

    func testANodesOwnStyleBeatsItsClassAndTheDefaultClassStylesTheRest() throws {
        let diagram = try flowchart("""
        classDef default fill:#eee
        classDef hot fill:#f00,stroke:#a00
        A:::hot --> B
        style A fill:#00f
        """)
        XCTAssertEqual(diagram.nodes[0].style, DiagramElementStyle(fill: color(0x0000FF), stroke: color(0xAA0000)), "style beats the class, property by property")
        XCTAssertEqual(diagram.nodes[1].style, DiagramElementStyle(fill: color(0xEEEEEE)))
    }

    func testSeveralClassesTakeInTheOrderTheyWereGivenAndAClassDefinedAgainKeepsWhatItSet() throws {
        let diagram = try flowchart("""
        classDef a fill:#111,stroke:#222
        classDef b fill:#333
        classDef a stroke-width:3px
        X:::a:::b
        """)
        XCTAssertEqual(diagram.nodes[0].style, DiagramElementStyle(fill: color(0x333333), stroke: color(0x222222), strokeWidth: 3))
    }

    func testAClassNobodyDefinedStylesNothing() throws {
        let diagram = try flowchart("A:::nobody --> B\nclass B nobody")
        XCTAssertEqual(diagram.nodes.map(\.style), [nil, nil])
        XCTAssertEqual(diagram.unappliedStatementCount, 0)
    }

    func testLinkStyleStylesEdgesByIndexAndDefault() throws {
        let diagram = try flowchart("""
        A --> B --> C
        A --> C
        linkStyle default stroke:#999
        linkStyle 0,2 stroke:#f00,stroke-width:4px
        """)
        XCTAssertEqual(diagram.edges.map(\.style), [
            DiagramElementStyle(stroke: color(0xFF0000), strokeWidth: 4), DiagramElementStyle(stroke: color(0x999999)),
            DiagramElementStyle(stroke: color(0xFF0000), strokeWidth: 4),
        ])
        XCTAssertEqual(diagram.unappliedStatementCount, 0)
    }

    func testStatementsNamingNothingThereAndPartsNotDrawnAreCounted() throws {
        let diagram = try flowchart("""
        A --> B
        linkStyle 5 stroke:#f00
        style Nowhere fill:#f00
        style A fill:#f00,font-size:20px
        linkStyle 0 stroke:#f00,color:red
        click A "https://example.com"
        """)
        XCTAssertEqual(diagram.unappliedStatementCount, 5, "An index out of range, an unknown node, a font size, a link's text color and a click")
        XCTAssertEqual(diagram.nodes[0].style, DiagramElementStyle(fill: color(0xFF0000)), "What can be applied is")
        XCTAssertEqual(diagram.edges[0].style, DiagramElementStyle(stroke: color(0xFF0000)))
    }

    func testAStyleBeforeItsNodeAndAClassOnAGroupDoNotMakeNodes() throws {
        let diagram = try flowchart("style A fill:#f00\nA --> B\nsubgraph one\nC\nend\nstyle one fill:#0f0")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["A", "B", "C"])
        XCTAssertEqual(diagram.nodes[0].style, DiagramElementStyle(fill: color(0xFF0000)))
        XCTAssertEqual(diagram.unappliedStatementCount, 1, "A group's box is not styled yet")
    }

    func testAMalformedStyleStatementIsCountedAndTheRestIsRead() throws {
        let diagram = try flowchart("A --> B\nclassDef\nclass A\nlinkStyle first stroke:#f00\nB --> C")
        XCTAssertEqual(diagram.edges.count, 2)
        XCTAssertEqual(diagram.unappliedStatementCount, 3)
    }

    // MARK: Layout and drawing

    func testStyledNodesAndEdgesAreDrawnApartInTheirOwnColors() throws {
        let layout = try laidOut("flowchart TD\nA[Start] --> B[Finish]\nstyle A fill:#ff0000,stroke:#0000ff,stroke-width:4px,color:#00ff00\nlinkStyle 0 stroke:#00aa00,stroke-width:6px")
        let parts = FlowchartDrawingParts(layout: layout)
        XCTAssertEqual(parts.styledNodes.count, 1)
        XCTAssertEqual(parts.nodeTexts.count, 1, "The styled node's text is drawn with its color, not with the others")
        XCTAssertEqual(parts.styledEdges.count, 1)
        XCTAssertTrue(parts.solidEdges.isEmpty)
        XCTAssertEqual(parts.styledEdges[0].lineWidth, 6)
        XCTAssertEqual(parts.styledNodes[0].lineWidth, 4)

        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.draw(layout, palette: .peleLight)
        let first = layout.nodes[0].frame
        XCTAssertEqual(bitmap.color(at: CGPoint(x: first.minX + 6, y: first.midY)), [0xFF, 0x00, 0x00], "Inside the styled node: its fill")
        XCTAssertEqual(bitmap.color(at: CGPoint(x: first.minX + 1, y: first.midY)), [0x00, 0x00, 0xFF], "On its outline: its stroke")
        let second = layout.nodes[1].frame
        XCTAssertEqual(bitmap.color(at: CGPoint(x: second.minX + 4, y: second.midY)), [0xF3, 0xF3, 0xF3], "The other node keeps the usual look")
        let edge = layout.edges[0]
        XCTAssertEqual(bitmap.color(at: CGPoint(x: first.midX, y: (first.maxY + second.minY) / 2)), [0x00, 0xAA, 0x00], "The link in its stroke")
        XCTAssertNotNil(edge.style)
    }

    func testAStyledNodesTextTakesItsColor() throws {
        let layout = try laidOut("flowchart TD\nA[Wide enough text] --> B\nstyle A fill:#ffffff,color:#ff0000")
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.draw(layout, palette: .peleLight)
        let text = layout.nodes[0].text.frame
        var hasRedPixel = false
        for y in Int(text.minY)..<Int(text.maxY) {
            for x in Int(text.minX)..<Int(text.maxX) {
                let pixel = bitmap.color(at: CGPoint(x: x, y: y))
                if pixel[0] > 200, pixel[1] < 100, pixel[2] < 100 { hasRedPixel = true }
            }
        }
        XCTAssertTrue(hasRedPixel, "The text is drawn in the color the style sets")
    }

    func testAnUnstyledFlowchartDrawsAsBefore() throws {
        let layout = try laidOut("flowchart TD\nA --> B")
        let parts = FlowchartDrawingParts(layout: layout)
        XCTAssertTrue(parts.styledNodes.isEmpty)
        XCTAssertTrue(parts.styledEdges.isEmpty)
        XCTAssertEqual(parts.nodeTexts.count, 2)
    }
}
