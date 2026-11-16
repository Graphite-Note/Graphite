/**
 * File: DiagramColumnWidthHostedTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Hosted tests of mermaid diagrams in columns as wide as an iPad's and an iPhone's: a flowchart running across
 *              is turned to run down where it does not fit, composite states are drawn as boxes, and a theme's Pele colors
 *              paint them in the dark appearance, with screenshots.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import MermaidDiagrams
import GraphiteCore
@testable import GraphiteUI

/// The fourteen shapes in a row from left to right were 2,245 points wide and, scaled to an iPad's column, too small to
/// read. In a column too narrow for them the reading view now shows them turned to run down, with tighter gaps, as Pele
/// lays out a flowchart that does not fit its container.
@MainActor
final class DiagramColumnWidthHostedTests: XCTestCase {
    private var window: UIWindow?

    /// An iPad's reading column in landscape, and an iPhone's in portrait.
    private static let iPadColumnWidth: CGFloat = 700
    private static let iPhoneColumnWidth: CGFloat = 360

    private static let fourteenShapes = """
        flowchart LR
          A[Rectangle] --> B(Rounded) --> C([Stadium]) --> D[[Subroutine]] --> E[(Database)] --> F((Circle)) --> G(((Double circle)))
          G --> H>Flag] --> I{Diamond} --> J{{Hexagon}} --> K[/Lean right/] --> L[\\Lean left\\] --> M[/Trapezoid\\] --> N[\\Inverted/]
        """

    private static let compositeStates = """
        stateDiagram-v2
          [*] --> Draft
          Draft --> Review : submit
          state Review {
            [*] --> Screening
            Screening --> Decision
            --
            [*] --> Checks
            Checks --> Signed
          }
          Review --> Published : approved
          Review --> Draft : rejected
          Published --> [*]
        """

    override func setUp() async throws {
        // SwiftUI builds its accessibility elements, by which the diagram is found, only while an assistive technology asks.
        try Self.setAccessibilityRuntimeEnabled(true)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try Self.setAccessibilityRuntimeEnabled(false)
    }

    func testTheFourteenShapesRunDownReadablyInAnIPadColumnAndAnIPhoneColumn() async throws {
        let diagram = ReadingDiagram(source: Self.fourteenShapes, typography: DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17)))
        guard case .flowchart(let flowchart) = diagram, let narrow = flowchart.narrow else { return XCTFail("A flowchart with a narrow layout") }
        for columnWidth in [Self.iPadColumnWidth, Self.iPhoneColumnWidth] {
            let drawn = try await show(diagram, columnWidth: columnWidth)
            XCTAssertEqual(drawn.width, narrow.layout.size.width, accuracy: 1, "Shown at its own size, not scaled down, in a column \(columnWidth) wide.")
            XCTAssertEqual(drawn.height, narrow.layout.size.height, accuracy: 1)
            XCTAssertGreaterThan(drawn.height, drawn.width, "The shapes run down.")
            attachScreenshot(named: "Fourteen shapes in a column \(Int(columnWidth)) points wide")
        }
        let wideColumn = flowchart.layout.size.width + 40
        let drawn = try await show(diagram, columnWidth: wideColumn)
        XCTAssertEqual(drawn.width, flowchart.layout.size.width, accuracy: 1, "A column wide enough shows the row as written.")
    }

    func testCompositeStatesAndTheirRegionsAreDrawnAsBoxesInBothColumns() async throws {
        let diagram = ReadingDiagram(source: Self.compositeStates, typography: DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17)))
        guard case .stateDiagram(let states) = diagram else { return XCTFail("The state diagram is drawn") }
        XCTAssertEqual(states.layout.composites.count, 1)
        XCTAssertEqual(states.layout.regionDividers.count, 1)
        for columnWidth in [Self.iPadColumnWidth, Self.iPhoneColumnWidth] {
            let drawn = try await show(diagram, columnWidth: columnWidth)
            XCTAssertLessThanOrEqual(drawn.width, columnWidth + 0.5)
            attachScreenshot(named: "Composite states in a column \(Int(columnWidth)) points wide")
        }
    }

    /// A vault theme or snippet that sets Pele's variables for the dark appearance paints the diagram in them there:
    /// the pie's only slice in `--pele-series-1`, the flowchart's lines in `--pele-line`.
    func testAThemesPeleColorsPaintDiagramsInTheDarkAppearance() async throws {
        var dark = ThemeModeTokens()
        dark.diagramColors = ["series-1": ThemeColor(red: 1, green: 0.4, blue: 0), "line": ThemeColor(red: 0.2, green: 0.8, blue: 1),
                              "surface": ThemeColor(red: 0.15, green: 0.1, blue: 0.3)]
        let theme = NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "pele-hosted", themeName: "Pele", light: ThemeModeTokens(), dark: dark))
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
        let pie = ReadingDiagram(source: "pie title Only one\n  \"All\" : 1", typography: typography)
        let drawn = try await show(pie, columnWidth: Self.iPadColumnWidth, theme: theme, style: .dark)
        XCTAssertGreaterThan(drawn.width, 0)
        let screenshot = attachScreenshot(named: "A pie in the theme's dark --pele-series-1")
        let pieFrame = try XCTUnwrap(Self.diagramFrame(in: try XCTUnwrap(window)))
        guard case .pieChart(let chart) = pie else { return XCTFail("A pie") }
        // The pie's middle, a quarter of its radius up from its center, inside the only slice.
        let center = CGPoint(x: pieFrame.minX + chart.layout.center.x * pieFrame.width / chart.layout.size.width,
                             y: pieFrame.minY + (chart.layout.center.y - chart.layout.radius / 2) * pieFrame.height / chart.layout.size.height)
        let pixel = try XCTUnwrap(Self.pixel(of: try XCTUnwrap(screenshot), at: center))
        XCTAssertEqual(pixel.red, 1, accuracy: 0.03)
        XCTAssertEqual(pixel.green, 0.4, accuracy: 0.03)
        XCTAssertEqual(pixel.blue, 0, accuracy: 0.03)
        _ = try await show(ReadingDiagram(source: Self.compositeStates, typography: typography), columnWidth: Self.iPadColumnWidth, theme: theme, style: .dark)
        attachScreenshot(named: "Composite states in the theme's dark --pele-line and --pele-surface")
    }

    // MARK: Helpers

    /// Shows the diagram as the reading view does, in a column `columnWidth` wide on the note's background, and returns
    /// the size its drawing takes once laid out.
    private func show(_ diagram: ReadingDiagram, columnWidth: CGFloat, theme: NoteThemeStyle? = nil,
                      style: UIUserInterfaceStyle = .light) async throws -> CGSize {
        // No link in these diagrams is followed: any folder stands for the vault.
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let view = ScrollView {
            ReadingDiagramView(diagram: diagram, textSize: 17, root: root, navigate: { _, _ in }, scrollToHeading: { _ in })
                .frame(width: columnWidth)
                .padding(20)
                .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
        .environment(\.noteTheme, theme)
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = style
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = self.window ?? UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        var drawnSize = CGSize.zero, unchangedPolls = 0
        try await waitUntil("the diagram is laid out in its column") {
            controller.view.layoutIfNeeded()
            let size = Self.diagramSize(in: controller.view)
            unchangedPolls = size == drawnSize && size != .zero ? unchangedPolls + 1 : 0
            drawnSize = size
            return unchangedPolls >= 10
        }
        return drawnSize
    }

    /// The size of the diagram's element, which carries the image trait.
    private static func diagramSize(in view: UIView) -> CGSize {
        diagramFrame(in: view)?.size ?? .zero
    }

    /// The diagram's element's frame on the screen.
    private static func diagramFrame(in view: UIView) -> CGRect? {
        accessibilityElements(in: view).first { element in element.accessibilityTraits.contains(.image) }?.accessibilityFrame
    }

    /// The color of the screenshot at `point`, in points from the window's top left.
    private static func pixel(of image: UIImage, at point: CGPoint) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let cgImage = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let scale = image.scale
        context.draw(cgImage, in: CGRect(x: -point.x * scale, y: -(CGFloat(cgImage.height) - point.y * scale), width: CGFloat(cgImage.width),
                                         height: CGFloat(cgImage.height)))
        return (CGFloat(bytes[0]) / 255, CGFloat(bytes[1]) / 255, CGFloat(bytes[2]) / 255)
    }

    private static func accessibilityElements(in object: NSObject) -> [NSObject] {
        var elements: [NSObject] = object.isAccessibilityElement ? [object] : []
        let count = object.accessibilityElementCount()
        if let children = object.accessibilityElements {
            elements += children.compactMap { child in child as? NSObject }.flatMap(accessibilityElements)
        } else if count != NSNotFound, count > 0 {
            elements += (0..<count).compactMap { elementIndex in object.accessibilityElement(at: elementIndex) as? NSObject }.flatMap(accessibilityElements)
        } else if let view = object as? UIView {
            elements += view.subviews.flatMap(accessibilityElements)
        }
        return elements
    }

    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }

    @discardableResult
    private func attachScreenshot(named name: String) -> UIImage? {
        guard let window else { return nil }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return screenshot
    }
}
#endif
