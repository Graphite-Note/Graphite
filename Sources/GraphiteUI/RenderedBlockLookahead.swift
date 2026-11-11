/**
 * File: RenderedBlockLookahead.swift
 * ----------------------------------
 * Layer: UI
 * Description: When Live Preview makes the views of the blocks just below the screen: once the
 *              note has stayed still a moment, one view a frame, stopped by a scroll or an edit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import GraphiteCore

/// Makes the views of the blocks just below the screen while the note is still, so scrolling on
/// shows them without building them: building a block's SwiftUI view was most of a slow scroll
/// frame (reading a long note a screen at a time on the iPad simulator, 23 of 24 steps over 16 ms
/// before, 4 to 10 after, 2026-11-11). The editors say when the viewport has settled and how to
/// make the next view (`LivePreviewRenderedBlocks.makeNextViewAhead`); this waits for stillness,
/// makes one view a frame, and lets each join the kept views once it has laid out.
@MainActor
final class RenderedBlockLookahead {
    /// How far below the screen views are made ahead, in screens of the note's characters.
    static let screens = 1.5
    /// At most this many blocks below the screen are looked at.
    static let blockLimit = 6
    /// How long the note stays still before views are made ahead.
    static let stillness = Duration.milliseconds(300)
    /// The time each view is given to lay out and draw, during which a touch or a key is
    /// answered, before the next one is made.
    static let pauseBetweenViews = Duration.milliseconds(20)

    private let renderedBlocks: LivePreviewRenderedBlocks
    private let clock: any ApplicationClock
    private var task: Task<Void, Never>?
    /// The viewport's first character the views are being made for.
    private var viewportStart: Int?

    init(renderedBlocks: LivePreviewRenderedBlocks, clock: any ApplicationClock = LiveApplicationClock()) {
        self.renderedBlocks = renderedBlocks
        self.clock = clock
    }

    /// The concealed blocks worth a view ahead of time below `viewport`: within `screens` of it, a
    /// screen being as many characters as the viewport holds, and at most `blockLimit` of them.
    static func blocksWorthMakingAhead(below viewport: NSRange, in concealedEntries: [LivePreviewBlockEntry]) -> [LivePreviewBlockEntry] {
        let viewportEnd = NSMaxRange(viewport)
        let lookaheadEnd = viewportEnd + Int(Double(viewport.length) * screens)
        return Array(concealedEntries.lazy.filter { entry in entry.range.location >= viewportEnd && entry.range.location < lookaheadEnd }
            .prefix(blockLimit))
    }

    /// The characters of the note TextKit lays out for the viewport; nil before it has one.
    static func viewportCharacters(of textLayoutManager: NSTextLayoutManager) -> NSRange? {
        guard let contentManager = textLayoutManager.textContentManager,
              let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange else { return nil }
        let documentStart = contentManager.documentRange.location
        let start = contentManager.offset(from: documentStart, to: viewportRange.location)
        let end = contentManager.offset(from: documentStart, to: viewportRange.endLocation)
        return NSRange(location: start, length: max(0, end - start))
    }

    /// The viewport has settled at `viewportStart`: once it has stayed still `stillness`, calls
    /// `makeNextView` a frame apart until it makes none. A viewport that moved starts the wait again.
    func makeViewsOnceStill(viewportStart: Int?, makeNextView: @escaping @MainActor () -> Bool) {
        guard let viewportStart, viewportStart != self.viewportStart else { return }
        stop()
        self.viewportStart = viewportStart
        task = Task { [weak self, clock] in
            do { try await clock.sleep(for: Self.stillness) } catch { return }
            while !Task.isCancelled, makeNextView() {
                do { try await clock.sleep(for: Self.pauseBetweenViews) } catch { break }
                self?.renderedBlocks.keepViewsMadeAhead()
            }
            self?.renderedBlocks.keepViewsMadeAhead()
        }
    }

    /// Stops making views, as a scroll or an edit begins; those made so far join the kept views.
    func stop() {
        task?.cancel()
        task = nil
        viewportStart = nil
        renderedBlocks.keepViewsMadeAhead()
    }
}
