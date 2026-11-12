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
///
/// The vault's frames name real pages (https://example.com, a page of Wikipedia) for a person browsing it. The pass must
/// reach no other host and play nothing, so in its copy of the vault every frame's address, whatever it is, becomes a
/// page of the pass's own server: `/release-vault/frame-1.html` for the first address met, and so on.
enum ReleaseVaultPassWebPages {
    static let framePathPrefix = "/release-vault/frame-"
    /// `src="…"` or `src='…'` inside an `<iframe` tag, as `WebFrameSyntax` reads it: the address is the second group.
    private static let frameSourcePattern = #"(<iframe\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2"#

    /// Whether the server's path is one of the frames' pages.
    static func isFramePage(_ path: String) -> Bool { path.hasPrefix(framePathPrefix) }

    /// Every frame address of the vault's notes, each once, in the order of the notes' paths and their lines.
    static func frameAddresses(in vaultRoot: URL = FixtureFolders.releaseVault) throws -> [String] {
        let expression = try NSRegularExpression(pattern: frameSourcePattern, options: [.caseInsensitive])
        var addresses: [String] = []
        for note in try notes(in: vaultRoot) {
            let text = try String(contentsOf: note, encoding: .utf8) as NSString
            for match in expression.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                let address = text.substring(with: match.range(at: 3))
                if !addresses.contains(address) { addresses.append(address) }
            }
        }
        return addresses
    }

    /// The server's page for each frame: text and colour only, naming the address it stands in for.
    static func pages() throws -> [String: String] {
        var pages: [String: String] = [:]
        for (addressIndex, address) in try frameAddresses().enumerated() {
            let escaped = address.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            pages[framePathPrefix + "\(addressIndex + 1).html"] = "<html><body style=\"font: 15px -apple-system; background: #eef3ff; margin: 16px\">"
                + "<h1>Frame \(addressIndex + 1)</h1><p>Served by the release pass on the loopback address, in place of \(escaped).</p></body></html>"
        }
        return pages
    }

    /// Copies `Tests/ReleaseVault` to `destination`, its settings folder included, and points every frame of every note
    /// at its page of `serverAddress` (`http://127.0.0.1:<port>/`).
    static func copyVault(to destination: URL, pointingFramesAt serverAddress: String) throws {
        let fileManager = FileManager.default
        for item in try fileManager.contentsOfDirectory(at: FixtureFolders.releaseVault, includingPropertiesForKeys: nil) {
            try fileManager.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
        }
        let addresses = try frameAddresses()
        let expression = try NSRegularExpression(pattern: frameSourcePattern, options: [.caseInsensitive])
        let serverRoot = serverAddress.hasSuffix("/") ? String(serverAddress.dropLast()) : serverAddress
        for note in try notes(in: destination) {
            let text = try String(contentsOf: note, encoding: .utf8) as NSString
            let matches = expression.matches(in: text as String, range: NSRange(location: 0, length: text.length))
            guard !matches.isEmpty else { continue }
            let rewritten = NSMutableString(string: text)
            // From the end, so earlier ranges stay where they were.
            for match in matches.reversed() {
                let addressIndex = addresses.firstIndex(of: text.substring(with: match.range(at: 3))) ?? 0
                rewritten.replaceCharacters(in: match.range(at: 3), with: serverRoot + framePathPrefix + "\(addressIndex + 1).html")
            }
            try Data((rewritten as String).utf8).write(to: note)
        }
    }

    private static func notes(in vaultRoot: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: vaultRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var notes: [URL] = []
        while let location = enumerator?.nextObject() as? URL {
            if location.pathExtension == "md" { notes.append(location) }
        }
        return notes.sorted { first, second in first.path < second.path }
    }
}
