/**
 * File: ReleaseVaultNotebooks.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The release vault's files made by Graphite's other writers: a notebook on every paper and every page
 *              size of the New Notebook sheet, the PDFs an import of the synthetic Goodnotes and Notability notebooks
 *              writes, pictures in every format Graphite opens, and the folders' colours and symbols.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(macOS)
import Foundation
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteFixtures
import NotebookImport
import PDFKit
@testable import GraphiteApple

/// What the New Notebook sheet, the notebook import and the library's folder styles write, for
/// Docs/Release-test-vault-todo.md section 1, each by the code the app runs.
enum ReleaseVaultNotebooks {
    /// One notebook on each paper of the sheet (`NotebookPaperChoice`), on A5, with a cover of each colour in turn and
    /// lines of each colour and strength in turn, so every choice of the sheet is in some notebook.
    static func notebooksByPaper() throws -> [(path: String, data: Data)] {
        let paperColors: [DrawingBackground] = [.white, .ivory, .yellow, .gray]
        return try NotebookPaperChoice.allCases.enumerated().map { paperIndex, paper in
            var style = PaperSpecification()
            style.lineColor = DrawingPaperLineColor.allCases[paperIndex % DrawingPaperLineColor.allCases.count]
            style.lineStrength = DrawingPaperLineStrength.allCases[paperIndex % DrawingPaperLineStrength.allCases.count]
            style.paperColorHex = paperColors[paperIndex % paperColors.count].colorHex
            var options = NewNotebookOptions(paperChoice: paper, paperStyle: style, pageSize: .named(.a5, .portrait), pageCount: 2)
            // The last paper has no cover, as a notebook made with None.
            options.cover = paperIndex < NotebookCoverColor.allCases.count ? NotebookCoverColor.allCases[paperIndex] : nil
            let name = paperName(paper)
            return ("Notebooks/Papers/\(name).pdf", try NewNotebookDocument.data(for: options, titled: name, templateLocation: nil))
        }
    }

    /// The paper's name as the sheet shows it (`NotebookPaperChoice.title` in GraphiteUI).
    private static func paperName(_ paper: NotebookPaperChoice) -> String {
        switch paper {
        case .blank: "Blank"
        case .dotted: "Dotted Paper"
        case .squared: "Squared Paper"
        case .ruledNarrow: "Ruled Narrow"
        case .ruledWide: "Ruled Wide"
        case .cornell: "Cornell"
        case .engineering: "Engineering"
        case .isometric: "Isometric"
        case .music: "Music Paper"
        }
    }

    /// One notebook of each page size of the sheet (`NotebookPageSize`), landscape for every second one, and one of a
    /// size of the person's own: one dotted page each, without a cover.
    static func notebooksBySize() throws -> [(path: String, data: Data)] {
        var choices: [(name: String, size: NotebookPageSizeChoice)] = NotebookPageSize.allCases.enumerated().map { sizeIndex, size in
            let orientation: PageOrientation = sizeIndex.isMultiple(of: 2) ? .portrait : .landscape
            let sizeName = switch size {
            case .letter: "Letter"
            case .tabloid: "Tabloid"
            case .a3, .a4, .a5, .a6, .a7: size.rawValue.uppercased()
            }
            return ("\(sizeName) \(orientation.rawValue)", .named(size, orientation))
        }
        choices.append(("Custom 5 by 5 inches", .custom(widthPoints: 360, heightPoints: 360)))
        return try choices.map { choice in
            let options = NewNotebookOptions(paperChoice: .dotted, paperStyle: PaperSpecification(), pageSize: choice.size, pageCount: 1)
            return ("Notebooks/Sizes/\(choice.name).pdf", try NewNotebookDocument.data(for: options, titled: choice.name, templateLocation: nil))
        }
    }

    /// A paper of one's own, as My Templates keeps it in `.obsidian/graphite-templates`, made from the scanned lab sheet
    /// (a PDF page), and a notebook of two pages on it.
    static func myTemplateAndNotebook(fromScannedPage scannedPage: URL, in folder: URL) throws -> [(path: String, data: Data)] {
        let template = try MyPaperTemplateBuilder.templateData(fromPDF: try Data(contentsOf: scannedPage), pageIndex: 0)
        let templateLocation = folder.appendingPathComponent("Lab sheet.pdf")
        try template.write(to: templateLocation)
        let notebook = try MyPaperTemplateNotebook.documentData(templateAt: templateLocation, pageCount: 2)
        return [("\(MyPaperTemplateList.directory)/Lab sheet.pdf", template), ("Notebooks/On my template.pdf", notebook)]
    }

    /// The PDF an import writes for each synthetic notebook (`Tests/SyntheticNotebooks`), by the import's own
    /// conversion. Their recordings are not copied: an audio file in the vault could play.
    static func importedNotebooks(into folder: URL) throws -> [(path: String, data: Data)] {
        let sources = try FileManager.default.contentsOfDirectory(at: FixtureFolders.syntheticNotebooks, includingPropertiesForKeys: nil)
            .filter { location in NotebookFileFormat(fileExtension: location.pathExtension) != nil }
            .sorted { first, second in first.lastPathComponent < second.lastPathComponent }
        return try sources.map { source in
            let format = try notebookFormat(source)
            let notebook = try OpenedNotebook.open(source, format: format, limits: .standard)
            let destination = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".pdf")
            _ = try NotebookConversion(fileWriter: AtomicFileWriter()).writePDF(of: notebook, to: destination,
                                                                               strokeCreationDate: ReleaseVaultDrawings.strokeDate) { _ in }
            return ("Imports/\(destination.lastPathComponent)", try namingTheVaultsAuthor(in: destination, writingIn: folder))
        }
    }

    /// The import names the author chosen in Settings on the annotations it makes, else the Mac's account; the vault names
    /// nobody, so its imports are saved again, as Graphite saves a PDF, with the vault's author on each annotation.
    private static func namingTheVaultsAuthor(in importedPDF: URL, writingIn folder: URL) throws -> Data {
        guard let document = PDFDocument(url: importedPDF) else { throw GraphiteError.invalidFile(importedPDF.lastPathComponent) }
        PDFPageManager.prepareForWriting(document)
        for pageIndex in 0..<document.pageCount {
            for annotation in document.page(at: pageIndex)?.annotations ?? [] where annotation.userName != nil {
                PDFAnnotationAuthor.write(ReleaseVaultWrittenPDF.authorName, on: annotation)
            }
        }
        return try ReleaseVaultWrittenPDF.written(document, named: "Author renamed " + importedPDF.lastPathComponent, in: folder)
    }

    private static func notebookFormat(_ source: URL) throws -> NotebookFileFormat {
        guard let format = NotebookFileFormat(fileExtension: source.pathExtension) else { throw GraphiteError.invalidFile(source.lastPathComponent) }
        return format
    }

    /// A small picture in each format Graphite opens as a picture besides PNG, SVG and WebP (which the system cannot write;
    /// the vault's script writes one): JPEG, an animated GIF, TIFF and HEIC. Rings of colour, made here, nothing photographed.
    static func picturesInOtherFormats() throws -> [(path: String, data: Data)] {
        let formats: [(name: String, type: UTType, frameCount: Int)] = [
            ("Rings.jpg", .jpeg, 1), ("Rings.gif", .gif, 3), ("Rings.tiff", .tiff, 1), ("Rings.heic", .heic, 1),
        ]
        let writableTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return try formats.filter { format in writableTypes.contains(format.type.identifier) }.map { format in
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, format.frameCount, nil) else {
                throw GraphiteError.invalidFile(format.name)
            }
            for frameIndex in 0..<format.frameCount {
                let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary
                CGImageDestinationAddImage(destination, try rings(turnedBy: frameIndex), format.frameCount > 1 ? properties : nil)
            }
            guard CGImageDestinationFinalize(destination) else { throw GraphiteError.invalidFile(format.name) }
            return ("Attachments/\(format.name)", data as Data)
        }
    }

    /// Coloured rings on a light ground, their colours shifted by `turn` so the GIF's frames differ.
    private static func rings(turnedBy turn: Int) throws -> CGImage {
        let side = 160
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw GraphiteError.invalidFile("No picture context.") }
        let palette: [(Double, Double, Double)] = [(0.86, 0.27, 0.27), (0.95, 0.65, 0.2), (0.3, 0.65, 0.4), (0.25, 0.45, 0.85)]
        context.setFillColor(CGColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        for ring in 0..<4 {
            let (red, green, blue) = palette[(ring + turn) % palette.count]
            let inset = Double(ring) * 18 + 10
            context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
            context.fillEllipse(in: CGRect(x: inset, y: inset, width: Double(side) - inset * 2, height: Double(side) - inset * 2))
        }
        guard let image = context.makeImage() else { throw GraphiteError.invalidFile("No picture.") }
        return image
    }

    /// The colours and marks of some of the vault's folders, as the library's Customize Folder writes them.
    static func folderStylesData() throws -> Data {
        let styles: [(folder: String, style: FolderStyle)] = [
            ("PDFs", FolderStyle(color: .red, mark: .symbol("doc.richtext"))),
            ("Notebooks", FolderStyle(color: .orange, mark: .emoji("📓"))),
            ("Drawings", FolderStyle(color: .purple, mark: .symbol("pencil.tip"))),
            ("Daily", FolderStyle(color: .teal, mark: .symbol("calendar"))),
            ("Embeds", FolderStyle(color: .custom(red: 0x2F, green: 0x3B, blue: 0x52))),
        ]
        var list = FolderStyleList()
        for entry in styles { list.setStyle(entry.style, for: try VaultPath(entry.folder)) }
        return try list.configurationData()
    }
}
#endif
