/**
 * File: BugHuntLooksHostedTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Hosted tests of bug hunt items that waited for a look on an iPhone or an iPad: the phone's bottom bar,
 *              its command palette, a note's More menu, a PDF's pages, the keyboard bar, Settings at the largest text,
 *              stopping a scan being prepared, the locked PDF's prompt and the author written into a PDF.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// Run on the iPhone simulator for the phone's items and on the iPad simulator for the others; a test that is for one
/// kind of device returns on the other. Each test checks what it can by itself, attaches pictures of its window, and
/// asks for a picture of the whole simulator screen (menus and the keyboard included) when a watcher is running
/// (`requestLook(named:)`). Nothing here plays sound.
@MainActor
final class BugHuntLooksHostedTests: SettingsHostedTestCase {
    private func makeVault(files: [String: String]) throws -> URL {
        try TemporaryVault.make(prefix: "BugHuntLooks", files: files, for: self).root
    }

    /// The window a phone gives: the whole screen on the iPhone simulator, an iPhone 17 Pro Max's on the iPad's.
    private func hostAsOnAPhone(_ view: some View) throws -> UIHostingController<AnyView> {
        try host(view, size: isPhone ? nil : CGSize(width: 440, height: 956), horizontalSizeClass: .compact)
    }

    private func attachPicture(named name: String) {
        guard let window else { return }
        let picture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: picture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Asks a watcher outside the simulator for a picture of its whole screen and waits until it is taken. A watcher
    /// says it is there by a file `look-watcher` in the app's caches folder; without one, nothing is asked.
    private func requestLook(named name: String) async throws {
        attachPicture(named: name)
        guard let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("look-watcher").path) else { return }
        let request = folder.appendingPathComponent("look-request")
        try Data(name.utf8).write(to: request)
        try await waitUntil("the picture \(name) is taken", timeoutSeconds: 20) { !FileManager.default.fileExists(atPath: request.path) }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }

    /// An element of any window of the scene: an open menu is drawn in a window of its own.
    private func elementInAnyWindow(_ description: String, matching matches: @escaping (NSObject) -> Bool) async throws -> (element: NSObject, window: UIWindow) {
        var found: (NSObject, UIWindow)?
        try await waitUntil(description, timeoutSeconds: 15) {
            let windows = self.window?.windowScene?.windows ?? []
            found = windows.reversed().lazy.compactMap { shown in self.accessibilityElements(in: shown).first(where: matches).map { element in (element, shown) } }.first
            return found != nil
        }
        let (element, shownWindow) = try XCTUnwrap(found, description)
        return (element, shownWindow)
    }

    /// A finger's tap in the middle of `element`, delivered to the window that draws it.
    private func tapAsAFinger(on element: NSObject, in shownWindow: UIWindow) async {
        let frame = shownWindow.convert(element.accessibilityFrame, from: shownWindow.screen.coordinateSpace)
        let touches = SynthesizedTouches(window: shownWindow)
        touches.begin(at: [CGPoint(x: frame.midX, y: frame.midY)])
        touches.end()
    }

    /// Opens the More menu of the document in front as a finger does.
    private func openMoreMenu(in controller: UIViewController) async throws {
        var moreButtons: [NSObject] = []
        try await waitUntil("the More button", timeoutSeconds: 15) {
            moreButtons = self.accessibilityElements(in: controller.view).filter { object in object.accessibilityLabel == "More" }
            return !moreButtons.isEmpty
        }
        // The document's own More is at the top right of the window.
        let more = try XCTUnwrap(moreButtons.min { left, right in
            (left.accessibilityFrame.minY, -left.accessibilityFrame.maxX) < (right.accessibilityFrame.minY, -right.accessibilityFrame.maxX)
        })
        let frame = more.accessibilityFrame
        await tapAsAFinger(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    private func tapAsAFinger(at point: CGPoint) async {
        guard let window else { return }
        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [point])
        touches.end()
    }

    private func openNote(_ path: String, in files: [String: String]) async throws -> WorkspaceModel {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: files))
        await workspace.open(try VaultPath(path))
        return workspace
    }

    // MARK: HUNT-156: the phone's bottom bar finds a file by name

    func testOnAPhoneTheBottomBarsPageWithAMagnifierOpensFindOrCreateANote() async throws {
        let workspace = try await openNote("Lecture.md", in: ["Lecture.md": "# Lecture\n\nText.\n", "Other.md": "Other.\n"])
        let controller = try hostAsOnAPhone(GraphiteRootView(workspace: workspace))
        try await requestLook(named: "Phone bottom bar with a note open")
        let button = try await element(in: controller, "the Quick Switcher button") { object in object.accessibilityLabel == "Quick Switcher" }
        if !button.accessibilityActivate() { await tap(button) }
        _ = try await element(in: controller, "Find or create a note") { object in
            [object.accessibilityLabel, object.accessibilityValue, (object as? UITextField)?.placeholder].contains("Find or create a note…")
        }
        try await requestLook(named: "Phone quick switcher from the bottom bar")
    }

    // MARK: HUNT-278: the command palette on a phone

    func testOnAPhoneTheCommandPaletteShowsNoKeyShortcutsAndReachesTheKeyboard() async throws {
        let workspace = try await openNote("Lecture.md", in: ["Lecture.md": "# Lecture\n\nText.\n"])
        let controller = try hostAsOnAPhone(GraphiteRootView(workspace: workspace))
        let button = try await element(in: controller, "the Command Palette button") { object in object.accessibilityLabel == "Command Palette" }
        if !button.accessibilityActivate() { await tap(button) }
        var paletteField: UITextField?
        try await waitUntil("the palette's field takes the typing", timeoutSeconds: 10) {
            paletteField = self.textFields(in: controller.view).first { field in field.isFirstResponder }
            return paletteField != nil
        }
        // The software keyboard comes up unless the simulator has a hardware keyboard connected.
        let keyboardDeadline = ContinuousClock.now + .seconds(5)
        try await waitUntil("the keyboard is up or five seconds have passed") {
            (self.window?.keyboardLayoutGuide.layoutFrame.height ?? 0) > 100 || ContinuousClock.now >= keyboardDeadline
        }
        let rows = accessibilityElements(in: controller.view).compactMap(\.accessibilityLabel)
        if isPhone {
            XCTAssertFalse(rows.contains { label in label.contains("⌘") || label.contains("⇧") }, "A phone shows no key shortcuts: \(rows)")
        }
        try await requestLook(named: "Phone command palette with the keyboard up")
        paletteField?.resignFirstResponder()
    }

    // MARK: HUNT-277: a note's More menu on a phone

    func testOnAPhoneANotesMoreMenuHoldsMoveAndDeleteInItsFileMenu() async throws {
        let workspace = try await openNote("Lecture.md", in: ["Lecture.md": "# Lecture\n\nText.\n"])
        let controller = try hostAsOnAPhone(GraphiteRootView(workspace: workspace))
        try await openMoreMenu(in: controller)
        let file = try await elementInAnyWindow("the File menu in the note's More menu") { object in object.accessibilityLabel == "File" }
        // The menu settles before its picture is taken: whether every entry fits is seen in that picture, as UIKit draws
        // the menu's list in a view of its own that the test does not reach.
        let settledUntil = ContinuousClock.now + .seconds(1)
        try await waitUntil("the menu has opened") { ContinuousClock.now >= settledUntil }
        try await requestLook(named: "Phone note's More menu")
        if !file.element.accessibilityActivate() { await tapAsAFinger(on: file.element, in: file.window) }
        _ = try await elementInAnyWindow("Move to… in the File menu") { object in object.accessibilityLabel == "Move to…" }
        _ = try await elementInAnyWindow("Delete in the File menu") { object in object.accessibilityLabel == "Delete" }
        _ = try await elementInAnyWindow("Rename… in the File menu") { object in object.accessibilityLabel == "Rename…" }
        try await requestLook(named: "Phone note's File menu")
    }

    // MARK: HUNT-269: Show Pages on a phone

    func testOnAPhoneShowPagesIsASheetThatClosesOnThePageChosen() async throws {
        let directory = try makeVault(files: [:])
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 5).write(to: directory.appendingPathComponent("Paper.pdf"))
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(directory)
        await workspace.open(try VaultPath("Paper.pdf"))
        let session = try XCTUnwrap(workspace.pdfSession)
        let controller = try hostAsOnAPhone(GraphiteRootView(workspace: workspace))
        try await openMoreMenu(in: controller)
        let showPages = try await elementInAnyWindow("Show Pages in the More menu") { object in object.accessibilityLabel == "Show Pages" }
        try await requestLook(named: "Phone PDF More menu")
        await tapAsAFinger(on: showPages.element, in: showPages.window)
        try await waitUntil("the pages show in a sheet", timeoutSeconds: 10) { controller.presentedViewController != nil }
        _ = try await element(in: controller, "page 3 in the sheet") { object in object.accessibilityLabel == "Page 3" }
        try await requestLook(named: "Phone Show Pages sheet")
        // The sheet opens at half the screen's height with the first page in view; page 3 is a scroll below it.
        let sheetView = try XCTUnwrap(controller.presentedViewController?.view)
        // The list keeps the page it was last scrolled to (`PDFCurrentPageFollower`, page 1) and, while the sheet settles,
        // puts itself back there at its updates: an offset set once was undone within a second. It is set again at each look.
        var pageThree: NSObject?
        try await waitUntil("page 3 scrolled into view", timeoutSeconds: 10) {
            pageThree = self.find(in: controller) { object in
                object.accessibilityLabel == "Page 3" && sheetView.window.map { window in window.bounds.contains(CGPoint(x: object.accessibilityFrame.midX, y: object.accessibilityFrame.midY)) } == true
            }
            if pageThree != nil { return true }
            for pages in self.scrollViews(in: sheetView) where pages.contentSize.height > pages.bounds.height {
                pages.setContentOffset(CGPoint(x: 0, y: min(pages.contentSize.height - pages.bounds.height, 2 * 240)), animated: false)
            }
            return false
        }
        let pageThreeElement = try XCTUnwrap(pageThree)
        try await requestLook(named: "Phone Show Pages sheet scrolled to page 3")
        if !pageThreeElement.accessibilityActivate(), let window { await tapAsAFinger(on: pageThreeElement, in: window) }
        try await waitUntil("choosing page 3 closes the sheet", timeoutSeconds: 10) { controller.presentedViewController == nil }
        try await waitUntil("the PDF is on page 3", timeoutSeconds: 10) { session.currentPageIndex == 2 }
        try await requestLook(named: "Phone PDF on page 3 after the sheet")
    }

    // MARK: HUNT-247: Settings at the largest text on a phone

    func testOnAPhoneSettingsAtTheLargestTextHasNoIconsAndTheGeneralTitleClearsTheBackButton() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Note.md": "x"]))
        let controller = try hostAsOnAPhone(SettingsView(workspace: workspace) {}.dynamicTypeSize(.accessibility5))
        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        let appearance = try await element(in: controller, "the Appearance row") { object in object.accessibilityLabel == "Appearance" }
        _ = appearance
        try await requestLook(named: "Phone Settings list at the largest text")
        await tap(try await element(in: controller, "the General row") { object in object.accessibilityLabel == "General" })
        _ = try await element(in: controller, "the General page") { object in object.accessibilityLabel == "Your Name" }
        try await requestLook(named: "Phone Settings General at the largest text")
    }

    // MARK: HUNT-216: stopping a scan being prepared asks first

    func testTappingTheNewButtonWhileAScanIsPreparedAsksBeforeStoppingIt() async throws {
        let processing = DocumentScanProcessing(wordRecognizer: .onDevice)
        var savedScans = 0
        let release = AsyncStream<Void>.makeStream()
        let actions = NewItemActions(directory: nil, create: { _, _ in }, openDailyNote: {}, newFolder: { _ in }, importFiles: { _, _ in },
                                     saveScannedNotebook: { _, _, _ in }, reportProblem: { _ in }, savePicture: { _, _, _ in }, canTakePhoto: false)
        let controller = try host(NavigationStack {
            NewItemButton(firstKind: .note, isEnabled: { _ in true }, actions: actions, scanProcessing: processing) { Label("New", systemImage: "plus") }
        })
        let page = try XCTUnwrap(CGContext(data: nil, width: 64, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        page.setFillColor(UIColor.white.cgColor)
        page.fill(CGRect(x: 0, y: 0, width: 64, height: 80))
        let pageImage = try XCTUnwrap(page.makeImage())
        // The PDF is held at its save, so the scan stays "being prepared" for as long as the test needs.
        let scanTask = processing.process(pageImages: [pageImage, pageImage], save: { _, _ in
            for await _ in release.stream { break }
            savedScans += 1
        }, report: { error in XCTFail("The scan failed: \(error)") })
        XCTAssertTrue(processing.isProcessing)

        let spinner = try await element(in: controller, "the New button while the scan is prepared") { object in
            object.accessibilityHint == "Preparing a scan. Asks whether to stop it."
        }
        XCTAssertTrue(spinner.accessibilityActivate())
        _ = try await element(in: controller, "Stop and Discard the Scan") { object in object.accessibilityLabel == "Stop and Discard the Scan" }
        try await requestLook(named: "Stop preparing the scan question")
        XCTAssertTrue(processing.isProcessing, "Asking stops nothing.")
        // Keep Preparing is the question's cancel: iOS 27 draws the question as a popover over the button and leaves the
        // cancel out of it, so a tap beside it answers it; where it is drawn as a button, it is pressed.
        let pressedKeepPreparing = find(in: controller, matching: { object in object.accessibilityLabel == "Keep Preparing" })?.accessibilityActivate() ?? false
        if !pressedKeepPreparing { controller.presentedViewController?.dismiss(animated: false) }
        try await waitUntil("the question goes", timeoutSeconds: 10) { controller.presentedViewController == nil }
        XCTAssertTrue(processing.isProcessing, "Keep Preparing lets the scan go on.")
        release.continuation.yield()
        await scanTask?.value
        XCTAssertEqual(savedScans, 1, "The scan kept is saved.")
        XCTAssertFalse(processing.isProcessing)

        // Stopping: the scan is held at its save again, so the question finds it being prepared.
        let secondRelease = AsyncStream<Void>.makeStream()
        let secondTask = processing.process(pageImages: [pageImage], save: { _, _ in
            for await _ in secondRelease.stream { break }
        }, report: { _ in })
        let secondSpinner = try await element(in: controller, "the New button while the second scan is prepared") { object in
            object.accessibilityHint == "Preparing a scan. Asks whether to stop it."
        }
        XCTAssertTrue(secondSpinner.accessibilityActivate())
        let stop = try await element(in: controller, "Stop and Discard the Scan") { object in object.accessibilityLabel == "Stop and Discard the Scan" }
        if !stop.accessibilityActivate() { await tap(stop) }
        try await waitUntil("stopping ends the preparing", timeoutSeconds: 10) { !processing.isProcessing }
        _ = try await element(in: controller, "the New button again") { object in object.accessibilityLabel == "New" }
        secondRelease.continuation.finish()
        await secondTask?.value
    }

    // MARK: HUNT-327: the locked PDF's prompt on the iPad and the iPhone

    func testTheLockedPDFsPromptShowsItsFieldAndUnlockWhole() async throws {
        var unlockedWith: [String] = []
        let controller = try host(PDFPasswordPrompt(fileName: "Locked lecture.pdf", message: "This PDF is protected by a password.") { password in
            unlockedWith.append(password)
        })
        var field: UITextField?
        try await waitUntil("the password field", timeoutSeconds: 10) {
            field = self.textFields(in: controller.view).first { textField in textField.isSecureTextEntry }
            return field != nil
        }
        let passwordField = try XCTUnwrap(field)
        XCTAssertEqual(passwordField.bounds.width, PDFPasswordPrompt.passwordFieldWidth, accuracy: 1, "The field is not squeezed: \(passwordField.bounds.width)")
        try await requestLook(named: "Locked PDF prompt")
        passwordField.text = "lecture-2026"
        passwordField.sendActions(for: .editingChanged)
        let unlock = try await element(in: controller, "Unlock") { object in object.accessibilityLabel == "Unlock" }
        try await waitUntil("Unlock is enabled", timeoutSeconds: 10) { !unlock.accessibilityTraits.contains(.notEnabled) }
        XCTAssertTrue(unlock.accessibilityActivate())
        try await waitUntil("the password is given", timeoutSeconds: 10) { unlockedWith == ["lecture-2026"] }
    }

    // MARK: HUNT-315: the author written into a PDF saved on an iPad or iPhone

    func testInkAndMarkupsSavedHereNameTheChosenAuthorAndNeverMobileUser() throws {
        let folder = try makeVault(files: [:])
        let suiteName = "BugHuntLooks-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for chosenName in ["Ada Lovelace", nil] as [String?] {
            if let chosenName { defaults.set(chosenName, forKey: PDFAnnotationAuthor.preferenceKey) } else { defaults.removeObject(forKey: PDFAnnotationAuthor.preferenceKey) }
            let author = PDFAnnotationAuthor(defaults: defaults)
            let document = PDFDocument()
            document.insert(PDFPage(), at: 0)
            let stroke = PortableInkStroke(name: "ink", segments: [[CGPoint(x: 100, y: 400), CGPoint(x: 200, y: 450)]], width: 2, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
            try PDFPageManager.apply(.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [stroke], editableRecord: nil)),
                                     to: document, drawsInkOutlines: true, author: author)
            try PDFPageManager.apply(.addMarkup(page: 0, markup: PDFMarkup(name: "marker", kind: .highlight, color: .yellow, lineBounds: [CGRect(x: 60, y: 500, width: 200, height: 20)])),
                                     to: document, drawsInkOutlines: true, author: author)
            let file = folder.appendingPathComponent("\(UUID().uuidString).pdf")
            XCTAssertTrue(document.write(to: file), "PDFKit writes the file as a save does.")
            let reloaded = try XCTUnwrap(PDFDocument(url: file))
            let annotations = try XCTUnwrap(reloaded.page(at: 0)).annotations
            XCTAssertFalse(annotations.isEmpty)
            for annotation in annotations { XCTAssertEqual(annotation.userName, chosenName, annotation.type ?? "?") }
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(String(decoding: bytes, as: UTF8.self).range(of: "Mobile User"), "The device's generic name is never written.")
        }
    }
}
#endif
