/**
 * File: ReadingGitGraphTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The reading view's Git graphs.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 20/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteIndex
import MermaidDiagrams
@testable import GraphiteUI
import GraphiteTestSupport

/// A ```mermaid block holding a Git graph: read and laid out with the note's other blocks, off the main actor, in the
/// note's text size; one that cannot be read keeps its source and says why; one that sets Git graph options
/// Graphite does not apply shows its source and why.
final class ReadingGitGraphTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func gitGraph(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .gitGraph)
    }

    func testAGitGraphIsLaidOutInTheNotesTextSize() throws {
        let gitGraph = try gitGraph("gitGraph\n commit id:\"init\"\n branch develop\n commit tag:\"v1\"\n checkout main\n merge develop")
        XCTAssertEqual(gitGraph.scene.font.size, 17)
        XCTAssertEqual(gitGraph.accessibility.summary, ["main: init", "develop: v1"])
        XCTAssertEqual(gitGraph.scene.texts(reading: "develop").count, 1, "Each branch's lane is named.")
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try gitGraph("gitGraph\n title History\n accDescr: Two branches\n commit")
        XCTAssertEqual(titled.accessibility.title, "History")
        XCTAssertEqual(titled.accessibility.description, "Two branches")
        XCTAssertEqual(try gitGraph("gitGraph\n accTitle: Named\n title Shown\n commit").accessibility.title, "Named")
        XCTAssertNil(try gitGraph("gitGraph\n commit").accessibility.title)
        XCTAssertEqual(try gitGraph("gitGraph\n commit").accessibility.summary, ["main"])
    }

    func testAGitGraphThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "gitGraph\n commit\n checkout nope"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 3, problem: .gitGraph(.unknownBranch(name: "nope")))))
    }

    func testAGitGraphWithFrontMatterOptionsIsDrawnWithThem() throws {
        let source = "---\nconfig:\n  gitGraph:\n    showBranches: false\n    mainBranchName: trunk\n---\ngitGraph\n commit\n checkout trunk\n commit"
        let gitGraph = try gitGraph(source)
        XCTAssertTrue(gitGraph.scene.texts(reading: "trunk").isEmpty, "Branches hidden.")
        XCTAssertEqual(gitGraph.accessibility.summary, ["trunk"])
    }

    func testAGitGraphWithAnOptionPeleDoesNotKnowIsDrawnAsPeleDrawsIt() {
        let source = "---\nconfig:\n  gitGraph:\n    nodeLabel: x\n---\ngitGraph\n commit"
        XCTAssertNoThrow(try ReadingDiagram(source: source, typography: typography).drawn(as: .gitGraph))
    }

    /// Options in a `%%{init: …}%%` directive, on one line or several, are read as Pele reads them (9fc1219f).
    func testAGitGraphWithDirectiveOptionsIsDrawnWithThem() throws {
        for source in ["%%{init: {'gitGraph': {'mainBranchName': 'trunk'}}}%%\ngitGraph\n commit\n checkout trunk",
                       "%%{\n  init: {'gitGraph': {'mainBranchName': 'trunk'}}\n}%%\ngitGraph\n commit"] {
            XCTAssertEqual(try gitGraph(source).accessibility.summary, ["trunk"], source)
        }
    }

    func testEveryGitGraphProblemIsExplainedApart() {
        let problems: [GitGraphSyntaxProblem] = [
            .expectedBranchName, .expectedCommitType, .expectedOrder, .branchAlreadyExists(name: "b"), .unknownBranch(name: "b"),
            .branchMergedIntoItself(name: "b"), .currentBranchWithoutCommits(name: "b"), .mergedBranchWithoutCommits(name: "b"),
            .branchesShareTheirLastCommit(name: "b"), .duplicateCommitIdentifier("a"), .cherryPickWithoutIdentifier, .unknownCommit(identifier: "a"),
            .cherryPickFromCurrentBranch(identifier: "a"), .mergeCherryPickedWithoutParent(identifier: "a"), .notAParent(parent: "p", identifier: "a"),
        ]
        XCTAssertEqual(Set(problems.map(\.explanation)).count, problems.count)
        XCTAssertFalse(Set(problems.map(\.explanation)).contains(MermaidSyntaxProblem.unexpectedText("b").explanation))
    }

    /// A Git graph written to run down (`gitGraph TB:`) is drawn running down: taller than wide.
    func testTheReadingViewBuildsAGitGraphBlockBetweenTheTextAroundIt() async throws {
        let vault = try TemporaryVault.make(prefix: "GitGraphVault", for: self).root
        defer { try? FileManager.default.removeItem(at: vault) } // Best-effort removal of a temporary folder.
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let blocks = try await ReadingViewBuilder().build(source: "Before\n\n```mermaid\ngitGraph TB:\n  commit\n  commit\n  branch b\n  commit\n  commit\n```\n\nAfter",
                                                           note: try VaultPath("Note.md"), root: vault, index: index,
                                                           configuration: ReadingConfiguration()).blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .diagram(_, let diagram) = blocks[1] else { return XCTFail("The Git graph is drawn") }
        let scene = try diagram.drawn(as: .gitGraph).scene
        XCTAssertGreaterThan(scene.size.height, scene.size.width)
    }
}
