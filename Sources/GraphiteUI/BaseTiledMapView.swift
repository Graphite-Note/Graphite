/**
 * File: BaseTiledMapView.swift
 * ----------------------------
 * Layer: UI
 * Description: A Bases map drawn over raster tiles in MapKit's map view, and what the MapKit maps share: the map
 *              view that reports its layout, and MapKit's own location control.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 11/11/2026
 */

import SwiftUI
import MapKit
import GraphiteCore
import GraphiteApple
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Raster tiles from one template of a map view's `mapTiles`. A tile is fetched only from
/// the address the template names, with a session that keeps no cookies, credentials or
/// disk cache, and a response larger than `maximumTileBytes` is refused.
final class BaseMapTileOverlay: MKTileOverlay {
    /// A 256-point tile at twice the scale is well under a megabyte; anything far larger
    /// is not a map tile.
    static let maximumTileBytes = 4 * 1_048_576
    /// The Maps plugin gives MapLibre 256-point tiles.
    private static let tileSide: CGFloat = 256

    let tileTemplate: BaseMapTileTemplate
    private let session: URLSession

    init(tileTemplate: BaseMapTileTemplate, session: URLSession = BaseMapTileOverlay.tileSession) {
        self.tileTemplate = tileTemplate
        self.session = session
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: Self.tileSide, height: Self.tileSide)
    }

    /// Shared by every tiled map, so tiles seen once stay in memory while the app runs.
    static let tileSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1_048_576, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        let deliver = TileResultHandler(result)
        guard let tileURL = tileTemplate.url(column: path.x, row: path.y, zoom: path.z, scale: Double(path.contentScaleFactor)) else {
            deliver(nil, GraphiteError.invalidFile("This map tile has no web address."))
            return
        }
        let session = session
        Task.detached(priority: .utility) {
            do { deliver(try await Self.tileData(at: tileURL, session: session), nil) } catch { deliver(nil, error) }
        }
    }

    static func tileData(at tileURL: URL, session: URLSession) async throws -> Data {
        let tooLargeError = GraphiteError.oversized("This map tile is larger than \(maximumTileBytes / 1_048_576) MB.")
        let (bytes, response) = try await session.bytes(from: tileURL)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw GraphiteError.unavailable("The map tile could not be downloaded (HTTP \(httpResponse.statusCode)).")
        }
        guard response.expectedContentLength <= Int64(maximumTileBytes) else { throw tooLargeError }
        var tileData = Data()
        for try await byte in bytes {
            tileData.append(byte)
            guard tileData.count <= maximumTileBytes else { throw tooLargeError }
        }
        return tileData
    }
}

/// MapKit's handler for one tile. MapKit accepts it from any thread, and each handler is
/// called exactly once, so it can cross to the task that downloads the tile.
private struct TileResultHandler: @unchecked Sendable {
    private let handler: (Data?, (any Error)?) -> Void
    init(_ handler: @escaping (Data?, (any Error)?) -> Void) { self.handler = handler }
    func callAsFunction(_ tileData: Data?, _ error: (any Error)?) { handler(tileData, error) }
}

/// One marker of a map with custom tiles.
final class BaseMapMarkerAnnotation: NSObject, MKAnnotation {
    let path: VaultPath
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(path: VaultPath, coordinate: CLLocationCoordinate2D, title: String) {
        self.path = path
        self.coordinate = coordinate
        self.title = title
    }
}

/// MapKit's map view, telling its coordinator when it is laid out: SwiftUI can update the
/// map before it has a size, and the camera is placed once it has one.
final class BaseLaidOutMapView: MKMapView {
    var didLayOut: (() -> Void)?

    #if canImport(UIKit)
    override func layoutSubviews() {
        super.layoutSubviews()
        didLayOut?()
    }
    #else
    override func layout() {
        super.layout()
        didLayOut?()
    }
    #endif
}

/// MapKit's own location control on a MapKit map view (`NotesMapView`, `BaseTiledMapView`): the
/// map view's tracking button on the iPad, the iPhone and the Mac. MapKit asks for no access
/// itself, so the first use of the button asks through `MapUserLocationControl`; until then the map
/// neither shows nor follows the person, and nothing about location runs.
@MainActor
enum MapUserTracking {
    static func offerControl(on mapView: MKMapView, isOffered: Bool) {
        if mapView.showsUserTrackingButton != isOffered { mapView.showsUserTrackingButton = isOffered }
    }

