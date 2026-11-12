/**
 * File: TaskReminders.swift
 * -------------------------
 * Layer: Core
 * Description: Tasks written with the Tasks plugin's fields (`- [ ] Pay rent 📅 2026-11-20`), the block ID that links
 *              a task to its reminder, the edits that link and tick a task, and which side of a link changed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation

/// A task line of a note, read with the Tasks plugin's conventions, which Obsidian users already write: the due day
/// after 📅, the day it was done after ✅, and an optional block ID (`^reminder-k3j9x2ab`) at the end.
public struct MarkdownTaskLine: Equatable, Sendable {
    /// The status character between the brackets: a space for an open task, `x` for a done one.
    public let status: Character
    /// The task's words without its date fields, priority signs and block ID.
    public let description: String
    public let dueDay: CalendarDay?
    public let blockIdentifier: String?

    public var isDone: Bool { status != " " }

    private static let taskPattern = TaskReminderPattern.task.compiled()
    private static let dueDayPattern = TaskReminderPattern.dueDay.compiled()
    private static let blockIdentifierPattern = TaskReminderPattern.blockIdentifier.compiled()
    private static let fieldPattern = TaskReminderPattern.removedField.compiled()

    /// Reads one line (without its line break); nil when it is not a task.
    public init?(line: String) {
        let source = line as NSString
        guard let match = Self.taskPattern.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { return nil }
        status = Character(source.substring(with: match.range(at: 2)))
        let body = source.substring(with: match.range(at: 4))
        let bodySource = body as NSString
        let bodyRange = NSRange(location: 0, length: bodySource.length)
        dueDay = Self.dueDayPattern.firstMatch(in: body, range: bodyRange).flatMap { dueMatch in
            CalendarDay(isoText: bodySource.substring(with: dueMatch.range(at: 1)))
        }
        let blockMatch = Self.blockIdentifierPattern.firstMatch(in: body, range: bodyRange)
        blockIdentifier = blockMatch.map { blockMatch in bodySource.substring(with: blockMatch.range(at: 1)) }
        var words = blockMatch.map { blockMatch in bodySource.substring(to: blockMatch.range.location) } ?? body
        words = Self.fieldPattern.stringByReplacingMatches(in: words, range: NSRange(location: 0, length: (words as NSString).length), withTemplate: "")
        description = words.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// The task line around `location` in `text`, with the line's range (without its line break); nil when the line
    /// there is not a task.
    public static func line(at location: Int, in text: String) -> (range: NSRange, task: MarkdownTaskLine)? {
        let source = text as NSString
        let clampedLocation = min(max(0, location), source.length)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        source.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: clampedLocation, length: 0))
        let range = NSRange(location: lineStart, length: contentsEnd - lineStart)
        return MarkdownTaskLine(line: source.substring(with: range)).map { task in (range, task) }
    }

    /// The line of the task whose block ID is `blockIdentifier`, as `line(at:in:)` gives it; nil when no task has it.
    public static func line(withBlockIdentifier blockIdentifier: String, in text: String) -> (range: NSRange, task: MarkdownTaskLine)? {
        let source = text as NSString
        var found: (range: NSRange, task: MarkdownTaskLine)?
        // Only lines that mention the ID are read as tasks, so a long note is passed over quickly.
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, stop in
            let line = source.substring(with: lineRange)
            guard line.contains("^" + blockIdentifier), let task = MarkdownTaskLine(line: line), task.blockIdentifier == blockIdentifier else { return }
            found = (lineRange, task)
            stop.pointee = true
        }
        return found
    }
}

/// The edits that link a task to its reminder and tick it, as the Tasks plugin writes them.
public enum TaskReminderEditing {
    private static let taskPattern = TaskReminderPattern.task.compiled()
    private static let doneFieldPattern = TaskReminderPattern.doneField.compiled()

    /// The edit that gives the task at `lineRange` the block ID `blockIdentifier` at its end; nil when the task has a
    /// block ID already, which then links it (another note may link to the task by it, so it is never replaced).
    public static func linkingEdit(lineRange: NSRange, in text: String, blockIdentifier: String) -> MarkdownTextEdit? {
        let source = text as NSString
        let line = source.substring(with: lineRange)
        guard let task = MarkdownTaskLine(line: line), task.blockIdentifier == nil else { return nil }
        let trimmedLength = (line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) as NSString).length
        let insertion = " ^" + blockIdentifier
        let location = lineRange.location + trimmedLength
        return MarkdownTextEdit(range: NSRange(location: location, length: lineRange.length - trimmedLength), replacement: insertion,
                                selectionAfter: NSRange(location: location + (insertion as NSString).length, length: 0))
    }

    /// The edit that ticks the task at `lineRange` with ` ✅ 2026-11-12` before its block ID, or unticks it and takes
    /// its done day away; nil when the task is already so.
    public static func completionEdit(lineRange: NSRange, in text: String, isDone: Bool, on day: CalendarDay) -> MarkdownTextEdit? {
        let source = text as NSString
        let line = source.substring(with: lineRange)
        guard let task = MarkdownTaskLine(line: line), task.isDone != isDone else { return nil }
        let lineSource = line as NSString
        guard let statusMatch = taskPattern.firstMatch(in: line, range: NSRange(location: 0, length: lineSource.length)) else { return nil }
        let statusRange = statusMatch.range(at: 2)
        var newLine = lineSource.replacingCharacters(in: statusRange, with: isDone ? "x" : " ")
        newLine = doneFieldPattern.stringByReplacingMatches(in: newLine, range: NSRange(location: 0, length: (newLine as NSString).length), withTemplate: "")
        if isDone {
            let doneField = " ✅ " + day.isoText
            if let blockIdentifier = task.blockIdentifier, let blockRange = newLine.range(of: " ^" + blockIdentifier, options: .backwards) {
                newLine.insert(contentsOf: doneField, at: blockRange.lowerBound)
            } else {
                newLine = newLine.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) + doneField
            }
        }
        let selectionAfter = NSRange(location: lineRange.location + (newLine as NSString).length, length: 0)
        return MarkdownTextEdit(range: lineRange, replacement: newLine, selectionAfter: selectionAfter)
    }

    /// A new block ID for a task's reminder: `reminder-` and eight lowercase letters and digits.
    public static func newBlockIdentifier(using generator: inout some RandomNumberGenerator) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return "reminder-" + String((0..<8).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
    }
}

/// The link a reminder Graphite made carries back to its task: the note's `graphite://open` link, which opens the note
/// from Reminders, with the task's block ID added (`…&block=reminder-k3j9x2ab`). Nothing else keeps the pairing, so
/// it can always be found again from the vault and the Reminders store.
public enum ReminderTaskLink {
    public static let blockParameter = "block"

    /// `openingLink` (from `VaultURI.openingLink`) with the block ID added.
    public static func url(openingLink: String, blockIdentifier: String) -> URL? {
        // Added to the text as it is, so the opening link keeps its own encoding (`%2F` for a folder's slash, as Obsidian).
        guard let encodedIdentifier = blockIdentifier.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) else {
            return nil
        }
        return URL(string: openingLink + (openingLink.contains("?") ? "&" : "?") + blockParameter + "=" + encodedIdentifier)
    }

    /// The vault's name, the note's path and the task's block ID of a reminder's link; nil for a link Graphite did not
    /// make for a task.
    public static func target(of link: URL) -> (vaultName: String, notePath: VaultPath, blockIdentifier: String)? {
        guard link.scheme == VaultURI.scheme, let components = URLComponents(url: link, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { item in item.name == name }?.value }
        guard let vaultName = value("vault"), let file = value("file"), let blockIdentifier = value(blockParameter), !blockIdentifier.isEmpty,
              let notePath = try? VaultPath((file as NSString).pathExtension.isEmpty ? file + ".md" : file) else { return nil } // No path: not a task's.
        return (vaultName, notePath, blockIdentifier)
    }
}

/// What makes a linked task and its reminder agree again.
public enum ReminderCompletionChange: Equatable, Sendable {
    case none, completeTask, reopenTask, completeReminder, reopenReminder

    /// The change for a task and its reminder that differ. `lastAgreedCompletion` is whether both were done when they
    /// last agreed, which tells the side that changed; when it was lost, being done wins, so no completion is undone.
    public static func needed(taskIsDone: Bool, reminderIsCompleted: Bool, lastAgreedCompletion: Bool?) -> ReminderCompletionChange {
        guard taskIsDone != reminderIsCompleted else { return .none }
        switch lastAgreedCompletion {
        case .some(let agreed) where agreed == taskIsDone: return reminderIsCompleted ? .completeTask : .reopenTask
        case .some: return taskIsDone ? .completeReminder : .reopenReminder
        case .none: return reminderIsCompleted ? .completeTask : .completeReminder
        }
    }
}

/// Reminders as Markdown tasks, to bring a Reminders list into a note.
public enum ReminderTaskList {
    /// The open reminders as tasks with their due days (`- [ ] Milk 📅 2026-11-13`), grouped by list under the list's
    /// name in bold when there is more than one list. Empty when no reminder is open.
    public static func markdown(for reminders: [ReminderItem]) -> String {
        let open = reminders.filter { reminder in !reminder.isCompleted }
        let lists = Dictionary(grouping: open, by: \.listTitle)
        let listTitles = lists.keys.sorted { first, second in first.localizedStandardCompare(second) == .orderedAscending }
        return listTitles.map { listTitle in
            let tasks = (lists[listTitle] ?? []).sorted(by: isListedBefore).map { reminder in
                "- [ ] " + oneLine(reminder.title) + (reminder.dueDay.map { day in " 📅 " + day.isoText } ?? "") + "\n"
            }.joined()
            return listTitles.count > 1 ? "**" + oneLine(listTitle) + "**\n" + tasks : tasks
        }.joined(separator: "\n")
    }

    /// Reminders with a due day first, the earliest first, then by title.
    private static func isListedBefore(_ first: ReminderItem, _ second: ReminderItem) -> Bool {
        switch (first.dueDay, second.dueDay) {
        case let (firstDay?, secondDay?) where firstDay != secondDay: return firstDay < secondDay
        case (.some, .none): return true
        case (.none, .some): return false
        case (.some, .some), (.none, .none): return first.title.localizedStandardCompare(second.title) == .orderedAscending
        }
    }

    private static func oneLine(_ text: String) -> String {
        let words = text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return words.isEmpty ? "Untitled Reminder" : words
    }
}

/// The constant patterns of the task fields; `StaticPatternTests` compiles every case.
enum TaskReminderPattern: String, StaticPatternSet {
    /// A list item with a checkbox: the marker and `[`, the status, `] `, then the task's words.
    case task = #"^([ \t]*(?:[-*+]|\d+[.)])[ \t]+\[)([^\]\n])(\][ \t]+)(.*)$"#
    /// The due day, after 📅 (or the Tasks plugin's other due signs 📆 and 🗓).
    case dueDay = #"(?:📅|📆|🗓)\x{FE0F}?[ \t]*(\d{4}-\d{2}-\d{2})"#
    /// A block ID at the end of the line.
    case blockIdentifier = #"(?:^|[ \t])\^([A-Za-z0-9-]+)[ \t]*$"#
    /// The done day, with the space before it.
    case doneField = #"[ \t]*✅\x{FE0F}?[ \t]*\d{4}-\d{2}-\d{2}"#
    /// The Tasks plugin's date fields and priority signs, left out of a reminder's title.
    case removedField = #"(?:(?:📅|📆|🗓|⏳|⌛|🛫|➕|✅|❌)\x{FE0F}?[ \t]*\d{4}-\d{2}-\d{2}|⏫|🔼|🔽|⏬|🔺)"#
}
