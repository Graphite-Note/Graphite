/**
 * File: ReadingDiagramScenePainting.swift
 * ---------------------------------------
 * Layer: UI
 * Description: Paints any laid-out diagram's scene as SwiftUI shapes and text in the note's colors.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import SwiftUI
import MermaidDiagrams

/// A diagram's scene (`DiagramScene`, whatever its type) painted back to front at its own size: each shape one SwiftUI
/// path filled, stroked, or filled and stroked, each line of text one `Text` at the middle of its line box. The package
/// has merged what is painted alike one after the other into one path already, so a scene paints as few views as it
/// can. Its paints are the palette's roles until here, where they take the note's colors (`ReadingDiagramColors`):
/// a theme or appearance change paints the same scene again. No `Canvas`: a canvas starts a graphics device, which held
/// about 200 MB while a note scrolled, and the shapes and text stay vector in a printed PDF
/// (`Docs/Native-diagrams-todo.md`, decision 5).
struct ReadingDiagramScenePainting: View {
    let scene: DiagramScene
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(scene.items.indices, id: \.self) { index in
                switch scene.items[index] {
                case .shape(let shape): ReadingDiagramSceneShape(shape: shape, sceneSize: scene.size, colors: colors)
                case .text(let text): ReadingDiagramSceneText(text: text, font: text.font(in: scene), color: colors.color(of: text.paint))
                }
            }
        }
        .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
    }
}

/// One shape of a scene, as its painting says. Every shape takes the whole page as its frame, so a gradient's ends,
/// given on the page, are its frame's unit points.
private struct ReadingDiagramSceneShape: View {
    let shape: DiagramSceneShape
    let sceneSize: CGSize
    let colors: ReadingDiagramColors

    var body: some View {
        let path = Path(shape.path)
        switch shape.painting {
        case .fill(let paint):
            path.fill(colors.color(of: paint))
        case .stroke(let paint, let stroke):
            path.stroke(colors.color(of: paint), style: Self.style(of: stroke))
        case .fillAndStroke(let fillPaint, let strokePaint, let stroke):
            path.fill(colors.color(of: fillPaint))
                .overlay { path.stroke(colors.color(of: strokePaint), style: Self.style(of: stroke)) }
        case .gradientFill(let gradient):
            // A linear gradient keeps its end colors past its ends, as the scene's does.
            path.fill(LinearGradient(colors: [colors.color(of: gradient.startPaint), colors.color(of: gradient.endPaint)],
                                     startPoint: unitPoint(gradient.startPoint), endPoint: unitPoint(gradient.endPoint)))
                .opacity(gradient.opacity)
        }
    }

    private func unitPoint(_ point: CGPoint) -> UnitPoint {
        UnitPoint(x: sceneSize.width > 0 ? point.x / sceneSize.width : 0, y: sceneSize.height > 0 ? point.y / sceneSize.height : 0)
    }

    private static func style(of stroke: DiagramStroke) -> StrokeStyle {
        StrokeStyle(lineWidth: stroke.lineWidth, lineCap: stroke.lineCap, lineJoin: stroke.lineJoin, dash: stroke.dashLengths)
    }
}

/// One placed text of a scene: each of its lines centered at the middle of its line box, as Pele's SVG anchors its text
/// and as Graphite's reading view has always set it, in the scene's font at the block's size, bold or italic as the
/// scene says. The package measured the lines in the regular font, so a bold title or class name centered by its own
/// width stays centered, where one started at the measured start, as the package's Core Graphics renderer does, would
/// lean right. A turned text turns each line about its own middle and moves that middle about the block's center,
/// which turns the block as a whole.
private struct ReadingDiagramSceneText: View {
    let text: DiagramSceneText
    let font: DiagramFont
    let color: Color

    var body: some View {
        let lines = text.lines
        let swiftUIFont = Self.swiftUIFont(font, isBold: text.isBold, isItalic: text.isItalic)
        ForEach(lines.indices, id: \.self) { index in
            Text(verbatim: lines[index].text)
                .font(swiftUIFont)
                .foregroundStyle(color)
                .fixedSize()
                .rotationEffect(.radians(text.rotation ?? 0))
                .position(turned(lines[index].center))
        }
    }

    /// `point` turned about the block's center by the text's rotation (clockwise on the page, whose y runs down, as
    /// SwiftUI's rotation is).
    private func turned(_ point: CGPoint) -> CGPoint {
        guard let rotation = text.rotation, rotation != 0 else { return point }
        let center = text.block.center
        let offset = CGPoint(x: point.x - center.x, y: point.y - center.y)
        return CGPoint(x: center.x + offset.x * cos(rotation) - offset.y * sin(rotation),
                       y: center.y + offset.x * sin(rotation) + offset.y * cos(rotation))
    }

    /// The font the text was measured in: the system font, or the installed font by its PostScript name.
    static func swiftUIFont(_ font: DiagramFont, isBold: Bool, isItalic: Bool) -> Font {
        var swiftUIFont = font.postScriptName.map { name in Font.custom(name, fixedSize: font.size) } ?? .system(size: font.size)
        if isBold { swiftUIFont = swiftUIFont.bold() }
        if isItalic { swiftUIFont = swiftUIFont.italic() }
        return swiftUIFont
    }
}

extension ReadingDiagramColors {
    /// The color of a scene's paint: its role's color, a mixture of two roles' colors, or the color the diagram's text
    /// wrote, at the paint's opacity.
    func color(of paint: DiagramPaint) -> Color {
        let resolved: Color = switch paint.source {
        case .role(let role): color(of: role)
        case .mixture(let start, let end, let share): color(of: start).mix(with: color(of: end), by: share, in: .device)
        case .color(let written): Color(written)
        }
        return paint.opacity == 1 ? resolved : resolved.opacity(paint.opacity)
    }

    /// The color of a palette role in the note's colors.
    func color(of role: DiagramPaletteRole) -> Color {
        switch role {
        case .background: background
        case .foreground: foreground
        case .line: line
        case .surface: surface
        case .border: border
        case .accent: accent
        case .critical: critical
        case .muted: muted
        case .alternateSurface: alternateSurface
        case .series(let index): seriesColor(index)
        }
    }
}

extension Color {
    /// The color a diagram's statement wrote.
    init(_ color: DiagramColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
