/**
 * File: HostedDevicePreferences.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The app's own preferences a hosted test changes, set for the test and put back as the device had
 *              them: on a person's iPad the hosted tests run in their own app, with their own settings.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

#if os(iOS)
import Foundation

/// The app's standard preferences, which its views read and a hosted test cannot give an isolated suite. The first
/// run on the owner's iPad (2026-11-04) met his own settings (the even highlighter, his toolbar style), and tests
/// that removed a preference after changing it left his settings without it.
enum HostedDevicePreferences {
    private static var deviceDefaults: UserDefaults { .standard }

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
}
#endif
