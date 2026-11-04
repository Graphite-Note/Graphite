// swift-tools-version: 6.2
/**
 * File: Package.swift
 * -------------------
 * Layer: Build
 * Description: The standalone package that reads Goodnotes and Notability notebooks, with its tests; a warning in
 *              any of its targets fails the build.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */
import PackageDescription

// Reads Goodnotes (`.goodnotes`) and Notability (`.note`) notebooks page by page and plans each page as plain values
// (page size, background, strokes, pictures, recordings) with a report of what it simplified or left out.
// Foundation, CoreGraphics and zlib only: it knows no app and writes no file.
let package = Package(
    name: "NotebookImport",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "NotebookImport", targets: ["NotebookImport"])
    ],
    targets: [
        .target(name: "NotebookImport"),
        .testTarget(name: "NotebookImportTests", dependencies: ["NotebookImport"])
    ]
)

// Graphite's own code builds with no warning (RULES.md, "No warnings"): a warning in any of this package's
// targets fails the build. Dependencies are other packages and keep their own settings.
for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
