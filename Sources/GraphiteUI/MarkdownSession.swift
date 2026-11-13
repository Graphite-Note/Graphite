/**
 * File: MarkdownSession.swift
 * ---------------------------
 * Layer: UI
 * Description: An open note: its text, saving, conflicts, drafts of what cannot be saved, and queued insertions.
 *
 * Authors: Bahey Shalash, felixchvl
 * Version: 0.19
 * Date: 11/11/2026
 */

import Foundation
import Observation
import GraphiteCore

@MainActor @Observable
final class MarkdownSession {
    /// The largest note that opens in the editor; a larger one opens read-only (`OversizedNoteDocument`).
    static let maximumEditableBytes = 8 * 1_048_576
    /// The largest note that Edit Anyway loads into the editor, for trimming.
    static let maximumBytesEditableAnyway = 32 * 1_048_576
    /// The most of its file this session reads again: more than `maximumEditableBytes` after Edit Anyway.
    @ObservationIgnored var maximumBytesRead = MarkdownSession.maximumEditableBytes
    /// Another app took the file past `maximumBytesRead`, so the text shown is an old version.
    @ObservationIgnored private(set) var fileOutgrewEditor = false
    /// The note's place in the vault. It changes only as the file moves (`followFile(to:)`), so
    /// closures read it when they run rather than keeping it.
    private(set) var path: VaultPath
    let store: VaultStore
    private let didSave: @MainActor (VaultPath) -> Void
    var text: String {
        didSet {
            guard text != oldValue else { return }
            editVersion += 1
            textDidChange?()
            if !isTakingSharedText { shareText() }
        }
    }
    /// The open notes of every window, where this note's other sessions are found; nil for a
    /// session alone, as in tests.
    @ObservationIgnored let openNotes: OpenNoteFiles?
    /// This note's key among the open notes.
    @ObservationIgnored var fileKey: String
    /// Set while the text comes from another session of the note, so it is not sent back.
    @ObservationIgnored private var isTakingSharedText = false
    /// A window-level consumer can invalidate a reading snapshot even when the
    /// editor is hidden in another tab. The session does not own that consumer.
    @ObservationIgnored var textDidChange: (@MainActor () -> Void)?
    /// Also counts queued insertions, so an asynchronous reload cannot erase work the
    /// editor has not applied yet, or an edit followed by an undo back to the same text.
    private(set) var editVersion = 0
    var selection = NSRange(location: 0, length: 0)
    /// Reading view, Live Preview, or source mode, as for an Obsidian tab. The new mode is stored, and the switch made,
    /// before observers hear of it: SwiftUI can draw the note's pane at once from inside that notice, which Observation
    /// sends before a stored property changes, and a pane drawn there read the mode it was leaving and was not drawn again,
    /// the reading view left on screen in source mode (Docs/Editor-scrolling-todo.md).
    var viewMode: NoteViewMode {
        get {
            access(keyPath: \.viewMode)
            return viewModeSwitch.mode
        }
        set {
            let change = viewModeSwitch.switchMode(to: newValue) { readingPosition.topLocation() }
            if case .leftReading(let topLocation) = change { savedScrollLocation = topLocation }
            if change != .unchanged { didChangeViewMode?(newValue) }
            withMutation(keyPath: \.viewMode) {}
        }
    }
    @ObservationIgnored private var viewModeSwitch = NoteViewModeSwitch()
    /// Tells the workspace a switch to remember, after the note opened in its view.
    @ObservationIgnored var didChangeViewMode: ((NoteViewMode) -> Void)?

    /// The character the reading view starts at, once, after the note switched from writing.
    func takeReadingStartLocation() -> Int? {
        viewModeSwitch.takeReadingStartsWhereEditorWas() ? savedScrollLocation ?? 0 : nil
    }

    /// The character the editor starts at, once, after the note switched from reading.
    func takeEditingStartLocation() -> Int? {
        viewModeSwitch.takeEditingStartLocation()
    }
    /// Link and tag suggestions at the cursor.
    let completion = CompletionModel()
    var errorMessage: String?
    var hasExternalConflict = false
    /// The character at the top of the editor when it last closed, so a tab shows the
    /// note where it was left; nil at the top.
    @ObservationIgnored var savedScrollLocation: Int?
    /// Set by the editor while it shows the note: records the character at its top in
    /// `savedScrollLocation` now, as it does when it closes.
    @ObservationIgnored var recordEditorPlace: (@MainActor () -> Void)?

