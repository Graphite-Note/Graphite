/**
 * File: MarkdownEditorContainerView.swift
 * ---------------------------------------
 * Layer: UI
 * Description: The view that holds a note's text view on the iPad, the iPhone and the Mac.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit

final class MarkdownEditorContainerView: UIView {
    private(set) weak var hostedTextView: MarkdownTextView?
    /// The latest update of this container's SwiftUI view, made while an earlier view of
    /// the note still showed the text view. It runs when the text view arrives here.
    var updateWhenTextViewArrives: ((MarkdownTextView) -> Void)?

    func host(_ textView: MarkdownTextView) {
        textView.removeFromSuperview()
        textView.frame = bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(textView)
        hostedTextView = textView
        let waitingUpdate = updateWhenTextViewArrives
        updateWhenTextViewArrives = nil
        waitingUpdate?(textView)
    }

    /// The text view, while this container shows it rather than another view of the note.
    var textViewShownHere: MarkdownTextView? {
        guard let hostedTextView, hostedTextView.superview === self else { return nil }
        return hostedTextView
    }
}
#endif

#if os(macOS)
import AppKit

final class MarkdownEditorContainerView: NSView {
    private(set) weak var hostedScrollView: NSScrollView?
    /// The latest update of this container's SwiftUI view, made while an earlier view of
    /// the note still showed the editor. It runs when the editor arrives here.
    var updateWhenScrollViewArrives: ((NSScrollView) -> Void)?

    func host(_ scrollView: NSScrollView) {
        scrollView.removeFromSuperview()
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
        hostedScrollView = scrollView
        let waitingUpdate = updateWhenScrollViewArrives
        updateWhenScrollViewArrives = nil
        waitingUpdate?(scrollView)
    }

    /// The scroll view, while this container shows it rather than another view of the note.
    var scrollViewShownHere: NSScrollView? {
        guard let hostedScrollView, hostedScrollView.superview === self else { return nil }
        return hostedScrollView
    }
}
#endif
