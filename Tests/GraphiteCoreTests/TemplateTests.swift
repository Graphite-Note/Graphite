/**
 * File: TemplateTests.swift
 * -------------------------
 * Layer: Tests
 * Description: Moment date formats, and the variables and templates that use them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteCore

final class MomentDateFormatTests: XCTestCase {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!

    /// Thursday 24 September 2026, 09:05:07.250 in Zurich.
    private var sample: Date {
        var components = DateComponents(year: 2026, month: 9, day: 24, hour: 9, minute: 5, second: 7, nanosecond: 250_000_000)
        components.timeZone = zurich
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func formatted(_ format: String) -> String {
        MomentDateFormat.string(from: sample, format: format, timeZone: zurich)
    }

    func testFormatsDatesAsMomentDoes() {
        XCTAssertEqual(formatted("YYYY-MM-DD"), "2026-09-24")
        XCTAssertEqual(formatted("dddd, MMMM Do YYYY"), "Thursday, September 24th 2026")
        XCTAssertEqual(formatted("ddd D MMM YY"), "Thu 24 Sep 26")
        XCTAssertEqual(formatted("HH:mm:ss.SSS"), "09:05:07.250")
        XCTAssertEqual(formatted("h:mm a"), "9:05 am")
        XCTAssertEqual(formatted("[Week] W, GGGG"), "Week 39, 2026", "ISO week")
        XCTAssertEqual(formatted("[Day] DDDD of YYYY, Q[th quarter]"), "Day 267 of 2026, 3th quarter",
                       "Text in brackets is kept as written, even after a token.")
        XCTAssertEqual(formatted("YYYY/MM/YYYY-MM-DD"), "2026/09/2026-09-24", "Folders by year and month.")
        XCTAssertEqual(formatted("LL"), "September 24, 2026")
        XCTAssertEqual(formatted("E e d"), "4 4 4")
        XCTAssertEqual(formatted("Z"), "+02:00")
        XCTAssertEqual(formatted("kk"), "09")
    }

    func testLowerCaseLongFormatsAreTheShortForms() {
        XCTAssertEqual(formatted("l"), "9/24/2026")
        XCTAssertEqual(formatted("ll"), "Sep 24, 2026")
        XCTAssertEqual(formatted("lll"), "Sep 24, 2026 9:05 AM")
        XCTAssertEqual(formatted("llll"), "Thu, Sep 24, 2026 9:05 AM")
        XCTAssertEqual(formatted("LT"), "9:05 AM")
        XCTAssertEqual(formatted("LTS"), "9:05:07 AM")
    }

    func testBackslashWritesTheTokenAfterItAsText() {
        XCTAssertEqual(formatted("YYYY-MM-DD \\W\\e\\e\\k"), "2026-09-24 Week")
        XCTAssertEqual(formatted("\\YYYY YYYY"), "YYYY 2026", "The whole token after a backslash is text.")
        XCTAssertEqual(formatted("\\LL"), "LL", "A long format after a backslash is not expanded.")
        XCTAssertEqual(formatted("\\[YYYY]"), "[2026]", "An escaped bracket opens no bracketed text.")
        XCTAssertEqual(formatted("D\\-M\\"), "24-9", "A backslash at the end writes nothing.")
        XCTAssertEqual(formatted("[abc"), "[ambc", "A bracket with no end stands alone, and the rest is a format.")
        XCTAssertEqual(formatted("[a[b]"), "[amb", "A second opening bracket ends the first one's reach.")
    }

    func testMomentTokensBeyondTheCommonOnes() {
        XCTAssertEqual(formatted("S SS SSS SSSS SSSSSS SSSSSSSSS"), "2 25 250 2500 250000 250000000")
        XCTAssertEqual(formatted("z|zz"), "|", "Moment writes no zone name for a local time.")
        XCTAssertEqual(formatted("N NNNN NNNNN"), "AD Anno Domini AD")
        XCTAssertEqual(formatted("y yyyy yo"), "2026 2026 2026th")
        XCTAssertEqual(formatted("YYYYY YYYYYY"), "02026 +002026")
        XCTAssertEqual(formatted("ggggg GGGGG"), "02026 02026")
    }

    func testAReaderPreparedOnceReadsTheSameDaysAsReadingEachName() throws {
        let formats = ["YYYY-MM-DD", "DD.MM.YYYY", "dddd, MMMM Do YYYY", "ll", "YY-M-D"]
        let names = ["2026-09-24", "24.09.2026", "Thursday, September 24th 2026", "Sep 24, 2026", "26-9-24", "Meeting notes", "2026-04-31", "2026-09-24 09"]
        for format in formats {
            let reader = try XCTUnwrap(MomentDateReader(format: format), format)
            for name in names {
                XCTAssertEqual(reader.date(from: name, timeZone: zurich), MomentDateFormat.date(from: name, format: format, timeZone: zurich), "\(format) reading \(name)")
            }
        }
        XCTAssertNil(MomentDateReader(format: "YYYY-MM-DD HH"), "Hours are not read.")
    }

    func testDailyNotesOfAFolderAreReadWithOneReader() throws {
        let settings = DailyNoteSettings(format: "YYYY-MM-DD", folder: "Daily", template: "", opensOnStartup: false)
        let reader = try XCTUnwrap(MomentDateReader(format: settings.format))
        let paths = try ["Daily/2026-09-24.md", "Daily/2026-09-25.md", "Daily/notes.md", "Other/2026-09-24.md", "Daily/2026-09-24.png"].map { path in try VaultPath(path) }

        let dated = paths.compactMap { path in settings.date(ofNoteAt: path, using: reader, timeZone: zurich) }

        XCTAssertEqual(dated.count, 2)
        XCTAssertEqual(settings.date(ofNoteAt: paths[0], timeZone: zurich), dated.first)
    }

    func testOrdinalsAndTwelveHourClock() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents(year: 2026, month: 1, day: 11, hour: 0, minute: 30)
        components.timeZone = zurich
        let date = calendar.date(from: components)!
        XCTAssertEqual(MomentDateFormat.string(from: date, format: "Do hh:mm A kk", timeZone: zurich), "11th 12:30 AM 24")
        components.day = 22
        XCTAssertEqual(MomentDateFormat.string(from: calendar.date(from: components)!, format: "Do", timeZone: zurich), "22nd")
    }

    func testReadsDatesBack() throws {
        let formats = ["YYYY-MM-DD", "DD.MM.YYYY", "YYYY/MM/YYYY-MM-DD", "dddd, MMMM Do YYYY", "YY-M-D", "ll", "\\D\\a\\y YYYY-MM-DD"]
        for format in formats {
            let text = formatted(format)
            let date = try XCTUnwrap(MomentDateFormat.date(from: text, format: format, timeZone: zurich), format)
            XCTAssertEqual(MomentDateFormat.string(from: date, format: "YYYY-MM-DD", timeZone: zurich), "2026-09-24", format)
        }
        XCTAssertNil(MomentDateFormat.date(from: "2026-04-31", format: "YYYY-MM-DD", timeZone: zurich), "No 31 April.")
        XCTAssertNil(MomentDateFormat.date(from: "Meeting notes", format: "YYYY-MM-DD", timeZone: zurich))
        XCTAssertNil(MomentDateFormat.date(from: "2026-09-24 09", format: "YYYY-MM-DD HH", timeZone: zurich), "Hours are not read.")
    }
}

final class TemplateTests: XCTestCase {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!

    private var sample: Date {
        var components = DateComponents(year: 2026, month: 9, day: 24, hour: 14, minute: 30)
        components.timeZone = zurich
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testFillsInTemplateVariables() {
        let template = "# {{title}}\nCreated {{date}} at {{time}}\n{{DATE:dddd}} {{ time : h A }}\nPrevious: [[{{yesterday}}]] Next: [[{{date+1d:YYYY-MM-DD}}]] Week later: {{date+1w}}\n{{unknown}}"
        XCTAssertEqual(TemplateRenderer.render(template, title: "Signals", date: sample, dateFormat: "YYYY-MM-DD", timeFormat: "HH:mm", timeZone: zurich), """
            # Signals
            Created 2026-09-24 at 14:30
            Thursday 2 PM
            Previous: [[2026-09-23]] Next: [[2026-09-25]] Week later: 2026-10-01
            {{unknown}}
            """)
    }

    func testDateOffsetsUseTheRequestedTimeZoneAcrossDaylightSaving() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        let beforeSpringChange = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 8, hour: 12)))
        let rendered = TemplateRenderer.render("{{date+1d:YYYY-MM-DD HH:mm}}", title: "", date: beforeSpringChange,
                                               dateFormat: "YYYY-MM-DD", timeFormat: "HH:mm", timeZone: newYork)
        XCTAssertEqual(rendered, "2025-03-09 12:00")
    }

    func testOffsetsTooLargeToRepresentKeepTheirSourceInsteadOfCrashing() {
        for unit in ["w", "Q", "y", "d"] {
            let template = "{{date+\(Int.max)\(unit):YYYY-MM-DD}}"
            XCTAssertEqual(TemplateRenderer.render(template, title: "", date: sample,
                                                   dateFormat: "YYYY-MM-DD", timeFormat: "HH:mm", timeZone: zurich), template)
        }
    }

    func testReadsAndWritesPluginSettings() throws {
        let templates = TemplateSettings(configurationData: Data(#"{"folder": "/Templates/", "dateFormat": "", "extra": 1}"#.utf8))
        XCTAssertEqual(templates, TemplateSettings(folder: "Templates", dateFormat: "YYYY-MM-DD", timeFormat: "HH:mm"))
        let written = try templates.mergedConfigurationData(existingData: Data(#"{"extra": 1}"#.utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertEqual(object["extra"] as? Int, 1, "Keys Graphite does not know are kept.")
        XCTAssertEqual(object["folder"] as? String, "Templates")

        let daily = DailyNoteSettings(configurationData: Data(#"{"folder": "Journal", "format": "", "template": "Templates/Daily", "autorun": true}"#.utf8))
        XCTAssertEqual(daily.format, "YYYY-MM-DD")
        XCTAssertEqual(daily.templatePath, try VaultPath("Templates/Daily.md"))
        XCTAssertTrue(daily.opensOnStartup)
        XCTAssertEqual(DailyNoteSettings(configurationData: nil), DailyNoteSettings())
    }

    func testDailyNotePathsAndDates() throws {
        let settings = DailyNoteSettings(format: "YYYY/MM/YYYY-MM-DD", folder: "Journal")
        let path = try settings.notePath(for: sample, timeZone: zurich)
        XCTAssertEqual(path.rawValue, "Journal/2026/09/2026-09-24.md")
        let date = try XCTUnwrap(settings.date(ofNoteAt: path, timeZone: zurich))
        XCTAssertEqual(MomentDateFormat.string(from: date, format: "YYYY-MM-DD", timeZone: zurich), "2026-09-24")
        XCTAssertNil(settings.date(ofNoteAt: try VaultPath("Journal/2026/09/Plans.md"), timeZone: zurich))
        XCTAssertNil(settings.date(ofNoteAt: try VaultPath("Other/2026/09/2026-09-24.md"), timeZone: zurich))
        XCTAssertEqual(try DailyNoteSettings().notePath(for: sample, timeZone: zurich).rawValue, "2026-09-24.md")
    }

    func testMergesTemplatePropertiesIntoTheNote() {
        let note = [NoteProperty(key: "tags", value: .list(["course"])), NoteProperty(key: "status", value: .text("draft")), NoteProperty(key: "due", value: .empty)]
        let template = [NoteProperty(key: "tags", value: .list(["lecture", "course"])), NoteProperty(key: "status", value: .text("todo")),
                        NoteProperty(key: "due", value: .date("2026-10-01")), NoteProperty(key: "reviewed", value: .checkbox(false))]
        XCTAssertEqual(TemplateInsertion.mergedProperties(note: note, template: template), [
            NoteProperty(key: "tags", value: .list(["course", "lecture"])),
            NoteProperty(key: "status", value: .text("draft")),
            NoteProperty(key: "due", value: .date("2026-10-01")),
            NoteProperty(key: "reviewed", value: .checkbox(false)),
        ])
    }

    private func applying(_ edit: MarkdownTextEdit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testInsertsTheBodyAtTheCursorAndMergesProperties() {
        let note = "---\ntags:\n  - course\n---\nIntro\n\nEnd"
        let cursor = NSRange(location: (note as NSString).range(of: "\n\nEnd").location, length: 0)
        let template = "---\ntags:\n  - lecture\ncourse: Signals\n---\n## Summary\n"
        let edit = TemplateInsertion.edit(inserting: template, into: note, at: cursor)
        let result = applying(edit, to: note)
        XCTAssertEqual(result, "---\ntags:\n  - course\n  - lecture\ncourse: Signals\n---\nIntro## Summary\n\n\nEnd")
        XCTAssertEqual((result as NSString).substring(to: edit.selectionAfter.location).hasSuffix("## Summary\n"), true)
    }

    func testTemplatesWithoutPropertiesGoInAsWritten() {
        let edit = TemplateInsertion.edit(inserting: "- [ ] Review\n", into: "---\na: 1\n---\n", at: NSRange(location: 0, length: 0))
        XCTAssertEqual(edit.range, NSRange(location: 13, length: 0), "Never inside the note's frontmatter.")
        XCTAssertEqual(edit.replacement, "- [ ] Review\n")
        let empty = TemplateInsertion.edit(inserting: "---\ntype: daily\n---\n# Today\n", into: "", at: NSRange(location: 0, length: 0))
        XCTAssertEqual(applying(empty, to: ""), "---\ntype: daily\n---\n# Today\n")
    }
}