    /// Where the note is shown, to open it there again after Graphite quits: the character
    /// at the top of the view, in the reading view or the editor, and the cursor.
    func placeToRemember() -> NotePlace {
        recordEditorPlace?()
        let topLocation: Int?
        if viewMode != .reading {
            topLocation = savedScrollLocation
        } else if readingPosition.hasLaidOutBlocks {
            // Laid out at the very top is a place too: the start.
            topLocation = readingPosition.topLocation() ?? 0
        } else {
            topLocation = savedScrollLocation
        }
        return NotePlace(topLocation: topLocation ?? 0, selectionLocation: selection.location, selectionLength: selection.length)
    }

    /// Opens the note where it was left: the editor and the reading view start at the line
    /// that was at the top, and the cursor is where it was. A place beyond the note's end,
    /// as after another app shortened it, is kept within the note.
    func returnTo(_ place: NotePlace) {
        let textLength = (text as NSString).length
        let topLocation = min(max(place.topLocation, 0), textLength)
        savedScrollLocation = topLocation > 0 ? topLocation : nil
        // The reading view starts at that line too, when the note opens in reading view.
        viewModeSwitch.startsReadingWhereEditorWas(topLocation > 0)
        let selectionLocation = min(max(place.selectionLocation, 0), textLength)
        selection = NSRange(location: selectionLocation, length: min(max(place.selectionLength, 0), textLength - selectionLocation))
    }
    /// Whether the person has put the cursor somewhere in this note since it opened; until
    /// then, quotes from a PDF go to the end of the note rather than its top.
    @ObservationIgnored var hasPlacedCursor = false
    /// Whether the editor should start editing as soon as it shows, as for a note just
    /// created. Observed, so an editor already on screen notices it.
    var startsEditingWhenShown = false
    /// Whether the note's editor is taking typing. On a phone the bar that moves between
    /// files gives way to the keyboard's own toolbar meanwhile, also with a hardware
    /// keyboard, where the toolbar shows alone and no keyboard notification says so.
    var isTyping = false
    /// The find bar to open once the editor shows, with replace or without, for Obsidian's
    /// "Search current file" from the command palette.
    var findRequest: FindRequest?

    enum FindRequest { case find, findAndReplace }

    /// A selection a community plugin set without changing the text (Advanced URI puts the
    /// cursor at the end of the note it appended to); the editor on screen takes it.
    var selectionRequest: NSRange?

    /// The last heading or match request an editor or reading view of this note showed,
    /// so switching tabs or views does not jump to it again.
    @ObservationIgnored var handledHeadingScrollToken: UUID?
    /// The last reading-view build of this note, so switching from editing back to reading shows it at once.
    @ObservationIgnored let readingBlocksCache = ReadingBlocksCache()
    @ObservationIgnored let readingPosition = ReadingPosition()
    /// Whether the note's editor can undo or redo. It follows the text view's own history
    /// while an editor shows the note, and nothing otherwise.
    @ObservationIgnored let undoAvailability = UndoAvailability()
    /// Insertions waiting for the editor view, which applies them one at a time so native
    /// undo stays intact. Each range is in the text as it will be once every earlier
    /// insertion in the queue is applied, so requests made before the editor catches up,
    /// such as several images dropped together, all land where they were aimed.
    private var pendingInsertions: [EditorInsertion] = []
    /// The next insertion for the editor to apply.
    var pendingInsertion: EditorInsertion? { pendingInsertions.first }
    private(set) var savedText: String
    /// Foundation's UTF-8 decoding drops a leading byte-order mark, so it is remembered and
    /// written back: saving must not change bytes the person did not edit.
    private(set) var hasByteOrderMark: Bool
    /// The version of the file the text was made over.
    private(set) var revision: FileRevision
    var activeSave: Task<Void, Error>?
    /// Where text that cannot reach the file waits, outside the vault; nil for a session
    /// that is not a tab's, as in tests.
    @ObservationIgnored var draftKeeper: DocumentDraftKeeper?
    /// The edit the draft on disk holds, nil when this session has no draft there.
    @ObservationIgnored var draftEditVersion: Int?
    var isSaving: Bool { activeSave != nil }
    /// The folder of the vault the note is in.
    var vaultRoot: URL { store.root }
    var hasUnsavedChanges: Bool { text != savedText || !pendingInsertions.isEmpty }

