/**
 * File: PDFSelectionMarking.swift
 * -------------------------------
 * Layer: UI
 * Description: Marks the text selected in a PDF view, recolours a mark and removes one, as steps of the PDF's
 *              history, for the iPad's menus and the Mac's markup row, menus and menu bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 16/11/2026
 */

import PDFKit
import GraphiteApple

/// Marks the text selected in a PDF view, and recolours and removes marks, as steps of the
/// PDF's history. A failure shows in the session's error banner.
@MainActor
enum PDFSelectionMarking {
    /// Marks the view's selected text with `style` and clears the selection. Nothing
    /// happens without selected text. Text a mark of the same kind is on changes that mark
    /// or joins it, never stacks another (`PDFSession.addMarkup`, `PDFMarkupOverlap`).
    static func markSelection(of view: PDFView, in session: PDFSession, as style: PDFMarkupStyle) {
        guard let selection = view.currentSelection, !(selection.string ?? "").isEmpty else { return }
        do {
            try session.addMarkup(style.kind, color: style.color, for: selection)
            view.clearSelection()
        } catch {
            session.errorMessage.report(error)
        }
    }

    static func recolor(_ mark: PDFAnnotation, on page: PDFPage, to color: PDFMarkupColor, in session: PDFSession) {
        do { try session.recolorMarkup(mark, on: page, to: color) } catch { session.errorMessage.report(error) }
    }

    static func remove(_ mark: PDFAnnotation, on page: PDFPage, in session: PDFSession) {
        do { try session.removeMarkup(mark, on: page) } catch { session.errorMessage.report(error) }
    }
}
