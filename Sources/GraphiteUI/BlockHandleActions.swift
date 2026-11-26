/**
 * File: BlockHandleActions.swift
 * ------------------------------
 * Layer: UI
 * Description: What a block handle's menu offers for each kind of block, and the Markdown edit of each choice, the
 *              same on the Mac and the iPad.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import CoreGraphics
import GraphiteCore

/// An item of a block handle's menu (Docs/Slash-menu-and-block-handles-todo.md, sections 2 and 3).
enum BlockHandleAction: CaseIterable, Equatable {
    case heading1, heading2, heading3, body, quote, callout, task, duplicate, delete

    var title: String {
        switch self {
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .body: "Body"
        case .quote: "Quote"
        case .callout: "Callout"
        case .task: "Task"
        case .duplicate: "Duplicate"
        case .delete: "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .heading1, .heading2, .heading3: "number"
        case .body: "text.alignleft"
        case .quote: "text.quote"
        case .callout: "text.bubble"
        case .task: "checklist"
        case .duplicate: "plus.square.on.square"
        case .delete: "trash"
        }
    }

    /// Whether the item turns the block into another kind, listed under "Turn Into".
    var turnsIntoAnotherKind: Bool { self != .duplicate && self != .delete }

    /// The items for a block: a paragraph turns into a heading, a quote, a callout or a task; a
    /// list item into a task, a quote or a callout; a heading takes another level or becomes
    /// body text. Every block can be duplicated and deleted.
    static func actions(for kind: HandleBlock.Kind) -> [BlockHandleAction] {
        let turnInto: [BlockHandleAction]
        switch kind {
        case .paragraph: turnInto = [.heading1, .heading2, .heading3, .quote, .callout, .task]
        case .listItem: turnInto = [.task, .quote, .callout]
        case .heading(let level): turnInto = [.heading1, .heading2, .heading3].filter { action in action.headingLevel != level } + [.body]
        case .quote, .callout, .table, .code, .math, .rule: turnInto = []
        }
        return turnInto + [.duplicate, .delete]
    }

    private var headingLevel: Int? {
        switch self {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        case .body, .quote, .callout, .task, .duplicate, .delete: nil
        }
    }

    /// The Markdown edit of the item on `block` of `text`; nil when it changes nothing.
    func edit(for block: HandleBlock, in text: NSString) -> MarkdownTextEdit? {
        let firstLine = NSRange(location: block.range.location, length: 0)
        switch self {
        case .heading1, .heading2, .heading3:
            return MarkdownEditing.settingHeading(level: headingLevel ?? 1, in: text, selection: firstLine)
        case .body: return ParagraphEditing.removingHeadingMarks(in: text, selection: firstLine)
        case .quote: return ParagraphEditing.togglingQuote(in: text, selection: block.range)
        case .callout: return BlockHandleEditing.turningIntoCallout(block, in: text)
        case .task: return MarkdownEditing.togglingTask(in: text, selection: block.range)
        case .duplicate: return BlockHandleEditing.duplicating(block, in: text)
        case .delete: return BlockHandleEditing.deleting(block, in: text)
        }
    }
}

/// Where a dragged block goes: the place whose line is nearest the pointer's height.
enum BlockHandleDrop {
    /// The destination whose height (the top of its line, or the bottom of the note) is nearest
    /// `pointerHeight`; destinations without a laid-out line are left out.
    static func nearest(_ destinations: [Int], to pointerHeight: CGFloat,
                        heightOf: (Int) -> CGFloat?) -> (destination: Int, height: CGFloat)? {
        destinations.compactMap { destination in heightOf(destination).map { height in (destination: destination, height: height) } }
            .min { leftCandidate, rightCandidate in abs(leftCandidate.height - pointerHeight) < abs(rightCandidate.height - pointerHeight) }
    }
}
