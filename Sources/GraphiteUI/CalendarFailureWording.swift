/**
 * File: CalendarFailureWording.swift
 * ----------------------------------
 * Layer: UI
 * Description: The words the person reads when a Calendar or Reminders feature fails: Graphite's own typed failures
 *              in their catalogue sentences, anything else in one sentence, with the detail kept for the log.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import OSLog
import GraphiteCore
import GraphiteApple

/// The words of a Calendar or Reminders failure. Graphite's typed failures (`CalendarStoreError`, `GraphiteError`,
/// `CalendarNoteFailure`) say what happened in their own sentences; a failure of EventKit or the file system is told in
/// one sentence, and its detail goes to the log only.
enum CalendarFailureWording {
    private static let log = Logger(subsystem: "com.graphite.study", category: "Calendar")

    static func words(for failure: any Error, doing activity: CalendarActivity) -> String {
        switch failure {
        case let storeFailure as CalendarStoreError: return storeFailure.errorDescription ?? activity.failureSentence
        case let vaultFailure as GraphiteError: return vaultFailure.errorDescription ?? activity.failureSentence
        case let noteFailure as CalendarNoteFailure: return noteFailure.sentence
        default:
            log.error("\(activity.failureSentence, privacy: .public) \(String(describing: failure), privacy: .private)")
            return activity.failureSentence
        }
    }
}

/// What the Calendar core plugin was doing when it failed, for the sentence that tells the person.
enum CalendarActivity {
    case readingEvents, makingEventNote, savingSettings, sendingTask, readingReminders, tickingTasks

    var failureSentence: String {
        switch self {
        case .readingEvents: "Graphite could not read the events from Calendar. Try again in a moment."
        case .makingEventNote: "Graphite could not make the event's note."
        case .savingSettings: "Graphite could not save the Calendar settings in “.obsidian/graphite-calendar.json”."
        case .sendingTask: "Graphite could not send the task to Reminders. Try again in a moment."
        case .readingReminders: "Graphite could not read your reminders. Try again in a moment."
        case .tickingTasks: "Graphite could not tick a linked task."
        }
    }
}

/// Why a note with a linked task could not be read or ticked.
enum CalendarNoteFailure: Error, Equatable {
    case noVaultOpen
    case notText(VaultPath)

    var sentence: String {
        switch self {
        case .noVaultOpen: "Open the task's vault first."
        case .notText(let path): "“\(path.stem)” is not a text note."
        }
    }
}
