/**
 * File: GitGraphOptions.swift
 * ---------------------------
 * Layer: Core
 * Description: The options of a Git graph its front matter sets under `config:` and `gitGraph:`.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

/// The options of Git graphs a diagram's front matter sets (`config:`, then `gitGraph:`), with Mermaid's defaults: the
/// main branch's name and lane order, whether branch names and lanes, and commit ids, are shown, whether ids are turned
/// an eighth of a turn, and whether commits stand by their distance from the first one rather than one after another.
public struct GitGraphOptions: Equatable, Sendable {
    /// `mainBranchName`: the branch every graph starts on.
    public internal(set) var mainBranchName = "main"
    /// `mainBranchOrder`: the main branch's place among the lanes, as `order:` gives the others'.
    public internal(set) var mainBranchOrder = 0
    /// `showBranches`: the lanes' lines and the branches' names.
    public internal(set) var showsBranches = true
    /// `showCommitLabel`: the commits' ids (their tags are shown either way).
    public internal(set) var showsCommitLabels = true
    /// `rotateCommitLabel`: ids turned an eighth of a turn, else level under (or beside) their commit.
    public internal(set) var rotatesCommitLabels = true
    /// `parallelCommits`: each commit one step past its farthest parent, so commits of different branches made from the
    /// same point stand side by side; else every commit one step past the commit made before it.
    public internal(set) var placesCommitsInParallel = false
    /// Whether the front matter sets a `gitGraph` option this does not apply, or one of these to a value of the wrong
    /// kind: such a graph is refused rather than drawn otherwise than Mermaid draws it.
    public internal(set) var setsOptionsNotApplied = false

    /// Options that set nothing: Mermaid's defaults.
    public init() {}

    /// Options without effect on a drawing of fixed size: `useMaxWidth` (the reading view always fits the column).
    private static let ignoredNames: Set<String> = ["useMaxWidth"]

    init(_ options: MermaidFrontMatterOptions) {
        for (name, value) in options.values {
            switch (name, value) {
            case ("mainBranchName", .text(let text)) where !text.isEmpty: mainBranchName = text
            case ("mainBranchOrder", .number(let number)) where number == number.rounded() && abs(number) < 1_000_000: mainBranchOrder = Int(number)
            case ("showBranches", .boolean(let isShown)): showsBranches = isShown
            case ("showCommitLabel", .boolean(let isShown)): showsCommitLabels = isShown
            case ("rotateCommitLabel", .boolean(let isTurned)): rotatesCommitLabels = isTurned
            case ("parallelCommits", .boolean(let isParallel)): placesCommitsInParallel = isParallel
            default: if !Self.ignoredNames.contains(name) { setsOptionsNotApplied = true }
            }
        }
    }
}