    /// The person changed how the map follows them with the button: the first time, access is
    /// asked; once granted the map shows and follows them; refused, it stops trying and the
    /// control explains how to turn access on.
    static func trackingModeChanged(on mapView: MKMapView, to mode: MKUserTrackingMode, control: MapUserLocationControl,
                                    location: (any DeviceLocation)?) {
        guard mode != .none, let location else { return }
        Task { [weak mapView] in
            let use = await control.controlWasUsed(with: location)
            guard let mapView else { return }
            switch use {
            case .alreadyAllowed:
                break
            case .justAllowed:
                mapView.showsUserLocation = true
                mapView.setUserTrackingMode(.follow, animated: true)
            case .refused:
                mapView.setUserTrackingMode(.none, animated: false)
            }
        }
    }

    /// Lets a camera placed by Graphite (Show All, a base's view) stay rather than follow the person.
    static func stopFollowingThePerson(on mapView: MKMapView) {
        if mapView.userTrackingMode != .none { mapView.setUserTrackingMode(.none, animated: false) }
    }

    /// The map's annotations other than the person's own position, which MapKit keeps.
    static func annotationsBesidesThePerson(on mapView: MKMapView) -> [any MKAnnotation] {
        mapView.annotations.filter { annotation in !(annotation is MKUserLocation) }
    }
}

/// Where a tiled map's camera goes: a region, around every marker, or, with nothing to show,
/// where MapKit opens a map (around the device's country), never latitude 0, longitude 0.
enum BaseMapCameraTarget: Equatable {
    case region(MKCoordinateRegion)
    case fittingMarkers
    case mapKitOpening

    static func == (leftTarget: BaseMapCameraTarget, rightTarget: BaseMapCameraTarget) -> Bool {
        switch (leftTarget, rightTarget) {
        case (.fittingMarkers, .fittingMarkers), (.mapKitOpening, .mapKitOpening): true
        case (.region(let leftRegion), .region(let rightRegion)):
            leftRegion.center.latitude == rightRegion.center.latitude && leftRegion.center.longitude == rightRegion.center.longitude
                && leftRegion.span.latitudeDelta == rightRegion.span.latitudeDelta && leftRegion.span.longitudeDelta == rightRegion.span.longitudeDelta
        default: false
        }
    }
}

/// Where a Bases map view's camera goes (`BaseMapView`, `BaseTiledMapView`).
@MainActor
extension BaseMapCameraTarget {
    /// The zoom a map without markers opens at on the person's position: a town and its surroundings.
    static let personPositionZoom = 12.0

    /// The configured center at the configured zoom, the markers' middle at the configured
    /// zoom, or, like the plugin without a center and zoom, every marker in sight. Without
    /// markers: the person's position, else the vault's placed notes, else MapKit's own opening
    /// region; never latitude 0, longitude 0, in the Atlantic.
    static func forView(center: BaseCoordinate?, defaultZoom: Double?, markerCoordinates: [CLLocationCoordinate2D], opening: BaseMapOpening?,
                        size: CGSize) -> BaseMapCameraTarget {
        if let center {
            return .region(BaseMapView.region(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                                              zoom: defaultZoom ?? BaseMapOptions.defaultZoom, size: size))
        } else if !markerCoordinates.isEmpty {
            guard let defaultZoom else { return .fittingMarkers }
            return .region(BaseMapView.region(center: BaseMapView.centerCoordinate(of: markerCoordinates), zoom: defaultZoom, size: size))
        }
        switch opening {
        case .person(let position)?:
            return .region(BaseMapView.region(center: CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude),
                                              zoom: defaultZoom ?? personPositionZoom, size: size))
        case .vaultPlaces(let places)?:
            return .region(region(fitting: places.map { place in CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude) }))
        case .nothingKnown?, nil:
            return .mapKitOpening
        }
    }

    /// Room around the vault's places, so the markers nearest the edges stay in sight.
    private static let fittingMargin = 1.3
    /// The smallest span shown around places that are all close together, in degrees: a town.
    private static let minimumFittingDelta: CLLocationDegrees = 0.05

    /// A region showing every coordinate, with a margin.
    static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let rectangle = coordinates.reduce(MKMapRect.null) { rectangle, coordinate in
            rectangle.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        let fitted = MKCoordinateRegion(rectangle)
        return MKCoordinateRegion(center: fitted.center, span: MKCoordinateSpan(
            latitudeDelta: min(max(fitted.span.latitudeDelta * fittingMargin, minimumFittingDelta), BaseMapView.maximumLatitudeDelta),
            longitudeDelta: min(max(fitted.span.longitudeDelta * fittingMargin, minimumFittingDelta), BaseMapView.maximumLongitudeDelta)))
    }
}

