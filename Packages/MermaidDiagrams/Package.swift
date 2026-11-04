// swift-tools-version: 6.2
/**
 * File: Package.swift
 * -------------------
 * Layer: Build
 * Description: The standalone package that reads, lays out and draws Mermaid diagrams, with its benchmark and
 *              tests; a warning in any of its targets fails the build.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 04/11/2026
 */
import PackageDescription

// Reads Mermaid diagram text, lays the diagram out and draws it into a Core Graphics context, in Pele's visual style.
// Foundation, CoreGraphics and CoreText only: it knows no app, and reads and writes no file.
let package = Package(
    name: "MermaidDiagrams",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "MermaidDiagrams", targets: ["MermaidDiagrams"])
    ],
    targets: [
        .target(name: "MermaidDiagrams"),
        // Times reading, layout and drawing on the inputs of Pele's benchmark (`swift run -c release MermaidDiagramsBenchmark`);
        // its resources are the flowchart examples of Mermaid's documentation, as Pele's benchmark collects them.
        .executableTarget(name: "MermaidDiagramsBenchmark", dependencies: ["MermaidDiagrams"], resources: [.copy("Resources")]),
        .testTarget(name: "MermaidDiagramsTests", dependencies: ["MermaidDiagrams", "MermaidDiagramsBenchmark"])
    ]
)

// Graphite's own code builds with no warning (RULES.md, "No warnings"): a warning in any of this package's
// targets fails the build. Dependencies are other packages and keep their own settings.
for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
