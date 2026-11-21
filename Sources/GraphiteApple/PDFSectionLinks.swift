/**
 * File: PDFSectionLinks.swift
 * ---------------------------
 * Layer: Apple
 * Description: The /Link annotation over each picture of a note's section on a PDF page, kept in step with its
 *              picture, so every PDF reader follows it to the section.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import Foundation
import PDFKit
import GraphiteCore

/// A section's picture is a stamp, which PDF readers do not follow; the standard gives links
/// to `/Link` annotations alone. Each such picture therefore has one `/Link` over it, named
/// after it and marked as its own (`sectionLinkOwnerKey`), with the section's address.
extension PDFPageManager {
    /// On the picture of a note's section: Obsidian's address of the section (`PDFPicture.sectionLinkAddress`).
    public static let sectionLinkKey = PDFAnnotationKey(rawValue: "GraphiteSectionLink")
    /// On the picture of a note's section: a digest of the section's text it shows (`PDFPicture.sectionTextDigest`).
    public static let sectionTextDigestKey = PDFAnnotationKey(rawValue: "GraphiteSectionTextDigest")
    /// On the `/Link` over a section's picture: the name of the picture it belongs to.
    public static let sectionLinkOwnerKey = PDFAnnotationKey(rawValue: "GraphiteSectionLinkOwner")

    /// After an edit of a page's objects: whatever moved, turned, replaced or removed a
    /// section's picture, its `/Link` follows (`PDFPageManager.apply`).
    static func synchronizeSectionLinks(after edit: PDFEdit, in document: PDFDocument) {
        guard edit.changesPageObjects, let pageIndex = edit.changedPageIndex, pageIndex >= 0, pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else { return }
        synchronizeSectionLinks(on: page)
    }

    /// The section address a picture's annotation keeps, without decoding its picture.
    public static func sectionLinkAddress(of annotation: PDFAnnotation) -> String? {
        guard let address = annotation.value(forAnnotationKey: sectionLinkKey) as? String, !address.isEmpty else { return nil }
        return address
    }

    /// The section a page's annotation links to, when it is a section's picture or its link.
    public static func sectionLink(of annotation: PDFAnnotation) -> SectionLink? {
        let isLinkOfPicture = annotation.value(forAnnotationKey: sectionLinkOwnerKey) != nil
        let address = sectionLinkAddress(of: annotation) ?? (isLinkOfPicture ? annotation.url?.absoluteString : nil)
        return address.flatMap(URL.init(string:)).flatMap(SectionLink.init(openingURL:))
    }

    /// Gives each section's picture on the page exactly one `/Link` over it with its address,
    /// and removes the links whose picture is gone or has moved. Links of other kinds and
    /// other applications' are left alone.
    static func synchronizeSectionLinks(on page: PDFPage) {
        let annotations = page.annotations
        var addressByPicture: [String: (address: String, bounds: CGRect)] = [:]
        for annotation in annotations where isPicture(annotation) {
            guard let name = annotation.persistentName, let address = sectionLinkAddress(of: annotation) else { continue }
            addressByPicture[name] = (address, annotation.bounds)
        }
        var linkedPictures = Set<String>()
        for link in annotations {
            guard let ownerName = link.value(forAnnotationKey: sectionLinkOwnerKey) as? String else { continue }
            if let picture = addressByPicture[ownerName], !linkedPictures.contains(ownerName),
               link.url?.absoluteString == picture.address, link.bounds == picture.bounds {
                linkedPictures.insert(ownerName)
            } else {
                page.removeAnnotation(link)
            }
        }
        for (name, picture) in addressByPicture.sorted(by: { left, right in left.key < right.key }) where !linkedPictures.contains(name) {
            guard let url = URL(string: picture.address) else { continue }
            page.addAnnotation(makeSectionLinkAnnotation(url: url, bounds: picture.bounds, ownerName: name))
        }
    }

    private static func makeSectionLinkAnnotation(url: URL, bounds: CGRect, ownerName: String) -> PDFAnnotation {
        let link = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
        link.url = url
        let border = PDFBorder()
        border.lineWidth = 0
        link.border = border
        link.setPersistentName(ownerName + "-section-link")
        link.setValue(ownerName, forAnnotationKey: sectionLinkOwnerKey)
        return link
    }
}
