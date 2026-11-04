/**
 * File: PDFAnnotationAuthor.swift
 * -------------------------------
 * Layer: Apple
 * Description: The name written as the author (`/T`) of what Graphite adds to a PDF: the name chosen in
 *              Settings, else the Mac owner's name, else none.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */
import Foundation
import PDFKit

/// Who a PDF annotation says wrote it. PDFKit gives every annotation it creates the system's
/// full user name as `/T`, which on an iPad or iPhone is the generic "Mobile User" that Preview
/// shows beside ink, highlights and text boxes. Graphite sets the author itself when it makes an
/// annotation: the name chosen in Settings, else the name of the Mac's owner, else no `/T` at all
/// (an iPad or iPhone offers no owner name without asking permission).
///
/// Annotations already in a file keep the author they have; only ones Graphite creates are stamped.
public struct PDFAnnotationAuthor {
    /// The device preference holding the name chosen in Settings (invariant ST-31).
    public static let preferenceKey = "GraphiteAnnotationAuthorName"

    private let defaults: UserDefaults
    private let ownerName: () -> String?

    /// - Parameter ownerName: The name offered when none is chosen; tests give their own.
    public init(defaults: UserDefaults = .standard, ownerName: @escaping () -> String? = { PDFAnnotationAuthor.deviceOwnerName }) {
        self.defaults = defaults
        self.ownerName = ownerName
    }

    /// The name chosen in Settings, trimmed; empty when none is chosen.
    public static func chosenName(in defaults: UserDefaults = .standard) -> String {
        (defaults.string(forKey: preferenceKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name of the device's owner where the system gives it without asking: the Mac's account
    /// name. An iPad or iPhone gives none (`NSFullUserName` there is "Mobile User", which names nobody).
    public static let deviceOwnerName: String? = {
        #if os(macOS)
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return fullName.isEmpty ? nil : fullName
        #else
        return nil
        #endif
    }()

    /// The author to write: the chosen name, else the owner's name, else nil.
    public var name: String? {
        let chosenName = Self.chosenName(in: defaults)
        if !chosenName.isEmpty { return chosenName }
        let offeredName = ownerName()?.trimmingCharacters(in: .whitespacesAndNewlines)
        return offeredName?.isEmpty == false ? offeredName : nil
    }

    /// Writes `authorName` as the annotation's `/T`, or takes `/T` away when it is nil, so
    /// PDFKit's own "Mobile User" is not left in the file.
    public static func write(_ authorName: String?, on annotation: PDFAnnotation) {
        if let authorName {
            annotation.userName = authorName
        } else {
            annotation.removeValue(forAnnotationKey: .textLabel)
        }
    }
}
