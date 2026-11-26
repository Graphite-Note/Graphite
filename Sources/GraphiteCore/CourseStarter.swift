/**
 * File: CourseStarter.swift
 * -------------------------
 * Layer: Core
 * Description: The files of the course starter: a base of courses with rollups of their assignments, bases of
 *              assignments and lectures with a view filtered by this, and the course page's template.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// The course starter (`Docs/Bases-relations-todo.md`, section 4): ordinary `.base` and Markdown files made once in a
/// folder, which Obsidian reads the same. Their text is in the app's resources (`Resources/CourseStarter`), with the
/// course folder and the template's path left as placeholders that `text(of:resourceText:courseFolder:templatePath:)`
/// fills in.
public enum CourseStarter {
    /// Where the starter goes when New Course is chosen outside a folder.
    public static let defaultCourseFolder = "Courses"
    /// Where the course template goes when the vault has no Templates folder.
    public static let defaultTemplatesFolder = "Templates"
    /// The folders of assignments and lectures, inside the course folder.
    public static let assignmentsFolderName = "Assignments"
    public static let lecturesFolderName = "Lectures"

    private static let courseFolderPlaceholder = "@COURSE_FOLDER@"
    private static let courseTemplatePlaceholder = "@COURSE_TEMPLATE@"

    /// One file of the starter, named as its resource is.
    public enum File: String, CaseIterable, Sendable {
        case courses = "Courses.base"
        case assignments = "Assignments.base"
        case lectures = "Lectures.base"
        case courseTemplate = "Course.md"

        /// The resource's name without its extension, and its extension, as `Bundle.url(forResource:withExtension:)` takes them.
        public var resourceName: (name: String, fileExtension: String) {
            ((rawValue as NSString).deletingPathExtension, (rawValue as NSString).pathExtension)
        }
    }

    /// The types the starter's properties take, written to `.obsidian/types.json` for those the vault has not declared.
    public static let propertyTypes: [(name: String, type: PropertyType)] = [
        ("course", .multitext), ("due", .date), ("done", .checkbox), ("weight", .number), ("credits", .number), ("studied", .checkbox),
    ]

    /// Where the file goes: the bases in the course folder, the template in the Templates folder.
    public static func path(of file: File, courseFolder: VaultPath, templatesFolder: VaultPath) throws -> VaultPath {
        switch file {
        case .courses, .assignments, .lectures: try courseFolder.appending(file.rawValue)
        case .courseTemplate: try templatesFolder.appending(file.rawValue)
        }
    }

    /// The folders the starter makes, inside the course folder.
    public static func folders(courseFolder: VaultPath) throws -> [VaultPath] {
        try [courseFolder.appending(assignmentsFolderName), courseFolder.appending(lecturesFolderName)]
    }

    /// The file's text with the course folder and the template's path filled in: inside a base's quoted text and
    /// expressions with `"` and `\` escaped, in the template's Markdown as written.
    public static func text(of file: File, resourceText: String, courseFolder: VaultPath, templatePath: VaultPath) -> String {
        let isBase = file != .courseTemplate
        func filled(_ value: String) -> String {
            isBase ? value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") : value
        }
        return resourceText.replacingOccurrences(of: courseFolderPlaceholder, with: filled(courseFolder.rawValue))
            .replacingOccurrences(of: courseTemplatePlaceholder, with: filled(templatePath.rawValue))
    }
}

/// Why the course starter could not be made.
public enum CourseStarterError: Error, Equatable, LocalizedError, Sendable {
    /// A file of the starter is missing from the app's resources.
    case missingResource(String)

    public var errorDescription: String? {
        switch self {
        case .missingResource(let name): "Graphite's course starter file “\(name)” is missing from the app."
        }
    }
}
