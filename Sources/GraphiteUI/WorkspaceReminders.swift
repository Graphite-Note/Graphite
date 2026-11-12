/**
 * File: WorkspaceReminders.swift
 * ------------------------------
 * Layer: UI
 * Description: The Calendar core plugin's tasks and reminders: a task sent to Reminders, ticked on either side and
 *              ticked on the other, and reminders brought into a note as tasks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

/// The Calendar core plugin's tasks and reminders. Only the tasks the person sends are linked, each by the block ID on
/// its line and the link its reminder carries back (`ReminderTaskLink`); nothing else keeps the pairing. Graphite ticks
/// and unticks the reminders it made, and never deletes a reminder.
extension WorkspaceModel {
    /// Whether each linked task was done when it and its reminder last agreed, by block ID, kept on this device for the
    /// vault (`GraphiteLinkedTasks.<vault UUID>`). It only tells which side changed; when it is lost, being done wins.
    static func linkedTasksKey(for vaultIdentifier: UUID) -> String {
        "GraphiteLinkedTasks." + vaultIdentifier.uuidString
    }

    private var linkedTaskAgreements: [String: Bool] {
        get {
            guard let currentVaultIdentifier else { return [:] }
            return deviceDefaults.dictionary(forKey: Self.linkedTasksKey(for: currentVaultIdentifier)) as? [String: Bool] ?? [:]
        }
        set {
            guard let currentVaultIdentifier else { return }
            deviceDefaults.set(newValue, forKey: Self.linkedTasksKey(for: currentVaultIdentifier))
        }
    }

    /// Sends the task at the cursor of `session`'s note to Reminders, with its words as the title and its 📅 day as the
    /// due date, and links the two by a block ID at the end of the task's line (one it has already is used).
    func sendTaskToReminders(from session: MarkdownSession) async {
        guard let (_, task) = MarkdownTaskLine.line(at: session.selection.location, in: session.text), !task.description.isEmpty else {
            notice = "Put the cursor on a task to send it to Reminders."
            return
        }
        guard !task.isDone else {
            notice = "This task is done already."
            return
        }
        guard await calendarAccess(to: .reminders, asking: true).canRead else {
            errorMessage = CalendarStoreError.accessRefused(.reminders).errorDescription
            return
        }
        let calendarStore = processServices.calendar.store
        var generator = SystemRandomNumberGenerator()
        let blockIdentifier = task.blockIdentifier ?? TaskReminderEditing.newBlockIdentifier(using: &generator)
        do {
            if try await linkedReminders().contains(where: { linked in linked.blockIdentifier == blockIdentifier }) {
                notice = "This task is in Reminders already."
                return
            }
            guard let link = ReminderTaskLink.url(openingLink: openingLink(to: session.path), blockIdentifier: blockIdentifier) else { return }
            let settings = (try? await store?.calendarSettings()) ?? CalendarSettings() // An unreadable file: the default list.
            let draft = ReminderDraft(title: task.description, dueDay: task.dueDay, listTitle: settings.taskListTitle.isEmpty ? nil : settings.taskListTitle,
                                      link: link)
            try await calendarStore.save(.add(draft))
            // The note may have changed while Reminders saved: the task is found again at the cursor's line.
            if task.blockIdentifier == nil, let (lineRange, currentTask) = MarkdownTaskLine.line(at: session.selection.location, in: session.text),
               currentTask.description == task.description,
               let edit = TaskReminderEditing.linkingEdit(lineRange: lineRange, in: session.text, blockIdentifier: blockIdentifier) {
                session.apply(edit)
            }
            linkedTaskAgreements[blockIdentifier] = false
            followReminderChanges()
            notice = "“\(task.description)” is in Reminders."
        } catch { errorMessage = CalendarFailureWording.words(for: error, doing: .sendingTask) }
    }

    /// Brings the open reminders into `session`'s note as tasks at the cursor: those of the list chosen in
    /// Settings › Calendar, or of every list.
    func insertReminders(into session: MarkdownSession) async {
        guard await calendarAccess(to: .reminders, asking: true).canRead else {
            errorMessage = CalendarStoreError.accessRefused(.reminders).errorDescription
            return
        }
        do {
            let settings = (try? await store?.calendarSettings()) ?? CalendarSettings() // An unreadable file: every list.
            let reminders = try await processServices.calendar.store.reminders().filter { reminder in
                settings.importedListTitle.isEmpty || reminder.listTitle == settings.importedListTitle
            }
            let tasks = ReminderTaskList.markdown(for: reminders)
            guard !tasks.isEmpty else {
                notice = settings.importedListTitle.isEmpty
                    ? "There are no open reminders." : "There are no open reminders in “\(settings.importedListTitle)”."
                return
            }
            session.apply(BlockInsertion.edit(inserting: tasks, into: session.text, at: session.selection))
        } catch { errorMessage = CalendarFailureWording.words(for: error, doing: .readingReminders) }
    }

    // MARK: Keeping linked tasks and reminders ticked alike

    /// Ticks each linked task whose reminder was completed, and each reminder whose task was ticked (and unticks
    /// likewise), as Graphite comes to the front or leaves it, opens a vault, or hears that Reminders changed. It asks
    /// nothing: until the person used Reminders through Graphite on this device, and without access, it reads nothing.
    func updateLinkedTasksAndReminders() async {
        guard preferences.isEnabled(.calendar), store != nil, deviceDefaults.bool(forKey: Self.usesRemindersKey),
              processServices.calendar.store.access(to: .reminders).canRead else { return }
        followReminderChanges()
        do {
            let linked = try await linkedReminders()
            guard !linked.isEmpty else { return }
            var agreements = linkedTaskAgreements
            let today = CalendarDay(.now, in: personalCalendar)
            var unchangedNotes: [String] = []
            for linkedReminder in linked {
                do {
                    let lastAgreedCompletion = agreements[linkedReminder.blockIdentifier]
                    if let agreed = try await bringIntoAgreement(linkedReminder, lastAgreedCompletion: lastAgreedCompletion, today: today) {
                        agreements[linkedReminder.blockIdentifier] = agreed
                    }
                } catch {
                    unchangedNotes.append("“\(linkedReminder.notePath.stem)”: " + CalendarFailureWording.words(for: error, doing: .tickingTasks))
                }
            }
            linkedTaskAgreements = agreements
            if !unchangedNotes.isEmpty {
                errorMessage = "Some tasks could not be ticked as their reminders are:\n" + unchangedNotes.prefix(5).joined(separator: "\n")
            }
        } catch { errorMessage = CalendarFailureWording.words(for: error, doing: .readingReminders) }
    }

    /// Listens for changes in Calendar and Reminders once this vault links tasks, for as long as the window lives.
    func followReminderChanges() {
        processServices.calendar.follow(self) { [weak self] in await self?.updateLinkedTasksAndReminders() }
    }

    /// The reminders Graphite made for tasks of this vault, with the note and block ID each links to.
    private func linkedReminders() async throws -> [LinkedReminder] {
        try await processServices.calendar.store.reminders().compactMap { reminder in
            guard let link = reminder.link, let target = ReminderTaskLink.target(of: link), isCurrentVault(named: target.vaultName) else { return nil }
            return LinkedReminder(reminder: reminder, notePath: target.notePath, blockIdentifier: target.blockIdentifier)
        }
    }

    /// Makes one task and its reminder agree; returns whether the task is done once they agree, or nil when the task
    /// is not found (its note was moved or its ID removed), which leaves both as they are.
    private func bringIntoAgreement(_ linkedReminder: LinkedReminder, lastAgreedCompletion: Bool?, today: CalendarDay) async throws -> Bool? {
        let reminder = linkedReminder.reminder
        guard let notePath = try await noteHoldingTask(linkedReminder.blockIdentifier, expectedAt: linkedReminder.notePath) else { return nil }
        let text = try await linkedNoteText(at: notePath)
        guard let (lineRange, task) = MarkdownTaskLine.line(withBlockIdentifier: linkedReminder.blockIdentifier, in: text) else { return nil }
        switch ReminderCompletionChange.needed(taskIsDone: task.isDone, reminderIsCompleted: reminder.isCompleted, lastAgreedCompletion: lastAgreedCompletion) {
        case .none:
            return task.isDone
        case .completeTask, .reopenTask:
            guard let edit = TaskReminderEditing.completionEdit(lineRange: lineRange, in: text, isDone: reminder.isCompleted, on: today) else {
                return task.isDone
            }
            try await applyToLinkedNote(edit, at: notePath, expectedText: text)
            return reminder.isCompleted
        case .completeReminder, .reopenReminder:
            try await processServices.calendar.store.save(.setCompleted(reminderIdentifier: reminder.id, isCompleted: task.isDone))
            return task.isDone
        }
    }

    /// The note that holds the task: where its reminder's link says, or, after a move, the note the search finds it in.
    private func noteHoldingTask(_ blockIdentifier: String, expectedAt expectedPath: VaultPath) async throws -> VaultPath? {
        guard let vaultStore = store else { return nil }
        if try await vaultStore.fileExists(expectedPath),
           MarkdownTaskLine.line(withBlockIdentifier: blockIdentifier, in: try await linkedNoteText(at: expectedPath)) != nil {
            return expectedPath
        }
        guard let index else { return nil }
        let candidates = try await index.search(blockIdentifier, limit: Self.movedTaskSearchLimit).results.map(\.path)
        for candidate in candidates where candidate != expectedPath {
            if MarkdownTaskLine.line(withBlockIdentifier: blockIdentifier, in: try await linkedNoteText(at: candidate)) != nil { return candidate }
        }
        return nil
    }

    private static var movedTaskSearchLimit: Int { 5 }

    /// The note's text as the person sees it: the open editor's, or the file's.
    private func linkedNoteText(at path: VaultPath) async throws -> String {
        if let session = openMarkdownSession(at: path) { return session.text }
        guard let vaultStore = store else { throw CalendarNoteFailure.noVaultOpen }
        let snapshot = try await vaultStore.read(path, maximumBytes: MarkdownSession.maximumEditableBytes)
        guard let decoded = NoteTextEncoding.decode(snapshot.data) else { throw CalendarNoteFailure.notText(path) }
        return decoded.text
    }

    /// Ticks a task in its note: through the open editor, so it can be undone there, or in the file when it did not
    /// change since it was read.
    private func applyToLinkedNote(_ edit: MarkdownTextEdit, at path: VaultPath, expectedText: String) async throws {
        if let session = openMarkdownSession(at: path) {
            guard session.text == expectedText else { return } // Typed meanwhile: the next update ticks it.
            session.apply(edit)
            if !session.isEditorAttached { try await session.save() }
            return
        }
        guard let vaultStore = store else { return }
        let snapshot = try await vaultStore.read(path, maximumBytes: MarkdownSession.maximumEditableBytes)
        guard let decoded = NoteTextEncoding.decode(snapshot.data), decoded.text == expectedText else { return } // Changed meanwhile: next time.
        let editedText = (decoded.text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        _ = try await vaultStore.save(NoteTextEncoding.encode(editedText, hasByteOrderMark: decoded.hasByteOrderMark), at: path,
                                      expecting: .revision(snapshot.revision))
        refreshIndex(for: [path])
    }
}

/// A reminder Graphite made for a task of the open vault, with the note and block ID its link names.
private struct LinkedReminder {
    let reminder: ReminderItem
    let notePath: VaultPath
    let blockIdentifier: String
}
