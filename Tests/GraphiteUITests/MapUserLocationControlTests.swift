/**
 * File: MapUserLocationControlTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The maps' location control asks for access only when used, and a Bases map without markers opens on
 *              the person, the vault's notes or MapKit's own region, never on latitude 0, longitude 0.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
import MapKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MapUserLocationControlTests: XCTestCase {
    private var lausanne: BaseCoordinate {
        get throws { try XCTUnwrap(BaseCoordinate(latitude: 46.5197, longitude: 6.6323)) }
    }
    private let mapSize = CGSize(width: 600, height: 400)

    // MARK: The control

    func testTheFirstUseAsksOnceAndTheNextUsesDoNotAskAgain() async throws {
        let location = AnsweringDeviceLocation(access: .notAsked, answer: .granted, position: try lausanne)
        let control = MapUserLocationControl()
        XCTAssertFalse(location.wasAskedAnything, "Making the control asks nothing.")
        XCTAssertFalse(control.showsPerson)

        let firstUse = await control.controlWasUsed(with: location)
        XCTAssertEqual(firstUse, .justAllowed)
        XCTAssertEqual(location.accessRequestCount, 1)
        XCTAssertTrue(control.showsPerson, "Once allowed, the map shows the person.")

        let secondUse = await control.controlWasUsed(with: location)
        XCTAssertEqual(secondUse, .alreadyAllowed, "MapKit follows the person by itself once access was granted.")
        XCTAssertEqual(location.accessRequestCount, 1, "The question is asked once.")
        XCTAssertNil(control.refusal)
    }

    func testARefusalExplainsHowToTurnAccessOnAndCanBeClosed() async throws {
        let location = AnsweringDeviceLocation(access: .notAsked, answer: .refused, position: try lausanne)
        let control = MapUserLocationControl()

        let use = await control.controlWasUsed(with: location)
        XCTAssertEqual(use, .refused(.refused))
        XCTAssertEqual(control.refusal, .refused)
        XCTAssertFalse(control.showsPerson)
        XCTAssertTrue(MapLocationRefusal.refused.message.contains("Settings"), "The notice says where access is turned on.")
        XCTAssertNotNil(MapLocationRefusal.refused.settingsURL)

        // Asked again later: the answer stands and the notice comes back, without a second question.
        control.dismissRefusal()
        XCTAssertNil(control.refusal)
        let laterUse = await control.controlWasUsed(with: location)
        XCTAssertEqual(laterUse, .refused(.refused))
        XCTAssertEqual(location.accessRequestCount, 1)
        XCTAssertEqual(control.refusal, .refused)
    }

    func testARestrictedDeviceIsNotSentToSettings() async throws {
        let location = AnsweringDeviceLocation(access: .restricted, answer: .restricted, position: nil)
        let control = MapUserLocationControl()

        let use = await control.controlWasUsed(with: location)
        XCTAssertEqual(use, .refused(.restricted))
        XCTAssertEqual(location.accessRequestCount, 0, "Nothing is asked of a device that decides for the person.")
        XCTAssertNil(MapLocationRefusal.restricted.settingsURL, "The person cannot turn it on there.")
    }

    // MARK: Where a Bases map opens

    func testAMapWithoutMarkersOpensOnThePersonWhenTheirPositionIsKnown() throws {
        let target = BaseMapCameraTarget.forView(center: nil, defaultZoom: nil, markerCoordinates: [], opening: .person(try lausanne), size: mapSize)
        guard case .region(let region) = target else { return XCTFail("A known position places the camera: \(target)") }
        XCTAssertEqual(region.center.latitude, try lausanne.latitude, accuracy: 0.000_001)
        XCTAssertEqual(region.center.longitude, try lausanne.longitude, accuracy: 0.000_001)
        XCTAssertLessThan(region.span.latitudeDelta, 1, "A town, not a continent, is shown around the person.")
    }

    func testAMapWithoutMarkersOrPositionOpensOnTheVaultsNotes() throws {
        let tokyo = try XCTUnwrap(BaseCoordinate(latitude: 35.6762, longitude: 139.6503))
        let paris = try XCTUnwrap(BaseCoordinate(latitude: 48.8566, longitude: 2.3522))
        let target = BaseMapCameraTarget.forView(center: nil, defaultZoom: nil, markerCoordinates: [], opening: .vaultPlaces([tokyo, paris]), size: mapSize)
        guard case .region(let region) = target else { return XCTFail("The vault's notes place the camera: \(target)") }
        for place in [tokyo, paris] {
            XCTAssertLessThanOrEqual(abs(place.latitude - region.center.latitude), region.span.latitudeDelta / 2, "\(place)")
            XCTAssertLessThanOrEqual(abs(place.longitude - region.center.longitude), region.span.longitudeDelta / 2, "\(place)")
        }
    }

    func testAMapWithNothingToOpenOnLeavesItToMapKitRatherThanTheAtlantic() {
        for opening in [BaseMapOpening.nothingKnown, nil] {
            let target = BaseMapCameraTarget.forView(center: nil, defaultZoom: nil, markerCoordinates: [], opening: opening, size: mapSize)
            XCTAssertEqual(target, .mapKitOpening, "Not latitude 0, longitude 0 (\(String(describing: opening))).")
        }
    }

    func testMarkersAndAConfiguredCenterStillComeBeforeThePerson() throws {
        let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        XCTAssertEqual(BaseMapCameraTarget.forView(center: nil, defaultZoom: nil, markerCoordinates: [paris], opening: .person(try lausanne), size: mapSize),
                       .fittingMarkers)
        let center = try XCTUnwrap(BaseCoordinate(latitude: 40.7128, longitude: -74.006))
        let target = BaseMapCameraTarget.forView(center: center, defaultZoom: 10, markerCoordinates: [], opening: .person(try lausanne), size: mapSize)
        guard case .region(let region) = target else { return XCTFail("The configured center places the camera: \(target)") }
        XCTAssertEqual(region.center.latitude, center.latitude, accuracy: 0.000_001)
    }
}
