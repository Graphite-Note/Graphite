/**
 * File: SettingsHostedTestCase.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The common part of the hosted tests of Settings: the page in a real window, found by what an assistive
 *              technology reads, tapped as a finger taps and scrolled to the row wanted.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
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
        return try XCTUnwrap(found)
    }

    /// The element, after scrolling the page down to it: a list builds the rows near the screen only.
    func elementScrolling(in controller: UIViewController, _ description: String, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        for _ in 0..<20 {
            if let found = find(in: controller, matching: matches) { return found }
            try await Task.sleep(for: .milliseconds(100))
        }
        while scrollDown(in: controller) {
            try await Task.sleep(for: .milliseconds(150))
            if let found = find(in: controller, matching: matches) { return found }
        }
        return try await element(in: controller, description, matching: matches)
    }

    /// Scrolls the tallest scrolling list by most of a screen; false once it is at its end.
    func scrollDown(in controller: UIViewController) -> Bool {
        let scrollable = scrollViews(in: controller.view).filter { scrollView in scrollView.contentSize.height > scrollView.bounds.height + 1 }
        guard let page = scrollable.max(by: { first, second in first.bounds.width * first.bounds.height < second.bounds.width * second.bounds.height }) else { return false }
        let end = page.contentSize.height - page.bounds.height + page.adjustedContentInset.bottom
        guard page.contentOffset.y < end - 1 else { return false }
        page.setContentOffset(CGPoint(x: page.contentOffset.x, y: min(end, page.contentOffset.y + page.bounds.height * 0.7)), animated: false)
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
