/**
 * File: MarkdownMacTextViewPastedHTML.swift
 * -----------------------------------------
 * Layer: UI
 * Description: Pasting a web page or rich text into the Mac editor as Markdown.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

#if os(macOS)
import AppKit
import GraphiteCore

/// A web page or rich text pasted into the Mac editor becomes Markdown, as with Obsidian's
/// "Auto convert HTML" (the iPad editor does the same).
extension MarkdownMacTextView {
    /// Pastes the HTML on the pasteboard as Markdown; false when the option is off or the
    /// pasteboard has no HTML, or more than can be converted.
    func pasteConvertedHTML(from pasteboard: NSPasteboard) -> Bool {
        guard convertsPastedHTML, let htmlData = pasteboard.data(forType: .html), htmlData.count <= HTMLToMarkdown.maximumConvertedLength else { return false }
        insertConvertedHTML(htmlData, plainText: pasteboard.string(forType: .string), at: selectedRange())
        return true
    }

    /// Converts off the main thread, since a large page takes long to convert. The Markdown
    /// goes where the paste was asked for while the note is unchanged; after an edit that place
    /// may no longer exist, so the text goes at the cursor instead.
    func insertConvertedHTML(_ htmlData: Data, plainText: String?, at pastedRange: NSRange) {
        let textWhenPasted = string
        Task { @MainActor [weak self] in
            let markdown = await Task.detached(priority: .userInitiated) { () -> String? in
                guard let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .utf16) else { return nil }
                let markdown = HTMLToMarkdown.markdown(from: html)
                return markdown.isEmpty ? nil : markdown
            }.value
            guard let self else { return }
            let isTextUnchanged = self.string == textWhenPasted
            guard let pastedText = isTextUnchanged ? (markdown ?? plainText) : plainText, !pastedText.isEmpty else { return }
            let range = isTextUnchanged ? pastedRange : self.selectedRange()
            guard shouldChangeText(in: range, replacementString: pastedText) else { return }
            replaceCharacters(in: range, with: pastedText)
            didChangeText()
            setSelectedRange(NSRange(location: range.location + (pastedText as NSString).length, length: 0))
        }
    }
}
#endif
