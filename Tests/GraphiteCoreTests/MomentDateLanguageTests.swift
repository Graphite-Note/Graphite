/**
 * File: MomentDateLanguageTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Dates in another language, written and read as Obsidian's Moment writes them (HUNT-154).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import Foundation
import XCTest
@testable import GraphiteCore

final class MomentDateLanguageTests: XCTestCase {
    private let zurich = TimeZone(identifier: "Europe/Zurich") ?? .current
    private let german = MomentDateLanguage.named("de")
    private let germanDailyFormat = "dddd, DD. MMMM YYYY"

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zurich
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)))
    }

    func testAGermanDailyNoteHasTheNameObsidianGivesIt() throws {
        let settings = DailyNoteSettings(format: germanDailyFormat, folder: "Journal")
        let path = try settings.notePath(for: day(2026, 11, 1), timeZone: zurich, language: german)
        XCTAssertEqual(path.rawValue, "Journal/Sonntag, 01. November 2026.md")
    }

    func testAGermanNameIsReadBackAsThatDay() throws {
        let settings = DailyNoteSettings(format: germanDailyFormat, folder: "Journal")
        let path = try VaultPath("Journal/Sonntag, 01. November 2026.md")
        XCTAssertEqual(settings.date(ofNoteAt: path, timeZone: zurich, languages: [german]), try day(2026, 11, 1))
        XCTAssertEqual(settings.date(ofNoteAt: try VaultPath("Journal/Mittwoch, 04. März 2026.md"), timeZone: zurich, languages: [german]), try day(2026, 3, 4))
    }

    func testEnglishStaysTheDefaultSoExistingVaultsKeepTheirNames() throws {
        let settings = DailyNoteSettings(format: germanDailyFormat)
        XCTAssertEqual(try settings.notePath(for: day(2026, 11, 1), timeZone: zurich).rawValue, "Sunday, 01. November 2026.md")
        XCTAssertNil(settings.date(ofNoteAt: try VaultPath("Sonntag, 01. November 2026.md"), timeZone: zurich), "English alone reads no German.")
        XCTAssertEqual(MomentDateLanguage.named(nil), .english)
        XCTAssertEqual(MomentDateLanguage.named("not a language"), .english)
    }

    func testNotesNamedBeforeTheLanguageChangedAreStillRead() throws {
        let settings = DailyNoteSettings(format: germanDailyFormat)
        let languages = [german, MomentDateLanguage.named("fr"), .english]
        let reader = try XCTUnwrap(MomentDateReader(format: settings.format, languages: languages))
        XCTAssertEqual(settings.date(ofNoteAt: try VaultPath("Sonntag, 01. November 2026.md"), using: reader, timeZone: zurich), try day(2026, 11, 1))
        XCTAssertEqual(settings.date(ofNoteAt: try VaultPath("Sunday, 01. November 2026.md"), using: reader, timeZone: zurich), try day(2026, 11, 1))
        XCTAssertEqual(settings.date(ofNoteAt: try VaultPath("dimanche, 01. novembre 2026.md"), using: reader, timeZone: zurich), try day(2026, 11, 1))
    }

    func testAWeekdayOrDayThatDoesNotFitIsNoDay() throws {
        XCTAssertNil(MomentDateFormat.date(from: "Montag, 01. November 2026", format: germanDailyFormat, timeZone: zurich, languages: [german]))
        XCTAssertNil(MomentDateFormat.date(from: "Donnerstag, 31. April 2026", format: germanDailyFormat, timeZone: zurich, languages: [german]))
        XCTAssertNil(MomentDateFormat.date(from: "Sonntag, 1. November 2026", format: germanDailyFormat, timeZone: zurich, languages: [german]), "DD writes two digits.")
    }

    /// Foundation's `Sept.` against Moment's `Sep.`: Graphite writes the first, and a note Obsidian wrote is read all the same.
    func testBothWritersAbbreviationsAreRead() throws {
        let format = "ddd, DD. MMM YYYY"
        let september = try day(2026, 9, 1)
        XCTAssertEqual(MomentDateFormat.string(from: september, format: format, timeZone: zurich, language: german), "Di., 01. Sept. 2026")
        XCTAssertEqual(MomentDateFormat.date(from: "Di., 01. Sept. 2026", format: format, timeZone: zurich, languages: [german]), september)
        XCTAssertEqual(MomentDateFormat.date(from: "Di., 01. Sep. 2026", format: format, timeZone: zurich, languages: [german]), september, "As Moment writes it.")
        let spanish = MomentDateLanguage.named("es")
        XCTAssertEqual(MomentDateFormat.date(from: "mar., 01. sep. 2026", format: format, timeZone: zurich, languages: [spanish]), september, "Moment's, where the system has `sept`.")
    }

    /// Each expected text is what the Moment inside Obsidian 1.15 wrote, `moment.locale(code)` with Obsidian's mapping
    /// of codes, on those days. The languages listed have stable names; every language was compared once by hand
    /// (`Docs/Bug-hunt-todo.md`, HUNT-154).
    func testFullNamesOrdinalsAndDigitsAreMoments() throws {
        let format = "dddd, Do MMMM YYYY"
        let expectedByLanguage: [(code: String, firstOfNovember: String, thirdOfMay: String)] = [
            ("de", "Sonntag, 1. November 2026", "Sonntag, 3. Mai 2026"),
            ("fr", "dimanche, 1er novembre 2026", "dimanche, 3 mai 2026"),
            ("es", "domingo, 1º noviembre 2026", "domingo, 3º mayo 2026"),
            ("it", "domenica, 1º novembre 2026", "domenica, 3º maggio 2026"),
            ("nl", "zondag, 1ste november 2026", "zondag, 3de mei 2026"),
            ("sv", "söndag, 1:a november 2026", "söndag, 3:e maj 2026"),
            ("ru", "воскресенье, 1-го ноября 2026", "воскресенье, 3-го мая 2026"),
            ("pl", "niedziela, 1. listopad 2026", "niedziela, 3. maj 2026"),
            ("ja", "日曜日, 1日 11月 2026", "日曜日, 3日 5月 2026"),
            ("zh", "星期日, 1日 十一月 2026", "星期日, 3日 五月 2026"),
            ("zh-TW", "星期日, 1日 十一月 2026", "星期日, 3日 五月 2026"),
            ("he", "ראשון, 1 נובמבר 2026", "ראשון, 3 מאי 2026"),
            ("ar", "الأحد، ١ نوفمبر ٢٠٢٦", "الأحد، ٣ مايو ٢٠٢٦"),
        ]
        for (code, firstOfNovember, thirdOfMay) in expectedByLanguage {
            let language = MomentDateLanguage.named(code)
            XCTAssertEqual(language.id, code)
            XCTAssertEqual(MomentDateFormat.string(from: try day(2026, 11, 1), format: format, timeZone: zurich, language: language), firstOfNovember, code)
            XCTAssertEqual(MomentDateFormat.string(from: try day(2026, 5, 3), format: format, timeZone: zurich, language: language), thirdOfMay, code)
            XCTAssertEqual(MomentDateFormat.date(from: firstOfNovember, format: format, timeZone: zurich, languages: [language]), try day(2026, 11, 1), code)
        }
    }

    func testAMonthAfterADayTakesItsInflectedFormOnlyThere() throws {
        let russian = MomentDateLanguage.named("ru")
        let day = try day(2026, 11, 1)
        XCTAssertEqual(MomentDateFormat.string(from: day, format: "D MMMM YYYY", timeZone: zurich, language: russian), "1 ноября 2026")
        XCTAssertEqual(MomentDateFormat.string(from: day, format: "MMMM YYYY, DD", timeZone: zurich, language: russian), "ноябрь 2026, 01")
        XCTAssertEqual(MomentDateFormat.date(from: "ноябрь 2026, 01", format: "MMMM YYYY, DD", timeZone: zurich, languages: [russian]), day)
    }

    /// A language's own digits are in the file name too, even in the default format.
    func testADateInALanguageWithItsOwnDigitsIsWrittenAndReadInThem() throws {
        let arabic = MomentDateLanguage.named("ar")
        let settings = DailyNoteSettings()
        let path = try settings.notePath(for: day(2026, 11, 1), timeZone: zurich, language: arabic)
        XCTAssertEqual(path.rawValue, "٢٠٢٦-١١-٠١.md")
        XCTAssertEqual(settings.date(ofNoteAt: path, timeZone: zurich, languages: [arabic]), try day(2026, 11, 1))
        XCTAssertEqual(settings.date(ofNoteAt: try VaultPath("2026-11-01.md"), timeZone: zurich, languages: [arabic, .english]), try day(2026, 11, 1))
    }

    /// Weeks are the language's: in German they start on Monday and week 1 holds January 4, so December 28, 2026 is in week 53.
    func testWeekNumbersFollowTheLanguage() throws {
        let date = try day(2026, 12, 28)
        XCTAssertEqual(MomentDateFormat.string(from: date, format: "gggg-[W]ww", timeZone: zurich, language: german), "2026-W53")
        XCTAssertEqual(MomentDateFormat.string(from: date, format: "gggg-[W]ww", timeZone: zurich), "2027-W01", "English: from Sunday, and week 1 holds January 1.")
    }

    func testATemplateDateIsInTheLanguage() throws {
        let rendered = TemplateRenderer.render("{{date:dddd}} {{date}}", title: "", date: try day(2026, 11, 1), dateFormat: "D. MMMM", timeFormat: "HH:mm", timeZone: zurich, language: german)
        XCTAssertEqual(rendered, "Sonntag 1. November")
    }

    /// The language is the device's: nothing about it reaches the vault's file (OB-07).
    func testTheLanguageIsNotInTheVaultsSettingsFile() throws {
        let data = try DailyNoteSettings(format: germanDailyFormat).mergedConfigurationData(existingData: Data(#"{"other": 1}"#.utf8))
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["autorun", "folder", "format", "other", "template"])
    }

    // MARK: Names that could be read two ways

    /// `mar` starts `marraskuu` in Finnish, and was taken for November before English's March was looked at.
    func testAnEnglishMonthIsNotTakenForTheFinnishMonthItBegins() throws {
        let format = "MMM DD YYYY"
        let languages = [MomentDateLanguage.named("fi"), .english]
        XCTAssertEqual(MomentDateFormat.date(from: "Mar 15 2024", format: format, timeZone: zurich, languages: languages), try day(2024, 3, 15))
    }

    /// As Moment writes it, the name is read, in the language's own list and beside English.
    func testMomentsAbbreviationsAreReadWithoutGuessing() throws {
        let format = "MMM DD YYYY"
        let expected: [(code: String, name: String, month: Int)] = [
            ("fi", "marras", 11), ("fi", "maalis", 3), ("hu", "szept.", 9), ("ru", "мар.", 3), ("ru", "март", 3), ("es", "sep.", 9), ("de", "Sep.", 9), ("tr", "Eki", 10), ("ja", "11月", 11),
        ]
        for (code, name, month) in expected {
            let languages = [MomentDateLanguage.named(code), .english]
            XCTAssertEqual(MomentDateFormat.date(from: "\(name) 15 2024", format: format, timeZone: zurich, languages: languages), try day(2024, month, 15), "\(code) \(name)")
        }
    }

    /// Every name of every month in all 46 languages, Foundation's and Moment's, in a reading list with any
    /// other language: it reads as that month or, when another name of the list is written the same, as no day.
    func testNoMonthNameIsReadAsAnotherMonthInAnyPairOfLanguages() throws {
        let languages = MomentDateLanguage.choices.map { choice in MomentDateLanguage.named(choice.id) }
        XCTAssertEqual(languages.count, 47)
        func names(of language: MomentDateLanguage, token: String) -> [[String]] {
            if token == "MMMM" { return [language.months, language.monthsAfterDay] + language.otherMonthForms }
            return [language.abbreviatedMonths] + language.otherAbbreviatedMonthForms
        }
        for token in ["MMM", "MMMM"] {
            let format = "\(token) DD YYYY"
            for first in languages {
                for second in languages {
                    let reader = try XCTUnwrap(MomentDateReader(format: format, languages: [first, second]))
                    for forms in names(of: second, token: token) {
                        for (monthIndex, name) in forms.enumerated() where !name.isEmpty {
                            guard let date = reader.date(from: "\(second.inOwnDigits(name)) \(second.inOwnDigits("15 2024"))", timeZone: zurich) else { continue }
                            XCTAssertEqual(date, try day(2024, monthIndex + 1, 15), "\(first.id), \(second.id): \(name) in \(token)")
                        }
                    }
                }
            }
        }
    }

    /// Alone, a language reads the months it writes. The names it writes for two months are not guessed at.
    func testEachLanguageReadsWhatItWrites() throws {
        for code in MomentDateLanguage.choices.map(\.id) {
            let language = MomentDateLanguage.named(code)
            for format in ["DD MMMM YYYY", "MMMM DD YYYY", "DD MMM YYYY", "dddd, DD. MMMM YYYY", "ddd DD MMMM YYYY", "dd DD MMMM YYYY"] {
                let reader = try XCTUnwrap(MomentDateReader(format: format, languages: [language, .english]))
                for month in 1...12 {
                    let date = try day(2026, month, 15)
                    let written = MomentDateFormat.string(from: date, format: format, timeZone: zurich, language: language)
                    XCTAssertEqual(reader.date(from: written, timeZone: zurich), date, "\(code) \(format): \(written)")
                }
            }
        }
    }

    // MARK: Weekdays

    /// Any word took the place of a weekday once the list held a language other than English.
    func testAnOrdinaryNoteIsNotReadAsADailyNote() {
        for languages in [[MomentDateLanguage.named("de"), .english], [.english, MomentDateLanguage.named("fi")], [MomentDateLanguage.named("ja")]] {
            for format in ["YYYY-MM-DD ddd", "YYYY-MM-DD dd"] {
                let reader = MomentDateReader(format: format, languages: languages)
                XCTAssertNil(reader?.date(from: "2026-11-02 Review", timeZone: zurich), format)
                XCTAssertNil(reader?.date(from: "2026-11-02 Plan", timeZone: zurich), format)
            }
        }
    }

    /// November 2, 2026 is a Monday. The weekday in each is what Moment writes, read from Obsidian 1.15.
    func testAWeekdayOfMomentsIsReadThoughFoundationWritesAnother() throws {
        let monday = try day(2026, 11, 2)
        let expected: [(code: String, ddd: String, dd: String)] = [
            ("hu", "hét", "h"), ("ar", "إثنين", "ن"), ("tr", "Pzt", "Pt"), ("fi", "ma", "ma"), ("ja", "月", "月"), ("th", "จันทร์", "จ."), ("de", "Mo.", "Mo"),
            ("pl", "pon", "Pn"), ("pt", "Seg", "2ª"), ("lv", "P", "P"), ("zh", "周一", "一"), ("vi", "T2", "T2"), ("id", "Sen", "Sn"), ("km", "ច", "ច"),
        ]
        for (code, ddd, dd) in expected {
            let languages = [MomentDateLanguage.named(code), .english]
            XCTAssertEqual(MomentDateFormat.date(from: "2026-11-02 \(ddd)", format: "YYYY-MM-DD ddd", timeZone: zurich, languages: languages), monday, "\(code) \(ddd)")
            XCTAssertEqual(MomentDateFormat.date(from: "2026-11-02 \(dd)", format: "YYYY-MM-DD dd", timeZone: zurich, languages: languages), monday, "\(code) \(dd)")
        }
        let german = [MomentDateLanguage.named("de"), .english]
        XCTAssertNil(MomentDateFormat.date(from: "2026-11-02 Di.", format: "YYYY-MM-DD ddd", timeZone: zurich, languages: german), "Tuesday's name on a Monday names no day.")
        XCTAssertEqual(MomentDateFormat.date(from: "2026-11-02 Mon", format: "YYYY-MM-DD ddd", timeZone: zurich, languages: german), monday)
    }

    func testLanguagesOfferedAreObsidiansWithEnglishFirst() {
        let codes = MomentDateLanguage.choices.map(\.id)
        XCTAssertEqual(codes.first, "en")
        XCTAssertEqual(Set(codes).count, codes.count)
        for code in ["de", "fr", "es", "it", "ja", "ru", "zh", "zh-TW", "pt-BR", "ar", "no"] { XCTAssertTrue(codes.contains(code), code) }
        for code in ["am", "kab", "sa"] { XCTAssertFalse(codes.contains(code), "Obsidian's Moment has no \(code), so it writes English in it.") }
    }
}
