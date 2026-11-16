/**
 * File: PDFSessionStacking.swift
 * ------------------------------
 * Layer: UI
 * Description: Bring to Front, Bring Forward, Send Backward and Send to Back for a PDF page's pictures, text boxes
 *              and shapes, each one step of the PDF's history, and the topmost object under a point.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import PDFKit
import GraphiteCore
import GraphiteApple

extension PDFArrangement {
    /// The four arrangements the menus offer, in the order they list them.
    static let menuArrangements: [PDFArrangement] = [.bringToFront, .bringForward, .sendBackward, .sendToBack]

    /// The menu item's title, and the name of its step in Undo.
    var title: String {
        switch self {
        case .bringToFront: "Bring to Front"
        case .bringForward: "Bring Forward"
        case .sendBackward: "Send Backward"
        case .sendToBack: "Send to Back"
        case .position: "Arrange"
        }
    }

    /// The two arrangements of the ink as one layer the menus offer.
    static let inkMenuArrangements: [PDFArrangement] = [.bringToFront, .sendToBack]

    /// The menu item's title for the page's ink, and the name of its step in Undo.
    var inkTitle: String {
        switch self {
        case .bringToFront: "Ink to Front"
        case .sendToBack: "Ink to Back"
        case .bringForward, .sendBackward, .position: "Arrange Ink"
        }
    }

    var systemImageName: String {
        switch self {
        case .bringToFront: "square.3.layers.3d.top.filled"
        case .bringForward: "square.2.layers.3d.top.filled"
        case .sendBackward: "square.2.layers.3d.bottom.filled"
        case .sendToBack, .position: "square.3.layers.3d.bottom.filled"
        }
    }
}

/// The stacking order of a page's objects. The order is the page's annotation order
/// (`PDFPageStacking`), so it is kept in the file and every reader draws it.
extension PDFSession {
    /// Arranges a picture, text box or shape, as one step named after the arrangement; Undo puts it back where it was.
    func arrange(_ annotation: PDFAnnotation, on page: PDFPage, _ arrangement: PDFArrangement) throws {
        let historyPage = historyPage(for: page)
        guard let formerPosition = PDFPageManager.stackingPosition(of: annotation, on: page),
              PDFPageManager.possibleArrangements(of: annotation, on: page).contains(arrangement) else { return }
        // The annotation keeps its name, kind and rectangle through a change of order.
        let name = annotation.persistentName, annotationType = annotation.type ?? "", bounds = annotation.bounds
        func arrange(in session: PDFSession, _ arrangement: PDFArrangement) throws {
            let reference = PDFAnnotationReference(pageIndex: try session.currentIndex(of: historyPage), name: name, annotationType: annotationType,
                                                   bounds: bounds)
            try session.apply(.arrange(reference, arrangement))
            session.stackingOrderDidChange()
        }
        try arrange(in: self, arrangement)
        registerStep(named: arrangement.title) { session in
            try arrange(in: session, .position(formerPosition))
        } redo: { session in
            try arrange(in: session, arrangement)
        }
    }

    /// Puts the page's ink, as one layer, over or under every object, as one step; Undo puts it back where it was.
    func arrangeInk(on page: PDFPage, _ arrangement: PDFArrangement) throws {
        let historyPage = historyPage(for: page)
        guard let formerPosition = PDFPageManager.inkStackingPosition(on: page),
              PDFPageManager.possibleInkArrangements(on: page).contains(arrangement) else { return }
        func arrange(in session: PDFSession, _ arrangement: PDFArrangement) throws {
            try session.apply(.arrangeInk(page: try session.currentIndex(of: historyPage), arrangement))
            session.stackingOrderDidChange()
        }
        try arrange(in: self, arrangement)
        registerStep(named: arrangement.inkTitle) { session in
            try arrange(in: session, .position(formerPosition))
        } redo: { session in
            try arrange(in: session, arrangement)
        }
    }

    /// Ink to Front and Ink to Back, those that would move the page's ink.
    func possibleInkArrangements(on page: PDFPage) -> Set<PDFArrangement> {
        PDFPageManager.possibleInkArrangements(on: page)
    }

    /// The arrangements that would move the annotation, for dimming the others.
    func possibleArrangements(of annotation: PDFAnnotation, on page: PDFPage) -> Set<PDFArrangement> {
        PDFPageManager.possibleArrangements(of: annotation, on: page)
    }

    /// The annotation of the selected picture, for Arrange.
    func annotation(of selection: PDFPictureSelection) -> (PDFAnnotation, PDFPage)? {
        guard let page = selection.page.page, page.document === document,
              let annotation = page.annotations.first(where: { annotation in
                  PDFPageManager.isPicture(annotation) && annotation.persistentName == selection.pictureName
              }) else { return nil }
        return (annotation, page)
    }

    /// The annotation of the selected text box, for Arrange.
    func annotation(of selection: PDFTextBoxSelection) -> (PDFAnnotation, PDFPage)? {
        guard let page = selection.page.page, page.document === document,
              let annotation = page.annotations.first(where: { annotation in
                  annotation.type == PDFTextBox.annotationTypeName && annotation.persistentName == selection.boxName
              }) else { return nil }
        return (annotation, page)
    }

    /// The topmost picture, text box or shape at a point of the page, in the page's coordinates.
    func topmostObjectAnnotation(at pagePoint: CGPoint, on page: PDFPage, shapeTolerance: CGFloat) -> PDFAnnotation? {
        PDFPageManager.objectAnnotationsTopmostFirst(on: page).first { annotation in
            if let picture = PDFPicture(annotation: annotation) { return picture.contains(pagePoint) }
            if let box = PDFTextBox(annotation: annotation) { return box.contains(pagePoint) }
            return PDFShape(annotation: annotation)?.contains(pagePoint, tolerance: shapeTolerance) == true
        }
    }

    /// Where an object is among its page's layers, to put it back there when a removal is undone.
    func stackingPosition(ofObjectNamed name: String, annotationType: String, on page: PDFPage) -> Int? {
        page.annotations.first { annotation in annotation.type == annotationType && annotation.persistentName == name }
            .flatMap { annotation in PDFPageManager.stackingPosition(of: annotation, on: page) }
    }

    /// Puts an object added back by Undo at the place it had among its page's layers.
    func putBack(_ reference: PDFAnnotationReference, at position: Int?) throws {
        guard let position else { return }
        try apply(.arrange(reference, .position(position)))
    }

    /// Tells the views that show the selection's frame and the Mac's text box tool.
    func stackingOrderDidChange() {
        textBoxesDidChange()
        NotificationCenter.default.post(name: Self.picturesDidChange, object: self)
    }
}
