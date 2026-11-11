/**
 * File: MapUserLocationHostedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The maps' "my location" control in the app: MapKit's own control on every map, nothing asked before
 *              it is used, following the person once allowed, the explanation after a refusal, where a Bases map
 *              without markers opens, and the vault map framing every placed note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import MapKit
import GraphiteCore
import GraphiteApple
import GraphiteIndex
@testable import GraphiteUI

/// The device's location is always `AnsweringDeviceLocation`, so these tests never ask the real
/// location service and never show its question. Using the control is MapKit's report of a
/// tracking mode chosen with its button (`mapView(_:didChange:animated:)`), as a tap would make it.
@MainActor
final class MapUserLocationHostedTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        try await super.tearDown()
    }

    private static let placedNotes = [
        "Paris.md": "---\ncoordinates: [48.8566, 2.3522]\n---\n# Paris\nOn the way to [[Lausanne]].\n",
        "Lausanne.md": "---\ncoordinates: \"46.5197, 6.6323\"\n---\n# Lausanne\n",
        "Rome.md": "---\ncoordinates: [41.9028, 12.4964]\n---\n# Rome\n",
        "New York.md": "---\ncoordinates: [40.7128, -74.006]\n---\n# New York\n",
    ]
    private static let lausanne = CLLocationCoordinate2D(latitude: 46.5197, longitude: 6.6323)
    private static let rome = CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964)

    // MARK: The control on every map

    func testEveryMapOffersMapKitsLocationControlAndAsksNothingBeforeItIsUsed() async throws {
        let location = AnsweringDeviceLocation(access: .notAsked, answer: .granted, position: nil)
        let workspace = try await makeWorkspace()

        let vaultMap = try await mapView(in: host(VaultMapScreen(workspace: workspace).environment(\.deviceLocation, location)))
        try await waitUntil("the vault map's notes") { Self.notePaths(on: vaultMap).count == 4 }
        assertOffersTheControlAndShowsNoPerson(vaultMap, "the vault map")

        let store = try XCTUnwrap(workspace.store)
        let parisPath = try VaultPath("Paris.md")
        let session = try MarkdownSession(path: parisPath, snapshot: try await store.read(parisPath), store: store, didSave: { _ in })
        let localMap = try await mapView(in: host(LocalMapPanel(session: session, workspace: workspace).environment(\.deviceLocation, location)))
        try await waitUntil("the local map's notes") { Self.notePaths(on: localMap).count == 2 }
        assertOffersTheControlAndShowsNoPerson(localMap, "the sidebar's map")

        let index = try XCTUnwrap(workspace.index)
        let baseMap = try await mapView(in: host(baseView("Places.base", store: store, index: index).environment(\.deviceLocation, location)))
        assertOffersTheControlAndShowsNoPerson(baseMap, "a base's Apple map")

        let tiledMap = try await mapView(in: host(tiledMapView(location: location, control: MapUserLocationControl())))
        assertOffersTheControlAndShowsNoPerson(tiledMap, "a base's map over tiles")

        XCTAssertFalse(location.wasAskedAnything, "Showing four maps asks nothing of the device's location.")
        let withoutLocation = try await mapView(in: host(VaultMapScreen(workspace: workspace)))
        XCTAssertFalse(withoutLocation.showsUserTrackingButton, "No location to ask, no control.")
    }

    // MARK: Using it

    func testTheFirstUseAsksOnceThenShowsAndFollowsThePersonAndShowAllFramesTheNotesAgain() async throws {
        let location = AnsweringDeviceLocation(access: .notAsked, answer: .granted, position: nil)
        let harness = NotesMapHarness(location: location, notes: try Self.placedNoteValues())
        let mapView = try await mapView(in: host(NotesMapHarnessView(harness: harness)))
        try await waitUntil("the notes framed") { Self.notePaths(on: mapView).count == 4 && Self.framesEveryNote(mapView) }

        let coordinator = try XCTUnwrap(mapView.delegate as? NotesMapView.Coordinator)
        coordinator.mapView(mapView, didChange: .follow, animated: false)
        try await waitUntil("the person shown") { mapView.showsUserLocation }
        XCTAssertEqual(location.accessRequestCount, 1, "The first use asks.")
        XCTAssertEqual(mapView.userTrackingMode, .follow, "Once allowed, the map follows the person.")
        XCTAssertTrue(harness.control.showsPerson)
        XCTAssertNil(harness.control.refusal)

        coordinator.mapView(mapView, didChange: .followWithHeading, animated: false)
        try await waitUntil("the second use answered") { location.accessReadCount >= 3 }
        XCTAssertEqual(location.accessRequestCount, 1, "Access granted once is not asked again.")

        mapView.setRegion(MKCoordinateRegion(center: Self.lausanne, latitudinalMeters: 2_000, longitudinalMeters: 2_000), animated: false)
        harness.fitRequest += 1
        try await waitUntil("Show All framing the notes again") { Self.framesEveryNote(mapView) }
        XCTAssertEqual(mapView.userTrackingMode, .none, "Show All stops following the person, so the notes stay framed.")
    }

    func testARefusalExplainsHowToTurnAccessOnAndTheMapKeepsWorking() async throws {
        let location = AnsweringDeviceLocation(access: .notAsked, answer: .refused, position: nil)
        let harness = NotesMapHarness(location: location, notes: try Self.placedNoteValues())
        let controller = try host(NotesMapHarnessView(harness: harness))
        let mapView = try await mapView(in: controller)
        try await waitUntil("the notes on the map") { Self.notePaths(on: mapView).count == 4 }

        let coordinator = try XCTUnwrap(mapView.delegate as? NotesMapView.Coordinator)
        coordinator.mapView(mapView, didChange: .follow, animated: false)
        try await waitUntil("the refusal explained") { harness.control.refusal == .refused }
        XCTAssertEqual(location.accessRequestCount, 1)
        XCTAssertFalse(mapView.showsUserLocation, "Refused, the map does not try to show the person.")
        XCTAssertEqual(mapView.userTrackingMode, .none)
        attachScreenshot(of: controller, named: "Map with the notice after location access was refused")

        let newYork = try XCTUnwrap(mapView.annotations.first { annotation in (annotation as? PlacedNoteAnnotation)?.path.rawValue == "New York.md" })
        mapView.selectAnnotation(newYork, animated: false)
        try await waitUntil("a marker still opening its note") { harness.openedPaths.map(\.rawValue) == ["New York.md"] }
    }

    /// A base's Apple map is SwiftUI's `Map`, whose location button is the map view's own: choosing
    /// it moves the camera to the person, which asks for access the first time. Over tiles, the map
    /// is MapKit's map view, as on the map screens.
    func testUsingTheControlOfABasesMapsAsksOnceAndARefusalLeavesTheMapAsItWas() async throws {
        let workspace = try await makeWorkspace()
        let (store, index) = (try XCTUnwrap(workspace.store), try XCTUnwrap(workspace.index))
        let appleMapLocation = AnsweringDeviceLocation(access: .notAsked, answer: .refused, position: nil)
        let appleMap = try await mapView(in: host(baseView("Places.base", store: store, index: index).environment(\.deviceLocation, appleMapLocation)))
        appleMap.setUserTrackingMode(.follow, animated: false)
        try await waitUntil("the Apple map's question") { appleMapLocation.accessRequestCount == 1 }
        try await waitUntil("the Apple map no longer following") { appleMap.userTrackingMode == .none }

        let tiledLocation = AnsweringDeviceLocation(access: .notAsked, answer: .refused, position: nil)
        let tiledControl = MapUserLocationControl()
        let tiledMap = try await mapView(in: host(tiledMapView(location: tiledLocation, control: tiledControl)))
        let coordinator = try XCTUnwrap(tiledMap.delegate as? BaseTiledMapView.Coordinator)
        coordinator.mapView(tiledMap, didChange: .follow, animated: false)
        try await waitUntil("the tiled map's refusal") { tiledControl.refusal == .refused }
        XCTAssertEqual(tiledLocation.accessRequestCount, 1)
        XCTAssertFalse(tiledMap.showsUserLocation)
    }

    // MARK: Where a base's map opens without markers

    func testABaseMapWithoutMarkersOpensOnThePersonOnlyWhenAccessWasGrantedElseOnTheVaultsNotes() async throws {
        let workspace = try await makeWorkspace(extraFiles: [
            "Rome trip.md": "---\ncoordinates: \"41.8902, 12.4922\"\n---\n",
            "Trips.base": "filters: file.inFolder(\"Trips\")\nviews:\n  - type: map\n    name: Trips\n    coordinates: note.coordinates\n",
        ])
        let (store, index) = (try XCTUnwrap(workspace.store), try XCTUnwrap(workspace.index))

        let granted = AnsweringDeviceLocation(access: .granted, answer: .granted, position: BaseCoordinate(latitude: 46.5197, longitude: 6.6323))
        let personMap = try await mapView(in: host(baseView("Trips.base", store: store, index: index).environment(\.deviceLocation, granted)))
        try await waitUntil("the map on the person") { Self.distanceInDegrees(personMap.centerCoordinate, Self.lausanne) < 0.05 }
        XCTAssertEqual(granted.accessRequestCount, 0, "Opening on the person asks nothing.")
        XCTAssertFalse(personMap.showsUserLocation, "Opening on the last known position starts no location updates.")

        let neverAsked = AnsweringDeviceLocation(access: .notAsked, answer: .granted, position: BaseCoordinate(latitude: 46.5197, longitude: 6.6323))
        let notesMap = try await mapView(in: host(baseView("Trips.base", store: store, index: index).environment(\.deviceLocation, neverAsked)))
        // Paris, Lausanne, Rome, New York and the Rome trip, all in sight, far from 0, 0.
        try await waitUntil("the map on the vault's notes") { Self.framesEveryNote(notesMap, coordinates: Self.vaultCoordinates) }
        XCTAssertGreaterThan(Self.distanceInDegrees(notesMap.centerCoordinate, CLLocationCoordinate2D(latitude: 0, longitude: 0)), 10)
        XCTAssertEqual(neverAsked.accessRequestCount, 0, "Without access the map opens on the notes and asks nothing.")
    }

    // MARK: The vault map

    /// The owner's "ça se focalise pas" may also have meant the notes: the vault map frames every one.
    func testTheVaultMapFramesEveryPlacedNoteWhenItOpens() async throws {
        let workspace = try await makeWorkspace()
        let mapView = try await mapView(in: host(VaultMapScreen(workspace: workspace)))
        try await waitUntil("every note in sight") { Self.notePaths(on: mapView).count == 4 && Self.framesEveryNote(mapView) }
    }

    // MARK: Helpers

    private func assertOffersTheControlAndShowsNoPerson(_ mapView: MKMapView, _ mapName: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(mapView.showsUserTrackingButton, "\(mapName) offers MapKit's location control.", file: file, line: line)
        XCTAssertFalse(mapView.showsUserLocation, "\(mapName) shows no person before the control is used.", file: file, line: line)
        XCTAssertEqual(mapView.userTrackingMode, .none, mapName, file: file, line: line)
    }

    private static let vaultCoordinates = [
        CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), lausanne, rome,
        CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.006), CLLocationCoordinate2D(latitude: 41.8902, longitude: 12.4922),
    ]

    private static func placedNoteValues() throws -> [PlacedNote] {
        let places: [(String, Double, Double)] = [("Paris.md", 48.8566, 2.3522), ("Lausanne.md", 46.5197, 6.6323), ("Rome.md", 41.9028, 12.4964),
                                                  ("New York.md", 40.7128, -74.006)]
        return try places.map { path, latitude, longitude in
            PlacedNote(path: try VaultPath(path), coordinate: try XCTUnwrap(BaseCoordinate(latitude: latitude, longitude: longitude)))
        }
    }

    private static func notePaths(on mapView: MKMapView) -> [String] {
        mapView.annotations.compactMap { annotation in (annotation as? PlacedNoteAnnotation)?.path.rawValue }.sorted()
    }

    private static func framesEveryNote(_ mapView: MKMapView) -> Bool {
        let coordinates = mapView.annotations.compactMap { annotation in (annotation as? PlacedNoteAnnotation)?.coordinate }
        return !coordinates.isEmpty && framesEveryNote(mapView, coordinates: coordinates)
    }

    private static func framesEveryNote(_ mapView: MKMapView, coordinates: [CLLocationCoordinate2D]) -> Bool {
        coordinates.allSatisfy { coordinate in mapView.visibleMapRect.contains(MKMapPoint(coordinate)) }
    }

    private static func distanceInDegrees(_ first: CLLocationCoordinate2D, _ second: CLLocationCoordinate2D) -> Double {
        hypot(first.latitude - second.latitude, first.longitude - second.longitude)
    }

    private func makeWorkspace(extraFiles: [String: String] = [:]) async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "MapUserLocation", for: self).root
        for (name, text) in Self.placedNotes.merging(extraFiles, uniquingKeysWith: { first, _ in first }) {
            let fileURL = vault.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: fileURL)
        }
        let places = "filters: file.hasProperty(\"coordinates\")\nviews:\n  - type: map\n    name: Places\n    coordinates: note.coordinates\n"
        try Data(places.utf8).write(to: vault.appendingPathComponent("Places.base"))
        let index = try VaultIndex(databaseURL: try TemporaryVault.make(prefix: "MapUserLocationIndex", for: self).root.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        await workspace.refreshDirectory()
        return workspace
    }

    private func baseView(_ basePath: String, store: VaultStore, index: VaultIndex) throws -> BaseContainerView {
        let path = try VaultPath(basePath)
        return BaseContainerView(source: .file(path), contextPath: path, preferredViewName: nil, store: store, index: index, contentVersion: 1,
                                 isIndexComplete: true, presentation: .document, open: { _ in }, openBase: { _, _ in }, filesChanged: { _ in })
    }

    private func tiledMapView(location: AnsweringDeviceLocation, control: MapUserLocationControl) throws -> BaseTiledMapView {
        let template = try XCTUnwrap(BaseMapTileTemplate("https://tiles.graphite.test/{z}/{x}/{y}.png"))
        let configuration = URLSessionConfiguration.ephemeral
        // No tile is fetched: every request fails at once, offline.
        configuration.protocolClasses = [RefusingTileProtocol.self]
        return BaseTiledMapView(
            tileTemplates: [template],
            annotations: [BaseMapMarkerAnnotation(path: try VaultPath("Lausanne.md"), coordinate: Self.lausanne, title: "Lausanne")],
            cameraTarget: .fittingMarkers, cameraConfiguration: 1, cameraLayout: 1, cameraDistances: 100...10_000_000,
            selectedPath: .constant(nil), pinImage: { _, _ in nil }, locationControl: control, deviceLocation: location,
            tileSession: URLSession(configuration: configuration))
    }

    private func host(_ rootView: some View) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(rootView))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        return controller
    }

    private func mapView(in controller: UIViewController) async throws -> MKMapView {
        var mapView: MKMapView?
        try await waitUntil("a map view laid out") {
            mapView = Self.firstMapView(in: controller.view)
            return (mapView?.bounds.width ?? 0) > 0
        }
        return try XCTUnwrap(mapView)
    }

    private static func firstMapView(in view: UIView) -> MKMapView? {
        if let mapView = view as? MKMapView { return mapView }
        return view.subviews.lazy.compactMap(firstMapView(in:)).first
    }

    private func attachScreenshot(of controller: UIViewController, named name: String) {
        guard let window = controller.view.window else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// What a test changes on a hosted `NotesMapView`: Show All's request, and the notes opened.
@MainActor @Observable
private final class NotesMapHarness {
    let location: AnsweringDeviceLocation
    let notes: [PlacedNote]
    let control = MapUserLocationControl()
    var fitRequest = 0
    var openedPaths: [VaultPath] = []

    init(location: AnsweringDeviceLocation, notes: [PlacedNote]) {
        self.location = location
        self.notes = notes
    }
}

/// A notes map as the map screens show it, with the refusal notice over it.
private struct NotesMapHarnessView: View {
    let harness: NotesMapHarness

    var body: some View {
        NotesMapView(notes: harness.notes, title: { path in path.stem }, highlightedPath: nil, accent: .blue,
                     open: { path in harness.openedPaths.append(path) }, fitRequest: harness.fitRequest,
                     locationControl: harness.control, deviceLocation: harness.location)
        .mapLocationRefusalNotice(of: harness.control)
    }
}

/// Fails every tile request without the network.
private final class RefusingTileProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
#endif
