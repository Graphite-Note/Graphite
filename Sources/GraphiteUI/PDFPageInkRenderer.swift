/**
 * File: PDFPageInkRenderer.swift
 * ------------------------------
 * Layer: UI
 * Description: Draws a page's Graphite ink, or one of its ink groups, as one picture from a separate copy of the PDF's
 *              file, off the main thread: the Mac's page ink layers and the iPad's combined ink groups show it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */
import Foundation
import CoreGraphics
import IOSurface
import PDFKit
import Synchronization
import GraphiteApple

/// What the renderer needs to draw a page's ink: the file as it was read and the page's place and geometry in it.
struct PDFPageInkRequest: Sendable {
    /// Mapped from a file that is never rewritten; the same for every request a renderer gets.
    let fileData: Data
    /// One-based page number in the file.
    let pageNumber: Int
    /// A copy with another page count is not the file the page came from.
    let filePageCount: Int
    let cropBox: CGRect
    /// Clockwise quarter turns, in degrees, as the live page shows it.
    let rotation: Int
    let pixelWidth: Int
    let pixelHeight: Int
    /// Only this ink group's strokes, without those named here; every Graphite stroke of the page when nil.
    var group: String? = nil
    var excludedNames: Set<String> = []
    /// Draws the strokes with the page turned and cropped as the request says, rather than refusing a copy whose page
    /// is not (a combined group's picture on the iPad follows the live page, which may have been turned since).
    var adoptsShownGeometry = false
    /// Draws into an IOSurface, for a layer to show, instead of a `CGImage`. Core Animation keeps a copy of its own of
    /// a `CGImage` a layer shows, so a page's picture took its memory twice; an IOSurface it shows as it is.
    var drawsIntoSurface = false
}

/// A page's ink drawn by `PDFPageInkRenderer`.
enum PDFPageInkDrawing: Sendable {
    case picture(CGImage)
    /// The picture, in an IOSurface of premultiplied BGRA in sRGB, its first row the page's top, for a request that
    /// `drawsIntoSurface`.
    case surface(IOSurface)
    /// The page has no Graphite ink.
    case noInk
    /// The copy does not have the page as shown (another page count, crop box or turn).
    case unavailable
}

/// Draws one PDF's pages' Graphite ink from a separate copy of its file, one page at a time, off the main thread. The
/// copy is opened again every few pages, so the strokes it read are let go as a scroll goes on.
///
/// PDFKit's annotations must be freed on the main thread: freed here, `PDFAKAnnotationAdaptor` said "Called from a
/// background thread" for every stroke and the Mac test bundle stopped with signal 5 (HUNT-361). So the copy is kept in a
/// `Mutex`, from which a copy let go is taken out whole and handed to a main-actor task, the last to hold it.
actor PDFPageInkRenderer {
    private static let pagesPerSeparateDocument = 16

    /// The copy of the file, with its annotations, and how many pages were drawn from it.
    private final class SeparateCopy {
        let document: PDFDocument?
        var drawnPageCount = 0
        init(_ document: PDFDocument?) { self.document = document }
    }

    private let separateCopy = Mutex<SeparateCopy?>(nil)

    func draw(_ request: PDFPageInkRequest) -> PDFPageInkDrawing {
        guard !Task.isCancelled else { return .unavailable }
        Self.freeOnTheMainThread(separateCopy.withLock { copy in
            guard let current = copy, current.drawnPageCount >= Self.pagesPerSeparateDocument else { return nil }
            let letGo = copy
            copy = nil
            return letGo
        })
        return separateCopy.withLock { copy in
            if copy == nil { copy = SeparateCopy(PDFDocument(data: request.fileData)) }
            copy?.drawnPageCount += 1
            guard let document = copy?.document else { return .unavailable }
            return Self.draw(request, from: document)
        }
    }

    deinit {
        Self.freeOnTheMainThread(separateCopy.withLock { copy in
            let letGo = copy
            copy = nil
            return letGo
        })
    }

    /// Frees a copy let go, and the annotations PDFKit made for it, on the main thread.
    private static func freeOnTheMainThread(_ letGo: sending SeparateCopy?) {
        guard let letGo else { return }
        Task { @MainActor in withExtendedLifetime(letGo) {} }
    }

    private static func draw(_ request: PDFPageInkRequest, from document: PDFDocument) -> PDFPageInkDrawing {
        guard document.pageCount == request.filePageCount, let page = document.page(at: request.pageNumber - 1) else { return .unavailable }
        if request.adoptsShownGeometry {
            // The copy is the renderer's own, never shown or written.
            if page.bounds(for: .cropBox) != request.cropBox { page.setBounds(request.cropBox, for: .cropBox) }
            if ((page.rotation % 360) + 360) % 360 != request.rotation { page.rotation = request.rotation }
        }
        guard page.bounds(for: .cropBox) == request.cropBox, ((page.rotation % 360) + 360) % 360 == request.rotation else { return .unavailable }
        let strokes = page.annotations.filter { annotation in
            guard let group = annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String, annotation.shouldDisplay else { return false }
            guard let requestedGroup = request.group else { return true }
            return group == requestedGroup && !(annotation.persistentName.map(request.excludedNames.contains) ?? false)
        }
        guard !strokes.isEmpty else { return .noInk }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let surface = request.drawsIntoSurface ? PDFPageInkSurface.make(pixelWidth: request.pixelWidth, pixelHeight: request.pixelHeight,
                                                                        colorSpace: colorSpace) : nil
        if request.drawsIntoSurface, surface == nil { return .unavailable }
        surface?.lock(options: [], seed: nil)
        defer { surface?.unlock(options: [], seed: nil) }
        guard let context = CGContext(data: surface?.baseAddress, width: request.pixelWidth, height: request.pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: surface?.bytesPerRow ?? 0, space: colorSpace,
                                      bitmapInfo: surface == nil ? CGImageAlphaInfo.premultipliedLast.rawValue : PDFPageInkSurface.bitmapInfo)
        else { return .unavailable }
        if surface != nil { context.clear(CGRect(x: 0, y: 0, width: request.pixelWidth, height: request.pixelHeight)) }
        // As the thumbnails draw annotations: in a context with the PDF's upward y axis, scaled to the page as shown; each
        // annotation applies the crop box and the page's turn itself.
        let displayedWidth = request.rotation % 180 == 0 ? request.cropBox.width : request.cropBox.height
        guard displayedWidth > 0 else { return .unavailable }
        let pixelsPerPagePoint = CGFloat(request.pixelWidth) / displayedWidth
        context.scaleBy(x: pixelsPerPagePoint, y: pixelsPerPagePoint)
        for stroke in strokes { stroke.draw(with: .cropBox, in: context) }
        if let surface { return .surface(surface) }
        return context.makeImage().map(PDFPageInkDrawing.picture) ?? .unavailable
    }
}

