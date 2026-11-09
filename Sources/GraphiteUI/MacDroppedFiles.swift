/**
 * File: MacDroppedFiles.swift
 * ---------------------------
 * Layer: UI
 * Description: Reads the files a drop on the Mac carries: Finder's file addresses and the files Photos and Mail promise.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 09/11/2026
 */

#if os(macOS)
import AppKit
import Synchronization
import GraphiteApple

/// The files a drag from another Mac app carries. The Finder puts file addresses on the
/// pasteboard; Photos and Mail promise their files instead and write them only where the
/// receiver asks (`NSFilePromiseReceiver`), so a photo dragged from Photos carries no address
/// at all. Both are read here, for a note and for the file tree.
@MainActor
enum MacDroppedFiles {
    /// The pasteboard types of promised files.
    static let promisedFileTypes = NSFilePromiseReceiver.readableDraggedTypes.map { type in NSPasteboard.PasteboardType(type) }

    /// File addresses and promised files, which a view registers for to take files.
    static var pasteboardTypes: [NSPasteboard.PasteboardType] { [.fileURL] + promisedFileTypes }

    /// Whether the pasteboard carries a file, by address or by promise.
    static func isOffered(on pasteboard: NSPasteboard) -> Bool {
        hasFileAddresses(on: pasteboard) || hasPromisedFiles(on: pasteboard)
    }

    static func hasFileAddresses(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    static func hasPromisedFiles(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
    }

    /// The files the pasteboard carries: addresses as they are (never copied or moved), then
    /// promised files written into a staging folder, which `DroppedFileBatch.discard` removes.
    /// A promise its app fails to keep is left out.
    static func read(from pasteboard: NSPasteboard) async -> [DroppedFile] {
        let addresses = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !addresses.isEmpty { return addresses.map { location in DroppedFile(location: location, stagingFolder: nil) } }
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        var files: [DroppedFile] = []
        for receiver in receivers {
            files += await receivedFiles(of: receiver)
        }
        return files
    }

    /// Reads the files a drop carries and hands them to `importBatch`, which copies them in
    /// (`WorkspaceModel.importFiles`, which removes the staged copies). False when the drop
    /// carries no file.
    static func takeFiles(on pasteboard: NSPasteboard, importBatch: @escaping @MainActor (DroppedFileBatch) async -> Void) -> Bool {
        guard isOffered(on: pasteboard) else { return false }
        Task {
            let files = await read(from: pasteboard)
            guard !files.isEmpty else { return }
            await importBatch(DroppedFileBatch(files: files))
        }
        return true
    }

    /// Asks the promising app to write its files into a new staging folder, and waits for them.
    private static func receivedFiles(of receiver: NSFilePromiseReceiver) async -> [DroppedFile] {
        let expectedCount = receiver.fileTypes.count
        guard expectedCount > 0, let folder = try? DroppedFileStaging.makeStagingFolder() else { return [] } // No folder to write into: nothing received.
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        let locations = await withCheckedContinuation { (continuation: CheckedContinuation<[URL], Never>) in
            let collector = PromisedFileCollector(expectedCount: expectedCount, continuation: continuation)
            receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { location, error in
                collector.receive(error == nil ? location : nil)
            }
        }
        if locations.isEmpty { DroppedFileStaging.discard([folder]) }
        return locations.map { location in DroppedFile(location: location, stagingFolder: folder) }
    }
}

/// Collects the files of one promise as the promising app writes them, and resumes the
/// waiting task once every file has arrived or failed.
private final class PromisedFileCollector: Sendable {
    private struct Progress {
        var remainingCount: Int
        var received: [URL] = []
    }
    private let progress: Mutex<Progress>
    private let continuation: CheckedContinuation<[URL], Never>

    init(expectedCount: Int, continuation: CheckedContinuation<[URL], Never>) {
        progress = Mutex(Progress(remainingCount: expectedCount))
        self.continuation = continuation
    }

    /// One promised file written at `location`, or nil when it failed.
    func receive(_ location: URL?) {
        let finished: [URL]? = progress.withLock { progress in
            if let location { progress.received.append(location) }
            progress.remainingCount -= 1
            return progress.remainingCount == 0 ? progress.received : nil
        }
        if let finished { continuation.resume(returning: finished) }
    }
}
#endif