    init(path: VaultPath, snapshot: FileSnapshot, store: VaultStore, openNotes: OpenNoteFiles? = nil,
         didSave: @escaping @MainActor (VaultPath) -> Void) throws {
        guard let decoded = NoteTextEncoding.decode(snapshot.data) else { throw GraphiteError.invalidFile("This note is not UTF-8 encoded.") }
        self.path = path; self.store = store; self.didSave = didSave
        text = decoded.text; savedText = decoded.text; hasByteOrderMark = decoded.hasByteOrderMark; revision = snapshot.revision
        self.openNotes = openNotes
        fileKey = OpenNoteFiles.key(for: try path.url(in: store.root))
        // Open in another window already: this one shows its text, edits not saved yet included.
        if let openSession = openNotes?.register(self, file: fileKey) {
            takeSharedText(openSession.text)
            takeSavedState(of: openSession)
        }
    }

    // MARK: One note in several windows

    var siblings: [MarkdownSession] { openNotes?.siblings(of: self, file: fileKey) ?? [] }

    private func shareText() {
        for sibling in siblings { sibling.takeSharedText(text) }
    }

    /// Shows the text another session of the note has; its editor applies the difference.
    private func takeSharedText(_ sharedText: String) {
        isTakingSharedText = true
        text = sharedText
        isTakingSharedText = false
    }

    /// After a save or a reload: the other sessions of the note know what is on disk now, so
    /// their next save expects this revision and nothing is left for them to save.
    private func shareSavedState() {
        for sibling in siblings { sibling.takeSavedState(of: self) }
    }

    private func takeSavedState(of session: MarkdownSession) {
        savedText = session.savedText
        hasByteOrderMark = session.hasByteOrderMark
        revision = session.revision
        if !session.hasExternalConflict { hasExternalConflict = false }
    }

    /// Saves the current text. A save already in flight is awaited first, so autosave,
    /// navigation, and the keyboard shortcut never race or report a spurious error.
    func save() async throws {
        try await waitForSavesInFlight()
        // A move let go of this session while it waited; what it had is in a copy by then.
        guard !wasLeftBehindByMove else { return }
        bringWaitingTextIntoNote()
        guard hasUnsavedChanges else {
            // Undone back to what the file holds: there is nothing left to bring back.
            discardDraft()
            letGoOfLostFile()
            return
        }
        guard !hasExternalConflict else {
            await keepUnsavedTextInDraft()
            throw GraphiteError.conflict
        }
        let textToSave = text
        let expectedRevision = revision
        willReplaceSavedText?(savedText, .bySave)
        let dataToSave = NoteTextEncoding.encode(textToSave, hasByteOrderMark: hasByteOrderMark)
        let saveTask = Task { [store, path, hasLostFileToMove] in
            // Another note has this path now, so the text starts a file of its own beside it.
            let target = hasLostFileToMove ? try await store.separateCopyPath(of: path, fileExtension: "md") : path
            let newRevision = try await store.save(dataToSave, at: target, expecting: hasLostFileToMove ? .absent : .revision(expectedRevision))
            self.revision = newRevision
            self.savedText = textToSave
            // Before anyone waiting for this save resumes: another window's save of the note,
            // waiting for this one, must expect the new revision.
            self.shareSavedState()
            if hasLostFileToMove { try self.goOnInCopy(at: target) }
        }
        activeSave = saveTask
        defer { if activeSave == saveTask { activeSave = nil } }
        do {
            try await saveTask.value
            // A note can grow past what opens again; better said now than when it will not open.
            errorMessage = dataToSave.count > Self.maximumEditableBytes ? Self.grownTooLargeMessage : nil
            // Text typed during the save is not in the file yet: its draft stays until it is.
            if !hasUnsavedChanges { discardDraft() }
            didSave(path)
        } catch {
            if error as? GraphiteError == .conflict, !hasLostFileToMove { hasExternalConflict = true }
            errorMessage = hasLostFileToMove ? Self.lostFileMessage : error.localizedDescription
            await keepUnsavedTextInDraft()
            throw error
        }
    }

