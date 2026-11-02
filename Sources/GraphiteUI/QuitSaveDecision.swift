/**
 * File: QuitSaveDecision.swift
 * ----------------------------
 * Layer: UI
 * Description: Whether Graphite quits once saving the open documents has ended, and what it says when it does not.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */

import Foundation

/// How saving the open documents ended when the person asked to quit.
enum QuitSaveOutcome {
    case succeeded
    /// A save failed and what it held could not be kept anywhere else.
    case failed(any Error)
    /// The deadline passed while a save was still running.
    case timedOut
    /// Something could not be saved, or a save did not end in time, but all of it is in
    /// drafts outside the vault, which come back when the document opens next.
    case keptInDrafts
}

/// Why Graphite stays open instead of quitting.
enum QuitBlockingReason: Equatable {
    case saveFailed(errorDescription: String)
    case saveTooSlow

    /// What the workspace's alert tells the person, who can then resolve the conflict or
    /// save a copy of the note before quitting again.
    var presentedMessage: String {
        switch self {
        case .saveFailed(let errorDescription):
            return "Graphite did not quit because a note could not be saved, and quitting would lose what you typed. Resolve the conflict or save a copy of the note, then quit again. " + errorDescription
        case .saveTooSlow:
            return "Graphite did not quit because saving your notes is taking longer than expected, and quitting now could lose what you typed. Try quitting again in a moment."
        }
    }
}

/// Whether Graphite quits once saving the open documents has ended. It quits when nothing
/// is left only in memory: every save succeeded, or what could not be saved is in a draft
/// outside the vault. So a note that can never be saved does not keep Graphite open for
/// good, and text that is nowhere else does.
struct QuitSaveDecision: Equatable {
    let allowsTermination: Bool
    let blockingReason: QuitBlockingReason?

    init(outcome: QuitSaveOutcome) {
        switch outcome {
        case .succeeded, .keptInDrafts:
            allowsTermination = true
            blockingReason = nil
        case .failed(let error):
            allowsTermination = false
            blockingReason = .saveFailed(errorDescription: error.localizedDescription)
        case .timedOut:
            allowsTermination = false
            blockingReason = .saveTooSlow
        }
    }
}
