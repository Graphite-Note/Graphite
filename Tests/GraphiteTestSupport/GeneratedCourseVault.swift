/**
 * File: GeneratedCourseVault.swift
 * --------------------------------
 * Layer: Tests
 * Description: A made-up vault of course notes of any size, shaped as the owner's vault of 4,700 notes is (few
 *              links, many tags, many notes with neither), for the graph's benchmarks and its look.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation
import GraphiteCore

/// A made-up vault of lecture notes in course folders, with the proportions of the owner's
/// vault of about 4,700 notes (2026-10-21: "4,700 notes · 699 tags · 1,690 links"): about one
/// link for every three notes, mostly to a lecture of the same course, one tag for every seven
/// notes, mostly a course's own, and many notes with neither. Nothing in it comes from a real
/// note. The same count and seed give the same vault, so runs compare.
public struct GeneratedCourseVault: Sendable {
    public struct Note: Sendable {
        public let path: VaultPath
        public let markdown: String
        /// The notes this one links to, as `[[name]]` in its text.
        public let linkedPaths: [VaultPath]
        /// Its tags, without `#`, as written in its text.
        public let tags: [String]
    }

    public let notes: [Note]

    /// Lectures per course folder: the owner's courses have a few dozen to a few hundred notes.
    static let notesPerCourse = 150
    /// Topic tags per course, beside the course's own tag.
    static let topicTagsPerCourse = 21
    /// The shares of notes that link to the lecture before, to another lecture of their course,
    /// and to a lecture of another course; about 0.36 links a note in all.
    static let previousLectureLinkShare = 0.25
    static let sameCourseLinkShare = 0.08
    static let otherCourseLinkShare = 0.03
    /// The shares of notes that carry their course's tag and one of its topics.
    static let courseTagShare = 0.45
    static let topicTagShare = 0.25

    public init(noteCount: Int, seed: UInt64 = 2_026) {
        var generator = SeededRandomNumberGenerator(seed: seed)
        let courseCount = max(1, (noteCount + Self.notesPerCourse - 1) / Self.notesPerCourse)
        let paths = (0..<noteCount).map { noteNumber in Self.path(ofNote: noteNumber) }
        notes = (0..<noteCount).map { noteNumber in
            let course = noteNumber / Self.notesPerCourse
            let courseStart = course * Self.notesPerCourse, courseEnd = min(courseStart + Self.notesPerCourse, noteCount)
            var linked: [Int] = []
            if noteNumber > courseStart, Double.random(in: 0..<1, using: &generator) < Self.previousLectureLinkShare { linked.append(noteNumber - 1) }
            if Double.random(in: 0..<1, using: &generator) < Self.sameCourseLinkShare { linked.append(Int.random(in: courseStart..<courseEnd, using: &generator)) }
            if courseCount > 1, Double.random(in: 0..<1, using: &generator) < Self.otherCourseLinkShare {
                linked.append(Int.random(in: 0..<noteCount, using: &generator))
            }
            linked = linked.filter { linkedNumber in linkedNumber != noteNumber }
            var tags: [String] = []
            if Double.random(in: 0..<1, using: &generator) < Self.courseTagShare { tags.append(Self.courseTag(course)) }
            if Double.random(in: 0..<1, using: &generator) < Self.topicTagShare {
                tags.append("topic-\(course * Self.topicTagsPerCourse + Int.random(in: 0..<Self.topicTagsPerCourse, using: &generator))")
            }
            let linkedPaths = linked.map { linkedNumber in paths[linkedNumber] }
            return Note(path: paths[noteNumber], markdown: Self.markdown(ofNote: noteNumber, linking: linkedPaths, tags: tags), linkedPaths: linkedPaths, tags: tags)
        }
    }

    /// The graph the index builds from these notes, made without one: every link resolves to
    /// its note, and each note carries its tags.
    public var linkGraph: LinkGraph {
        LinkGraph.build(files: notes.map(\.path),
                        links: notes.flatMap { note in note.linkedPaths.map { target in (source: note.path, target: target) } },
                        unresolvedLinks: [],
                        tags: notes.flatMap { note in note.tags.map { tag in (path: note.path, tag: tag) } })
    }

    static func path(ofNote noteNumber: Int) -> VaultPath {
        let course = noteNumber / notesPerCourse
        // Made of letters, digits and spaces only, so it is always a valid path.
        return (try? VaultPath("Course \(course)/Lecture \(course)-\(noteNumber % notesPerCourse).md")) ?? .root
    }

    static func courseTag(_ course: Int) -> String { "course/c\(course)" }

    private static func markdown(ofNote noteNumber: Int, linking linkedPaths: [VaultPath], tags: [String]) -> String {
        var lines = ["# Lecture \(noteNumber)", "", "Sampling, quantization and the delay of a chain of inverters."]
        if !tags.isEmpty { lines += ["", tags.map { tag in "#" + tag }.joined(separator: " ")] }
        for path in linkedPaths { lines += ["", "See [[\(path.stem)]]."] }
        return lines.joined(separator: "\n")
    }
}

/// SplitMix64: a small generator whose numbers depend only on its seed, so a generated vault
/// is the same on every run and platform.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
