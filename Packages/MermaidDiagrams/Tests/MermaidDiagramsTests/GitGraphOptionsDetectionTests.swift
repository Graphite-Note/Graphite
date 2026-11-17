import XCTest
@testable import MermaidDiagrams

/// A Git graph's options from its front matter and its directives are applied, and one not applied, or written in a
/// form not read, is known; other configuration and comments are not options.
final class GitGraphOptionsDetectionTests: XCTestCase {
    private func setsOptions(_ source: String) throws -> Bool {
        try GitGraphReading.gitGraph(source).setsGitGraphOptions
    }

    func testFrontMatterOptionsAreReadAndThoseNotAppliedOrNotReadAreKnown() throws {
        let read = try GitGraphReading.gitGraph("---\nconfig:\n  logLevel: 'debug'\n  gitGraph:\n    showBranches: false\n---\n      gitGraph\n        commit")
        XCTAssertFalse(read.setsGitGraphOptions)
        XCTAssertFalse(read.options.showsBranches)
        XCTAssertTrue(try setsOptions("---\nconfig: {\"gitGraph\" : {\"parallelCommits\": true}}\n---\ngitGraph\n commit"), "Flow-style options are not read.")
        XCTAssertTrue(try setsOptions("---\nconfig:\n  gitGraph:\n    nodeLabel: x\n---\ngitGraph\n commit"), "An option not applied.")
        XCTAssertTrue(try setsOptions("---\nconfig:\n  gitGraph:\n    showBranches: maybe\n---\ngitGraph\n commit"), "A value of the wrong kind.")
    }

    func testADirectivesOptionsBeforeTheKeywordOrAmongTheStatementsAreAppliedAndThoseNotAppliedAreKnown() throws {
        let before = try GitGraphReading.gitGraph("%%{init: { 'logLevel': 'debug', 'gitGraph': {'showBranches': false}} }%%\ngitGraph\n commit")
        XCTAssertFalse(before.setsGitGraphOptions)
        XCTAssertFalse(before.options.showsBranches)
        let among = try GitGraphReading.gitGraph("gitGraph\n commit\n %%{init: {\"gitGraph\": {\"mainBranchName\": \"dev\"}}}%%\n commit")
        XCTAssertFalse(among.setsGitGraphOptions)
        XCTAssertEqual(among.branches.map(\.name), ["dev"])
        XCTAssertTrue(try setsOptions("%%{init: {'gitGraph': {'nodeLabel': 'x'}}}%%\ngitGraph\n commit"), "An option not applied.")
        XCTAssertFalse(try setsOptions("%%{init: {'gitGraph': {'showBranches': false},}}%%\ngitGraph\n commit"),
                       "A directive whose JSON is not read sets nothing, as in Pele.")
    }

    func testOtherConfigurationAndCommentsSetNone() throws {
        let themed = "---\ntitle: Example Git diagram\nconfig:\n  theme: base\n  themeVariables:\n    git0: '#ff0000'\n---\ngitGraph\n commit"
        XCTAssertFalse(try setsOptions(themed))
        XCTAssertFalse(try setsOptions("%% gitGraph: release flow\ngitGraph\n commit\n %% gitGraph: a note"))
        XCTAssertFalse(try setsOptions("%%{init: {'theme': 'dark'}}%%\ngitGraph:\n commit"))
    }

    func testTheKeyIsFoundWithItsColonOnly() {
        XCTAssertTrue(GitGraphOptionsDetection.setsOptions(in: Array("  gitGraph:".utf8)[...]))
        XCTAssertTrue(GitGraphOptionsDetection.setsOptions(in: Array("'gitGraph' :".utf8)[...]))
        XCTAssertFalse(GitGraphOptionsDetection.setsOptions(in: Array("gitGraph TB:".utf8)[...]))
        XCTAssertFalse(GitGraphOptionsDetection.setsOptions(in: Array("gitGraph".utf8)[...]))
    }
}
