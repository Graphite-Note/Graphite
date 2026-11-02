/**
 * File: MomentDateLanguageDefinition.swift
 * ----------------------------------------
 * Layer: Core
 * Description: What Moment does in each language of Obsidian that Foundation's month and weekday names do not tell.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

/// One language of Obsidian's Language setting, as the Moment Obsidian ships has it (Moment 2.30.1, MIT, read from
/// Obsidian 1.15). Every full name not listed here is the same in Foundation on macOS 27. Listed names are Moment's.
struct MomentDateLanguageDefinition: Sendable {
    /// Obsidian's code for the language.
    let code: String
    /// Foundation's identifier, which has the same script as Moment's locale: Serbian in Latin, Uzbek in Cyrillic.
    let systemIdentifier: String
    let firstWeekday: Int
    let minimumDaysInFirstWeek: Int
    /// How `Do` writes a number, `%d` being its digits.
    let ordinal: String
    let ordinalExceptionsByNumber: [Int: String]
    /// The digits zero to nine, for a language whose Moment writes its own.
    let digits: String?
    let comma: Character?
    let months: [String]?
    let monthsAfterDay: [String]?
    let weekdays: [String]?

    init(code: String, systemIdentifier: String, firstWeekday: Int, minimumDaysInFirstWeek: Int, ordinal: String, ordinalExceptions: [String: [Int]] = [:],
         digits: String? = nil, comma: Character? = nil, months: [String]? = nil, monthsAfterDay: [String]? = nil, weekdays: [String]? = nil) {
        self.code = code
        self.systemIdentifier = systemIdentifier
        self.firstWeekday = firstWeekday
        self.minimumDaysInFirstWeek = minimumDaysInFirstWeek
        self.ordinal = ordinal
        var exceptionsByNumber: [Int: String] = [:]
        for (template, numbers) in ordinalExceptions { for number in numbers { exceptionsByNumber[number] = template } }
        ordinalExceptionsByNumber = exceptionsByNumber
        self.digits = digits
        self.comma = comma
        self.months = months
        self.monthsAfterDay = monthsAfterDay
        self.weekdays = weekdays
    }

    static let all: [MomentDateLanguageDefinition] = [
        MomentDateLanguageDefinition(code: "ar", systemIdentifier: "ar", firstWeekday: 7, minimumDaysInFirstWeek: 1, ordinal: "%d", digits: "٠١٢٣٤٥٦٧٨٩", comma: "،",
            weekdays: ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]),
        MomentDateLanguageDefinition(code: "be", systemIdentifier: "be", firstWeekday: 2, minimumDaysInFirstWeek: 1, ordinal: "%d-га",
            months: ["студзень", "люты", "сакавік", "красавік", "травень", "чэрвень", "ліпень", "жнівень", "верасень", "кастрычнік", "лістапад", "снежань"],
            monthsAfterDay: ["студзеня", "лютага", "сакавіка", "красавіка", "траўня", "чэрвеня", "ліпеня", "жніўня", "верасня", "кастрычніка", "лістапада", "снежня"]),
        MomentDateLanguageDefinition(code: "bg", systemIdentifier: "bg", firstWeekday: 2, minimumDaysInFirstWeek: 1, ordinal: "%d-ти", ordinalExceptions: ["%d-ви": [1,21,31],"%d-ри": [2,22],"%d-ми": [7,8,27,28]]),
        MomentDateLanguageDefinition(code: "bn", systemIdentifier: "bn", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%d", digits: "০১২৩৪৫৬৭৮৯",
            months: ["জানুয়ারি", "ফেব্রুয়ারি", "মার্চ", "এপ্রিল", "মে", "জুন", "জুলাই", "আগস্ট", "সেপ্টেম্বর", "অক্টোবর", "নভেম্বর", "ডিসেম্বর"],
            monthsAfterDay: ["জানুয়ারি", "ফেব্রুয়ারি", "মার্চ", "এপ্রিল", "মে", "জুন", "জুলাই", "আগস্ট", "সেপ্টেম্বর", "অক্টোবর", "নভেম্বর", "ডিসেম্বর"]),
        MomentDateLanguageDefinition(code: "ca", systemIdentifier: "ca", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%dè", ordinalExceptions: ["%dr": [1,3],"%dn": [2],"%dt": [4]],
            monthsAfterDay: ["de gener", "de febrer", "de març", "d'abril", "de maig", "de juny", "de juliol", "d'agost", "de setembre", "d'octubre", "de novembre", "de desembre"]),
        MomentDateLanguageDefinition(code: "cs", systemIdentifier: "cs", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d."),
        MomentDateLanguageDefinition(code: "da", systemIdentifier: "da", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d."),
        MomentDateLanguageDefinition(code: "de", systemIdentifier: "de", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d."),
        MomentDateLanguageDefinition(code: "el", systemIdentifier: "el", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%dη"),
        MomentDateLanguageDefinition(code: "es", systemIdentifier: "es", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%dº"),
        MomentDateLanguageDefinition(code: "fa", systemIdentifier: "fa", firstWeekday: 7, minimumDaysInFirstWeek: 1, ordinal: "%dم", digits: "۰۱۲۳۴۵۶۷۸۹", comma: "،",
            monthsAfterDay: ["ژانویه", "فوریه", "مارس", "آوریل", "مه", "ژوئن", "ژوئیه", "اوت", "سپتامبر", "اکتبر", "نوامبر", "دسامبر"],
            weekdays: ["یک\u{200C}شنبه", "دوشنبه", "سه\u{200C}شنبه", "چهارشنبه", "پنج\u{200C}شنبه", "جمعه", "شنبه"]),
        MomentDateLanguageDefinition(code: "fi", systemIdentifier: "fi", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d.",
            monthsAfterDay: ["tammikuu", "helmikuu", "maaliskuu", "huhtikuu", "toukokuu", "kesäkuu", "heinäkuu", "elokuu", "syyskuu", "lokakuu", "marraskuu", "joulukuu"]),
        MomentDateLanguageDefinition(code: "fr", systemIdentifier: "fr", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d", ordinalExceptions: ["%der": [1]]),
        MomentDateLanguageDefinition(code: "ga", systemIdentifier: "ga", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%dmh", ordinalExceptions: ["%dd": [1],"%dna": [2,12,22]]),
        MomentDateLanguageDefinition(code: "gl", systemIdentifier: "gl", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%dº"),
        MomentDateLanguageDefinition(code: "he", systemIdentifier: "he", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%d",
            weekdays: ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"]),
        MomentDateLanguageDefinition(code: "hu", systemIdentifier: "hu", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d."),
        MomentDateLanguageDefinition(code: "id", systemIdentifier: "id", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%d"),
        MomentDateLanguageDefinition(code: "it", systemIdentifier: "it", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%dº"),
        MomentDateLanguageDefinition(code: "ja", systemIdentifier: "ja", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%d日"),
        MomentDateLanguageDefinition(code: "ka", systemIdentifier: "ka", firstWeekday: 2, minimumDaysInFirstWeek: 1, ordinal: "მე-%d", ordinalExceptions: ["%d-ლი": [1],"%d-ე": [21,22,23,24,25,26,27,28,29,30,31]]),
        MomentDateLanguageDefinition(code: "km", systemIdentifier: "km", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "ទី%d", digits: "០១២៣៤៥៦៧៨៩",
            weekdays: ["អាទិត្យ", "ច័ន្ទ", "អង្គារ", "ពុធ", "ព្រហស្បតិ៍", "សុក្រ", "សៅរ៍"]),
        MomentDateLanguageDefinition(code: "ko", systemIdentifier: "ko", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%d일"),
        MomentDateLanguageDefinition(code: "lv", systemIdentifier: "lv", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d.",
            weekdays: ["svētdiena", "pirmdiena", "otrdiena", "trešdiena", "ceturtdiena", "piektdiena", "sestdiena"]),
        MomentDateLanguageDefinition(code: "ms", systemIdentifier: "ms", firstWeekday: 2, minimumDaysInFirstWeek: 1, ordinal: "%d"),
        MomentDateLanguageDefinition(code: "ne", systemIdentifier: "ne", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%d", digits: "०१२३४५६७८९",
            months: ["जनवरी", "फेब्रुवरी", "मार्च", "अप्रिल", "मई", "जुन", "जुलाई", "अगष्ट", "सेप्टेम्बर", "अक्टोबर", "नोभेम्बर", "डिसेम्बर"],
            monthsAfterDay: ["जनवरी", "फेब्रुवरी", "मार्च", "अप्रिल", "मई", "जुन", "जुलाई", "अगष्ट", "सेप्टेम्बर", "अक्टोबर", "नोभेम्बर", "डिसेम्बर"]),
        MomentDateLanguageDefinition(code: "nl", systemIdentifier: "nl", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%dde", ordinalExceptions: ["%dste": [1,8,20,21,22,23,24,25,26,27,28,29,30,31]]),
        MomentDateLanguageDefinition(code: "no", systemIdentifier: "nb", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d."),
        MomentDateLanguageDefinition(code: "pl", systemIdentifier: "pl", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d."),
        MomentDateLanguageDefinition(code: "pt", systemIdentifier: "pt", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%dº",
            weekdays: ["Domingo", "Segunda-feira", "Terça-feira", "Quarta-feira", "Quinta-feira", "Sexta-feira", "Sábado"]),
        MomentDateLanguageDefinition(code: "pt-BR", systemIdentifier: "pt-BR", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%dº"),
        MomentDateLanguageDefinition(code: "ro", systemIdentifier: "ro", firstWeekday: 2, minimumDaysInFirstWeek: 1, ordinal: "%d"),
        MomentDateLanguageDefinition(code: "ru", systemIdentifier: "ru", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d-го"),
        MomentDateLanguageDefinition(code: "si", systemIdentifier: "si", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%d වැනි",
            months: ["ජනවාරි", "පෙබරවාරි", "මාර්තු", "අප්\u{200D}රේල්", "මැයි", "ජූනි", "ජූලි", "අගෝස්තු", "සැප්තැම්බර්", "ඔක්තෝබර්", "නොවැම්බර්", "දෙසැම්බර්"],
            monthsAfterDay: ["ජනවාරි", "පෙබරවාරි", "මාර්තු", "අප්\u{200D}රේල්", "මැයි", "ජූනි", "ජූලි", "අගෝස්තු", "සැප්තැම්බර්", "ඔක්තෝබර්", "නොවැම්බර්", "දෙසැම්බර්"]),
        MomentDateLanguageDefinition(code: "sk", systemIdentifier: "sk", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d.",
            monthsAfterDay: ["január", "február", "marec", "apríl", "máj", "jún", "júl", "august", "september", "október", "november", "december"]),
        MomentDateLanguageDefinition(code: "sq", systemIdentifier: "sq", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d.",
            months: ["Janar", "Shkurt", "Mars", "Prill", "Maj", "Qershor", "Korrik", "Gusht", "Shtator", "Tetor", "Nëntor", "Dhjetor"],
            monthsAfterDay: ["Janar", "Shkurt", "Mars", "Prill", "Maj", "Qershor", "Korrik", "Gusht", "Shtator", "Tetor", "Nëntor", "Dhjetor"],
            weekdays: ["E Diel", "E Hënë", "E Martë", "E Mërkurë", "E Enjte", "E Premte", "E Shtunë"]),
        MomentDateLanguageDefinition(code: "sr", systemIdentifier: "sr-Latn", firstWeekday: 2, minimumDaysInFirstWeek: 1, ordinal: "%d."),
        MomentDateLanguageDefinition(code: "sv", systemIdentifier: "sv", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d:e", ordinalExceptions: ["%d:a": [1,2,21,22,31]]),
        MomentDateLanguageDefinition(code: "ta", systemIdentifier: "ta", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%dவது", digits: "௦௧௨௩௪௫௬௭௮௯",
            months: ["ஜனவரி", "பிப்ரவரி", "மார்ச்", "ஏப்ரல்", "மே", "ஜூன்", "ஜூலை", "ஆகஸ்ட்", "செப்டெம்பர்", "அக்டோபர்", "நவம்பர்", "டிசம்பர்"],
            monthsAfterDay: ["ஜனவரி", "பிப்ரவரி", "மார்ச்", "ஏப்ரல்", "மே", "ஜூன்", "ஜூலை", "ஆகஸ்ட்", "செப்டெம்பர்", "அக்டோபர்", "நவம்பர்", "டிசம்பர்"],
            weekdays: ["ஞாயிற்றுக்கிழமை", "திங்கட்கிழமை", "செவ்வாய்கிழமை", "புதன்கிழமை", "வியாழக்கிழமை", "வெள்ளிக்கிழமை", "சனிக்கிழமை"]),
        MomentDateLanguageDefinition(code: "th", systemIdentifier: "th", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%d",
            weekdays: ["อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัสบดี", "ศุกร์", "เสาร์"]),
        MomentDateLanguageDefinition(code: "tr", systemIdentifier: "tr", firstWeekday: 2, minimumDaysInFirstWeek: 1, ordinal: "%d"),
        MomentDateLanguageDefinition(code: "uk", systemIdentifier: "uk", firstWeekday: 2, minimumDaysInFirstWeek: 1, ordinal: "%d-го",
            weekdays: ["неділя", "понеділок", "вівторок", "середа", "четвер", "п’ятниця", "субота"]),
        MomentDateLanguageDefinition(code: "uz", systemIdentifier: "uz-Cyrl", firstWeekday: 2, minimumDaysInFirstWeek: 1, ordinal: "%d",
            weekdays: ["Якшанба", "Душанба", "Сешанба", "Чоршанба", "Пайшанба", "Жума", "Шанба"]),
        MomentDateLanguageDefinition(code: "vi", systemIdentifier: "vi", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d",
            months: ["tháng 1", "tháng 2", "tháng 3", "tháng 4", "tháng 5", "tháng 6", "tháng 7", "tháng 8", "tháng 9", "tháng 10", "tháng 11", "tháng 12"],
            weekdays: ["chủ nhật", "thứ hai", "thứ ba", "thứ tư", "thứ năm", "thứ sáu", "thứ bảy"]),
        MomentDateLanguageDefinition(code: "zh", systemIdentifier: "zh-Hans", firstWeekday: 2, minimumDaysInFirstWeek: 4, ordinal: "%d日"),
        MomentDateLanguageDefinition(code: "zh-TW", systemIdentifier: "zh-Hant", firstWeekday: 1, minimumDaysInFirstWeek: 1, ordinal: "%d日",
            months: ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"],
            monthsAfterDay: ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]),
    ]
}