/// What a Bases map with no markers and no configured center opens on.
enum BaseMapOpening: Hashable {
    /// The person's last known position, when they let Graphite use it before.
    case person(BaseCoordinate)
    /// The vault's placed notes, never empty.
    case vaultPlaces([BaseCoordinate])
    /// Neither: MapKit's own opening region.
    case nothingKnown
}

/// A map whose background is raster tiles from the base's `mapTiles`. SwiftUI's `Map`
/// draws only Apple's maps, so this one wraps MapKit's map view, which takes tile
/// overlays. The first template replaces Apple's map, so none of it is loaded; later ones
/// are drawn over it, as the plugin layers them. Markers look and select as in
/// `BaseMapView`, which shows the selected marker's callout.
@MainActor
struct BaseTiledMapView {
    let tileTemplates: [BaseMapTileTemplate]
    let annotations: [BaseMapMarkerAnnotation]
    let cameraTarget: BaseMapCameraTarget
    /// Changes with the view, its center or its zoom, which always place the camera again.
    let cameraConfiguration: AnyHashable
    /// Changes when markers move or the map is resized, which place the camera again only
    /// until the person moves the map, as in `BaseMapView`.
    let cameraLayout: Int
    /// The closest and farthest the camera may be, in meters, from `minZoom` and `maxZoom`.
    let cameraDistances: ClosedRange<CLLocationDistance>
    @Binding var selectedPath: VaultPath?
    /// The pin drawn for a marker, selected or not.
    let pinImage: (VaultPath, Bool) -> CGImage?
    /// What the location control decided, for the notice the base's map shows.
    let locationControl: MapUserLocationControl
    /// Nil shows no location control.
    let deviceLocation: (any DeviceLocation)?
    /// Fetches the tiles.
    var tileSession = BaseMapTileOverlay.tileSession

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: BaseTiledMapView
        var shownTemplates: [BaseMapTileTemplate] = []
        var shownAnnotationPaths: [VaultPath] = []
        var placedCameraConfiguration: AnyHashable?
        var placedCameraLayout: Int?
        var isPositionedByUser = false
        /// Set while the camera is placed from here, so only the person's moves count as theirs.
        var isPlacingCamera = false

