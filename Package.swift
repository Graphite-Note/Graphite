// swift-tools-version: 6.2
/**
 * File: Package.swift
 * -------------------
 * Layer: Build
 * Description: The Swift package of Graphite's modules, tests and benchmarks, its dependencies, the system framework
 *              linked by name (AVKit), and the setting that makes a warning in any of its targets fail the build.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.23
 * Date: 28/11/2026
 */
import PackageDescription

let package = Package(
    name: "Graphite",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [
        .library(name: "GraphiteUI", targets: ["GraphiteUI"]),
        .library(name: "GraphiteCore", targets: ["GraphiteCore"]),
        .library(name: "GraphiteApple", targets: ["GraphiteApple"]),
        .executable(name: "GraphiteBenchmarks", targets: ["GraphiteBenchmarks"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        // Vendored Textual 0.5.0 with Graphite's patches, each listed in Vendor/textual/GRAPHITE-PATCHES.md.
        .package(path: "Vendor/textual"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        // SwiftDraw (zlib license) draws the SVG files Graphite did not write; Apple's frameworks read no SVG.
        .package(url: "https://github.com/swhitty/SwiftDraw.git", exact: "0.29.0"),
        // The PostgreSQL Mirror core plugin's client: the PostgreSQL wire protocol over SwiftNIO.
        .package(url: "https://github.com/vapor/postgres-nio.git", exact: "1.33.1"),
        // A trimmed copy of mlx-audio-swift (MIT) that runs the downloadable Read Aloud voices;
        // its changes from upstream are listed in Vendor/mlx-audio-swift/GRAPHITE-PATCHES.md.
        .package(path: "Vendor/mlx-audio-swift"),
        // Standalone packages (Docs/solid/rewrite-foundations.md section 3.5): they know nothing of Graphite.
        .package(path: "Packages/NotebookImport"),
        // Mermaid diagrams read, laid out and drawn natively, in Pele's style: Graphite's own package, in a repository of its own.
        .package(url: "https://github.com/Graphite-Note/MermaidDiagrams.git", exact: "0.8.1"),
        // Other note apps' exports turned into vault files, Notion's HTML export and API first: Graphite's own package, in a repository of its own.
        .package(url: "https://github.com/Graphite-Note/Importer.git", exact: "0.5.2")
    ],
    targets: [
        .target(name: "GraphiteCore", dependencies: [
            .product(name: "Markdown", package: "swift-markdown"),
            .product(name: "Yams", package: "Yams")
        ]),
        .target(name: "GraphiteIndex", dependencies: ["GraphiteCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "GraphiteApple", dependencies: ["GraphiteCore", .product(name: "NotebookImport", package: "NotebookImport"),
                                            .product(name: "SwiftDraw", package: "SwiftDraw")], resources: [.copy("Resources/MathSpeech")]),
        // The PostgreSQL Mirror core plugin: a one-way copy of the index into a PostgreSQL database.
        .target(name: "GraphitePostgreSQLMirror", dependencies: ["GraphiteCore", "GraphiteIndex", .product(name: "PostgresNIO", package: "postgres-nio")]),
        // The on-device neural voices: model loading and rendering with MLX.
        .target(name: "GraphiteVoices", dependencies: ["GraphiteCore", "GraphiteApple", .product(name: "MLXAudioTTS", package: "mlx-audio-swift")],
                resources: [.copy("Resources/NeuralVoices.json"), .copy("Resources/DiaVoicePrompt.json")]),
        .target(name: "GraphiteUI", dependencies: ["GraphiteCore", "GraphiteIndex", "GraphiteApple", "GraphiteVoices", "GraphitePostgreSQLMirror", .product(name: "Textual", package: "textual"),
                                          .product(name: "NotebookImport", package: "NotebookImport"),
                                          .product(name: "MermaidDiagrams", package: "MermaidDiagrams"),
                                          .product(name: "Importer", package: "Importer")],
                // The Obsidian plugin runtime's page, scripts and vendored libraries, copied as
                // one folder so the page's relative script paths keep working.
                // The theme resolver's default variables and probe script (`ThemeTokenResolver`).
                // The course starter's bases and template (`CourseStarter`).
                // The release history the What's New page shows (`ReleaseHistory.bundledForThisDevice`).
                resources: [.copy("Resources/CommunityPluginRuntime"), .copy("Resources/ThemeResolver"), .copy("Resources/CourseStarter"), .copy("Resources/ReleaseNotes.md")],
                // SwiftUI's VideoPlayer (`EmbeddedMediaPlayer`) subclasses AVKit's AVPlayerView. `import AVKit` only
                // hints AVKit to the linker, which drops it as no symbol of it is named, and `_AVKit_SwiftUI` does not
                // load it on macOS 27.2: without this link the Swift runtime aborts as it builds the player (HUNT-398).
                linkerSettings: [.linkedFramework("AVKit")]),
        .executableTarget(name: "GraphiteBenchmarks", dependencies: ["GraphiteCore", "GraphiteIndex"]),
        // Fakes and helpers the test targets share (temporary vaults, isolated preferences, the one polling
        // wait, the conflict-version fake). It imports XCTest, so only test targets depend on it.
        .target(name: "GraphiteTestSupport", dependencies: ["GraphiteCore", "GraphiteApple"], path: "Tests/GraphiteTestSupport"),
        // Where the checked-in fixture vaults under `Tests/` are found, for every test target that reads one.
        .target(name: "GraphiteFixtures", path: "Tests/GraphiteFixtures"),
        // The babbling clip is a real Qwen3-TTS rendering, to test the checks on real audio.
        .testTarget(name: "GraphiteCoreTests", dependencies: ["GraphiteCore", "GraphiteTestSupport", "GraphiteFixtures"], resources: [.copy("Resources/QwenBabbling.m4a")]),
        .testTarget(name: "GraphiteIndexTests", dependencies: ["GraphiteIndex", "GraphiteBenchmarks", "GraphiteTestSupport", "GraphiteFixtures"]),
        .testTarget(name: "GraphiteAppleTests", dependencies: ["GraphiteApple", "GraphiteTestSupport", "GraphiteFixtures",
                                                          .product(name: "NotebookImport", package: "NotebookImport")]),
        .testTarget(name: "GraphitePostgreSQLMirrorTests", dependencies: ["GraphitePostgreSQLMirror", "GraphiteIndex", "GraphiteTestSupport", .product(name: "PostgresNIO", package: "postgres-nio")]),
        .testTarget(name: "GraphiteUITests", dependencies: ["GraphiteUI", "GraphiteTestSupport", "GraphiteFixtures", .product(name: "Textual", package: "textual"),
                                                       .product(name: "NotebookImport", package: "NotebookImport"),
                                                       .product(name: "PostgresNIO", package: "postgres-nio"),
                                                       .product(name: "MermaidDiagrams", package: "MermaidDiagrams"),
                                                       .product(name: "Importer", package: "Importer")])
    ]
)

// Graphite's own code builds with no warning (RULES.md, "No warnings"): a warning in any of this package's
// targets fails the build. Dependencies are other packages and keep their own settings.
for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
