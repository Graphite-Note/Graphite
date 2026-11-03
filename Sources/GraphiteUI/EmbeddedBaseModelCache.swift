/**
 * File: EmbeddedBaseModelCache.swift
 * ----------------------------------
 * Layer: UI
 * Description: The models of bases embedded in notes, kept for when a note scrolls back or opens again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The state of recently shown embedded bases. A note's editor drops the views of bases
/// scrolled out of sight; with this cache a base scrolled back shows its last results at
/// once and runs again only if the vault changed meanwhile. Keep one per open vault and
/// note editor, and drop it when the vault closes.
///
/// Bounded by what its models hold as well as by count, since one base can hold thousands of
/// rows. A model off screen lets go of its loaded records (`releaseLoadedRecords`), and the
/// whole cache goes on a memory warning: all it saves is a run of each base.
@MainActor
public final class EmbeddedBaseModelCache {
    /// Each kept model holds its result, so only a few are kept.
    private let capacity: Int
    /// The most its models may hold together, estimated; the model used last always stays.
    static let maximumEstimatedBytes = 32 * 1_048_576
    /// Most recently used last.
    private var entries: [(identity: EmbeddedBaseView.EmbedIdentity, model: BaseDocumentModel)] = []
    private var memoryWarningObserver: (any NSObjectProtocol)?

    public init(capacity: Int = 8) {
        self.capacity = capacity
        #if canImport(UIKit)
        memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
            queue: .main) { [weak self] _ in
            Task { @MainActor in self?.removeAllModels() }
        }
        #endif
    }

    isolated deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    /// Models kept now, which a test counts.
    var modelCount: Int { entries.count }

    /// Gives back the memory, as a memory warning asks. A base on screen keeps its model.
    func removeAllModels() {
        entries.removeAll()
    }

    func model(for identity: EmbeddedBaseView.EmbedIdentity, makeModel: () -> BaseDocumentModel) -> BaseDocumentModel {
        if let position = entries.firstIndex(where: { entry in entry.identity == identity }) {
            let entry = entries.remove(at: position)
            entries.append(entry)
            removeModelsBeyondBudget()
            return entry.model
        }
        let model = makeModel()
        entries.append((identity, model))
        removeModelsBeyondBudget()
        return model
    }

    /// A base finished a run, so what its model holds may have grown.
    func modelDidLoad() {
        removeModelsBeyondBudget()
    }

    private func removeModelsBeyondBudget() {
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        var estimatedBytes = entries.reduce(0) { total, entry in total + entry.model.estimatedHeldBytes }
        while estimatedBytes > Self.maximumEstimatedBytes, entries.count > 1 {
            estimatedBytes -= entries.removeFirst().model.estimatedHeldBytes
        }
    }
}
