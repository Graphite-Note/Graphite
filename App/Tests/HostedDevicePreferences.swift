/**
 * File: HostedDevicePreferences.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The app's own preferences a hosted test changes, set for the test and put back as the device had
 *              them, and the guard that snapshots the app's whole preferences domain before each test class and puts
 *              it back exactly after: on a person's iPad the hosted tests run in their own app, with their own settings.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 05/11/2026
 */

import Foundation
import XCTest

/// The app's standard preferences, which its views read and a hosted test cannot give an isolated suite. The first
/// run on the owner's iPad (2026-11-04) met his own settings (the even highlighter, his toolbar style), and tests
/// that removed a preference after changing it left his settings without it.
enum HostedDevicePreferences {
    private static var deviceDefaults: UserDefaults { .standard }

    /// The name of the app's own preferences domain: the host app's bundle identifier.
    private static var domainName: String? { Bundle.main.bundleIdentifier }

    /// The device's value for `key`, nil when none was saved.
    static func value(forKey key: String) -> Any? {
        deviceDefaults.object(forKey: key)
    }

    /// Sets `value` for `key`, and returns what puts the device's own value back.
    static func set(_ value: Any, forKey key: String) -> () -> Void {
        let restore = saving([key])
        deviceDefaults.set(value, forKey: key)
        return restore
    }

    /// Returns what puts the device's values for `keys`, as they are now, back: a value saved, or none.
    static func saving(_ keys: [String]) -> () -> Void {
        let savedValues = keys.map { key in (key: key, value: deviceDefaults.object(forKey: key)) }
        return {
            for saved in savedValues {
                if let value = saved.value { deviceDefaults.set(value, forKey: saved.key) } else { deviceDefaults.removeObject(forKey: saved.key) }
            }
        }
    }

    /// Removes the device's value for `key`.
    static func remove(forKey key: String) {
        deviceDefaults.removeObject(forKey: key)
    }

    /// Every key of the app's own preferences domain as it is now, the system's keys kept there too (UIKit's split
    /// view state, PencilKit's palette); nil where the domain has no name.
    static func snapshotOfTheWholeDomain() -> [String: Any]? {
        guard let domainName else { return nil }
        return deviceDefaults.persistentDomain(forName: domainName) ?? [:]
    }

    /// Puts the domain back exactly as `snapshot` held it: changed keys get their values back, added keys go.
    static func restoreTheWholeDomain(_ snapshot: [String: Any]) {
        guard let domainName else { return }
        deviceDefaults.setPersistentDomain(snapshot, forName: domainName)
    }
}

/// The hosted test bundle's principal class (`NSPrincipalClass` of GraphiteIntegrationTests): it watches every test
/// suite and puts the app's preferences back as they were when the suite began. The device run of 2026-11-05 left ten
/// of the owner's keys changed (the toolbox, the toolbar style, the lasso's shape, UIKit's split view state among
/// them), set by tests and by the views they hosted; no test can leave them changed now, whatever it touches.
@MainActor
final class HostedPreferencesGuard: NSObject, @preconcurrency XCTestObservation {
    /// The snapshots of the suites under way, the innermost last.
    private var snapshotsOfSuitesUnderWay: [[String: Any]?] = []
    /// Whether the guard watches this run's suites: the hosted test of the guard checks it.
    private(set) static var isWatchingTestSuites = false

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
        Self.isWatchingTestSuites = true
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        snapshotsOfSuitesUnderWay.append(HostedDevicePreferences.snapshotOfTheWholeDomain())
    }

    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        guard let snapshot = snapshotsOfSuitesUnderWay.popLast() else { return }
        if let snapshot { HostedDevicePreferences.restoreTheWholeDomain(snapshot) }
    }
}

/// The guard's own check: keys a test changes, removes and adds are put back exactly by the restore the guard runs
/// when each test class ends, and the guard is installed for the run.
final class HostedPreferencesGuardTests: XCTestCase {
    @MainActor
    func testTheWholeDomainIsPutBackExactlyChangedRemovedAndAddedKeysAlike() throws {
        XCTAssertTrue(HostedPreferencesGuard.isWatchingTestSuites, "The bundle's principal class watches every test class.")
        let changedKey = "GraphitePreferencesGuardTest.changed"
        let removedKey = "GraphitePreferencesGuardTest.removed"
        let addedKey = "GraphitePreferencesGuardTest.added"
        _ = HostedDevicePreferences.set("before", forKey: changedKey)
        _ = HostedDevicePreferences.set(7, forKey: removedKey)
        HostedDevicePreferences.remove(forKey: addedKey)
        defer { for key in [changedKey, removedKey, addedKey] { HostedDevicePreferences.remove(forKey: key) } }
        let snapshot = try XCTUnwrap(HostedDevicePreferences.snapshotOfTheWholeDomain())
        _ = HostedDevicePreferences.set("after", forKey: changedKey)
        HostedDevicePreferences.remove(forKey: removedKey)
        _ = HostedDevicePreferences.set(true, forKey: addedKey)
        HostedDevicePreferences.restoreTheWholeDomain(snapshot)
        XCTAssertEqual(HostedDevicePreferences.value(forKey: changedKey) as? String, "before", "A changed key gets its value back.")
        XCTAssertEqual(HostedDevicePreferences.value(forKey: removedKey) as? Int, 7, "A removed key comes back.")
        XCTAssertNil(HostedDevicePreferences.value(forKey: addedKey), "An added key goes.")
        let restored = try XCTUnwrap(HostedDevicePreferences.snapshotOfTheWholeDomain())
        XCTAssertEqual(Set(restored.keys), Set(snapshot.keys), "Every key, and no other, is as the snapshot held it.")
    }
}
