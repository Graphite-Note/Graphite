/**
 * File: InlineImagesSideBySideHostedTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of a note whose Photos section writes several image embeds on a line, as the
 *              owner's "Butter-basted steak.md" does: once the index has read the vault, the reading view and
 *              Live Preview draw every picture, in paragraph lines, a list item, a table and a callout, and
 *              none is left as a link (issue #102).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The owner, 2026-10-24: "![] are not showing properly". A line such as `![[IMG_6652.JPG|250]] ![[IMG_6653.JPG|250]]`
/// showed as link-colored text, `IMG_6652.JPG|250`. The pictures here are small generated files in an
/// `Attachments` folder, which only the index finds, as Obsidian's attachment folder is found. Pictures are
/// found as VoiceOver finds them: a picture inside text (the reading view's, a table's, a callout's) is an
/// element named after its file with the picture's Zoom In command; a picture Live Preview draws as an embed
/// is an element with the hint "Opens the image to zoom".
@MainActor
final class InlineImagesSideBySideHostedTests: XCTestCase {
    private var window: UIWindow?

    private static let notePath = "Recipes/Butter-basted steak.md"
    /// The owner's two lines of photos, with made-up names and the owner's widths and extension cases.
    private static let photoNames = ["IMG_3599.jpg", "IMG_3598.PNG"] + (6652...6661).map { number in "IMG_\(number).JPG" }
    private static let listPictureNames = ["Step_1.jpg", "Step_2.jpg"]
    private static let tablePictureNames = ["Raw.png", "Seared.png", "Done.png"]
    private static let calloutPictureNames = ["Rest_1.png", "Rest_2.png"]
    private static let allPictureNames = photoNames + listPictureNames + tablePictureNames + calloutPictureNames

    private static let note: String = {
        let tenPhotos = (6652...6661).map { number in "![[IMG_\(number).JPG|250]]" }.joined(separator: " ")
        return """
        # Butter-basted steak

        Sear hard, then baste with butter, thyme and garlic.

        ## Photos

        ![[IMG_3599.jpg|300]] ![[IMG_3598.PNG|200]]

        \(tenPhotos)

        ## Steps

        - ![[Step_1.jpg|120]] ![[Step_2.jpg|120]]

        | Before | After |
        | --- | --- |
        | ![[Raw.png\\|100]] ![[Seared.png\\|100]] | ![Done\\|100](../Attachments/Done.png) |

        > [!tip] Resting
        > ![[Rest_1.png|100]] ![[Rest_2.png|100]]

        The end.

        """
    }()

    override func setUp() async throws {
        // SwiftUI builds its accessibility elements only while an assistive technology asks for them.
        try Self.setAccessibilityRuntimeEnabled(true)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try Self.setAccessibilityRuntimeEnabled(false)
    }

    // MARK: Reading view

    /// Before the index has read the pictures they are links, as an embed the index does not know yet is; once it
    /// has, every picture of the note is drawn, those of the Photos section side by side, and none is a link.
    func testTheReadingViewDrawsEveryPictureOfThePhotosSectionOnceTheIndexHasReadTheVault() async throws {
        let (workspace, picturePaths) = try await makeWorkspace(viewMode: .reading)
        let controller = try host(workspace)
        let scrollView = try await noteScrollView(in: controller)
        try await indexThePictures(picturePaths, of: workspace)

        let sightings = try await pictureSightings(scrolling: scrollView, in: controller) { sightings in
            Set(Self.allPictureNames.map(Self.stem)).isSubset(of: sightings.inlineLabels)
        }
        XCTAssertEqual(Set(Self.allPictureNames.map(Self.stem)).subtracting(sightings.inlineLabels), [], "Every picture is drawn.")
        XCTAssertEqual(sightings.linkLabels.filter { label in Self.allPictureNames.contains { name in label.contains(Self.stem(name)) } }, [],
                       "No picture is left as a link.")
        // Side by side: the two photos of the first line share a row, and the ten 250-point photos take rows of several.
        let firstRow = try XCTUnwrap(sightings.inlineFrames["IMG_3599"]), secondPicture = try XCTUnwrap(sightings.inlineFrames["IMG_3598"])
        XCTAssertEqual(firstRow.maxY, secondPicture.maxY, accuracy: 2, "The first two photos stand on one row.")
        XCTAssertEqual(firstRow.width, 300, accuracy: 1)
        XCTAssertEqual(secondPicture.width, 200, accuracy: 1)
        let tenRowTops = Set((6652...6661).compactMap { number in sightings.inlineFrames["IMG_\(number)"].map { frame in Int(frame.minY.rounded()) } })
        XCTAssertLessThan(tenRowTops.count, 10, "The ten photos share rows: \(tenRowTops.sorted())")
        XCTAssertTrue((6652...6661).allSatisfy { number in abs((sightings.inlineFrames["IMG_\(number)"]?.width ?? 0) - 250) < 1 }, "Each is 250 points wide.")
        try await attachScreenshot(named: "The reading view's photos", showingContentFrom: firstRow.minY - 60, of: scrollView)
        try await attachScreenshot(named: "The reading view's list, table and callout",
                                   showingContentFrom: (sightings.inlineFrames["Step_1"]?.minY ?? 0) - 60, of: scrollView)
    }

    // MARK: Live Preview

    /// Live Preview draws the Photos section's lines and the list item as pictures at their widths, and the
    /// table's and callout's pictures inside their blocks, once the index has read the pictures.
    func testLivePreviewDrawsEveryPictureOfTheNoteOnceTheIndexHasReadTheVault() async throws {
        let (workspace, picturePaths) = try await makeWorkspace(viewMode: .livePreview)
        let controller = try host(workspace)
        let scrollView = try await noteScrollView(in: controller)
        try await indexThePictures(picturePaths, of: workspace)

        let embedCount = Self.photoNames.count + Self.listPictureNames.count
        let insideTextNames = Set((Self.tablePictureNames + Self.calloutPictureNames).map(Self.stem))
        let sightings = try await pictureSightings(scrolling: scrollView, in: controller) { sightings in
            sightings.embedFrames.count >= embedCount && insideTextNames.isSubset(of: sightings.inlineLabels)
        }
        XCTAssertEqual(sightings.embedFrames.count, embedCount, "The photo lines and the list item draw \(embedCount) pictures.")
        XCTAssertEqual(insideTextNames.subtracting(sightings.inlineLabels), [], "The table and the callout draw their pictures.")
        // The pictures' widths, as their embeds give them: 300, 200, ten of 250, and 120 for the list item's two.
        let widths = sightings.embedFrames.map { frame in Int(frame.width.rounded()) }.sorted()
        XCTAssertEqual(widths, ([300, 200] + Array(repeating: 250, count: 10) + [120, 120]).sorted())
        // Side by side: the list item's two pictures share a row, to the right of its bullet.
        let listPictures = sightings.embedFrames.filter { frame in abs(frame.width - 120) < 1 }.sorted { leftFrame, rightFrame in leftFrame.minX < rightFrame.minX }
        XCTAssertEqual(listPictures.count, 2)
        if listPictures.count == 2 {
            XCTAssertEqual(listPictures[0].maxY, listPictures[1].maxY, accuracy: 2, "The list item's pictures share a row.")
            let firstPhoto = try XCTUnwrap(sightings.embedFrames.first { frame in abs(frame.width - 300) < 1 })
            XCTAssertGreaterThan(listPictures[0].minX, firstPhoto.minX + 8, "The list item's pictures start after its bullet.")
        }
        let firstPhotoTop = sightings.embedFrames.first { frame in abs(frame.width - 300) < 1 }?.minY ?? 0
        try await attachScreenshot(named: "Live Preview's photos", showingContentFrom: firstPhotoTop - 60, of: scrollView)
        try await attachScreenshot(named: "Live Preview's list, table and callout", showingContentFrom: (listPictures.first?.minY ?? 0) - 60, of: scrollView)
    }

    // MARK: Helpers

    /// What was seen of the note's pictures while it scrolled: the pictures inside text by label, their frames
    /// in the note's content, Live Preview's embedded pictures by frame, and the labels of links.
    private struct PictureSightings {
        var inlineLabels: Set<String> = []
        var inlineFrames: [String: CGRect] = [:]
        var embedFrames: [CGRect] = []
        var linkLabels: Set<String> = []
    }

    private static func stem(_ name: String) -> String { (name as NSString).deletingPathExtension }

    /// Scrolls the note from its top to its end, half a screen at a time, up to three times, until `isComplete`
    /// holds for what has been seen. At each place it waits until what is on screen stops changing (pictures
    /// load, rows find their heights), so a frame is read where it is; frames are in the scroll view's content,
    /// so a picture seen from two places counts once.
    private func pictureSightings(scrolling scrollView: UIScrollView, in controller: UIViewController,
                                  until isComplete: (PictureSightings) -> Bool) async throws -> PictureSightings {
        var sightings = PictureSightings()
        let windowBounds = try XCTUnwrap(window).bounds
        func onScreen() -> [NSObject] {
            elements(in: controller).filter { element in windowBounds.intersects(element.accessibilityFrame) }
        }
        func record() {
            for element in onScreen() {
                let frame = scrollView.convert(element.accessibilityFrame, from: nil)
                if element.accessibilityHint == "Opens the image to zoom" {
                    if !sightings.embedFrames.contains(where: { seen in abs(seen.minX - frame.minX) < 3 && abs(seen.minY - frame.minY) < 3 }) {
                        sightings.embedFrames.append(frame)
                    }
                } else if let label = element.accessibilityLabel, actionNames(of: element).contains("Zoom In") {
                    sightings.inlineLabels.insert(label)
                    sightings.inlineFrames[label] = frame
                } else if element.accessibilityTraits.contains(.link), let label = element.accessibilityLabel {
                    sightings.linkLabels.insert(label)
                }
            }
        }
        for _ in 0..<3 {
            var offset: CGFloat = 0
            while true {
                scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                var lastScreen = "", unchangedPolls = 0
                try await waitUntil("the note settles at \(offset)", timeoutSeconds: 30) {
                    let screen = onScreen().map { element in "\(element.accessibilityLabel ?? "")|\(element.accessibilityFrame)" }.joined(separator: ",")
                        + "|\(scrollView.contentSize.height)|\(scrollView.contentOffset.y)"
                    unchangedPolls = screen == lastScreen ? unchangedPolls + 1 : 0
                    lastScreen = screen
                    return unchangedPolls >= 15
                }
                record()
                if isComplete(sightings) { return sightings }
                let bottomOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                guard offset < bottomOffset - 1 else { break }
                offset = min(offset + scrollView.bounds.height / 2, bottomOffset)
            }
        }
        return sightings
    }

    /// The vault: the note in `Recipes`, its pictures in `Attachments`, an index that has read the note and not
    /// yet the pictures.
    private func makeWorkspace(viewMode: NoteViewMode) async throws -> (WorkspaceModel, [VaultPath]) {
        let vault = try TemporaryVault.make(prefix: "InlineImages", files: [Self.notePath: Self.note], for: self)
        let attachments = vault.root.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let colors: [UIColor] = [.systemTeal, .systemOrange, .systemPurple, .systemGreen, .systemPink, .systemIndigo]
        var picturePaths: [VaultPath] = []
        for (index, name) in Self.allPictureNames.enumerated() {
            let data = try Self.pictureData(color: colors[index % colors.count], isJPEG: name.lowercased().hasSuffix(".jpg"))
            try data.write(to: attachments.appendingPathComponent(name))
            picturePaths.append(try VaultPath("Attachments/" + name))
        }
        try FileManager.default.createDirectory(at: vault.cacheDirectory, withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        try await index.refresh(paths: [try VaultPath(Self.notePath)], root: vault.root)
        workspace.index = index
        await workspace.open(try VaultPath(Self.notePath))
        try XCTUnwrap(workspace.markdownSession).viewMode = viewMode
        return (workspace, picturePaths)
    }

    /// The index reads the pictures, as its scan of the vault does after the note opened, and tells the workspace.
    private func indexThePictures(_ picturePaths: [VaultPath], of workspace: WorkspaceModel) async throws {
        let index = try XCTUnwrap(workspace.index), root = try XCTUnwrap(workspace.folderAccess?.root)
        try await index.refresh(paths: picturePaths, root: root)
        workspace.recordIndexChange(paths: Set(picturePaths))
    }

    /// A 4:3 picture with a frame, so it can be told from the paper around it.
    private static func pictureData(color: UIColor, isJPEG: Bool) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            UIColor.white.setFill()
            context.fill(CGRect(x: 40, y: 40, width: 320, height: 220))
        }
        return try XCTUnwrap(isJPEG ? image.jpegData(compressionQuality: 0.8) : image.pngData())
    }

    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<GraphiteRootView> {
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    /// The note's scroll view: the reading view's, or Live Preview's text view, once the note is laid out.
    private func noteScrollView(in controller: UIViewController) async throws -> UIScrollView {
        var noteScrollView: UIScrollView?
        try await waitUntil("the note is laid out") {
            noteScrollView = self.descendants(of: controller.view, matching: UIScrollView.self)
                .filter { scrollView in scrollView.window != nil && scrollView.contentSize.height > 200 && scrollView.bounds.width > 300 }
                .max { leftScrollView, rightScrollView in leftScrollView.contentSize.height < rightScrollView.contentSize.height }
            return noteScrollView != nil
        }
        return try XCTUnwrap(noteScrollView)
    }

    private func actionNames(of element: NSObject) -> [String] {
        (element.accessibilityCustomActions ?? []).map(\.name)
    }

    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }

    private func elements(in controller: UIViewController) -> [NSObject] {
        accessibilityElements(in: controller.view)
    }

    private func accessibilityElements(in object: NSObject) -> [NSObject] {
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

    /// A screenshot of the window with the note scrolled to show its content from `contentTop` down, once it has drawn.
    private func attachScreenshot(named name: String, showingContentFrom contentTop: CGFloat, of scrollView: UIScrollView) async throws {
        let bottomOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: min(max(0, contentTop), bottomOffset)), animated: false)
        var polls = 0
        try await waitUntil("the note draws where it was scrolled") {
            polls += 1
            return polls >= 40
        }
        attachScreenshot(named: name)
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { matchingChild in [matchingChild] } ?? []) + descendants(of: child, matching: type)
        }
    }
}
#endif