/// The IOSurfaces the Mac's page ink layers show (`PDFPageInkRequest.drawsIntoSurface`).
enum PDFPageInkSurface {
    /// Premultiplied BGRA, the order Core Animation shows without converting.
    static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    private static let bytesPerPixel = 4
    /// 'BGRA'.
    private static let pixelFormat: UInt32 = 0x4247_5241

    /// A surface of the size asked, tagged with the color space the picture is drawn in, so the layer shows its colors
    /// as a `CGImage` of that space would be shown.
    static func make(pixelWidth: Int, pixelHeight: Int, colorSpace: CGColorSpace) -> IOSurface? {
        guard let surface = IOSurface(properties: [.width: pixelWidth, .height: pixelHeight, .bytesPerElement: bytesPerPixel,
                                                   .pixelFormat: pixelFormat]) else { return nil }
        if let colorSpaceDescription = colorSpace.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, colorSpaceDescription)
        }
        return surface
    }

    /// A copy of the surface's picture as a `CGImage`, which tests compare with PDFKit's drawing.
    static func image(of surface: IOSurface) -> CGImage? {
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let bytes = Data(bytes: surface.baseAddress, count: surface.bytesPerRow * surface.height)
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(width: surface.width, height: surface.height, bitsPerComponent: 8, bitsPerPixel: bytesPerPixel * 8,
                       bytesPerRow: surface.bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}

extension PDFPageInkRenderer {
    /// Draws a combined ink group's strokes, without those erased, for the page as it is shown now, `pixelSize` large;
    /// nil when there is nothing to draw or the copy is not the page's file.
    @MainActor
    static func picture(of combinedGroup: PDFCombinedInkGroup, on page: PDFPage, pixelSize: CGSize,
                        with renderer: PDFPageInkRenderer) async -> PDFCombinedInkGroup.Picture? {
        let cropBox = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        let version = combinedGroup.version
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
        let request = PDFPageInkRequest(fileData: combinedGroup.fileData, pageNumber: combinedGroup.filePageIndex + 1,
                                        filePageCount: combinedGroup.filePageCount, cropBox: cropBox, rotation: rotation,
                                        pixelWidth: Int(pixelSize.width), pixelHeight: Int(pixelSize.height),
                                        group: combinedGroup.group, excludedNames: combinedGroup.removedNames, adoptsShownGeometry: true)
        guard case .picture(let image) = await renderer.draw(request) else { return nil }
        return PDFCombinedInkGroup.Picture(image: image, cropBox: cropBox, rotation: rotation, version: version)
    }
}
