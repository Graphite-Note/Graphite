/**
 * File: MomentDateShortNames.swift
 * --------------------------------
 * Layer: Core
 * Description: The short month and weekday names of Moment in each language of Obsidian, so a note Obsidian named is read.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

/// The abbreviated names `MMM`, `ddd` and `dd` as the Moment Obsidian ships writes them (Moment 2.30.1, read from Obsidian
/// 1.15), each list joined by underscores as Moment's own tables are. Graphite writes Foundation's forms and reads both.
struct MomentDateShortNames: Sendable {
    let months: [String]
    /// Where `D MMM` takes other forms than `MMM`.
    let monthsAfterDay: [String]
    /// From Sunday.
    let weekdays: [String]
    /// From Sunday.
    let shortestWeekdays: [String]

    private init(months: String, monthsAfterDay: String = "", weekdays: String, shortestWeekdays: String) {
        self.months = Self.names(months)
        self.monthsAfterDay = Self.names(monthsAfterDay)
        self.weekdays = Self.names(weekdays)
        self.shortestWeekdays = Self.names(shortestWeekdays)
    }

    private static func names(_ joinedNames: String) -> [String] {
        joinedNames.split(separator: "_").map(String.init)
    }

    /// By Obsidian's code for the language.
    static let byLanguage: [String: MomentDateShortNames] = [
        "ar": MomentDateShortNames(months: "يناير_فبراير_مارس_أبريل_مايو_يونيو_يوليو_أغسطس_سبتمبر_أكتوبر_نوفمبر_ديسمبر",
            weekdays: "أحد_إثنين_ثلاثاء_أربعاء_خميس_جمعة_سبت", shortestWeekdays: "ح_ن_ث_ر_خ_ج_س"),
        "be": MomentDateShortNames(months: "студ_лют_сак_крас_трав_чэрв_ліп_жнів_вер_каст_ліст_снеж",
            weekdays: "нд_пн_ат_ср_чц_пт_сб", shortestWeekdays: "нд_пн_ат_ср_чц_пт_сб"),
        "bg": MomentDateShortNames(months: "яну_фев_мар_апр_май_юни_юли_авг_сеп_окт_ное_дек",
            weekdays: "нед_пон_вто_сря_чет_пет_съб", shortestWeekdays: "нд_пн_вт_ср_чт_пт_сб"),
        "bn": MomentDateShortNames(months: "জানু_ফেব্রু_মার্চ_এপ্রিল_মে_জুন_জুলাই_আগস্ট_সেপ্ট_অক্টো_নভে_ডিসে",
            weekdays: "রবি_সোম_মঙ্গল_বুধ_বৃহস্পতি_শুক্র_শনি", shortestWeekdays: "রবি_সোম_মঙ্গল_বুধ_বৃহ_শুক্র_শনি"),
        "ca": MomentDateShortNames(months: "gen._febr._març_abr._maig_juny_jul._ag._set._oct._nov._des.",
            weekdays: "dg._dl._dt._dc._dj._dv._ds.", shortestWeekdays: "dg_dl_dt_dc_dj_dv_ds"),
        "cs": MomentDateShortNames(months: "led_úno_bře_dub_kvě_čvn_čvc_srp_zář_říj_lis_pro",
            weekdays: "ne_po_út_st_čt_pá_so", shortestWeekdays: "ne_po_út_st_čt_pá_so"),
        "da": MomentDateShortNames(months: "jan_feb_mar_apr_maj_jun_jul_aug_sep_okt_nov_dec",
            weekdays: "søn_man_tir_ons_tor_fre_lør", shortestWeekdays: "sø_ma_ti_on_to_fr_lø"),
        "de": MomentDateShortNames(months: "Jan._Feb._März_Apr._Mai_Juni_Juli_Aug._Sep._Okt._Nov._Dez.",
            weekdays: "So._Mo._Di._Mi._Do._Fr._Sa.", shortestWeekdays: "So_Mo_Di_Mi_Do_Fr_Sa"),
        "el": MomentDateShortNames(months: "Ιαν_Φεβ_Μαρ_Απρ_Μαϊ_Ιουν_Ιουλ_Αυγ_Σεπ_Οκτ_Νοε_Δεκ",
            weekdays: "Κυρ_Δευ_Τρι_Τετ_Πεμ_Παρ_Σαβ", shortestWeekdays: "Κυ_Δε_Τρ_Τε_Πε_Πα_Σα"),
        "es": MomentDateShortNames(months: "ene._feb._mar._abr._may._jun._jul._ago._sep._oct._nov._dic.",
            weekdays: "dom._lun._mar._mié._jue._vie._sáb.", shortestWeekdays: "do_lu_ma_mi_ju_vi_sá"),
        "fa": MomentDateShortNames(months: "ژانویه_فوریه_مارس_آوریل_مه_ژوئن_ژوئیه_اوت_سپتامبر_اکتبر_نوامبر_دسامبر",
            weekdays: "یک‌شنبه_دوشنبه_سه‌شنبه_چهارشنبه_پنج‌شنبه_جمعه_شنبه", shortestWeekdays: "ی_د_س_چ_پ_ج_ش"),
        "fi": MomentDateShortNames(months: "tammi_helmi_maalis_huhti_touko_kesä_heinä_elo_syys_loka_marras_joulu",
            weekdays: "su_ma_ti_ke_to_pe_la", shortestWeekdays: "su_ma_ti_ke_to_pe_la"),
        "fr": MomentDateShortNames(months: "janv._févr._mars_avr._mai_juin_juil._août_sept._oct._nov._déc.",
            weekdays: "dim._lun._mar._mer._jeu._ven._sam.", shortestWeekdays: "di_lu_ma_me_je_ve_sa"),
        "ga": MomentDateShortNames(months: "Ean_Feabh_Márt_Aib_Beal_Meith_Iúil_Lún_M.F._D.F._Samh_Noll",
            weekdays: "Domh_Luan_Máirt_Céad_Déar_Aoine_Sath", shortestWeekdays: "Do_Lu_Má_Cé_Dé_A_Sa"),
        "gl": MomentDateShortNames(months: "xan._feb._mar._abr._mai._xuñ._xul._ago._set._out._nov._dec.",
            weekdays: "dom._lun._mar._mér._xov._ven._sáb.", shortestWeekdays: "do_lu_ma_mé_xo_ve_sá"),
        "he": MomentDateShortNames(months: "ינו׳_פבר׳_מרץ_אפר׳_מאי_יוני_יולי_אוג׳_ספט׳_אוק׳_נוב׳_דצמ׳",
            weekdays: "א׳_ב׳_ג׳_ד׳_ה׳_ו׳_ש׳", shortestWeekdays: "א_ב_ג_ד_ה_ו_ש"),
        "hu": MomentDateShortNames(months: "jan._feb._márc._ápr._máj._jún._júl._aug._szept._okt._nov._dec.",
            weekdays: "vas_hét_kedd_sze_csüt_pén_szo", shortestWeekdays: "v_h_k_sze_cs_p_szo"),
        "id": MomentDateShortNames(months: "Jan_Feb_Mar_Apr_Mei_Jun_Jul_Agt_Sep_Okt_Nov_Des",
            weekdays: "Min_Sen_Sel_Rab_Kam_Jum_Sab", shortestWeekdays: "Mg_Sn_Sl_Rb_Km_Jm_Sb"),
        "it": MomentDateShortNames(months: "gen_feb_mar_apr_mag_giu_lug_ago_set_ott_nov_dic",
            weekdays: "dom_lun_mar_mer_gio_ven_sab", shortestWeekdays: "do_lu_ma_me_gi_ve_sa"),
        "ja": MomentDateShortNames(months: "1月_2月_3月_4月_5月_6月_7月_8月_9月_10月_11月_12月",
            weekdays: "日_月_火_水_木_金_土", shortestWeekdays: "日_月_火_水_木_金_土"),
        "ka": MomentDateShortNames(months: "იან_თებ_მარ_აპრ_მაი_ივნ_ივლ_აგვ_სექ_ოქტ_ნოე_დეკ",
            weekdays: "კვი_ორშ_სამ_ოთხ_ხუთ_პარ_შაბ", shortestWeekdays: "კვ_ორ_სა_ოთ_ხუ_პა_შა"),
        "km": MomentDateShortNames(months: "មករា_កុម្ភៈ_មីនា_មេសា_ឧសភា_មិថុនា_កក្កដា_សីហា_កញ្ញា_តុលា_វិច្ឆិកា_ធ្នូ",
            weekdays: "អា_ច_អ_ព_ព្រ_សុ_ស", shortestWeekdays: "អា_ច_អ_ព_ព្រ_សុ_ស"),
        "ko": MomentDateShortNames(months: "1월_2월_3월_4월_5월_6월_7월_8월_9월_10월_11월_12월",
            weekdays: "일_월_화_수_목_금_토", shortestWeekdays: "일_월_화_수_목_금_토"),
        "lv": MomentDateShortNames(months: "jan_feb_mar_apr_mai_jūn_jūl_aug_sep_okt_nov_dec",
            weekdays: "Sv_P_O_T_C_Pk_S", shortestWeekdays: "Sv_P_O_T_C_Pk_S"),
        "ms": MomentDateShortNames(months: "Jan_Feb_Mac_Apr_Mei_Jun_Jul_Ogs_Sep_Okt_Nov_Dis",
            weekdays: "Ahd_Isn_Sel_Rab_Kha_Jum_Sab", shortestWeekdays: "Ah_Is_Sl_Rb_Km_Jm_Sb"),
        "ne": MomentDateShortNames(months: "जन._फेब्रु._मार्च_अप्रि._मई_जुन_जुलाई._अग._सेप्ट._अक्टो._नोभे._डिसे.",
            weekdays: "आइत._सोम._मङ्गल._बुध._बिहि._शुक्र._शनि.", shortestWeekdays: "आ._सो._मं._बु._बि._शु._श."),
        "nl": MomentDateShortNames(months: "jan._feb._mrt._apr._mei_jun._jul._aug._sep._okt._nov._dec.",
            weekdays: "zo._ma._di._wo._do._vr._za.", shortestWeekdays: "zo_ma_di_wo_do_vr_za"),
        "no": MomentDateShortNames(months: "jan._feb._mars_apr._mai_juni_juli_aug._sep._okt._nov._des.",
            weekdays: "sø._ma._ti._on._to._fr._lø.", shortestWeekdays: "sø_ma_ti_on_to_fr_lø"),
        "pl": MomentDateShortNames(months: "sty_lut_mar_kwi_maj_cze_lip_sie_wrz_paź_lis_gru",
            weekdays: "ndz_pon_wt_śr_czw_pt_sob", shortestWeekdays: "Nd_Pn_Wt_Śr_Cz_Pt_So"),
        "pt": MomentDateShortNames(months: "jan_fev_mar_abr_mai_jun_jul_ago_set_out_nov_dez",
            weekdays: "Dom_Seg_Ter_Qua_Qui_Sex_Sáb", shortestWeekdays: "Do_2ª_3ª_4ª_5ª_6ª_Sá"),
        "pt-BR": MomentDateShortNames(months: "jan_fev_mar_abr_mai_jun_jul_ago_set_out_nov_dez",
            weekdays: "dom_seg_ter_qua_qui_sex_sáb", shortestWeekdays: "do_2ª_3ª_4ª_5ª_6ª_sá"),
        "ro": MomentDateShortNames(months: "ian._feb._mart._apr._mai_iun._iul._aug._sept._oct._nov._dec.",
            weekdays: "Dum_Lun_Mar_Mie_Joi_Vin_Sâm", shortestWeekdays: "Du_Lu_Ma_Mi_Jo_Vi_Sâ"),
        "ru": MomentDateShortNames(months: "янв._февр._март_апр._май_июнь_июль_авг._сент._окт._нояб._дек.",
            monthsAfterDay: "янв._февр._мар._апр._мая_июня_июля_авг._сент._окт._нояб._дек.",
            weekdays: "вс_пн_вт_ср_чт_пт_сб", shortestWeekdays: "вс_пн_вт_ср_чт_пт_сб"),
        "si": MomentDateShortNames(months: "ජන_පෙබ_මාර්_අප්_මැයි_ජූනි_ජූලි_අගෝ_සැප්_ඔක්_නොවැ_දෙසැ",
            weekdays: "ඉරි_සඳු_අඟ_බදා_බ්‍රහ_සිකු_සෙන", shortestWeekdays: "ඉ_ස_අ_බ_බ්‍ර_සි_සෙ"),
        "sk": MomentDateShortNames(months: "jan_feb_mar_apr_máj_jún_júl_aug_sep_okt_nov_dec",
            weekdays: "ne_po_ut_st_št_pi_so", shortestWeekdays: "ne_po_ut_st_št_pi_so"),
        "sq": MomentDateShortNames(months: "Jan_Shk_Mar_Pri_Maj_Qer_Kor_Gus_Sht_Tet_Nën_Dhj",
            weekdays: "Die_Hën_Mar_Mër_Enj_Pre_Sht", shortestWeekdays: "D_H_Ma_Më_E_P_Sh"),
        "sr": MomentDateShortNames(months: "jan._feb._mar._apr._maj_jun_jul_avg._sep._okt._nov._dec.",
            weekdays: "ned._pon._uto._sre._čet._pet._sub.", shortestWeekdays: "ne_po_ut_sr_če_pe_su"),
        "sv": MomentDateShortNames(months: "jan_feb_mar_apr_maj_jun_jul_aug_sep_okt_nov_dec",
            weekdays: "sön_mån_tis_ons_tor_fre_lör", shortestWeekdays: "sö_må_ti_on_to_fr_lö"),
        "ta": MomentDateShortNames(months: "ஜனவரி_பிப்ரவரி_மார்ச்_ஏப்ரல்_மே_ஜூன்_ஜூலை_ஆகஸ்ட்_செப்டெம்பர்_அக்டோபர்_நவம்பர்_டிசம்பர்",
            weekdays: "ஞாயிறு_திங்கள்_செவ்வாய்_புதன்_வியாழன்_வெள்ளி_சனி", shortestWeekdays: "ஞா_தி_செ_பு_வி_வெ_ச"),
        "th": MomentDateShortNames(months: "ม.ค._ก.พ._มี.ค._เม.ย._พ.ค._มิ.ย._ก.ค._ส.ค._ก.ย._ต.ค._พ.ย._ธ.ค.",
            weekdays: "อาทิตย์_จันทร์_อังคาร_พุธ_พฤหัส_ศุกร์_เสาร์", shortestWeekdays: "อา._จ._อ._พ._พฤ._ศ._ส."),
        "tr": MomentDateShortNames(months: "Oca_Şub_Mar_Nis_May_Haz_Tem_Ağu_Eyl_Eki_Kas_Ara",
            weekdays: "Paz_Pzt_Sal_Çar_Per_Cum_Cmt", shortestWeekdays: "Pz_Pt_Sa_Ça_Pe_Cu_Ct"),
        "uk": MomentDateShortNames(months: "січ_лют_бер_квіт_трав_черв_лип_серп_вер_жовт_лист_груд",
            weekdays: "нд_пн_вт_ср_чт_пт_сб", shortestWeekdays: "нд_пн_вт_ср_чт_пт_сб"),
        "uz": MomentDateShortNames(months: "янв_фев_мар_апр_май_июн_июл_авг_сен_окт_ноя_дек",
            weekdays: "Якш_Душ_Сеш_Чор_Пай_Жум_Шан", shortestWeekdays: "Як_Ду_Се_Чо_Па_Жу_Ша"),
        "vi": MomentDateShortNames(months: "Thg 01_Thg 02_Thg 03_Thg 04_Thg 05_Thg 06_Thg 07_Thg 08_Thg 09_Thg 10_Thg 11_Thg 12",
            weekdays: "CN_T2_T3_T4_T5_T6_T7", shortestWeekdays: "CN_T2_T3_T4_T5_T6_T7"),
        "zh": MomentDateShortNames(months: "1月_2月_3月_4月_5月_6月_7月_8月_9月_10月_11月_12月",
            weekdays: "周日_周一_周二_周三_周四_周五_周六", shortestWeekdays: "日_一_二_三_四_五_六"),
        "zh-TW": MomentDateShortNames(months: "1月_2月_3月_4月_5月_6月_7月_8月_9月_10月_11月_12月",
            weekdays: "週日_週一_週二_週三_週四_週五_週六", shortestWeekdays: "日_一_二_三_四_五_六"),
    ]
}
