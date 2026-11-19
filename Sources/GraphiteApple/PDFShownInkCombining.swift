/**
 * File: PDFShownInkCombining.swift
 * --------------------------------
 * Layer: Apple
 * Description: Finds, in a PDF's bytes, the Graphite ink strokes a shown document leaves out of its pages, and the
 *              update, appended to a copy of the file only, that leaves them out: each densely written ink group keeps
 *              its first stroke, which draws the whole group.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */
import Foundation

/// The shown document's level of detail for densely written pages (HUNT-015, HUNT-347).
///
/// PDFKit's work on a page grows with its annotations, whatever they draw: on the iPad, scrolling a notebook of pages
/// written with 6,000 strokes each stopped the main thread for 450 to 620 ms as each page came on screen, in PDFKit's
/// own walks over the page's annotations (`-[PDFView _updateAnnotations]`, `-[PDFPage containsFormFields]`), and reading
/// a page's 6,000 annotations took 205 to 277 ms, taking them off the page again 482 to 494 ms (Mac, 2026-11-18). So a
/// page must not hold its strokes one by one while it is shown, and taking them off once PDFKit has read them costs
/// more than it saves.
///
/// Here the file's bytes are read for each page's Graphite ink groups (their strokes' annotation objects in the page's
/// `/Annots`, in order). A group of at least `minimumStrokeCount` strokes that follow each other in `/Annots` keeps
/// only its first stroke, the one that carries the group's re-editing record; the update that says so is appended to a
/// copy of the file the shown document is read from. The file itself, the baseline that saving replays edits on, and
/// everything saving, export and sharing write keep one `/Ink` annotation per stroke: what is combined lives in memory
/// only (`PDFCombinedInkGroup`).
///
/// Only the single-section, uncompressed cross-reference table PDFKit writes is understood; any other file is shown
/// as it is, one annotation per stroke.
public enum PDFShownInkCombining {
    /// A group with fewer strokes is shown one annotation per stroke, as before.
    public static let minimumStrokeCount = 64

    /// A stroke the shown page leaves out, as its annotation said.
    public struct Stroke: Sendable, Equatable {
        public let name: String?
        public let author: String?
        public let multipliesOverPage: Bool
    }

    /// A page's ink group shown by its first stroke.
    public struct Group: Sendable, Equatable {
        public let group: String
        /// Every stroke of the group in the page's order, the first (the one kept on the page) included.
        public let strokes: [Stroke]
    }

    /// What the shown document leaves out, and the update that leaves it out.
    public struct Plan: Sendable {
        /// Bytes to append to a copy of the file.
        public let update: Data
        /// The combined groups of each page, by zero-based page index.
        public let groupsByPageIndex: [Int: [Group]]
    }

    /// The plan for the file's bytes, or nil when no page has a group to combine or the file is not in the form PDFKit
    /// writes.
    public static func plan(for fileData: Data) -> Plan? {
        fileData.withUnsafeBytes { bytes in
            var planner = Planner(bytes: bytes)
            return planner.plan()
        }
    }

    /// Writes a copy of the file at `source` with the plan's update appended at `destination` (an APFS clone, so the
    /// copy costs only the update's bytes). Returns nil, and leaves nothing at `destination`, when there is no plan.
    public static func writeShownCopy(of source: URL, to destination: URL) throws -> Plan? {
        let fileData = try Data(contentsOf: source, options: .alwaysMapped)
        guard let plan = plan(for: fileData) else { return nil }
        try FileManager.default.copyItem(at: source, to: destination)
        do {
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() } // Closing a file written to whole loses nothing.
            try handle.seekToEnd()
            try handle.write(contentsOf: plan.update)
        } catch {
            try? FileManager.default.removeItem(at: destination) // A copy left in the temporary folder harms nothing.
            throw error
        }
        return plan
    }
}

// MARK: Planning

private struct Planner {
    /// Bounds memory and time on a damaged file.
    private static let maximumObjectCount = 10_000_000
    private static let maximumPageTreeDepth = 64
    private static let trailerSearchDistance = 4_096

