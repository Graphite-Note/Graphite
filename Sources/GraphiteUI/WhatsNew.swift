/**
 * File: WhatsNew.swift
 * --------------------
 * Layer: UI
 * Description: The What's New page: every version's Added, Changed and Fixed lines, newest first, with what
 *              came since the last update marked; and its opening once after an update.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import GraphiteCore
import OSLog
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension ReleaseHistory {
    /// The history bundled with this build, narrowed to this device. Read on first use: at a launch that
    /// decides whether to open the page, or when the page opens. A file the test of the bundled history
    /// would refuse reads as an empty history, so the page never shows a partial list.
    @MainActor static let bundledForThisDevice: ReleaseHistory = {
        do {
            return try readBundled().applying(to: .thisDevice)
        } catch {
            Logger(subsystem: "Graphite", category: "WhatsNew")
                .fault("The bundled release history cannot be read: \(String(describing: error), privacy: .public)")
            return ReleaseHistory(versions: [])
        }
    }()

    /// ReleaseNotes.md as this build bundles it, for every device.
    static func readBundled() throws -> ReleaseHistory {
        guard let address = Bundle.module.url(forResource: "ReleaseNotes", withExtension: "md") else { throw CocoaError(.fileNoSuchFile) }
        return try ReleaseHistory.read(String(contentsOf: address, encoding: .utf8))
    }
}

extension ReleaseNotePlatform {
    @MainActor static var thisDevice: ReleaseNotePlatform {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .phone ? .iPhone : .iPad
        #endif
    }
}

/// The build of the last What's New this device showed, or recorded without showing on a new install.
enum WhatsNewPreference {
    static let lastShownBuildKey = "GraphiteWhatsNewLastShownBuild"

    static var currentBuild: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String }
    static var currentVersion: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
}

/// Opens What's New once after an update, when the launch has settled. The build is recorded as seen as
/// the page opens, so when several windows reopen at once the first to settle opens it and the others
/// find the build seen. On a new install it opens nothing: it records the build, and the welcome tour
/// opens instead.
struct AfterUpdateWhatsNew: ViewModifier {
    /// False until the launch has settled, and always false for a launch that hosts tests.
    let isReadyToShow: Bool
    @AppStorage(WhatsNewPreference.lastShownBuildKey) private var lastShownBuild = ""
    @AppStorage(WelcomeTourPreference.shownKey) private var hasSeenWelcomeTour = false
    /// What this window opened the page with: the moment after which groups are new.
    @State private var presentation: WhatsNewPresentation?

    func body(content: Content) -> some View {
        content
            .onChange(of: isReadyToShow, initial: true) { _, isReady in
                if isReady { decide() }
            }
            .sheet(item: $presentation) { presentation in
                WhatsNewPage(history: .bundledForThisDevice, newSince: presentation.newSince)
                    .whatsNewSheetSize()
            }
    }

    private func decide() {
        switch WhatsNewAtLaunch.decide(currentBuild: WhatsNewPreference.currentBuild, lastShownBuild: lastShownBuild.isEmpty ? nil : lastShownBuild,
                                       hasSeenWelcomeTour: hasSeenWelcomeTour, history: .bundledForThisDevice) {
        case .show(let newSince):
            presentation = WhatsNewPresentation(newSince: newSince)
            recordCurrentBuild()
        case .recordSilently: recordCurrentBuild()
        case .nothing: break
        }
    }

    private func recordCurrentBuild() {
        if let build = WhatsNewPreference.currentBuild { lastShownBuild = build }
    }
}

private struct WhatsNewPresentation: Identifiable {
    let id = UUID()
    let newSince: ReleaseMoment?
}

extension View {
    /// Presents What's New as a sheet, from Settings › General.
    func whatsNew(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            WhatsNewPage(history: .bundledForThisDevice, newSince: nil)
                .whatsNewSheetSize()
        }
    }

    fileprivate func whatsNewSheetSize() -> some View {
        #if os(macOS)
        frame(minWidth: 520, idealWidth: 620, minHeight: 520, idealHeight: 720)
        #else
        presentationSizing(.page)
        #endif
    }
}

/// Every version's changes on this device, newest first, one version after another down a single
/// scroll. The groups written after `newSince` carry a New mark.
struct WhatsNewPage: View {
    let history: ReleaseHistory
    let newSince: ReleaseMoment?
    /// A sheet has Done; the Mac's What's New window closes as windows do.
    var showsDoneButton = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if history.versions.isEmpty {
                    ContentUnavailableView("No Changes Listed", systemImage: "sparkles", description: Text("This build lists no changes."))
                } else {
                    versionList
                }
            }
            .navigationTitle("What’s New")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
    }

    private var versionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28, pinnedViews: .sectionHeaders) {
                if newSince != nil, let newCount = newGroupCount, newCount > 0 {
                    Text("Changes since the last update you opened are marked New.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(history.versions, id: \.name) { version in
                    Section {
                        ForEach(version.groups, id: \.heading) { group in
                            WhatsNewGroupView(group: group, isNew: newSince.map { moment in group.moment > moment } ?? false)
                        }
                    } header: {
                        WhatsNewVersionHeader(name: version.name, isThisVersion: version.name == WhatsNewPreference.currentVersion)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var newGroupCount: Int? {
        guard let newSince else { return nil }
        return history.versions.reduce(0) { count, version in count + version.groups.count(where: { group in group.moment > newSince }) }
    }
}

private struct WhatsNewVersionHeader: View {
    let name: String
    let isThisVersion: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Version \(name)").font(.title2.weight(.bold))
            if isThisVersion {
                Text("Installed").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct WhatsNewGroupView: View {
    let group: ReleaseNoteGroup
    let isNew: Bool
    @Environment(\.accent) private var accent
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(dayText).font(.headline).foregroundStyle(.secondary)
                if isNew {
                    Text("New")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accent, in: Capsule())
                }
            }
            .accessibilityElement(children: .combine)
            ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                WhatsNewEntryRow(entry: entry)
            }
        }
    }

    /// The day, with the time for a group that has one: several uploads a day otherwise read as the same heading.
    private var dayText: String {
        if let dayAndTime = group.dayAndTime, let date = calendar.date(from: dayAndTime) {
            return date.formatted(date: .long, time: .shortened)
        }
        guard let date = calendar.date(from: group.day) else { return group.heading }
        return date.formatted(date: .long, time: .omitted)
    }
}

/// One line: its kind as a coloured word, then what changed, so the kind reads without a legend.
private struct WhatsNewEntryRow: View {
    let entry: ReleaseNoteEntry

    var body: some View {
        Text("\(Text(kindName).fontWeight(.semibold).foregroundStyle(tint))  \(entry.text)")
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kindName: String {
        switch entry.kind {
        case .added: String(localized: "Added")
        case .changed: String(localized: "Changed")
        case .fixed: String(localized: "Fixed")
        }
    }

    private var tint: Color {
        switch entry.kind {
        case .added: .green
        case .changed: .blue
        case .fixed: .orange
        }
    }
}
