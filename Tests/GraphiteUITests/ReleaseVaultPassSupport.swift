/**
 * File: ReleaseVaultPassSupport.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The release pass's window (shown as the app shows it, and its screenshots), its scrolling a page at a
 *              time, and the copy of the vault whose web frames point at the pass's own loopback server.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import SwiftUI
import XCTest
import GraphiteCore
#if canImport(GraphiteFixtures)
import GraphiteFixtures
#endif
@testable import GraphiteUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
import PDFKit
#endif

/// The window the pass shows the root view in: on the Mac a window of its own with its toolbar and title bridged as the
/// app's scene does, shown invisibly; on the iPad and the iPhone the scene's whole window, at the device's own size and
/// traits, so the iPhone shows its compact layout. The window closes when the test ends.
@MainActor
enum ReleaseVaultWindow {
    #if canImport(UIKit)
    static func show(_ rootView: GraphiteRootView, for testCase: XCTestCase) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: rootView)
        window.makeKeyAndVisible()
        testCase.addTeardownBlock { @MainActor in
            window.isHidden = true
            window.rootViewController = nil
        }
        return window
    }

    /// A PNG of the window at one pixel a point, so a few hundred pages stay small.
    static func screenshot(of window: UIWindow) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }.pngData()
    }
    #else
    static func show(_ rootView: GraphiteRootView, for testCase: XCTestCase) throws -> NSWindow {
        // As the app does before its first window.
        MacViewDrawing.drawLargeViewsWithoutTheMetalRenderer()
        let controller = NSHostingController(rootView: rootView)
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 1_280, height: 860))
        window.showInvisibly()
        testCase.addTeardownBlock { @MainActor in
            window.contentViewController = nil
            window.close()
        }
        return window
    }

    /// A PNG of the window's content at one pixel a point, so a few hundred pages stay small.
    static func screenshot(of window: NSWindow) -> Data? {
        guard let contentView = window.contentView,
              let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(contentView.bounds.width), pixelsHigh: Int(contentView.bounds.height),
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        representation.size = contentView.bounds.size
        contentView.cacheDisplay(in: contentView.bounds, to: representation)
        if let context = NSGraphicsContext(bitmapImageRep: representation) { drawPDFPages(in: contentView, into: context.cgContext) }
        return representation.representation(using: .png, properties: [:])
    }

    /// `cacheDisplay` leaves a PDF view's pages blank: PDFKit draws them in tiled layers of its own. Each shown PDF view's
    /// visible pages are drawn into the screenshot where the view lays them out, by PDFKit's own page drawing, which draws
    /// the pages' annotations too.
    private static func drawPDFPages(in contentView: NSView, into context: CGContext) {
        for pdfView in ReleaseVaultViews.descendants(of: contentView, ofType: PDFView.self) where ReleaseVaultViews.isShown(pdfView) {
            let shownArea = bitmapRect(pdfView.convert(pdfView.visibleRect, to: contentView), in: contentView)
            for page in pdfView.visiblePages {
                let pageBox = page.bounds(for: pdfView.displayBox)
                let pageArea = bitmapRect(pdfView.convert(pdfView.convert(pageBox, from: page), to: contentView), in: contentView)
                context.saveGState()
                context.clip(to: shownArea)
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                context.fill(pageArea)
                context.translateBy(x: pageArea.minX, y: pageArea.minY)
                context.scaleBy(x: pageArea.width / pageBox.width, y: pageArea.height / pageBox.height)
                context.translateBy(x: -pageBox.minX, y: -pageBox.minY)
                page.draw(with: pdfView.displayBox, to: context)
                context.restoreGState()
            }
        }
    }

    /// A rectangle of the content view in the bitmap's coordinates, whose origin is at the bottom left.
    private static func bitmapRect(_ rect: CGRect, in contentView: NSView) -> CGRect {
        contentView.isFlipped ? CGRect(x: rect.minX, y: contentView.bounds.height - rect.maxY, width: rect.width, height: rect.height) : rect
    }
    #endif
}

/// Scrolling the shown note a page at a time: the largest scroll view on screen, which is the note's text view in Live
/// Preview and source mode and the reading view's scroll view in reading view.
@MainActor
enum ReleaseVaultScrolling {
    /// A page is nine tenths of the visible height, so each screenshot overlaps the one before by a line or two.
    static let pageFraction: CGFloat = 0.9

    #if canImport(UIKit)
    /// The largest scroll view shown, scrollable or not: a short note does not scroll, and the sidebar's list or an embedded
    /// PDF must not be scrolled for it.
    static func pageScroller(in root: UIView) -> UIScrollView? {
        ReleaseVaultViews.descendants(of: root, ofType: UIScrollView.self).filter(ReleaseVaultViews.isShown)
            .max { first, second in first.bounds.width * first.bounds.height < second.bounds.width * second.bounds.height }
    }

    static func topOffset(of scroller: UIScrollView) -> CGFloat { -scroller.adjustedContentInset.top }

    private static func maximumOffset(of scroller: UIScrollView) -> CGFloat {
        scroller.contentSize.height + scroller.adjustedContentInset.bottom - scroller.bounds.height
    }

    static func nextPageOffset(of scroller: UIScrollView) -> CGFloat? {
        let current = scroller.contentOffset.y, maximum = maximumOffset(of: scroller)
        guard current < maximum - 1 else { return nil }
        return min(current + scroller.bounds.height * pageFraction, maximum)
    }

    static func scroll(_ scroller: UIScrollView, to offset: CGFloat) {
        scroller.setContentOffset(CGPoint(x: scroller.contentOffset.x, y: offset), animated: false)
    }
    #else
    /// The largest scroll view shown, scrollable or not: a short note does not scroll, and the sidebar's list or an embedded
    /// PDF must not be scrolled for it.
    static func pageScroller(in root: NSView) -> NSScrollView? {
        ReleaseVaultViews.descendants(of: root, ofType: NSScrollView.self).filter(ReleaseVaultViews.isShown)
            .max { first, second in first.bounds.width * first.bounds.height < second.bounds.width * second.bounds.height }
    }

    static func topOffset(of scroller: NSScrollView) -> CGFloat { 0 }

    private static func maximumOffset(of scroller: NSScrollView) -> CGFloat {
        (scroller.documentView?.frame.height ?? 0) - scroller.contentView.bounds.height
    }

    static func nextPageOffset(of scroller: NSScrollView) -> CGFloat? {
        let current = scroller.contentView.bounds.minY, maximum = maximumOffset(of: scroller)
        guard current < maximum - 1 else { return nil }
        return min(current + scroller.contentView.bounds.height * pageFraction, maximum)
    }

    static func scroll(_ scroller: NSScrollView, to offset: CGFloat) {
        scroller.contentView.scroll(to: NSPoint(x: scroller.contentView.bounds.minX, y: offset))
        scroller.reflectScrolledClipView(scroller.contentView)
    }
    #endif
}

/// The pages the pass's loopback server shows in the vault's frames, and the copy of the vault that points at it.
enum ReleaseVaultPassWebPages {
    /// The address the vault's frames and web links are written with: a placeholder on the loopback address, where
    /// nothing answers on port 9, that the pass points at its own server.
    static let placeholderAddress = "http://127.0.0.1:9/"
    static let framePath = "/release-vault/frame.html"
    static let smallFramePath = "/release-vault/small-frame.html"

    /// Text and colour only: nothing a test loads may play a sound.
    static let pages: [String: String] = [
        framePath: "<html><body style=\"font: 16px -apple-system; background: #eef3ff; margin: 16px\"><h1>A test page</h1>"
            + "<p>Served by the release pass on the loopback address.</p></body></html>",
        smallFramePath: "<html><body style=\"font: 14px -apple-system; background: #fff4e0; margin: 12px\"><p>A small frame.</p></body></html>",
    ]

    /// Copies `Tests/ReleaseVault` to `destination`, its settings folder included, and points every note's placeholder
    /// address at `serverAddress` (`http://127.0.0.1:<port>/`), so the frames load from the pass's server.
    static func copyVault(to destination: URL, pointingFramesAt serverAddress: String) throws {
        let fileManager = FileManager.default
        for item in try fileManager.contentsOfDirectory(at: FixtureFolders.releaseVault, includingPropertiesForKeys: nil) {
            try fileManager.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
        }
        let enumerator = fileManager.enumerator(at: destination, includingPropertiesForKeys: nil)
        while let location = enumerator?.nextObject() as? URL {
            guard location.pathExtension == "md" else { continue }
            let note = try String(contentsOf: location, encoding: .utf8)
            guard note.contains(placeholderAddress) else { continue }
            try Data(note.replacingOccurrences(of: placeholderAddress, with: serverAddress).utf8).write(to: location)
        }
    }
}
