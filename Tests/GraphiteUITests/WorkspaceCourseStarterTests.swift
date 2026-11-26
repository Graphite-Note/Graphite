/**
 * File: WorkspaceCourseStarterTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: New Course on a vault opened in a workspace: the starter's files made once, the course page made from
 *              its template through New, and a second course that changes no starter file.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class WorkspaceCourseStarterTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    private static let starterFiles = ["Courses/Courses.base", "Courses/Assignments.base", "Courses/Lectures.base", "Templates/Course.md"]

    func testNewCourseMakesTheStarterOnceAndACoursePageThatEmbedsItsViews() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Welcome.md": "Hello"])
        try await waitUntil("the vault is indexed", timeoutSeconds: 20) { workspace.hasCompletedIndexScan }
        await workspace.createCourse(named: "VLSI 3", in: nil)
        XCTAssertNil(workspace.errorMessage)

        for file in Self.starterFiles {
            XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(file).path), file)
        }
        let coursesBase = try BaseDefinition.parse(try testBed.text(of: "Courses/Courses.base", in: vault))
        XCTAssertEqual(coursesBase.newItemFolder, "Courses")
        XCTAssertEqual(coursesBase.newItemTemplate, "Templates/Course.md")
        XCTAssertEqual(coursesBase.formulas.map(\.name), ["assignments", "lectures", "done", "progress"])
        XCTAssertTrue(coursesBase.issues.isEmpty, "\(coursesBase.issues)")

        let course = try testBed.text(of: "Courses/VLSI 3.md", in: vault)
        XCTAssertTrue(course.hasPrefix("---\ntype: course\n"), course)
        XCTAssertTrue(course.contains("![[Courses/Assignments.base#This course]]"), course)
        XCTAssertTrue(course.contains("![[Courses/Lectures.base#This course]]"), course)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Courses/Assignments").path))
        let types = await workspace.store?.propertyTypes() ?? [:]
        XCTAssertEqual(types["course"], .multitext)
        XCTAssertEqual(types["done"], .checkbox)

        let starterTexts = try Self.starterFiles.map { file in try testBed.text(of: file, in: vault) }
        await workspace.createCourse(named: "Signals", in: try VaultPath("Courses"))
        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(try Self.starterFiles.map { file in try testBed.text(of: file, in: vault) }, starterTexts)
        XCTAssertTrue(try testBed.text(of: "Courses/Signals.md", in: vault).contains("![[Courses/Assignments.base#This course]]"))
    }

    func testTheStartersBasesReadWithoutProblems() throws {
        let folder = try VaultPath("Study/Courses")
        let template = try VaultPath("Templates/Course.md")
        for file in CourseStarter.File.allCases where file != .courseTemplate {
            let text = CourseStarter.text(of: file, resourceText: try CourseStarterResources.text(of: file), courseFolder: folder, templatePath: template)
            let definition = try BaseDefinition.parse(text)
            XCTAssertTrue(definition.issues.isEmpty, "\(file.rawValue): \(definition.issues)")
            XCTAssertFalse(text.contains("@COURSE"), file.rawValue)
            for formula in definition.formulas { XCTAssertNoThrow(try BaseExpression.parse(formula.sourceText), formula.name) }
            for view in definition.views { XCTAssertFalse(view.hasUnreadableFilters, "\(file.rawValue) › \(view.name)") }
        }
    }
}
