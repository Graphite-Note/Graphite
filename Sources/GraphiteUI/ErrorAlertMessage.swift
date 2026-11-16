/**
 * File: ErrorAlertMessage.swift
 * -----------------------------
 * Layer: UI
 * Description: The message an alert shows for an error, and none for a task that was only cancelled (HUNT-332).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation

extension Error {
    /// True for an error that only says the work was stopped: a cancelled task, a cancelled download, a
    /// choice the person cancelled. Nothing went wrong, so nothing is shown for it.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        if let cocoaError = self as? CocoaError, cocoaError.code == .userCancelled { return true }
        return false
    }
}

extension Optional where Wrapped == String {
    /// Shows `error`'s description in the alert this message drives, unless the error is a
    /// cancellation, which leaves the message as it was. A view's task, a save or a load stopped
    /// because a tab was hidden or replaced showed "The operation couldn't be completed.
    /// (Swift.CancellationError error 1.)" (HUNT-332).
    mutating func report(_ error: any Error) {
        guard !error.isCancellation else { return }
        self = error.localizedDescription
    }
}
