import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// The colors a diagram is painted in: the note's background and text, and between them the shapes' fill and
/// outline, the groups' boxes and their titles where Pele's own colors put them (5.4 %, 52 %, 11.2 % and 64.7 % of the
/// way from its white page to its #1f1f1f text). They are SwiftUI colors, so a change of appearance or theme paints
/// again without making anything else.
struct ReadingDiagramColors {
    static let surfaceShare = 0.054
    static let borderShare = 0.52
    static let alternateSurfaceShare = 0.112
    static let mutedShare = 0.647

    let background: Color
    let foreground: Color
    /// Lines, edges and their arrowheads: the text color unless a theme sets `--pele-line`.
    let line: Color
    let surface: Color
    let border: Color
    /// Pele's series colors, which a chart's slices take in turn, the same on a light page and a dark one, each replaced
    /// by the theme's `--pele-series-1` to `--pele-series-8` where it sets them.
    let series: [Color]
    /// What a chart marks, a Gantt chart's tasks and today's line: the vault theme's accent, else the app's.
    let accent: Color
    /// A Gantt chart's critical tasks: Pele's critical color.
    let critical: Color
    /// What is drawn quieter, such as a timeline's periods before its first section and a Gantt chart's dates: the vault
    /// theme's muted text, else Pele's #6e6e6e, where it is between its white page and its text.
    let muted: Color
    /// A second surface, a Gantt chart's finished tasks and excluded days and the inside of a group's box (painted at
    /// half its opacity): where Pele's is between its page and text.
    let alternateSurface: Color

    init(background: Color, foreground: Color, accent: Color = .accentColor, muted: Color? = nil,
         overrides: DiagramColorOverrides = DiagramColorOverrides()) {
        self.background = background
        self.foreground = foreground
        line = overrides.line ?? foreground
        surface = overrides.surface ?? background.mix(with: foreground, by: Self.surfaceShare, in: .device)
        border = overrides.border ?? background.mix(with: foreground, by: Self.borderShare, in: .device)
        series = DiagramPalette.peleSeries.indices.map { index in
            (index < overrides.series.count ? overrides.series[index] : nil) ?? Color(cgColor: DiagramPalette.peleSeries[index])
        }
        self.accent = accent
        critical = overrides.critical ?? Color(cgColor: DiagramPalette.peleCritical)
        self.muted = muted ?? background.mix(with: foreground, by: Self.mutedShare, in: .device)
        alternateSurface = overrides.alternateSurface ?? background.mix(with: foreground, by: Self.alternateSurfaceShare, in: .device)
    }

    /// The vault theme's background, text, accent and muted text where it sets them, else the system's; and over them the
    /// colors the theme or a snippet gives diagrams with Pele's variables (`--pele-bg` …) in the appearance shown.
    init(theme: NoteThemeStyle?, colorScheme: ColorScheme) {
        let modeTokens = colorScheme == .dark ? theme?.tokens.dark : theme?.tokens.light
        let pele = DiagramColorOverrides(variables: modeTokens?.diagramColors ?? [:])
        self.init(background: pele.background ?? Color(theme?.background ?? NoteThemeStyle.systemBackground),
                  foreground: pele.foreground ?? Color(theme?.textNormal ?? NoteThemeStyle.systemLabel),
                  accent: pele.accent ?? theme?.accent.map { accent in Color(accent) } ?? .accentColor,
                  muted: pele.muted ?? theme?.textMuted.map { muted in Color(muted) }, overrides: pele)
    }

    /// The color of the `index`th series, the colors taken in turn.
    func seriesColor(_ index: Int) -> Color {
        series[index % series.count]
    }
}

/// The colors an Obsidian theme or snippet gives diagrams with Pele's variables in one appearance, by role; nil for each
/// it leaves alone. Taken as written, as Obsidian draws them: the author chose them for the diagram.
struct DiagramColorOverrides {
    var background: Color?
    var foreground: Color?
    var line: Color?
    var surface: Color?
    var border: Color?
    var accent: Color?
    var critical: Color?
    var muted: Color?
    var alternateSurface: Color?
    /// `--pele-series-1` to `--pele-series-8`, each nil where unset.
    var series: [Color?] = []

    init() {}

    /// The overrides the variables give, by their names after `--pele-` (`ThemeModeTokens.diagramColorVariableNames`).
    init(variables: [String: ThemeColor]) {
        guard !variables.isEmpty else { return }
        func color(_ name: String) -> Color? {
            variables[name].map { color in Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha) }
        }
        background = color("bg")
        foreground = color("fg")
        line = color("line")
        surface = color("surface")
        border = color("border")
        accent = color("accent")
        critical = color("critical")
        muted = color("muted")
        alternateSurface = color("surface-alt")
        series = (1...DiagramPalette.peleSeries.count).map { series in color("series-\(series)") }
    }
}
