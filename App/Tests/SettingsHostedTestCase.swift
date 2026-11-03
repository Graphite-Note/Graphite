/**
 * File: SettingsHostedTestCase.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The common part of the hosted tests of Settings: the page in a real window, found by what an assistive
 *              technology reads, tapped as a finger taps and scrolled to the row wanted.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 02/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
@testable import GraphiteUI

/// A hosted test of Settings in a window on the simulator. Nothing here plays sound or shows anything on a screen a
/// person looks at.
@MainActor
class SettingsHostedTestCase: XCTestCase {
    var window: UIWindow?
    var device: IsolatedWorkspaceDevice!
    var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        // SwiftUI builds its accessibility elements only while an assistive technology asks
        // for them; the test switches the accessibility runtime on, as VoiceOver would.
        try Self.setAccessibilityRuntimeEnabled(true)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try Self.setAccessibilityRuntimeEnabled(false)
    }

    /// A finger tap in the middle of the element, as the screen delivers one: a list row is
    /// picked by a touch, not by an accessibility activation.
    func tap(_ object: NSObject) async {
        guard let window else { return XCTFail("No window.") }
        let touches = SynthesizedTouches(window: window)
        let frame = object.accessibilityFrame
        touches.begin(at: [CGPoint(x: frame.midX, y: frame.midY)])
        touches.end()
    }

    /// Follows a link of a page as VoiceOver does. Synthesized touches reach UIKit's gesture
    /// recognizers, which pick a row of the Settings list, but not SwiftUI's controls; a touch
    /// is what is left where the element does not answer.
    func follow(_ link: NSObject) async {
        if !link.accessibilityActivate() { await tap(link) }
    }

    func host(_ settings: some View) throws -> UIHostingController<AnyView> {
        window?.isHidden = true
        window?.rootViewController = nil
        let controller = UIHostingController(rootView: AnyView(settings))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    func textFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { field in [field] } ?? view.subviews.flatMap(textFields)
    }

    func scrollViews(in view: UIView) -> [UIScrollView] {
        let own = (view as? UIScrollView).map { scrollView in [scrollView] } ?? []
        return own + view.subviews.flatMap(scrollViews)
    }

    /// The first element on the screen of the controller, or in what it presents (a question, a menu).
    func find(in controller: UIViewController, matching matches: (NSObject) -> Bool) -> NSObject? {
        var shown: UIViewController? = controller
        while let current = shown {
            if let found = accessibilityElements(in: current.view).first(where: matches) { return found }
            shown = current.presentedViewController
        }
        return nil
    }

    func element(in controller: UIViewController, _ description: String, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        var found: NSObject?
        try await waitUntil(description, timeoutSeconds: 10) {
            found = self.find(in: controller, matching: matches)
            return found != nil
        }
        if found == nil { attachWhatIsOnScreen(in: controller, named: description) }
        return try XCTUnwrap(found)
    }

    /// The element, after scrolling the page down to it: a list builds the rows near the screen only.
    func elementScrolling(in controller: UIViewController, _ description: String, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        var found: NSObject?
        try await waitUntil(description, timeoutSeconds: 40, pollingIntervalSeconds: 0.2) {
            found = self.find(in: controller, matching: matches)
            if found == nil { _ = self.scrollDown(in: controller) }
            return found != nil
        }
        if found == nil { attachWhatIsOnScreen(in: controller, named: description) }
        return try XCTUnwrap(found)
    }

    /// The element where a finger can reach it: a list also prepares rows below the screen.
    func elementOnScreen(in controller: UIViewController, _ description: String, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        try await elementScrolling(in: controller, description) { object in
            guard let window = self.window, matches(object) else { return false }
            let frame = object.accessibilityFrame
            return window.bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    /// The navigation bar's item with this title, wherever the bar shows it: on the bar, which
    /// the accessibility tree lists, or gathered into a menu because the bar has no room. The
    /// center groups are left out: they are the "…" menu from the start.
    func barItem(titled title: String, in controller: UIViewController) -> NSObject? {
        if let shown = find(in: controller, matching: { $0.accessibilityLabel == title }) { return shown }
        let items = navigationBars(in: controller.view).compactMap(\.topItem).flatMap { item in
            (item.leadingItemGroups + item.trailingItemGroups).flatMap(\.barButtonItems)
        }
        return items.first { item in item.title == title || item.accessibilityLabel == title }
    }

    func requireBarItem(titled title: String, in controller: UIViewController, _ description: String) async throws {
        var found: NSObject?
        try await waitUntil(description, timeoutSeconds: 10) {
            found = self.barItem(titled: title, in: controller)
            return found != nil
        }
        if found == nil { attachWhatIsOnScreen(in: controller, named: description) }
    }

    private func navigationBars(in view: UIView) -> [UINavigationBar] {
        let own = (view as? UINavigationBar).map { bar in [bar] } ?? []
        return own + view.subviews.flatMap(navigationBars)
    }

    /// What the window showed and what the accessibility tree held when something was not
    /// found, so the results of a run on another machine say why.
    func attachWhatIsOnScreen(in controller: UIViewController, named name: String) {
        if let window {
            let picture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
            let attachment = XCTAttachment(image: picture)
            attachment.name = "Screen when waiting for \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        var shown: UIViewController? = controller
        var lines: [String] = []
        while let current = shown {
            lines += accessibilityElements(in: current.view).map { object in
                "\(type(of: object)) label: \(object.accessibilityLabel ?? "none") value: \(object.accessibilityValue ?? "none") traits: \(object.accessibilityTraits.rawValue) frame: \(object.accessibilityFrame)"
            }
            shown = current.presentedViewController
        }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "Accessibility elements when waiting for \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls the page to its end, a screen at a time.
    func scrollToEnd(in controller: UIViewController) async throws {
        try await waitUntil("the end of the page", timeoutSeconds: 40, pollingIntervalSeconds: 0.2) { !self.scrollDown(in: controller) }
    }

    /// Scrolls the tallest scrolling list by half a screen; false once it is at its end.
    func scrollDown(in controller: UIViewController) -> Bool {
        let scrollable = scrollViews(in: controller.view).filter { scrollView in scrollView.contentSize.height > scrollView.bounds.height + 1 }
        guard let page = scrollable.max(by: { first, second in first.bounds.width * first.bounds.height < second.bounds.width * second.bounds.height }) else { return false }
        let end = page.contentSize.height - page.bounds.height + page.adjustedContentInset.bottom
        guard page.contentOffset.y < end - 1 else { return false }
        page.setContentOffset(CGPoint(x: page.contentOffset.x, y: min(end, page.contentOffset.y + page.bounds.height * 0.5)), animated: false)
        return true
    }

    func accessibilityElements(in object: NSObject) -> [NSObject] {
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
}

#endif
