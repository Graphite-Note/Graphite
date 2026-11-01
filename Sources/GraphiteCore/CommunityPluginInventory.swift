import Foundation

/// What Graphite can tell about a plugin before running it: whether it can load at all,
/// and which modules its code asks for that Graphite does not provide.
public struct CommunityPluginCompatibility: Equatable, Sendable {
    /// The Obsidian plugin API version Graphite's runtime follows (`apiVersion`). Parts it
    /// does not implement report themselves as unsupported when a plugin uses them.
    public static let providedApiVersion = "1.14.4"

    public enum Blocker: Equatable, Sendable {
        /// `isDesktopOnly`: Obsidian mobile does not load it either.
        case desktopOnly
        /// `minAppVersion` is newer than the API Graphite provides.
        case needsNewerApi(required: String)
        /// The package has no `main.js`.
        case missingMainScript
    }

    public enum ModuleKind: Equatable, Sendable {
        /// Node.js or Electron, which only Obsidian's desktop app has.
        case desktopOnly
        /// A part of CodeMirror that Obsidian does not give plugins either.
        case codeMirror
        /// A module Obsidian does not provide to plugins either.
        case unknown
    }

    public struct RequiredModule: Equatable, Sendable {
        public let name: String
        public let kind: ModuleKind
    }

    public let blockers: [Blocker]
    /// Modules the code mentions in `require(…)` that Graphite lacks. A plugin may only
    /// reach them on desktop, so they are reported rather than refused. Empty until
    /// `CommunityPluginModuleScanner` has read the code.
    public let missingModules: [RequiredModule]

    public var canLoad: Bool { blockers.isEmpty }

    static let desktopModuleNames: Set<String> = [
        "electron", "fs", "fs/promises", "path", "os", "child_process", "crypto", "http", "https", "net", "tls", "dns", "zlib",
        "stream", "util", "url", "events", "buffer", "assert", "worker_threads", "readline", "process", "module", "vm",
        "querystring", "string_decoder", "timers", "tty", "dgram", "cluster", "perf_hooks", "v8", "original-fs",
    ]

    /// The CodeMirror 6 and Lezer modules Obsidian gives plugins, which the runtime vendors
    /// (`Resources/CommunityPluginRuntime/Vendor/VERSIONS.md`): plugins that require them load.
    static let providedCodeMirrorModuleNames: Set<String> = [
        "@codemirror/autocomplete", "@codemirror/commands", "@codemirror/language", "@codemirror/lint", "@codemirror/search",
        "@codemirror/state", "@codemirror/view", "@lezer/common", "@lezer/highlight", "@lezer/lr",
    ]

    private static let requirePattern = CommunityPluginCompatibilityPattern.requirePattern.compiled()

    public static func assess(manifest: CommunityPluginManifest, mainScript: String?, providedApiVersion: String = CommunityPluginCompatibility.providedApiVersion) -> Self {
        let withoutCode = assess(manifest: manifest, hasMainScript: mainScript != nil, providedApiVersion: providedApiVersion)
        return Self(blockers: withoutCode.blockers, missingModules: mainScript.map(missingModules(in:)) ?? [])
    }

    /// Whether the plugin can load, which takes its manifest and no reading of its code.
    public static func assess(manifest: CommunityPluginManifest, hasMainScript: Bool, providedApiVersion: String = CommunityPluginCompatibility.providedApiVersion) -> Self {
        var blockers: [Blocker] = []
        if manifest.isDesktopOnly { blockers.append(.desktopOnly) }
        if let required = manifest.minimumApplicationVersion, ObsidianVersionNumber.compare(required, providedApiVersion) == .orderedDescending {
            blockers.append(.needsNewerApi(required: required))
        }
        return Self(blockers: hasMainScript ? blockers : blockers + [.missingMainScript], missingModules: [])
    }

    func listing(missingModules: [RequiredModule]) -> Self {
        Self(blockers: blockers, missingModules: missingModules)
    }

