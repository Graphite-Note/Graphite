/**
 * File: NotionImportSession.swift
 * -------------------------------
 * Layer: UI
 * Description: One import of Notion's HTML export into the open vault, from the chosen export to closing its summary,
 *              with Pause, Resume and Cancel.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import Observation
import GraphiteCore

/// One import of Notion's export into the open vault, from the moment the person chooses the export until they close its
/// summary. It owns the import's work, which runs away from the main actor (`NotionImportRun`), and shows its progress,
/// then its summary. The workspace makes one only when an import starts and lets it go when its summary is closed, so
/// nothing of the Importer exists while it is not used.
@MainActor @Observable
final class NotionImportSession {
    enum State: Equatable {
        case importing(NotionImportProgress, isPaused: Bool, isCancelling: Bool)
        case finished(NotionImportSummary)
    }

    private(set) var state: State = .importing(NotionImportProgress(), isPaused: false, isCancelling: false)

    @ObservationIgnored private let pause: NotionImportPause
    @ObservationIgnored private var importTask: Task<NotionImportSummary, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    var isImporting: Bool {
        if case .importing = state { true } else { false }
    }

    /// Starts importing `sources` (Notion's zips, or the folder one unzips to, chosen by the person) into `directory`.
    init(sources: [URL], directory: VaultPath, run: NotionImportRun) {
        pause = run.pause
        let (progressUpdates, continuation) = AsyncStream.makeStream(of: NotionImportProgress.self, bufferingPolicy: .bufferingNewest(1))
        let importTask = Task.detached(priority: .utility) {
            let summary = await run.run(sources: sources, into: directory, progress: continuation)
            continuation.finish()
            return summary
        }
        self.importTask = importTask
        progressTask = Task { [weak self] in
            for await progress in progressUpdates { self?.show(progress) }
            let summary = await importTask.value
            self?.state = .finished(summary)
        }
    }

    /// Holds the import before its next write. What it has written stays, and the vault stays usable meanwhile.
    func pauseImport() {
        guard case .importing(let progress, isPaused: false, isCancelling: false) = state else { return }
        pause.pause()
        state = .importing(progress, isPaused: true, isCancelling: false)
    }

    func resumeImport() {
        guard case .importing(let progress, isPaused: true, let isCancelling) = state else { return }
        pause.resume()
        state = .importing(progress, isPaused: false, isCancelling: isCancelling)
    }

    /// Stops the import at its next page. The pages and attachments written so far stay, and the report note, written
    /// all the same, says the import was stopped.
    func cancelImport() {
        guard case .importing(let progress, _, isCancelling: false) = state else { return }
        state = .importing(progress, isPaused: false, isCancelling: true)
        importTask?.cancel()
        pause.resume()
    }

    /// Stops the import, if it runs, and the task that follows it: the session's end, when the workspace lets it go.
    func stopImportAndObservation() {
        importTask?.cancel()
        pause.resume()
        progressTask?.cancel()
    }

    private func show(_ progress: NotionImportProgress) {
        guard case .importing(_, let isPaused, let isCancelling) = state else { return }
        state = .importing(progress, isPaused: isPaused, isCancelling: isCancelling)
    }
}
