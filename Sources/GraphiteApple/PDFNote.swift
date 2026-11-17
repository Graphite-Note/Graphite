/**
 * File: PDFNote.swift
 * -------------------
 * Layer: Apple
 * Description: Notes on a PDF page, the sticky notes of Preview and Acrobat: a standard `/Text` annotation shown as an
 *              icon whose text a reader opens, read back from any application's file and written by Graphite.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */
import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Why a change of a note was not made.
public enum PDFNoteError: Error, LocalizedError, Equatable {
    /// The note the change names is no longer on its page, as after an undo.
    case noteMissing

    public var errorDescription: String? {
        switch self {
        case .noteMissing: "This note no longer exists."
        }
    }
}

/// One note on a page, in page space: its icon's place, its text and its colour. Graphite writes a note as a `/Text`
/// annotation with the Comment icon and no `/Popup`, which the standard leaves optional: every reader shows the icon and
/// opens the text in a window of its own. PDFKit cannot write a popup into a document read from a file (2026-11-17: one
/// linked before the note is on the page is left out of the file; one linked after is added twice and reads back
/// unlinked). A note another application wrote is read with its own icon, which it keeps; its popup is removed with it.
public struct PDFNote: Sendable, Equatable {
    /// The size of a note's icon on the page, in points, as Preview and Acrobat draw it.
    public static let iconSize = CGSize(width: 24, height: 24)
    /// The colours a note is given, as Preview offers them: the first is a new note's.
    public static let colors: [(name: String, color: PDFTextColor)] = [
        ("Yellow", PDFTextColor(red: 1, green: 0.83, blue: 0.2)),
        ("Green", PDFTextColor(red: 0.45, green: 0.85, blue: 0.4)),
        ("Blue", PDFTextColor(red: 0.4, green: 0.65, blue: 1)),
        ("Pink", PDFTextColor(red: 1, green: 0.5, blue: 0.7)),
        ("Purple", PDFTextColor(red: 0.7, green: 0.5, blue: 1)),
    ]

    public let name: String
    public var contents: String
    /// The icon's rectangle on the page.
    public var iconBounds: CGRect
    public var color: PDFTextColor
    /// The icon another application chose (`/Name`, such as Note or Key), kept when the note changes; Comment for Graphite's.
    public var iconName: String
    /// Who wrote the note, as the file names them; a new note takes the device's author.
    public var author: String?

    public init(name: String = UUID().uuidString, contents: String, iconBounds: CGRect, color: PDFTextColor = Self.colors[0].color,
                iconName: String = Self.commentIconName, author: String? = nil) {
        self.name = name
        self.contents = contents
        self.iconBounds = iconBounds
        self.color = color
        self.iconName = iconName
        self.author = author
    }

    public static let commentIconName = "Comment"

    /// A new note whose icon's top left corner is at `pagePoint`, kept on the page.
    public static func placed(at pagePoint: CGPoint, on pageBounds: CGRect, contents: String) -> PDFNote {
        let origin = CGPoint(x: min(max(pagePoint.x, pageBounds.minX), pageBounds.maxX - iconSize.width),
                             y: min(max(pagePoint.y - iconSize.height, pageBounds.minY), pageBounds.maxY - iconSize.height))
        return PDFNote(contents: contents, iconBounds: CGRect(origin: origin, size: iconSize))
    }

    /// The note an annotation is; nil for anything but a `/Text` annotation.
    public init?(annotation: PDFAnnotation) {
        guard Self.isNote(annotation) else { return nil }
        self.init(name: annotation.persistentName ?? UUID().uuidString, contents: annotation.contents ?? "", iconBounds: annotation.bounds,
                  color: Self.textColor(of: annotation.color) ?? Self.colors[0].color,
                  iconName: Self.iconName(of: annotation), author: annotation.userName)
    }

    public static func isNote(_ annotation: PDFAnnotation) -> Bool {
        annotation.type == PDFNoteAnnotation.typeName
    }