    static func missingModules(in mainScript: String) -> [RequiredModule] {
        let source = mainScript as NSString
        var seenNames: Set<String> = []
        var modules: [RequiredModule] = []
        for match in requirePattern.matches(in: mainScript, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1))
            guard name != "obsidian", !name.hasPrefix("."), !providedCodeMirrorModuleNames.contains(name), seenNames.insert(name).inserted else { continue }
            let baseName = name.hasPrefix("node:") ? String(name.dropFirst("node:".count)) : name
            let kind: ModuleKind
            if desktopModuleNames.contains(baseName) || desktopModuleNames.contains(String(baseName.split(separator: "/").first ?? "")) {
                kind = .desktopOnly
            } else if baseName.hasPrefix("@codemirror/") || baseName.hasPrefix("@lezer/") {
                kind = .codeMirror
            } else {
                kind = .unknown
            }
            modules.append(RequiredModule(name: baseName, kind: kind))
        }
        return modules.sorted { firstModule, secondModule in firstModule.name < secondModule.name }
    }
}

/// A plugin folder in `.obsidian/plugins`, read without running anything.
public struct InstalledCommunityPlugin: Identifiable, Equatable, Sendable {
    public var id: String { manifest.identifier }
    /// The plugin's folder, which Obsidian names after the identifier but does not require to.
    public let folder: VaultPath
    public let manifest: CommunityPluginManifest
    public let compatibility: CommunityPluginCompatibility

    public init(folder: VaultPath, manifest: CommunityPluginManifest, compatibility: CommunityPluginCompatibility) {
        self.folder = folder
        self.manifest = manifest
        self.compatibility = compatibility
    }
}

/// Everything the runtime needs to load a plugin.
public struct CommunityPluginPackage: Sendable {
    public let plugin: InstalledCommunityPlugin
    public let mainScript: String
    public let styles: String
}

/// A plugin folder that could not be read as a plugin, with the reason.
public struct UnreadableCommunityPlugin: Identifiable, Equatable, Sendable {
    public var id: VaultPath { folder }
    public let folder: VaultPath
    public let reason: String
}

public struct CommunityPluginInventory: Equatable, Sendable {
    public let plugins: [InstalledCommunityPlugin]
    public let unreadableFolders: [UnreadableCommunityPlugin]

    public init(plugins: [InstalledCommunityPlugin] = [], unreadableFolders: [UnreadableCommunityPlugin] = []) {
        self.plugins = plugins
        self.unreadableFolders = unreadableFolders
    }
}

public extension VaultStore {
    /// The largest `main.js` Graphite reads. Obsidian sets no limit; the largest popular
    /// plugins bundle about 10 MB.
    static let maximumPluginScriptBytes = 48 * 1_048_576
    static let maximumPluginStylesBytes = 8 * 1_048_576

    /// Every plugin folder in `.obsidian/plugins`, sorted by name, from their manifests and
    /// the size of their code: `main.js` is not read, so the listing stays small however
    /// large the plugins are. `CommunityPluginModuleScanner` reads it for the Settings page.
    func installedCommunityPlugins() throws -> CommunityPluginInventory {
        let pluginsFolder = try VaultPath(CommunityPluginList.pluginsFolderPath)
        guard try fileExists(pluginsFolder) else { return CommunityPluginInventory(plugins: [], unreadableFolders: []) }
        var plugins: [InstalledCommunityPlugin] = []
        var unreadableFolders: [UnreadableCommunityPlugin] = []
        for entry in try children(of: pluginsFolder) where entry.isDirectory {
            do {
                let manifestSnapshot = try read(entry.path.appending("manifest.json"), maximumBytes: CommunityPluginManifest.maximumManifestBytes)
                let manifest = try CommunityPluginManifest(manifestData: manifestSnapshot.data)
                let mainScriptPath = try entry.path.appending("main.js")
                let hasMainScript = try fileExists(mainScriptPath)
                if hasMainScript { try Self.checkPluginScriptSize(at: mainScriptPath.url(in: root)) }
                plugins.append(InstalledCommunityPlugin(folder: entry.path, manifest: manifest, compatibility: .assess(manifest: manifest, hasMainScript: hasMainScript)))
            } catch {
                unreadableFolders.append(UnreadableCommunityPlugin(folder: entry.path, reason: error.localizedDescription))
            }
        }
        plugins.sort { firstPlugin, secondPlugin in firstPlugin.manifest.name.localizedStandardCompare(secondPlugin.manifest.name) == .orderedAscending }
        return CommunityPluginInventory(plugins: plugins, unreadableFolders: unreadableFolders)
    }

