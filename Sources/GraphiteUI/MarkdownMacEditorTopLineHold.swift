/**
 * File: MarkdownMacEditorTopLineHold.swift
 * ----------------------------------------
 * Layer: UI
 * Description: Keeps the Mac note editor at the line at its top through a change of width.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */

#if os(macOS)
import AppKit
import GraphiteCore

/// The line a Mac note editor showed at its top when its width began to change, or when it left
/// the window: opening a split, or hiding its tab, takes it out and gives it a new width before
/// it returns. A new width makes TextKit replace its layout with estimates while the scroll
/// offset stays the same number, so another passage would be at the top. Going back lays out
/// everything before the line (12 ms in a 40 KB note, 125 ms in 400 KB), so it waits for the
/// width to settle.
@MainActor
final class MarkdownMacEditorTopLineHold {
    /// Longer than the sidebar's animation, which changes the width many times. The iPad's editor waits as long.
    private static let settlingTime: Duration = .milliseconds(350)

    private struct TopLine {
        let location: Int
        let textLength: Int
        /// The scroll offset when the line was held, which a new width leaves as it was.
        let scrollOffset: CGFloat?
    }

    private let clock: any ApplicationClock
    private var topLine: TopLine?
    private var settling: Task<Void, Never>?

    init(clock: any ApplicationClock) {
        self.clock = clock
    }

    /// Where the editor is while it waits: the view shows another passage until then.
    var heldLocation: Int? { topLine?.location }

    /// Only the first of a run of changes says what the line was: the later ones see estimates.
    func hold(location: Int?, textLength: Int, scrollOffset: CGFloat? = nil) {
        guard topLine == nil, let location else { return }
        topLine = TopLine(location: location, textLength: textLength, scrollOffset: scrollOffset)
    }

    /// The editor left the window: the line stays held for when it returns, with nothing to wait for until then.
    func stopWaiting() {
        settling?.cancel()
        settling = nil
    }

    /// Calls `returnToLine` once the width has stopped changing. Text edited in the meantime
    /// moved the line, and the edit has shown its own place. A scroll in the meantime chose
    /// another place: a new width leaves the scroll offset as it was, so an offset that moved
    /// since the line was held was moved by the scroll bar, the keyboard, or a trackpad
    /// gesture whose later events AppKit's responsive scrolling handles without the text view
    /// (only a gesture's first event reaches `scrollWheel(with:)`, which releases the line).
    func returnWhenSettled(currentTextLength: @escaping () -> Int?, currentScrollOffset: @escaping () -> CGFloat?,
                           returnToLine: @escaping (Int) -> Void) {
        guard let topLine else { return }
        guard !hasScrolled(since: topLine, currentScrollOffset: currentScrollOffset()) else { return release() }
        settling?.cancel()
        settling = Task { @MainActor [weak self, clock] in
            guard (try? await clock.sleep(for: Self.settlingTime)) != nil, // Fails only when cancelled: by a later width, or `release`.
                  let self, let topLine = self.topLine else { return }
            self.release()
            guard currentTextLength() == topLine.textLength, !self.hasScrolled(since: topLine, currentScrollOffset: currentScrollOffset()) else { return }
            returnToLine(topLine.location)
        }
    }

    /// How far the scroll offset may move without a scroll: the clip view aligns it to device pixels.
    private static let scrollAllowance: CGFloat = 1

    private func hasScrolled(since topLine: TopLine, currentScrollOffset: CGFloat?) -> Bool {
        guard let heldOffset = topLine.scrollOffset, let currentScrollOffset else { return false }
        return abs(currentScrollOffset - heldOffset) > Self.scrollAllowance
    }

    /// The person or a jump has chosen another place, or the editor left the screen.
    func release() {
        stopWaiting()
        topLine = nil
    }
}

extension NativeMarkdownEditor.Coordinator {
    /// Follows the text view's changes of width, its leaving the window and the person's scrolling.
    func holdTopLineThroughWidthChanges(of textView: MarkdownMacTextView) {
        textView.willLeaveWindow = { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.holdTopLine(of: textView)
            self.topLineHold.stopWaiting()
        }
        textView.willChangeWidth = { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.holdTopLine(of: textView)
        }
        textView.didChangeWidth = { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.returnToTopLineOnceSettled(in: textView)
        }
        textView.didScrollByWheel = { [weak self] in self?.topLineHold.release() }
    }

    private func holdTopLine(of textView: NSTextView) {
        guard textView.window != nil, textView.bounds.width > 0, pendingJump == nil else { return }
        topLineHold.hold(location: topCharacter(of: textView), textLength: textView.textStorage?.length ?? 0, scrollOffset: textView.visibleRect.minY)
    }

    /// In the window, as a change of width out of it says nothing yet about where the lines will be.
    func returnToTopLineOnceSettled(in textView: NSTextView) {
        guard textView.window != nil else { return }
        topLineHold.returnWhenSettled(currentTextLength: { [weak textView] in textView?.textStorage?.length },
                                      currentScrollOffset: { [weak textView] in textView?.visibleRect.minY }) { [weak self, weak textView] location in
            guard let self, let textView else { return }
            self.returnToTopLine(location, in: textView)
        }
    }

    private func returnToTopLine(_ location: Int, in textView: NSTextView) {
        // A width that gave the same lines back left the line where it was, and the jump's layout has a cost.
        guard textView.window != nil, pendingJump == nil, topCharacter(of: textView) != location else { return }
        pendingJump = .topOfCharacter(location)
        performPendingJumpIfReady(in: textView)
    }
}
#endif
