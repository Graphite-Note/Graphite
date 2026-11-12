import XCTest
import GraphiteFixtures

/// `App/Graphite.entitlements` and `App/Info.plist`, the files that decide what the sandboxed
/// Mac app may reach. Any entitlement added or dropped changes what a plugin or a note can
/// touch, so the full set is written out here and a change has to change this test as well.
final class GraphiteEntitlementsTests: XCTestCase {
    private static let applicationFolder = FixtureFolders.applicationFolder

    private func propertyList(named fileName: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.applicationFolder.appendingPathComponent(fileName))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }

    func testTheMacAppIsSandboxedWithExactlyTheNineEntitlements() throws {
        let entitlements = try propertyList(named: "Graphite.entitlements")
        let expectedEntitlements: [String: Bool] = [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.files.user-selected.read-write": true,
            "com.apple.security.files.bookmarks.app-scope": true,
            "com.apple.security.device.audio-input": true,
            "com.apple.security.device.camera": true,
            "com.apple.security.network.client": true,
            // The Calendar core plugin's events and reminders, which the sandbox's Calendars entitlement covers both of
            // (EventKit has no Reminders entitlement of its own); asked for at a feature's first use (Docs/Calendar-and-reminders-todo.md).
            "com.apple.security.personal-information.calendars": true,
            // The maps' location control, while Graphite is in use (Docs/Map-view-todo.md section 1).
            "com.apple.security.personal-information.location": true,
            // File › Print… (d896ecd).
            "com.apple.security.print": true,
        ]
        XCTAssertEqual(Set(entitlements.keys), Set(expectedEntitlements.keys), "No entitlement is added or dropped without a decision.")
        for (key, expectedValue) in expectedEntitlements {
            XCTAssertEqual(entitlements[key] as? Bool, expectedValue, key)
        }
    }

    func testTheMacAppAsksForNoOtherFileOrNetworkServerAccess() throws {
        let entitlementKeys = try propertyList(named: "Graphite.entitlements").keys
        let forbiddenKeyPrefixes = ["com.apple.security.network.server", "com.apple.security.files.all", "com.apple.security.temporary-exception"]
        for key in entitlementKeys {
            XCTAssertFalse(forbiddenKeyPrefixes.contains { prefix in key.hasPrefix(prefix) }, key)
        }
    }

    func testTheCameraMicrophonePhotoLibraryAddLocalNetworkLocationCalendarsAndRemindersReasonsStayInInformationPropertyList() throws {
        let information = try propertyList(named: "Info.plist")
        let usageDescriptionKeys = Set(information.keys.filter { key in key.hasSuffix("UsageDescription") })
        // The local network reason is the PostgreSQL Mirror's, for a server on the person's network. The location
        // reasons are the maps' (iOS reads the when-in-use one, the Mac the other); never "always". The calendars and
        // reminders reasons are the Calendar core plugin's, full access for reading.
        XCTAssertEqual(usageDescriptionKeys, ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription",
                                              "NSLocalNetworkUsageDescription", "NSLocationWhenInUseUsageDescription", "NSLocationUsageDescription",
                                              "NSCalendarsFullAccessUsageDescription", "NSRemindersFullAccessUsageDescription"])
        for key in usageDescriptionKeys {
            let reason = try XCTUnwrap(information[key] as? String, key)
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) states why the app asks.")
        }
    }
}
