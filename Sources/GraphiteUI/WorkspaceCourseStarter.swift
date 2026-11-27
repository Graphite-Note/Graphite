/**
 * File: WorkspaceCourseStarter.swift
 * ----------------------------------
 * Layer: UI
 * Description: New Course: makes the course starter's files where they are missing, then a course page through the
 *              starter's base of courses.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import Foundation
import GraphiteCore

extension WorkspaceModel {
    /// Makes the course starter in `directory` (or `Courses`) where its files are missing, never replacing one, then
    /// makes a course named `name` with New of the starter's `Courses.base`, which opens it in a new tab.
    func createCourse(named name: String, in directory: VaultPath?) async {
        guard let bases = baseVaultAccess, let services = baseNoteServices else { return }
        do {
            let courseFolder = try directory.flatMap { folder in folder.rawValue.isEmpty ? nil : folder } ?? VaultPath(CourseStarter.defaultCourseFolder)
            let coursesBase = try await installCourseStarter(in: courseFolder, store: bases.store)
            let model = bases.model(of: coursesBase)
            await model.reload()
            if let loadError = model.loadErrorMessage { throw GraphiteError.unavailable(loadError) }
            guard await model.createNewItem(named: name, services: services) != nil else {
                throw GraphiteError.unavailable(model.takeActionErrorMessage(otherwise: "The course was not made."))
            }
        } catch { errorMessage.report(error) }
    }

    /// Writes the starter's missing files and folders, declares its properties' types the vault has not declared, and
    /// returns its base of courses.
    private func installCourseStarter(in courseFolder: VaultPath, store: VaultStore) async throws -> VaultPath {
        let templatesFolder = try templateSettings.folderPath ?? VaultPath(CourseStarter.defaultTemplatesFolder)
        let templatePath = try CourseStarter.path(of: .courseTemplate, courseFolder: courseFolder, templatesFolder: templatesFolder)
        var written: [VaultPath] = []
        for file in CourseStarter.File.allCases {
            let path = try CourseStarter.path(of: file, courseFolder: courseFolder, templatesFolder: templatesFolder)
            guard try await !store.fileExists(path) else { continue }
            let resourceText = try CourseStarterResources.text(of: file)
            let text = CourseStarter.text(of: file, resourceText: resourceText, courseFolder: courseFolder, templatePath: templatePath)
            try await store.createDirectory(path.parent)
            _ = try await store.save(Data(text.utf8), at: path, expecting: .absent)
            written.append(path)
        }
        for folder in try CourseStarter.folders(courseFolder: courseFolder) { try await store.createDirectory(folder) }
        let declared = await store.propertyTypes()
        for (name, type) in CourseStarter.propertyTypes where declared[name] == nil {
            try await store.setPropertyType(type, forKey: name)
        }
        propertyTypesVersion += 1
        if !written.isEmpty { refreshIndex(for: written) }
        return try CourseStarter.path(of: .courses, courseFolder: courseFolder, templatesFolder: templatesFolder)
    }
}
