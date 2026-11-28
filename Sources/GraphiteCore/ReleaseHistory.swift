/**
 * File: ReleaseHistory.swift
 * --------------------------
 * Layer: Core
 * Description: The release history the What's New page shows: versions, their dated groups and their
 *              Added, Changed and Fixed lines, read from the strict Markdown of ReleaseNotes.md.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import Foundation

/// What a line of the release history says happened.
public enum ReleaseNoteKind: String, CaseIterable, Sendable {
    case added = "Added"
    case changed = "Changed"
    case fixed = "Fixed"
}

/// A device a line of the release history can be limited to.
public enum ReleaseNotePlatform: String, CaseIterable, Sendable {
    case mac = "Mac"
    case iPad = "iPad"
    case iPhone = "iPhone"
}

/// One line of the release history: what was added, changed or fixed, on which devices.
public struct ReleaseNoteEntry: Hashable, Sendable {
    public let kind: ReleaseNoteKind
    /// The devices the line is about; empty when it is about every device.
    public let platforms: [ReleaseNotePlatform]
    public let text: String

    public init(kind: ReleaseNoteKind, platforms: [ReleaseNotePlatform] = [], text: String) {
        self.kind = kind
        self.platforms = platforms
        self.text = text
    }

    public func applies(to platform: ReleaseNotePlatform) -> Bool {
        platforms.isEmpty || platforms.contains(platform)
    }
}

/// A moment of the release history, to the minute, as one number that orders like the
/// time: 2026-11-28 14:05 is 202611281405. A build number (`20261128.1405`, the archive's
/// date and time) reads as the same kind of moment, so the two compare directly.
public struct ReleaseMoment: Comparable, Hashable, Sendable {
    public let minutesNumber: Int

    public static func < (leftMoment: ReleaseMoment, rightMoment: ReleaseMoment) -> Bool {
        leftMoment.minutesNumber < rightMoment.minutesNumber
    }

    init(year: Int, month: Int, day: Int, hour: Int, minute: Int) {
        minutesNumber = (((year * 100 + month) * 100 + day) * 100 + hour) * 100 + minute
    }

    /// The moment of a build number of the form `YYYYMMDD.HHMM`; nil for any other build number,
    /// such as a development build's `1`. The time may have lost its leading zeros (`20261105.5`
    /// is 00:05), as App Store Connect shows it.
    public init?(buildNumber: String) {
        let parts = buildNumber.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 8, (1...4).contains(parts[1].count),
              let datePart = Int(parts[0]), let timePart = Int(parts[1]) else { return nil }
        let hour = timePart / 100, minute = timePart % 100
        let year = datePart / 10_000, month = datePart / 100 % 100, day = datePart % 100
        guard ReleaseMoment.isValid(month: month, day: day, hour: hour, minute: minute) else { return nil }
        self.init(year: year, month: month, day: day, hour: hour, minute: minute)
    }

    static func isValid(month: Int, day: Int, hour: Int, minute: Int) -> Bool {
        (1...12).contains(month) && (1...31).contains(day) && (0...23).contains(hour) && (0...59).contains(minute)
    }
}

/// The lines of one upload, or of one day when the time is not known, under their heading.
public struct ReleaseNoteGroup: Hashable, Sendable {
    /// The heading as written: `2026-11-28` or `2026-11-28 14:05`.
    public let heading: String
    /// When the group was written. A heading with no time counts as the end of its day, so a group
    /// of the same day as a build the person saw is shown as new rather than hidden.
    public let moment: ReleaseMoment
    public let entries: [ReleaseNoteEntry]

    public init(heading: String, moment: ReleaseMoment, entries: [ReleaseNoteEntry]) {
        self.heading = heading
        self.moment = moment
        self.entries = entries
    }

    /// The group's day, for display in the person's own date format.
    public var day: DateComponents {
        let number = moment.minutesNumber / 10_000
        return DateComponents(year: number / 10_000, month: number / 100 % 100, day: number % 100)
    }
}

/// A version people see (`1.0.3`) and its groups, newest first.
public struct ReleaseNoteVersion: Hashable, Sendable {
    public let name: String
    public let groups: [ReleaseNoteGroup]

    public init(name: String, groups: [ReleaseNoteGroup]) {
        self.name = name
        self.groups = groups
    }
}

/// Why a release history could not be read, with the line (counted from 1) that is wrong.
public struct ReleaseHistoryFormatError: Error, Equatable, CustomStringConvertible, Sendable {
    public let lineNumber: Int
    public let reason: String

    public var description: String { "ReleaseNotes.md line \(lineNumber): \(reason)" }
}

/// Every version's changes, newest first, read from ReleaseNotes.md.
///
/// The grammar is strict so a test refuses a malformed file instead of the page dropping lines:
/// one `# ` title, then `## <version>`, then `### <YYYY-MM-DD>` or `### <YYYY-MM-DD HH:MM>`,
/// then `- <Kind>: <text>` or `- <Kind> [<Platform>, …]: <text>`. Blank lines may go anywhere.
/// Groups are newest first through the whole file, no two share a heading, and no version or group is empty.
public struct ReleaseHistory: Hashable, Sendable {
    public let versions: [ReleaseNoteVersion]

    public init(versions: [ReleaseNoteVersion]) {
        self.versions = versions
    }

    public static func read(_ markdown: String) throws -> ReleaseHistory {
        var reader = ReleaseHistoryReader()
        for (offset, line) in markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            try reader.read(line: line.trimmingCharacters(in: .whitespaces), lineNumber: offset + 1)
        }
        return try reader.finish()
    }

    /// The history with only the lines that apply to `platform`, without groups or versions left empty.
    public func applying(to platform: ReleaseNotePlatform) -> ReleaseHistory {
        ReleaseHistory(versions: versions.compactMap { version in
            let groups = version.groups.compactMap { group -> ReleaseNoteGroup? in
                let entries = group.entries.filter { entry in entry.applies(to: platform) }
                return entries.isEmpty ? nil : ReleaseNoteGroup(heading: group.heading, moment: group.moment, entries: entries)
            }
            return groups.isEmpty ? nil : ReleaseNoteVersion(name: version.name, groups: groups)
        })
    }

    /// Whether any group was written after `moment`, so a build later than `moment` has something new.
    public func hasGroups(after moment: ReleaseMoment) -> Bool {
        versions.first?.groups.first.map { newestGroup in newestGroup.moment > moment } ?? false
    }
}

/// Reads the release history one line at a time, keeping the version and group being read.
private struct ReleaseHistoryReader {
    private var hasTitle = false
    private var versions: [ReleaseNoteVersion] = []
    private var versionName: String?
    private var versionLineNumber = 0
    private var groups: [ReleaseNoteGroup] = []
    private var group: (heading: String, moment: ReleaseMoment, lineNumber: Int)?
    private var entries: [ReleaseNoteEntry] = []
    private var previousMoment: ReleaseMoment?

    mutating func read(line: String, lineNumber: Int) throws {
        if line.isEmpty { return }
        if line.hasPrefix("### ") {
            try finishGroup()
            try startGroup(heading: String(line.dropFirst(4)), lineNumber: lineNumber)
        } else if line.hasPrefix("## ") {
            try finishVersion()
            try startVersion(name: String(line.dropFirst(3)), lineNumber: lineNumber)
        } else if line.hasPrefix("# ") {
            guard !hasTitle, versionName == nil else { throw formatError(lineNumber, "a second title, or a title after a version") }
            hasTitle = true
        } else if line.hasPrefix("- ") {
            guard group != nil else { throw formatError(lineNumber, "a line before any `### <date>` heading") }
            entries.append(try Self.entry(String(line.dropFirst(2)), lineNumber: lineNumber))
        } else {
            throw formatError(lineNumber, "not a heading or a `- <Kind>: <text>` line")
        }
    }

    mutating func finish() throws -> ReleaseHistory {
        try finishVersion()
        return ReleaseHistory(versions: versions)
    }

    private mutating func startVersion(name: String, lineNumber: Int) throws {
        let numbers = name.split(separator: ".", omittingEmptySubsequences: false)
        let isNumber = { (number: Substring) in !number.isEmpty && number.allSatisfy { character in character.isASCII && character.isNumber } }
        guard (1...3).contains(numbers.count), numbers.allSatisfy(isNumber) else {
            throw formatError(lineNumber, "`\(name)` is not a version of one to three numbers")
        }
        guard !versions.contains(where: { version in version.name == name }) else { throw formatError(lineNumber, "version \(name) appears twice") }
        versionName = name
        versionLineNumber = lineNumber
    }

    private mutating func finishVersion() throws {
        try finishGroup()
        guard let name = versionName else { return }
        guard !groups.isEmpty else { throw formatError(versionLineNumber, "version \(name) has no dated group") }
        versions.append(ReleaseNoteVersion(name: name, groups: groups))
        versionName = nil
        groups = []
    }

    private mutating func startGroup(heading: String, lineNumber: Int) throws {
        guard versionName != nil else { throw formatError(lineNumber, "a dated group before any `## <version>` heading") }
        guard let moment = Self.moment(ofHeading: heading) else {
            throw formatError(lineNumber, "`\(heading)` is not a date `YYYY-MM-DD` or `YYYY-MM-DD HH:MM`")
        }
        if let previousMoment, moment >= previousMoment {
            throw formatError(lineNumber, "`\(heading)` is not earlier than the group above it: groups go newest first, one per heading")
        }
        previousMoment = moment
        group = (heading, moment, lineNumber)
    }

    private mutating func finishGroup() throws {
        guard let group else { return }
        guard !entries.isEmpty else { throw formatError(group.lineNumber, "the group `\(group.heading)` has no lines") }
        groups.append(ReleaseNoteGroup(heading: group.heading, moment: group.moment, entries: entries))
        self.group = nil
        entries = []
    }

    /// `2026-11-28 14:05`, or `2026-11-28` as the last minute of that day.
    private static func moment(ofHeading heading: String) -> ReleaseMoment? {
        let parts = heading.split(separator: " ")
        guard (1...2).contains(parts.count) else { return nil }
        let dateNumbers = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard dateNumbers.count == 3, dateNumbers[0].count == 4, dateNumbers[1].count == 2, dateNumbers[2].count == 2,
              let year = Int(dateNumbers[0]), let month = Int(dateNumbers[1]), let day = Int(dateNumbers[2]) else { return nil }
        var hour = 23, minute = 59
        if parts.count == 2 {
            let timeNumbers = parts[1].split(separator: ":", omittingEmptySubsequences: false)
            guard timeNumbers.count == 2, timeNumbers.allSatisfy({ number in number.count == 2 }),
                  let readHour = Int(timeNumbers[0]), let readMinute = Int(timeNumbers[1]) else { return nil }
            hour = readHour
            minute = readMinute
        }
        guard ReleaseMoment.isValid(month: month, day: day, hour: hour, minute: minute) else { return nil }
        return ReleaseMoment(year: year, month: month, day: day, hour: hour, minute: minute)
    }

    /// `Fixed [Mac, iPad]: text` or `Added: text`.
    private static func entry(_ line: String, lineNumber: Int) throws -> ReleaseNoteEntry {
        guard let colon = line.firstIndex(of: ":") else { throw formatError(lineNumber, "no `:` after the kind") }
        let label = line[..<colon]
        let text = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw formatError(lineNumber, "the line says nothing after its kind") }
        var kindName = label.trimmingCharacters(in: .whitespaces)
        var platforms: [ReleaseNotePlatform] = []
        if let openingBracket = kindName.firstIndex(of: "[") {
            guard kindName.hasSuffix("]") else { throw formatError(lineNumber, "the platform list does not end with `]`") }
            let names = kindName[kindName.index(after: openingBracket)..<kindName.index(before: kindName.endIndex)]
            for name in names.split(separator: ",", omittingEmptySubsequences: false) {
                let platformName = name.trimmingCharacters(in: .whitespaces)
                guard let platform = ReleaseNotePlatform(rawValue: platformName) else {
                    throw formatError(lineNumber, "`\(platformName)` is not Mac, iPad or iPhone")
                }
                guard !platforms.contains(platform) else { throw formatError(lineNumber, "\(platformName) is listed twice") }
                platforms.append(platform)
            }
            kindName = kindName[..<openingBracket].trimmingCharacters(in: .whitespaces)
        }
        guard let kind = ReleaseNoteKind(rawValue: kindName) else {
            throw formatError(lineNumber, "`\(kindName)` is not Added, Changed or Fixed")
        }
        return ReleaseNoteEntry(kind: kind, platforms: platforms, text: text)
    }

    private func formatError(_ lineNumber: Int, _ reason: String) -> ReleaseHistoryFormatError {
        Self.formatError(lineNumber, reason)
    }

    private static func formatError(_ lineNumber: Int, _ reason: String) -> ReleaseHistoryFormatError {
        ReleaseHistoryFormatError(lineNumber: lineNumber, reason: reason)
    }
}