    /// Another window's save of the note is awaited too: it sets the revision this one expects.
    /// So is a move of the file, with what the text needs from it (`waitForMove`).
    private func waitForSavesInFlight() async throws {
        var awaitedSaves: Set<Task<Void, Error>> = []
        while true {
            if let moveHold = ([self] + siblings).lazy.compactMap(\.moveHold).first {
                bringWaitingTextIntoNote()
                guard hasUnsavedChanges else { return } // Nothing to write, so nothing to wait for.
                try await waitForMove(holding: moveHold)
                continue
            }
            let savesRunning = ([activeSave] + siblings.map(\.activeSave)).compactMap { save in save }
            guard let previousSave = savesRunning.first(where: { save in !awaitedSaves.contains(save) }) else { return }
            awaitedSaves.insert(previousSave)
            _ = try? await previousSave.value
            // Whichever waiter resumes first clears the finished save. Awaiting a finished
            // task does not suspend, so a waiter that left it in place would spin on the
            // main actor and the saver that owns it would never run again.
            if activeSave == previousSave { activeSave = nil }
        }
    }

    func checkExternalChange() async {
        guard !isSaving, !hasLostFileToMove else { return }
        let revisionBeforeRead = revision
        do {
            let snapshot = try await store.read(path, maximumBytes: maximumBytesRead)
            guard !isSaving, revision == revisionBeforeRead else { return }
            guard snapshot.revision != revision else {
                // The file went back to the version these edits were made over, so the
                // conflict is over and the edits can be saved.
                if hasExternalConflict {
                    hasExternalConflict = false
                    errorMessage = nil
                    try? await save() // A failure shows in the banner, and the draft keeps the text.
                }
                return
            }
            if hasUnsavedChanges {
                showConflict()
                await keepUnsavedTextInDraft()
            } else { try adopt(snapshot) }
        } catch GraphiteError.oversized {
            guard !isSaving, revision == revisionBeforeRead else { return }
            await checkFileTooLargeToRead()
        } catch {
            guard !isSaving, revision == revisionBeforeRead else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// The file is larger than this session reads, so it is hashed instead, a megabyte at a time.
    /// The session's own save may have made it that large, which is no change. Another app's
    /// version is a conflict under text not saved, and otherwise opens read-only in the tab.
    private func checkFileTooLargeToRead() async {
        let revisionBeforeRead = revision
        guard let fileRevision = try? await store.revision(of: path) else { return } // Cannot be looked at now: the next check tries again.
        guard !isSaving, revision == revisionBeforeRead, fileRevision != revision else { return }
        if hasUnsavedChanges {
            showConflict()
            await keepUnsavedTextInDraft()
        } else {
            fileOutgrewEditor = true
        }
    }

    func reload() async throws {
        guard !hasLostFileToMove else { throw GraphiteError.conflict }
        let versionBeforeRead = editVersion
        let revisionBeforeRead = revision
        guard try await store.fileExists(path) else { throw Self.removedExternallyError }
        let snapshot = try await store.read(path, maximumBytes: maximumBytesRead)
        guard editVersion == versionBeforeRead, revision == revisionBeforeRead, !isSaving else {
            showConflict()
            await keepUnsavedTextInDraft()
            throw GraphiteError.conflict
        }
        try adopt(snapshot)
    }

    // MARK: A move of the note's file (`MarkdownSessionMoves.swift`)

    /// Set when a move could not take this session along, so it never writes again.
    @ObservationIgnored var wasLeftBehindByMove = false
    /// The move of the note's file that its saves wait for.
    @ObservationIgnored var moveHold: SavesHeldDuringMove?
    /// How long a save waits for a move of the note's file. A big folder's links can take
    /// longer, and the save then fails with the text kept, which costs nothing but a message.
    @ObservationIgnored var longestWaitForMove = Duration.seconds(30)
    /// Set when another note's move took this session's path. What it holds is another text,
    /// which is never written there: its next save starts a file beside it (`save`).
    @ObservationIgnored var hasLostFileToMove = false
    /// Tells the session's window: the session goes on in the copy at this path, or, with
    /// nothing to keep (nil), is over, and its tab shows the moved note.
    @ObservationIgnored var didLoseFileToMove: (@MainActor (MarkdownSession, VaultPath?) -> Void)?

    func takeMovedFile(at newLocation: URL, fileKey newFileKey: String) {
        guard let newPath = WorkspaceModel.vaultPath(for: newLocation, root: store.root) else { return }
        openNotes?.moveSession(self, fromFile: fileKey, toFile: newFileKey)
        fileKey = newFileKey
        if draftEditVersion != nil { draftKeeper?.moveDraft(to: newPath) }
        draftKeeper = draftKeeper?.following(to: newPath)
        path = newPath
    }

    /// A draft's edits are made over `revision`, so saves expect that version and no newer one.
    func expectRevision(_ revision: FileRevision) {
        self.revision = revision
    }

    private static let removedExternallyError = GraphiteError.unavailable(
        "Another app deleted or moved this note, so there is no other version to use. Save a Copy keeps your edits.")

    private func adopt(_ snapshot: FileSnapshot) throws {
        guard let decoded = NoteTextEncoding.decode(snapshot.data) else { throw GraphiteError.invalidFile("External note is not UTF-8.") }
        // The version another app replaced is kept, in case its change was unwanted.
        if decoded.text != savedText { willReplaceSavedText?(savedText, .byOtherVersion) }
        pendingInsertions = []
        text = decoded.text; savedText = decoded.text; hasByteOrderMark = decoded.hasByteOrderMark; revision = snapshot.revision
        hasExternalConflict = false; errorMessage = nil
        discardDraft()
        shareSavedState()
    }

    /// Writes the edits to a new note beside this one and ends the conflict: this note
    /// shows the other app's version again, or, when the other app deleted or moved it,
    /// lets the edits go from here, since they are now in the copy. Either way nothing
    /// unsaved is left unless more work arrived while the copy was written or the original
    /// was reloaded. That newer work stays open in conflict. Once the copy is written this
    /// does not throw, so the copy is never reported as failed.
    func saveSeparateCopy() async throws -> VaultPath {
        if hasLostFileToMove {
            try await save()
            return path
        }
        flushPendingInsertions()
        let bytesToCopy = NoteTextEncoding.encode(text, hasByteOrderMark: hasByteOrderMark)
        let versionToCopy = editVersion
        let separatePath = try await store.separateCopyPath(of: path, fileExtension: "md")
        _ = try await store.save(bytesToCopy, at: separatePath, expecting: .absent)
        guard editVersion == versionToCopy else {
            showConflict()
            await keepUnsavedTextInDraft()
            return separatePath
        }
        do {
            try await reload()
        } catch {
            guard editVersion == versionToCopy else { return separatePath }
            let isRemoved = (try? await store.fileExists(path)) == false
            guard editVersion == versionToCopy else { return separatePath }
            text = savedText
            hasExternalConflict = false
            discardDraft()
            // The other version exists but cannot be shown, such as a file too large or
            // no longer UTF-8; the note says so when the person comes back to it.
            errorMessage = isRemoved ? nil : error.localizedDescription
        }
        return separatePath
    }

    /// Property types assigned in `.obsidian/types.json`, which the Properties view parses
    /// this note's frontmatter with.
    private(set) var declaredPropertyTypes: [String: PropertyType] = [:]

    /// Reads the vault's assigned property types again.
    func loadDeclaredPropertyTypes() async {
        let loadedTypes = await store.propertyTypes()
        if loadedTypes != declaredPropertyTypes { declaredPropertyTypes = loadedTypes }
    }

    /// Folded headings and list items (`NoteFolding` keys). As in Obsidian, folds are kept
    /// on the device, not written into the note.
    var foldedKeys: Set<String> = [] {
        didSet { if foldedKeys != oldValue { didChangeFolds?(foldedKeys) } }
    }
    @ObservationIgnored var didChangeFolds: ((Set<String>) -> Void)?

    /// Called with the note's saved text just before a save or a reload replaces it, so File
    /// recovery can keep a copy.
    @ObservationIgnored var willReplaceSavedText: ((String, SavedTextReplacement) -> Void)?

    /// A shown editor applies its waiting insertions through native undo before a save
    /// captures the text. Without an editor, the same work is applied to the model.
    @ObservationIgnored var applyPendingInsertionsBeforeSaving: (() -> Void)?

    /// What the note's rendered blocks' views hold for it: the table cells' drafts a save writes
    /// first, and the table cell whose commands the palette and the Edit menu offer.
    let blockViews = RenderedBlockViewsOfNote()

    /// What a save must take in first: the views' drafts, then the insertions waiting.
    func bringWaitingTextIntoNote() {
        for commit in blockViews.draftCommits.values { commit() }
        flushPendingInsertions()
    }

    func flushPendingInsertions() {
        guard !pendingInsertions.isEmpty else { return }
        applyPendingInsertionsBeforeSaving?()
        let waitingInsertions = pendingInsertions
        pendingInsertions = []
        waitingInsertions.forEach(applyWithoutEditor)
    }

    /// Whether an editor shows this note, which applies insertions so they can be undone.
    /// An editor that goes away before applying them leaves them in the text directly, so
    /// nothing requested is lost.
    @ObservationIgnored var isEditorAttached = false {
        didSet {
            guard !isEditorAttached, !pendingInsertions.isEmpty else { return }
            flushPendingInsertions()
        }
    }

    /// Applies an editing command's result, computed on the current text, through the
    /// editor, so it can be undone.
    func apply(_ edit: MarkdownTextEdit) {
        var replacementRange = edit.range
        var sourceLength = (text as NSString).length
        for insertion in pendingInsertions {
            let replacedRange = Self.clamped(insertion.range, toLength: sourceLength)
            let insertedLength = (insertion.text as NSString).length
            if replacementRange.length == 0 {
                replacementRange.location = Self.moved(replacementRange.location, pastReplacing: replacedRange, insertedLength: insertedLength)
            } else {
                let characterEdit = CharacterEdit(editedRange: NSRange(location: replacedRange.location, length: insertedLength),
                                                  changeInLength: insertedLength - replacedRange.length)
                guard let movedRange = TextRangeMapping.replacedRange(replacementRange, through: characterEdit) else {
                    errorMessage = "The note changed while this command was waiting. Try the command again."
                    return
                }
                replacementRange = movedRange
            }
            sourceLength += insertedLength - replacedRange.length
        }
        // The command's selection is already in the text after its replacement. Mapping
        // it as a range of the old text can widen it across a queued insertion or move it
        // past closing markers. Keep its offset within the unchanged replacement instead.
        let selectionAfter = edit.selectionAfter.shifted(by: replacementRange.location - edit.range.location)
        request(EditorInsertion(text: edit.replacement, range: replacementRange, selectionAfter: selectionAfter))
    }

    func request(_ insertion: EditorInsertion) {
        if isEditorAttached { pendingInsertions.append(insertion); editVersion += 1 } else { applyWithoutEditor(insertion) }
    }

    /// The text a new insertion goes into, which already includes the insertions still
    /// waiting for the editor, and `range` of the current text moved past them; without a
    /// range, the cursor as it will be once they are applied.
    func insertionTarget(for range: NSRange?) -> (text: NSString, range: NSRange) {
        var source = text as NSString
        guard !pendingInsertions.isEmpty else { return (source, range ?? selection) }
        var movedRange = range ?? selection
        var cursorAfterInsertions = selection
        for insertion in pendingInsertions {
            let replacedRange = Self.clamped(insertion.range, toLength: source.length)
            let insertedLength = (insertion.text as NSString).length
            source = source.replacingCharacters(in: replacedRange, with: insertion.text) as NSString
            let movedStart = Self.moved(movedRange.location, pastReplacing: replacedRange, insertedLength: insertedLength)
            let movedEnd = Self.moved(NSMaxRange(movedRange), pastReplacing: replacedRange, insertedLength: insertedLength)
            movedRange = NSRange(location: movedStart, length: max(movedEnd - movedStart, 0))
            cursorAfterInsertions = insertion.selectionAfter ?? NSRange(location: replacedRange.location + insertedLength, length: 0)
        }
        return (source, range == nil ? cursorAfterInsertions : movedRange)
    }

    /// Where `location` ends up after `replacedRange` becomes `insertedLength` characters:
    /// unchanged before it, shifted after it, and at the end of the new text inside it. A
    /// location right where an insertion goes lands after it, so requests keep their order.
    private static func moved(_ location: Int, pastReplacing replacedRange: NSRange, insertedLength: Int) -> Int {
        if location < replacedRange.location { return location }
        if location >= NSMaxRange(replacedRange) { return location + insertedLength - replacedRange.length }
        return replacedRange.location + insertedLength
    }

    private static func clamped(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }

    /// Changes the text directly when no editor shows the note, as in reading view: an
    /// insertion waiting for an editor would not be saved until one appeared.
    private func applyWithoutEditor(_ insertion: EditorInsertion) {
        let source = text as NSString
        let replacedRange = Self.clamped(insertion.range, toLength: source.length)
        text = source.replacingCharacters(in: replacedRange, with: insertion.text)
        selection = insertion.selectionAfter ?? NSRange(location: replacedRange.location + (insertion.text as NSString).length, length: 0)
    }

    func markInsertionApplied(_ insertion: EditorInsertion) {
        if pendingInsertions.first?.id == insertion.id { pendingInsertions.removeFirst() }
    }
}