        init(parent: BaseTiledMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let marker = annotation as? BaseMapMarkerAnnotation else { return nil }
            let reuseIdentifier = "BaseMapMarker"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) ?? MKAnnotationView(annotation: marker, reuseIdentifier: reuseIdentifier)
            annotationView.annotation = marker
            annotationView.canShowCallout = false
            setPin(of: annotationView, for: marker, isSelected: parent.selectedPath == marker.path)
            return annotationView
        }

        func mapView(_ mapView: MKMapView, didSelect annotationView: MKAnnotationView) {
            guard let marker = annotationView.annotation as? BaseMapMarkerAnnotation else { return }
            setPin(of: annotationView, for: marker, isSelected: true)
            if parent.selectedPath != marker.path { parent.selectedPath = marker.path }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotationView: MKAnnotationView) {
            guard let marker = annotationView.annotation as? BaseMapMarkerAnnotation else { return }
            setPin(of: annotationView, for: marker, isSelected: false)
            if parent.selectedPath == marker.path { parent.selectedPath = nil }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !isPlacingCamera { isPositionedByUser = true }
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            MapUserTracking.trackingModeChanged(on: mapView, to: mode, control: parent.locationControl, location: parent.deviceLocation)
        }

        private func setPin(of annotationView: MKAnnotationView, for marker: BaseMapMarkerAnnotation, isSelected: Bool) {
            guard let pinImage = parent.pinImage(marker.path, isSelected) else { return }
            #if canImport(UIKit)
            annotationView.image = UIImage(cgImage: pinImage, scale: annotationView.traitCollection.displayScale, orientation: .up)
            annotationView.accessibilityLabel = marker.title
            #else
            let scale = annotationView.window?.backingScaleFactor ?? 2
            annotationView.image = NSImage(cgImage: pinImage, size: CGSize(width: CGFloat(pinImage.width) / scale, height: CGFloat(pinImage.height) / scale))
            annotationView.setAccessibilityLabel(marker.title)
            #endif
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func makeMapView(context: Context) -> BaseLaidOutMapView {
        let mapView = BaseLaidOutMapView()
        mapView.delegate = context.coordinator
        let coordinator = context.coordinator
        mapView.didLayOut = { [weak mapView, weak coordinator] in
            guard let mapView, let coordinator else { return }
            coordinator.parent.placeCamera(on: mapView, coordinator: coordinator)
        }
        mapView.showsCompass = true
        #if canImport(UIKit)
        mapView.showsScale = true
        #endif
        MapUserTracking.offerControl(on: mapView, isOffered: deviceLocation != nil)
        return mapView
    }

    private func update(_ mapView: BaseLaidOutMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        MapUserTracking.offerControl(on: mapView, isOffered: deviceLocation != nil)
        if coordinator.shownTemplates != tileTemplates {
            mapView.removeOverlays(mapView.overlays)
            for (position, tileTemplate) in tileTemplates.enumerated() {
                let overlay = BaseMapTileOverlay(tileTemplate: tileTemplate, session: tileSession)
                overlay.canReplaceMapContent = position == 0
                mapView.addOverlay(overlay, level: .aboveLabels)
            }
            coordinator.shownTemplates = tileTemplates
        }
        if coordinator.shownAnnotationPaths != annotations.map(\.path) {
            mapView.removeAnnotations(MapUserTracking.annotationsBesidesThePerson(on: mapView))
            mapView.addAnnotations(annotations)
            coordinator.shownAnnotationPaths = annotations.map(\.path)
        }
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: cameraDistances.lowerBound,
                                                            maxCenterCoordinateDistance: cameraDistances.upperBound)
        // The markers on the map were made by an earlier update, so they are found by file.
        let isSelectionShown = mapView.selectedAnnotations.contains { annotation in (annotation as? BaseMapMarkerAnnotation)?.path == selectedPath }
        if !isSelectionShown {
            for annotation in mapView.selectedAnnotations { mapView.deselectAnnotation(annotation, animated: true) }
            if let selectedMarker = mapView.annotations.first(where: { annotation in selectedPath != nil && (annotation as? BaseMapMarkerAnnotation)?.path == selectedPath }) {
                mapView.selectAnnotation(selectedMarker, animated: true)
            }
        }
        placeCamera(on: mapView, coordinator: coordinator)
    }

    /// Places the camera when the configuration changed, or when the layout changed and
    /// the person has not moved the map. A map without a size yet waits for its layout.
    fileprivate func placeCamera(on mapView: MKMapView, coordinator: Coordinator) {
        guard mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
        let isNewConfiguration = coordinator.placedCameraConfiguration != cameraConfiguration
        guard isNewConfiguration || (coordinator.placedCameraLayout != cameraLayout && !coordinator.isPositionedByUser) else { return }
        coordinator.isPlacingCamera = true
        defer { coordinator.isPlacingCamera = false }
        MapUserTracking.stopFollowingThePerson(on: mapView)
        switch cameraTarget {
        case .region(let region): mapView.setRegion(region, animated: false)
        case .fittingMarkers:
            // The markers on the map, without the person's position.
            mapView.showAnnotations(mapView.annotations.filter { annotation in annotation is BaseMapMarkerAnnotation }, animated: false)
        case .mapKitOpening: break
        }
        coordinator.placedCameraConfiguration = cameraConfiguration
        coordinator.placedCameraLayout = cameraLayout
        if isNewConfiguration { coordinator.isPositionedByUser = false }
    }
}

#if canImport(UIKit)
extension BaseTiledMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> BaseLaidOutMapView { makeMapView(context: context) }
    func updateUIView(_ mapView: BaseLaidOutMapView, context: Context) { update(mapView, context: context) }
}
#else
extension BaseTiledMapView: NSViewRepresentable {
    func makeNSView(context: Context) -> BaseLaidOutMapView { makeMapView(context: context) }
    func updateNSView(_ mapView: BaseLaidOutMapView, context: Context) { update(mapView, context: context) }
}
#endif