    private static let inkSubtype = "Ink"
    private static let groupKey = PDFPageManager.groupKey.rawValue
    private static let nameKey = PDFPageManager.annotationNameKey.rawValue
    private static let multipliesKey = PDFPageManager.inkMultipliesKey.rawValue

    let bytes: UnsafeRawBufferPointer
    private var offsets: [Int: (offset: Int, generation: Int)] = [:]

    init(bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

    /// What `/Annots` a page is shown with: a new array object, or the page object itself written again when its
    /// `/Annots` is written in it.
    private struct Replacement {
        let number: Int
        let generation: Int
        let bytes: Data
    }

    mutating func plan() -> PDFShownInkCombining.Plan? {
        guard let crossReferenceOffset = findCrossReferenceOffset(), crossReferenceOffset < bytes.count,
              let trailer = readCrossReferenceTable(at: crossReferenceOffset),
              case .reference(let rootNumber)? = trailer.dictionary.entries["Root"],
              case .dictionary(let catalog)? = object(rootNumber)?.value,
              case .reference(let pagesNumber)? = catalog.entries["Pages"] else { return nil }
        var pageNumbers: [Int] = []
        var visited = Set<Int>()
        collectPages(pagesNumber, depth: 0, into: &pageNumbers, visited: &visited)
        guard !pageNumbers.isEmpty else { return nil }
        var replacements: [Replacement] = []
        var groupsByPageIndex: [Int: [PDFShownInkCombining.Group]] = [:]
        for (pageIndex, pageNumber) in pageNumbers.enumerated() {
            guard let (replacement, groups) = combinedPage(pageNumber) else { continue }
            replacements.append(replacement)
            groupsByPageIndex[pageIndex] = groups
        }
        guard !replacements.isEmpty, let trailerText = trailerText(trailer, previousCrossReference: crossReferenceOffset) else { return nil }
        return PDFShownInkCombining.Plan(update: update(replacements, trailerText: trailerText), groupsByPageIndex: groupsByPageIndex)
    }

    /// The page written again without its combined groups' strokes after their first (its `/Annots` array, or the page
    /// object itself when the array is written in it), and those groups; nil when no group of the page is combined.
    private func combinedPage(_ pageNumber: Int) -> (Replacement, [PDFShownInkCombining.Group])? {
        guard let page = object(pageNumber), case .dictionary(let pageDictionary) = page.value,
              let annotations = pageDictionary.entries["Annots"] else { return nil }
        let elements: [PDFSyntaxValue]
        let arrayObject: (number: Int, generation: Int)?
        switch annotations {
        case .array(let inline):
            elements = inline
            arrayObject = nil
        case .reference(let number):
            guard let arrayValue = object(number), case .array(let referenced) = arrayValue.value else { return nil }
            elements = referenced
            arrayObject = (number, arrayValue.generation)
        case .integer, .otherNumber, .boolean, .null, .name, .string, .dictionary:
            return nil
        }
        guard let (keptElements, groups) = combine(elements) else { return nil }
        let arrayText = Data(("[ " + keptElements.map(text(of:)).joined(separator: " ") + " ]").utf8)
        if let arrayObject { return (Replacement(number: arrayObject.number, generation: arrayObject.generation, bytes: arrayText), groups) }
        guard let valueRange = pageDictionary.sourceRanges["Annots"], let pageRange = page.valueRange else { return nil }
        var pageText = Data(UnsafeRawBufferPointer(rebasing: bytes[pageRange.lowerBound..<valueRange.lowerBound]))
        pageText.append(arrayText)
        pageText.append(Data(UnsafeRawBufferPointer(rebasing: bytes[valueRange.upperBound..<pageRange.upperBound])))
        return (Replacement(number: pageNumber, generation: page.generation, bytes: pageText), groups)
    }

    /// The page's annotations without the combined groups' strokes after their first, and those groups; nil when no
    /// group of the page is combined.
    private func combine(_ elements: [PDFSyntaxValue]) -> ([PDFSyntaxValue], [PDFShownInkCombining.Group])? {
        struct Run {
            var firstIndex: Int
            var lastIndex: Int
            var strokes: [PDFShownInkCombining.Stroke]
            var isContiguous = true
        }
        var runs: [String: Run] = [:]
        var groupOrder: [String] = []
        for (index, element) in elements.enumerated() {
            guard case .reference(let number) = element, let annotation = object(number), case .dictionary(let dictionary) = annotation.value,
                  case .name(Self.inkSubtype)? = dictionary.entries["Subtype"], let group = Self.text(dictionary.entries[Self.groupKey]) else { continue }
            let stroke = PDFShownInkCombining.Stroke(name: Self.text(dictionary.entries[Self.nameKey]) ?? Self.text(dictionary.entries["NM"]),
                                                     author: Self.text(dictionary.entries["T"]),
                                                     multipliesOverPage: dictionary.entries[Self.multipliesKey] != nil)
            if var run = runs[group] {
                if run.lastIndex != index - 1 { run.isContiguous = false }
                run.lastIndex = index
                run.strokes.append(stroke)
                runs[group] = run
            } else {
                runs[group] = Run(firstIndex: index, lastIndex: index, strokes: [stroke])
                groupOrder.append(group)
            }
        }
        // Strokes of another group or other annotations between a group's strokes would be drawn in another order.
        let combined = groupOrder.compactMap { group in
            runs[group].flatMap { run in run.isContiguous && run.strokes.count >= PDFShownInkCombining.minimumStrokeCount ? (group, run) : nil }
        }
        guard !combined.isEmpty else { return nil }
        var leftOut = Set<Int>()
        for (_, run) in combined { leftOut.formUnion((run.firstIndex + 1)...run.lastIndex) }
        let kept = elements.enumerated().compactMap { index, element in leftOut.contains(index) ? nil : element }
        return (kept, combined.map { group, run in PDFShownInkCombining.Group(group: group, strokes: run.strokes) })
    }

    private func collectPages(_ number: Int, depth: Int, into pageNumbers: inout [Int], visited: inout Set<Int>) {
        guard depth < Self.maximumPageTreeDepth, visited.insert(number).inserted, case .dictionary(let node)? = object(number)?.value else { return }
        if case .array(let kids)? = node.entries["Kids"] {
            for kid in kids { if case .reference(let kidNumber) = kid { collectPages(kidNumber, depth: depth + 1, into: &pageNumbers, visited: &visited) } }
        } else if case .name("Page")? = node.entries["Type"] {
            pageNumbers.append(number)
        }
    }

    // MARK: Objects

    private struct ReadObject {
        let generation: Int
        let value: PDFSyntaxValue
        /// Where the value's text is, after `obj`.
        let valueRange: Range<Int>?
    }

    private func object(_ number: Int) -> ReadObject? {
        guard let entry = offsets[number], entry.offset < bytes.count else { return nil }
        var scanner = PDFSyntaxScanner(bytes: bytes)
        scanner.position = entry.offset
        guard scanner.readUnsignedInteger() == number, scanner.readUnsignedInteger() == entry.generation, scanner.readKeyword() == "obj" else { return nil }
        let valueStart = scanner.skipWhitespaceAndComments()
        guard let value = scanner.readObjectValue() else { return nil }
        return ReadObject(generation: entry.generation, value: value, valueRange: valueStart..<scanner.position)
    }

    private struct Trailer {
        let dictionary: PDFSyntaxDictionary
        let range: Range<Int>
    }

    private mutating func readCrossReferenceTable(at crossReferenceOffset: Int) -> Trailer? {
        var scanner = PDFSyntaxScanner(bytes: bytes)
        scanner.position = crossReferenceOffset
        guard scanner.readKeyword() == "xref" else { return nil }
        while true {
            let keywordStart = scanner.position
            if scanner.readKeyword() == "trailer" { break }
            scanner.position = keywordStart
            guard let firstNumber = scanner.readUnsignedInteger(), let count = scanner.readUnsignedInteger(),
                  offsets.count + count <= Self.maximumObjectCount else { return nil }
            for entryIndex in 0..<count {
                guard let offset = scanner.readUnsignedInteger(), let generation = scanner.readUnsignedInteger() else { return nil }
                let kind = scanner.readKeyword()
                guard kind == "n" || kind == "f" else { return nil }
                if kind == "n" { offsets[firstNumber + entryIndex] = (offset, generation) }
            }
        }
        let trailerStart = scanner.skipWhitespaceAndComments()
        guard case .dictionary(let dictionary)? = scanner.readValue(),
              dictionary.entries["Prev"] == nil, dictionary.entries["XRefStm"] == nil, dictionary.entries["Encrypt"] == nil,
              case .integer? = dictionary.entries["Size"] else { return nil }
        return Trailer(dictionary: dictionary, range: trailerStart..<scanner.position)
    }

    private func findCrossReferenceOffset() -> Int? {
        let keyword = Array("startxref".utf8)
        let searchStart = max(0, bytes.count - Self.trailerSearchDistance)
        var candidate = bytes.count - keyword.count
        while candidate >= searchStart {
            if (0..<keyword.count).allSatisfy({ index in bytes[candidate + index] == keyword[index] }) {
                var scanner = PDFSyntaxScanner(bytes: bytes)
                scanner.position = candidate + keyword.count
                return scanner.readUnsignedInteger()
            }
            candidate -= 1
        }
        return nil
    }

    // MARK: Writing

    /// The original trailer, byte for byte, with `/Prev` added before its end.
    private func trailerText(_ trailer: Trailer, previousCrossReference: Int) -> Data? {
        var text = Data(UnsafeRawBufferPointer(rebasing: bytes[trailer.range]))
        guard text.count >= 2, text.suffix(2) == Data(">>".utf8) else { return nil }
        text.removeLast(2)
        text.append(Data(" /Prev \(previousCrossReference) >>".utf8))
        return text
    }

    private func update(_ replacements: [Replacement], trailerText: Data) -> Data {
        var update = Data("\n".utf8)
        var entries: [(number: Int, offset: Int, generation: Int)] = []
        for replacement in replacements {
            entries.append((replacement.number, bytes.count + update.count, replacement.generation))
            update.append(Data("\(replacement.number) \(replacement.generation) obj\n".utf8))
            update.append(replacement.bytes)
            update.append(Data("\nendobj\n".utf8))
        }
        let crossReferenceOffset = bytes.count + update.count
        update.append(Data("xref\n".utf8))
        for entry in entries.sorted(by: { left, right in left.number < right.number }) {
            update.append(Data("\(entry.number) 1\n".utf8))
            update.append(Data(Self.entry(entry.offset, entry.generation).utf8))
        }
        update.append(Data("trailer\n".utf8))
        update.append(trailerText)
        update.append(Data("\nstartxref\n\(crossReferenceOffset)\n%%EOF\n".utf8))
        return update
    }

    private static func entry(_ offset: Int, _ generation: Int) -> String {
        let offsetText = String(offset), generationText = String(generation)
        return String(repeating: "0", count: max(0, 10 - offsetText.count)) + offsetText + " "
            + String(repeating: "0", count: max(0, 5 - generationText.count)) + generationText + " n\r\n"
    }

    /// An element of `/Annots` as text: a reference, or, for anything else, a null, which readers skip.
    private func text(of element: PDFSyntaxValue) -> String {
        if case .reference(let number) = element { return "\(number) \(offsets[number]?.generation ?? 0) R" }
        return "null"
    }

    /// A PDF text string: UTF-16 after its byte order mark, otherwise PDFDocEncoding, read as Latin-1.
    static func text(_ value: PDFSyntaxValue?) -> String? {
        guard case .string(let data)? = value else { return nil }
        if data.count >= 2, data.prefix(2) == Data([0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(data: data, encoding: .isoLatin1)
    }
}