    private static func checkPluginScriptSize(at location: URL) throws {
        let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if size > maximumPluginScriptBytes { throw GraphiteError.oversized("This plugin's main.js is too large for Graphite to read.") }
    }

    /// The plugin's code and styles, read again so the runtime loads what is on disk now.
    func communityPluginPackage(for plugin: InstalledCommunityPlugin) throws -> CommunityPluginPackage {
        let mainScriptData = try read(plugin.folder.appending("main.js"), maximumBytes: Self.maximumPluginScriptBytes).data
        let stylesPath = try plugin.folder.appending("styles.css")
        let styles = try fileExists(stylesPath) ? String(decoding: try read(stylesPath, maximumBytes: Self.maximumPluginStylesBytes).data, as: UTF8.self) : ""
        return CommunityPluginPackage(plugin: plugin, mainScript: String(decoding: mainScriptData, as: UTF8.self), styles: styles)
    }
}

/// Finds the modules plugins' code asks for, for the Settings page. It reads each `main.js`
/// and goes through all of it, so this is its own actor, apart from the vault's store, and
/// note opening and saving never queue behind it. A plugin whose file has the same size and
/// date is not read again.
public actor CommunityPluginModuleScanner {
    private struct FileVersion: Equatable {
        let size: Int
        let modified: Date?
    }

    private var scans: [URL: (version: FileVersion, modules: [CommunityPluginCompatibility.RequiredModule])] = [:]
    private let findModules: @Sendable (String) -> [CommunityPluginCompatibility.RequiredModule]

    public init() {
        findModules = { mainScript in CommunityPluginCompatibility.missingModules(in: mainScript) }
    }

    /// - Parameter findModules: What reads a plugin's code; given here to count how often it runs.
    init(findModules: @escaping @Sendable (String) -> [CommunityPluginCompatibility.RequiredModule]) {
        self.findModules = findModules
    }

    /// The inventory with what the scans found. Only plugins scanned before fill in unless
    /// `isReadingCode` is true.
    public func inventory(_ inventory: CommunityPluginInventory, root: URL, isReadingCode: Bool) -> CommunityPluginInventory {
        let plugins = inventory.plugins.map { plugin -> InstalledCommunityPlugin in
            guard plugin.compatibility.blockers.contains(.missingMainScript) == false,
                  let location = try? plugin.folder.appending("main.js").url(in: root),
                  let modules = modules(at: location, isReadingCode: isReadingCode) else { return plugin }
            return InstalledCommunityPlugin(folder: plugin.folder, manifest: plugin.manifest, compatibility: plugin.compatibility.listing(missingModules: modules))
        }
        return CommunityPluginInventory(plugins: plugins, unreadableFolders: inventory.unreadableFolders)
    }

    private func modules(at location: URL, isReadingCode: Bool) -> [CommunityPluginCompatibility.RequiredModule]? {
        guard let values = try? location.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        let version = FileVersion(size: values.fileSize ?? 0, modified: values.contentModificationDate)
        if let scan = scans[location], scan.version == version { return scan.modules }
        guard isReadingCode, version.size <= VaultStore.maximumPluginScriptBytes, let code = try? Data(contentsOf: location, options: .mappedIfSafe) else { return nil }
        let modules = findModules(String(decoding: code, as: UTF8.self))
        scans[location] = (version, modules)
        return modules
    }
}

/// The constant patterns of `CommunityPluginCompatibility`; `StaticPatternTests` compiles every case.
enum CommunityPluginCompatibilityPattern: String, StaticPatternSet {
    case requirePattern = #"\brequire\(\s*["']([^"'\s]{1,200})["']\s*\)"#
}
