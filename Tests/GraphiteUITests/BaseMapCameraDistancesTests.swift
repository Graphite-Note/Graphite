/**
 * File: BaseMapCameraDistancesTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A Bases map's camera distances form a valid range at every zoom setting (HUNT-107).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import MapKit
@testable import GraphiteUI

final class BaseMapCameraDistancesTests: XCTestCase {
    /// At zoom 22 and a view 500 points high, both ends came to about 18.7 meters, so the range was
    /// 50...37 and forming it trapped as the map was shown.
    func testAHighMinimumAndMaximumZoomStillMakeARange() {
        let distances = BaseMapView.cameraDistances(for: CGSize(width: 400, height: 500), minimumZoom: 22, maximumZoom: 22)

        XCTAssertGreaterThanOrEqual(distances.lowerBound, 50, "The camera never gets nearer than 50 meters.")
        XCTAssertGreaterThan(distances.upperBound, distances.lowerBound)
    }

    func testEveryZoomSettingMakesAValidRange() {
        for minimumZoom in stride(from: 0.0, through: 24.0, by: 2) {
            for maximumZoom in stride(from: 0.0, through: 24.0, by: 2) {
                let distances = BaseMapView.cameraDistances(for: CGSize(width: 400, height: 500), minimumZoom: minimumZoom, maximumZoom: maximumZoom)
                XCTAssertLessThanOrEqual(distances.lowerBound, distances.upperBound, "minimum zoom \(minimumZoom), maximum zoom \(maximumZoom)")
                XCTAssertGreaterThanOrEqual(distances.lowerBound, 50)
            }
        }
    }

    func testTheDefaultZoomsKeepTheirRange() {
        let distances = BaseMapView.cameraDistances(for: CGSize(width: 400, height: 500), minimumZoom: 0, maximumZoom: 18)

        XCTAssertEqual(distances.lowerBound, 156_543.033_92 / 262_144 * 500, accuracy: 0.001)
        XCTAssertEqual(distances.upperBound, 156_543.033_92 * 500, accuracy: 0.001)
    }
}
