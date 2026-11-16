/**
 * File: ColorProfileSharing.swift
 * -------------------------------
 * Layer: Apple
 * Description: Makes the appearances of a file PDFKit wrote share one copy of each colour profile, where PDFKit wrote
 *              a profile of its own for every stroke's appearance.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import Foundation

/// Appearance forms that name a colour profile (`/ICCBased`) the file holds several identical copies of, made to name
/// the first copy, so the other copies are left unreachable and compaction leaves them out.
///
/// PDFKit writes the appearance of each annotation it creates in a document read from a file, as every save of a PDF
/// Graphite writes on is, with a colour space of its own and an sRGB profile of its own: 2.7 KB a stroke, more than the
/// stroke's annotation. Measured 2026-11-12 on an import of two pages of 2,000 strokes: 4,001 identical profiles, 10.8
/// MB of a 21.5 MB file. Only a form's own `/Resources`, written in its dictionary, is looked at, and only the object
/// numbers of its `/ICCBased` references change; a profile is shared only with copies identical to it byte for byte.
enum ColorProfileSharing {
    private static let profileToken = Array("/ICCBased".utf8)

    /// The forms' new bytes by object number, and for each copy of a profile no form names any more, the copy kept.
    struct Sharing {
        var replacements: [Int: Data] = [:]
        var keptCopyByDuplicate: [Int: Int] = [:]
    }

    /// Whether the dictionary is a form whose own resources name a colour profile.
    static func namesProfiles(_ dictionary: PDFSyntaxDictionary) -> Bool {
        guard case .name("Form")? = dictionary.entries["Subtype"], dictionary.entries["Length"] != nil,
              case .dictionary(let resources)? = dictionary.entries["Resources"],
              case .dictionary(let colorSpaces)? = resources.entries["ColorSpace"] else { return false }
        return colorSpaces.entries.values.contains { colorSpace in
            guard case .array(let elements) = colorSpace, case .name("ICCBased")? = elements.first, case .reference? = elements.last else { return false }
            return true
        }
    }

    static func find(in candidates: Set<Int>, objects: (Int) -> (generation: Int, range: Range<Int>)?, bytes: UnsafeRawBufferPointer) -> Sharing {
        var references: [(form: Int, numberRanges: [(profile: Int, range: Range<Int>)])] = []
        for number in candidates.sorted() {
            guard let object = objects(number) else { continue }
            var scanner = PDFSyntaxScanner(bytes: bytes)
            scanner.position = object.range.lowerBound
            guard scanner.readUnsignedInteger() == number, scanner.readUnsignedInteger() == object.generation, scanner.readKeyword() == "obj",
                  case .dictionary(let form)? = scanner.readValue(), namesProfiles(form), let resourcesRange = form.sourceRanges["Resources"],
                  object.range.contains(resourcesRange.lowerBound), resourcesRange.upperBound <= object.range.upperBound else { continue }
            references.append((number, profileReferences(in: resourcesRange, bytes: bytes)))
        }
        let keptCopy = keptCopies(of: Set(references.flatMap { reference in reference.numberRanges.map(\.profile) }), objects: objects, bytes: bytes)
        var sharing = Sharing()
        for (form, numberRanges) in references where numberRanges.contains(where: { reference in keptCopy[reference.profile] != nil }) {
            guard let object = objects(form) else { continue }
            var objectBytes = Data()
            var copiedUpTo = object.range.lowerBound
            for reference in numberRanges {
                guard let kept = keptCopy[reference.profile] else { continue }
                objectBytes.append(Data(UnsafeRawBufferPointer(rebasing: bytes[copiedUpTo..<reference.range.lowerBound])))
                objectBytes.append(Data(String(kept).utf8))
                copiedUpTo = reference.range.upperBound
                sharing.keptCopyByDuplicate[reference.profile] = kept
            }
            objectBytes.append(Data(UnsafeRawBufferPointer(rebasing: bytes[copiedUpTo..<object.range.upperBound])))
            sharing.replacements[form] = objectBytes
        }
        return sharing
    }

    /// Each `/ICCBased <number> <generation> R` in the range: the profile's number and where its digits are.
    private static func profileReferences(in range: Range<Int>, bytes: UnsafeRawBufferPointer) -> [(profile: Int, range: Range<Int>)] {
        var found: [(profile: Int, range: Range<Int>)] = []
        var position = range.lowerBound
        while position + profileToken.count <= range.upperBound {
            guard (0..<profileToken.count).allSatisfy({ offset in bytes[position + offset] == profileToken[offset] }) else {
                position += 1
                continue
            }
            position += profileToken.count
            var scanner = PDFSyntaxScanner(bytes: bytes)
            scanner.position = position
            let numberStart = scanner.skipWhitespaceAndComments()
            guard let profile = scanner.readUnsignedInteger() else { continue }
            let numberEnd = scanner.position
            guard scanner.readUnsignedInteger() != nil, scanner.readKeyword() == "R", scanner.position <= range.upperBound else { continue }
            found.append((profile, numberStart..<numberEnd))
            position = scanner.position
        }
        return found
    }

    /// For each profile with an identical copy of a lower number, that copy: the bytes after the object's header match.
    private static func keptCopies(of profiles: Set<Int>, objects: (Int) -> (generation: Int, range: Range<Int>)?,
                                   bytes: UnsafeRawBufferPointer) -> [Int: Int] {
        var firstCopyByContents: [Data: Int] = [:]
        var keptCopy: [Int: Int] = [:]
        for profile in profiles.sorted() {
            guard let object = objects(profile) else { continue }
            var scanner = PDFSyntaxScanner(bytes: bytes)
            scanner.position = object.range.lowerBound
            guard scanner.readUnsignedInteger() == profile, scanner.readUnsignedInteger() == object.generation, scanner.readKeyword() == "obj" else { continue }
            let contents = Data(UnsafeRawBufferPointer(rebasing: bytes[scanner.position..<object.range.upperBound]))
            if let firstCopy = firstCopyByContents[contents] { keptCopy[profile] = firstCopy } else { firstCopyByContents[contents] = profile }
        }
        return keptCopy
    }
}
