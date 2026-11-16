/**
 * File: PDFTextBoxPointerPress.swift
 * ----------------------------------
 * Layer: UI
 * Description: What a press of the Mac's Text Box tool does on a page: place a box, select, move or resize one,
 *              start typing in one, or end typing, decided from what is under the pointer and what is selected; and
 *              the box a drag of it or of its handle makes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import CoreGraphics
import GraphiteCore

/// Which side of a selected text box a resize handle is on, along its text.
enum PDFTextBoxEdge: Equatable, Sendable {
    case leading, trailing
}

/// What a press of the Mac's Text Box tool does, as Preview's text boxes behave: a click on
/// an empty part of the page places a box when none is selected, a click on a box selects
/// it and a drag moves it, a double-click types in it, a drag of a handle makes it wider
/// or narrower, and a click away from the box typed in ends typing.
enum PDFTextBoxPointerPress: Equatable, Sendable {
    case placeNewBox
    /// Selects the box; a drag that follows moves it.
    case select(boxName: String)
    case beginTyping(boxName: String)
    case resize(boxName: String, edge: PDFTextBoxEdge)
    case deselect
    /// Ends typing; the box pressed, if any, is selected in its place.
    case endTyping(selectingBoxName: String?)

    /// - Parameters:
    ///   - pressedBoxName: The topmost box under the pointer.
    ///   - pressedHandle: The selected box's handle under the pointer.
    ///   - selectedBoxName: The box selected or typed in.
    ///   - isTyping: Whether a box is being typed in; a press in its text never comes here.
    static func outcome(pressedBoxName: String?, pressedHandle: PDFTextBoxEdge?, selectedBoxName: String?, isTyping: Bool,
                        clickCount: Int) -> PDFTextBoxPointerPress {
        if isTyping { return .endTyping(selectingBoxName: pressedBoxName) }
        if let pressedHandle, let selectedBoxName { return .resize(boxName: selectedBoxName, edge: pressedHandle) }
        if let pressedBoxName { return clickCount >= 2 ? .beginTyping(boxName: pressedBoxName) : .select(boxName: pressedBoxName) }
        return selectedBoxName == nil ? .placeNewBox : .deselect
    }
}

/// The box a drag of the Mac's Text Box tool makes, from how far the pointer moved on the
/// page. The height follows the text again when the box is changed (`PDFTextBoxLayout.fitted`).
enum PDFTextBoxPointerDrag {
    /// The box moved by the pointer's movement on the page.
    static func moved(_ box: PDFTextBox, by pageDelta: CGVector) -> PDFTextBox {
        var moved = box
        moved.origin = CGPoint(x: box.origin.x + pageDelta.dx, y: box.origin.y + pageDelta.dy)
        return moved
    }

    /// The box made wider or narrower from one side, by the part of the pointer's movement
    /// along its text; the other side stays where it is, and the box keeps its narrowest width.
    static func resized(_ box: PDFTextBox, from edge: PDFTextBoxEdge, by pageDelta: CGVector) -> PDFTextBox {
        let direction = box.textDirection
        let alongText = Double(pageDelta.dx * direction.dx + pageDelta.dy * direction.dy)
        var resized = box
        switch edge {
        case .trailing:
            resized.width = max(PDFTextBox.minimumWidth, box.width + alongText)
        case .leading:
            let width = max(PDFTextBox.minimumWidth, box.width - alongText)
            let shift = box.width - width
            resized.width = width
            resized.origin = CGPoint(x: box.origin.x + CGFloat(shift) * direction.dx, y: box.origin.y + CGFloat(shift) * direction.dy)
        }
        return resized
    }
}
