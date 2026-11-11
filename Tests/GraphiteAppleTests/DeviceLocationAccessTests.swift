/**
 * File: DeviceLocationAccessTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: How the system's answers about location access read for the maps' location control.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
import CoreLocation
@testable import GraphiteApple

final class DeviceLocationAccessTests: XCTestCase {
    func testEverySystemAnswerReadsAsOneAccess() {
        XCTAssertEqual(LiveDeviceLocation.access(of: .notDetermined), .notAsked, "Only a never-answered question is asked.")
        #if os(iOS)
        XCTAssertEqual(LiveDeviceLocation.access(of: .authorizedWhenInUse), .granted)
        #endif
        XCTAssertEqual(LiveDeviceLocation.access(of: .authorizedAlways), .granted, "The Mac answers with always for an app it lets in.")
        XCTAssertEqual(LiveDeviceLocation.access(of: .denied), .refused)
        XCTAssertEqual(LiveDeviceLocation.access(of: .restricted), .restricted)
    }
}
