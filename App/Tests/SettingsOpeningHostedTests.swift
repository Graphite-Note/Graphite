/**
 * File: SettingsOpeningHostedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Hosted tests of what Settings opens on, the sheets that fit a phone and a page that keeps what was typed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
@testable import GraphiteUI

/// Settings opens on its list on an iPhone, with a Done button on it, and beside the list on
/// an iPad with the page used last (HUNT-237, HUNT-241). Run it on the iPad and on the iPhone
/// simulator: each checks what its own screen shows.
@MainActor
final class SettingsOpeningHostedTests: SettingsHostedTestCase {
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
}

#endif
