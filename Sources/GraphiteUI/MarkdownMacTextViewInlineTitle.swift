/**
 * File: MarkdownMacTextViewInlineTitle.swift
 * ------------------------------------------
 * Layer: UI
 * Description: The note's name above the text in the Mac's note editor, as on the iPad.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

#if os(macOS)
import AppKit

extension MarkdownMacTextView {
    private static let topInset: CGFloat = 32
    private static let inlineTitleSpacing: CGFloat = 20

    func updateInlineTitleLabel() {
        measuredInlineTitle = nil
        guard let inlineTitle else {
            inlineTitleLabel?.removeFromSuperview()
            inlineTitleLabel = nil
            setTopInset(Self.topInset)
            return
        }
        let label = inlineTitleLabel ?? NSTextField(wrappingLabelWithString: inlineTitle.text)
        label.stringValue = inlineTitle.text
        label.font = inlineTitle.font
        label.textColor = inlineTitle.color
        if label.superview == nil { addSubview(label) }
        inlineTitleLabel = label
        layOutInlineTitle()
    }

    func layOutInlineTitle() {
        guard let inlineTitleLabel, frame.width > 0 else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        let width = max(frame.width - 2 * textContainerInset.width - 2 * padding, 1)
        let height: CGFloat
        if let measuredInlineTitle, measuredInlineTitle.width == width {
            height = measuredInlineTitle.height
        } else {
            let measuringBounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
            height = ceil(inlineTitleLabel.cell?.cellSize(forBounds: measuringBounds).height ?? 0)
            measuredInlineTitle = (width, height)
        }
        inlineTitleLabel.frame = NSRect(x: textContainerInset.width + padding, y: Self.topInset, width: width, height: height)
        setTopInset(Self.topInset + height + Self.inlineTitleSpacing)
    }

    /// AppKit's inset is the same above and below the text, so a title leaves more room below too.
    private func setTopInset(_ inset: CGFloat) {
        guard abs(textContainerInset.height - inset) > 0.5 else { return }
        textContainerInset = CGSize(width: textContainerInset.width, height: inset)
        didMoveTextColumn?()
    }
}
#endif
