/**
 * File: CourseStarterResources.swift
 * ----------------------------------
 * Layer: UI
 * Description: Reads the course starter's files from the app's resources (`Resources/CourseStarter`).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore

/// The course starter's resource texts, with their placeholders (`CourseStarter`).
enum CourseStarterResources {
    /// The starter's files are small; a larger resource is not one of them.
    private static let maximumResourceBytes = 65_536

    static func text(of file: CourseStarter.File) throws -> String {
        let (name, fileExtension) = file.resourceName
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "CourseStarter"),
              let data = try? Data(contentsOf: url), data.count <= maximumResourceBytes, // Unreadable: reported as missing below.
              let text = String(data: data, encoding: .utf8) else {
            throw CourseStarterError.missingResource(file.rawValue)
        }
        return text
    }
}
