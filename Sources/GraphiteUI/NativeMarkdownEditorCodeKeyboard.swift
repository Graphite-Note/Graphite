/**
 * File: NativeMarkdownEditorCodeKeyboard.swift
 * --------------------------------------------
 * Layer: UI
 * Description: The iPad's and iPhone's keyboard leave code alone: no autocorrect and no automatic capitals in code blocks and inline code.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import UIKit

extension NativeMarkdownEditor.Coordinator {
    /// Turns autocorrect and automatic capitals off while the cursor is in code, and back on
    /// when it leaves, so `int` and `printf` are kept as typed. Obsidian leaves autocorrect on
    /// everywhere; code is never prose, and Apple's editors for code keep it off. The keyboard
    /// is reloaded only when the cursor crosses into or out of code.
    func updateKeyboardForCode(in textView: UITextView) {
        let isInCode = textView.selectedRange.length == 0
            && styling.isCode(at: textView.selectedRange.location, in: textView, source: currentSource(of: textView))
        let correction: UITextAutocorrectionType = isInCode ? .no : .default
        let capitalization: UITextAutocapitalizationType = isInCode ? .none : .sentences
        guard textView.autocorrectionType != correction || textView.autocapitalizationType != capitalization else { return }
        textView.autocorrectionType = correction
        textView.autocapitalizationType = capitalization
        if textView.isFirstResponder, textView.markedTextRange == nil { textView.reloadInputViews() }
    }
}
#endif