    /// The note moved by `delta`, kept on the page.
    public func moved(by delta: CGVector, within pageBounds: CGRect) -> PDFNote {
        var moved = self
        moved.iconBounds.origin = CGPoint(x: min(max(iconBounds.minX + delta.dx, pageBounds.minX), pageBounds.maxX - iconBounds.width),
                                          y: min(max(iconBounds.minY + delta.dy, pageBounds.minY), pageBounds.maxY - iconBounds.height))
        return moved
    }

    // MARK: The annotations

    /// The note's annotation. PDFKit writes its appearance with the file, so readers that draw only appearances show the
    /// icon too.
    func makeAnnotation(authorName: String?) -> PDFAnnotation {
        let note = PDFAnnotation(bounds: iconBounds, forType: .text, withProperties: nil)
        note.contents = contents
        note.color = Self.platformColor(color)
        note.iconType = Self.iconType(named: iconName)
        PDFAnnotationAuthor.write(author ?? authorName, on: note)
        note.shouldPrint = false
        note.setPersistentName(name)
        return note
    }

    private static func iconName(of annotation: PDFAnnotation) -> String {
        iconNames.first { pair in pair.type == annotation.iconType }?.name ?? commentIconName
    }

    /// The icons of `/Name` that PDFKit knows, by the name the file writes.
    private static let iconNames: [(name: String, type: PDFTextAnnotationIconType)] = [
        ("Comment", .comment), ("Key", .key), ("Note", .note), ("Help", .help), ("NewParagraph", .newParagraph), ("Paragraph", .paragraph),
        ("Insert", .insert),
    ]

    private static func iconType(named name: String) -> PDFTextAnnotationIconType {
        iconNames.first { pair in pair.name == name }?.type ?? .comment
    }

    #if canImport(UIKit)
    private static func platformColor(_ color: PDFTextColor) -> UIColor {
        UIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }

    private static func textColor(of color: UIColor) -> PDFTextColor? { textColor(of: color.cgColor) }
    #else
    private static func platformColor(_ color: PDFTextColor) -> NSColor {
        NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }

    private static func textColor(of color: NSColor) -> PDFTextColor? { textColor(of: color.cgColor) }
    #endif

    /// A colour in sRGB; nil for a transparent one, which PDFKit gives for a missing `/C`.
    private static func textColor(of color: CGColor) -> PDFTextColor? {
        guard let components = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                               intent: .defaultIntent, options: nil)?.components,
              components.count >= 3, components.count < 4 || components[3] > 0 else { return nil }
        return PDFTextColor(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

extension PDFPageManager {
    static func addNote(_ note: PDFNote, to page: PDFPage, authorName: String?) {
        page.addAnnotation(note.makeAnnotation(authorName: authorName))
    }

    /// A new note in the place of a note, Graphite's or another application's, as when it is edited, moved or recoloured;
    /// it keeps the former's author and its place among the page's annotations, and another application's popup goes
    /// with the former.
    static func replaceNote(_ reference: PDFAnnotationReference, with note: PDFNote, on page: PDFPage, authorName: String?) throws {
        guard let annotation = referencedAnnotation(reference, on: page), PDFNote.isNote(annotation) else { throw PDFNoteError.noteMissing }
        var replacement = note
        replacement.author = note.author ?? annotation.userName
        replaceKeepingItsPlace(annotation, on: page, removeFormer: {
            removePopup(of: annotation, from: page)
            page.removeAnnotation(annotation)
        }, addReplacement: { page.addAnnotation(replacement.makeAnnotation(authorName: authorName)) })
    }

    /// Takes an annotation's popup off the page, so none is left without its parent. On a note read from a file PDFKit
    /// hands back, as its `popup`, another object than the one in the page's list, with the popup's corner but not its
    /// size (seen 2026-11-17), which removing does nothing to: the page's own popup is found by identity, or as the popup
    /// at that corner.
    static func removePopup(of annotation: PDFAnnotation, from page: PDFPage) {
        guard let popup = annotation.popup else { return }
        let onThePage = page.annotations.first { candidate in candidate === popup }
            ?? page.annotations.first { candidate in candidate.type == "Popup" && candidate.bounds.origin == popup.bounds.origin }
        if let onThePage { page.removeAnnotation(onThePage) }
    }
}
