/**
 * File: GitGraphOptionsTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The Git graph options of the front matter applied: the main branch's name and order, hidden branches and
 *              ids, level ids and commits placed in parallel.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class GitGraphOptionsTests: XCTestCase {
    private let smallText = UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18)
    private let branchText = UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21)
    private let titleText = UniformWidthTextMeasurer()

    private func layout(options: String, _ statements: String) throws -> GitGraphLayout {
        let diagram = try GitGraphReading.gitGraph("---\nconfig:\n  gitGraph:\n\(options)\n---\ngitGraph\n\(statements)")
        XCTAssertFalse(diagram.setsGitGraphOptions)
        return try GitGraphLayoutEngine.layout(diagram, smallText: smallText, branchText: branchText, titleText: titleText, font: UniformWidthLayout.font)
    }

    private let history = " commit id: \"one\"\n branch develop\n commit id: \"two\"\n commit id: \"three\"\n checkout main\n commit id: \"four\"\n commit id: \"five\""

    func testEveryOptionIsReadWithMermaidsDefaults() throws {
        XCTAssertEqual(GitGraphOptions(), try GitGraphReading.gitGraph("gitGraph\n commit").options)
        let options = try GitGraphReading.gitGraph("---\nconfig:\n  gitGraph:\n    mainBranchName: 'MetroLine1'\n    mainBranchOrder: 2\n    showBranches: false\n"
                                                   + "    showCommitLabel: false\n    rotateCommitLabel: false\n    parallelCommits: true\n    useMaxWidth: true\n---\n"
                                                   + "gitGraph\n commit").options
        XCTAssertEqual(options.mainBranchName, "MetroLine1")
        XCTAssertEqual(options.mainBranchOrder, 2)
        XCTAssertFalse(options.showsBranches)
        XCTAssertFalse(options.showsCommitLabels)
        XCTAssertFalse(options.rotatesCommitLabels)
        XCTAssertTrue(options.placesCommitsInParallel)
        XCTAssertFalse(options.setsOptionsNotApplied)
    }

    func testTheMainBranchTakesItsNameAndOrder() throws {
        let diagram = try GitGraphReading.gitGraph("---\nconfig:\n  gitGraph:\n    mainBranchName: 'MetroLine1'\n---\ngitGraph\n commit id: \"NewYork\"\n"
                                                   + " branch MetroLine2\n commit id: \"LosAngeles\"\n checkout MetroLine1\n commit id: \"Dallas\"")
        XCTAssertEqual(diagram.branches.map(\.name), ["MetroLine1", "MetroLine2"])
        XCTAssertEqual(diagram.commits.map(\.branchIndex), [0, 1, 0])
        XCTAssertThrowsError(try GitGraphReading.gitGraph("---\nconfig:\n  gitGraph:\n    mainBranchName: trunk\n---\ngitGraph\n commit\n checkout main"),
                             "There is no main branch by its old name.")
    }

    func testHiddenBranchesHaveNoLanesOrNamesAndHiddenIdsNoLabels() throws {
        let shown = try layout(options: "    showBranches: true", history)
        XCTAssertEqual(shown.lanes.count, 2)
        let hidden = try layout(options: "    showBranches: false\n    showCommitLabel: false", history)
        XCTAssertTrue(hidden.lanes.isEmpty)
        XCTAssertEqual(hidden.commits.count, 5)
        XCTAssertTrue(hidden.commits.allSatisfy { commit in commit.label == nil })
        XCTAssertLessThan(hidden.size.height, shown.size.height, "No room is kept for ids below the commits.")
        XCTAssertLessThan(hidden.size.width, shown.size.width, "No room is kept for names before the lanes.")
    }

    func testLevelIdsAreCenteredUnderTheirCommitsAndSpaceThem() throws {
        let level = try layout(options: "    rotateCommitLabel: false", " commit id: \"feat(api): a long label\"\n commit id: \"b\"")
        let first = try XCTUnwrap(level.commits[0].label), second = level.commits[1]
        XCTAssertEqual(first.angle, 0)
        XCTAssertEqual(first.text.center.x, level.commits[0].center.x, accuracy: 0.01)
        XCTAssertGreaterThan(first.text.frame.minY, level.commits[0].center.y)
        XCTAssertLessThan(first.text.frame.maxX, second.center.x - GitGraphGeometry.dotRadius, "The next commit stands past the level id.")
        let turned = try layout(options: "    rotateCommitLabel: true", " commit id: \"feat(api): a long label\"\n commit id: \"b\"")
        XCTAssertNotEqual(try XCTUnwrap(turned.commits[0].label).angle, 0)
    }

    func testCommitsInParallelStandByTheirDistanceFromTheFirst() throws {
        let sequential = try layout(options: "    parallelCommits: false", history)
        XCTAssertEqual(Set(sequential.commits.map { commit in commit.center.x.rounded() }).count, 5, "One after another.")
        let parallel = try layout(options: "    parallelCommits: true", history)
        let xs = parallel.commits.map(\.center.x)
        XCTAssertEqual(xs[1], xs[3], accuracy: 0.01, "The first commits of develop and of main after the branch stand side by side.")
        XCTAssertEqual(xs[2], xs[4], accuracy: 0.01)
        XCTAssertLessThan(parallel.size.width, sequential.size.width)
    }
}
