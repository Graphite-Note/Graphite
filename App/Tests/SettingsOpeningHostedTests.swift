#if os(iOS)
import XCTest
import SwiftUI
@testable import GraphiteUI

/// Settings opens on its list on an iPhone, with a Done button on it, and beside the list on
/// an iPad with the page used last (HUNT-237, HUNT-241). Run it on the iPad and on the iPhone
/// simulator: each checks what its own screen shows.
@MainActor
final class SettingsOpeningHostedTests: XCTestCase {
    private var window: UIWindow?
    private var device: IsolatedWorkspaceDevice!
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

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

    func testSettingsOpensOnItsListOnAPhoneAndBesideThePageUsedLastOnAnIPad() async throws {
        let workspace = device.makeWorkspace()
        var controller = try host(SettingsView(workspace: workspace) {})

        // The list is on screen in both; so is the way out of it on a phone.
        _ = try await element(in: controller, "Appearance") { $0.accessibilityLabel == "Appearance" }
        if isPhone {
            _ = try await element(in: controller, "Done on the list") { $0.accessibilityLabel == "Done" && $0.accessibilityTraits.contains(.button) }
            XCTAssertNil(find(in: controller) { $0.accessibilityLabel == "Manage Vaults…" }, "The General page is not open under the list on a phone.")
        } else {
            _ = try await element(in: controller, "General page beside the list") { $0.accessibilityLabel == "Manage Vaults…" }
        }

        // Picking a page shows it; on a phone it replaces the list, and Back returns to it.
        await tap(try await element(in: controller, "Appearance row") { $0.accessibilityLabel == "Appearance" })
        _ = try await element(in: controller, "Appearance page") { ($0.accessibilityLabel ?? "").hasPrefix("Base Color Scheme") }
        if isPhone {
            XCTAssertNil(find(in: controller) { $0.accessibilityLabel == "Editor" }, "The page has the screen to itself.")
            _ = try await element(in: controller, "Done on the page") { $0.accessibilityLabel == "Done" && $0.accessibilityTraits.contains(.button) }
            await tap(try await element(in: controller, "Back to the list") { $0.accessibilityTraits.contains(.button) && $0.accessibilityLabel == "Settings" })
            _ = try await element(in: controller, "the list again") { $0.accessibilityLabel == "Editor" }
        }

        // Settings opened again goes to the same place: the list on a phone, the page used on an iPad.
        window?.rootViewController = nil
        controller = try host(SettingsView(workspace: workspace) {})
        if isPhone {
            _ = try await element(in: controller, "the list on the second opening") { $0.accessibilityLabel == "Editor" }
            XCTAssertNil(find(in: controller) { ($0.accessibilityLabel ?? "").hasPrefix("Base Color Scheme") })
        } else {
            _ = try await element(in: controller, "Appearance page remembered") { ($0.accessibilityLabel ?? "").hasPrefix("Base Color Scheme") }
            XCTAssertNil(find(in: controller) { $0.accessibilityLabel == "Manage Vaults…" }, "General is only the first opening.")
        }
    }

    // MARK: HUNT-243: sheets that fit a phone

    func testTheCommunityPluginBrowserFitsTheWidthOfAPhone() {
        let controller = UIHostingController(rootView: CommunityPluginBrowser(workspace: device.makeWorkspace()))
        let size = controller.sizeThatFits(in: CGSize(width: 390, height: 800))
        XCTAssertLessThanOrEqual(size.width, 390, "A minimum width of 480 points would be laid out wider than the screen and cut off.")
    }

    // MARK: HUNT-254: what is typed is kept

    func testPostgreSQLMirrorSettingsTypedAreKeptWhenThePageIsLeftWithoutSaving() async throws {
        guard !isPhone else { return }
        let workspace = device.makeWorkspace()
        workspace.setCorePluginEnabled(.postgreSQLMirror, true)
        let controller = try host(SettingsView(workspace: workspace) {})
        await tap(try await element(in: controller, "PostgreSQL Mirror row") { $0.accessibilityLabel == "PostgreSQL Mirror" })
        var addressField: UITextField?
        try await waitUntil("the Address field", timeoutSeconds: 10) {
            addressField = self.textFields(in: controller.view).first { field in field.placeholder == "localhost or db.example.org" }
            return addressField != nil
        }
        let field = try XCTUnwrap(addressField)
        field.text = "db.example.org"
        field.sendActions(for: .editingChanged)

        await tap(try await element(in: controller, "Editor row") { $0.accessibilityLabel == "Editor" })

        try await waitUntil("the address is kept", timeoutSeconds: 10) { workspace.preferences.postgreSQLMirrorConfiguration.host == "db.example.org" }
    }

    // MARK: Hosting and finding

    /// A finger tap in the middle of the element, as the screen delivers one: a list row is
    /// picked by a touch, not by an accessibility activation.
    private func tap(_ object: NSObject) async {
        guard let window else { return XCTFail("No window.") }
        let touches = SynthesizedTouches(window: window)
        let frame = object.accessibilityFrame
        touches.begin(at: [CGPoint(x: frame.midX, y: frame.midY)])
        try? await Task.sleep(for: .seconds(0.05))
        touches.end()
    }

    private func host(_ settings: SettingsView) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(settings))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    private func textFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { field in [field] } ?? view.subviews.flatMap(textFields)
    }

    private func find(in controller: UIViewController, matching matches: (NSObject) -> Bool) -> NSObject? {
        accessibilityElements(in: controller.view).first(where: matches)
    }

    private func element(in controller: UIViewController, _ description: String, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        var found: NSObject?
        try await waitUntil(description, timeoutSeconds: 10) {
            found = self.find(in: controller, matching: matches)
            return found != nil
        }
        return try XCTUnwrap(found)
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
