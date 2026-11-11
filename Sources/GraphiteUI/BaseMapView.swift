/**
 * File: BaseMapView.swift
 * -----------------------
 * Layer: UI
 * Description: The Maps plugin's map view of a base, drawn with MapKit: a marker per file with coordinates.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 11/11/2026
 */

import SwiftUI
import MapKit
import GraphiteCore
import GraphiteApple

/// The Maps plugin's `map` view, drawn with MapKit: one marker per file with
/// coordinates, colored and iconned from the configured properties. A background of
/// raster tiles from `mapTiles` is drawn by `BaseTiledMapView`; otherwise the map is
/// Apple's.
struct BaseMapView: View {
    /// Web-map ground resolution at zoom 0 on the equator, in meters per point.
    private static let metersPerPointAtZoomZero = 156_543.033_92

    let result: BaseQueryResult
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    let actions: BaseViewActions
    /// The vault's placed notes, which a map with no markers and no center opens on.
    let vaultPlaces: () async -> [BaseCoordinate]
    @Environment(\.deviceLocation) private var deviceLocation
    @State private var locationControl = MapUserLocationControl()
    /// What a map with no markers and no configured center opens on, once read.
    @State private var opening: BaseMapOpening?
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedPath: VaultPath?
    @State private var positionedCamera: CameraConfiguration?
    /// Worked out once per result, not again whenever a pin is selected.
    private let markers: [Marker]
    /// Changes when any marker moves, appears or disappears.
    private let markerLayoutSignature: Int

    private var options: BaseMapOptions { result.view.map }

    private struct Marker: Identifiable {
        let row: BaseResultRow
        let coordinate: CLLocationCoordinate2D
        let symbolName: String?
        var id: VaultPath { row.path }
    }

    /// The camera the base configures for a view.
    private struct CameraConfiguration: Hashable {
        let viewIdentifier: Int
        let center: BaseCoordinate?
        let defaultZoom: Double?
    }

    /// Everything the automatic camera depends on.
    private struct CameraInputs: Hashable {
        let configuration: CameraConfiguration
        let markerLayoutSignature: Int
        let opening: BaseMapOpening?
        let width: Int
        let height: Int
    }

    init(result: BaseQueryResult, actions: BaseViewActions, vaultPlaces: @escaping () async -> [BaseCoordinate]) {
        self.result = result
        self.actions = actions
        self.vaultPlaces = vaultPlaces
        markers = result.groups.flatMap(\.rows).compactMap { row in
            row.presentation.coordinate.map { coordinate in
                Marker(row: row, coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                       symbolName: row.presentation.markerIcon.flatMap(BaseIconMapping.symbolName(forLucideIcon:)))
            }
        }
        var hasher = Hasher()
        for marker in markers {
            hasher.combine(marker.coordinate.latitude)
            hasher.combine(marker.coordinate.longitude)
        }
        markerLayoutSignature = hasher.finalize()
    }

    /// What `mapTiles` asks for in the current appearance.
    private var background: BaseMapBackground? { options.background(isDark: colorScheme == .dark) }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if case .rasterTiles(let tileTemplates)? = background {
                    tiledMap(tileTemplates, size: geometry.size)
                } else {
                    appleMap(size: geometry.size)
                }
            }
            .overlay(alignment: .bottom) {
                if let selectedPath, let marker = markers.first(where: { marker in marker.row.path == selectedPath }) {
                    callout(for: marker.row).padding(12)
                }
            }
            .overlay(alignment: .topLeading) { notices.padding(10) }
        }
        .task(id: needsOpening) { await readOpening() }
    }

    /// A map with nothing of its own to place its camera reads where to open.
    private var needsOpening: Bool { markers.isEmpty && result.mapCenter == nil }

    /// The person's last known position when they let Graphite use it before (this asks nothing
    /// and starts no location updates), else the vault's placed notes.
    private func readOpening() async {
        guard needsOpening else {
            opening = nil
            return
        }
        if let position = deviceLocation?.lastKnownPosition {
            opening = .person(position)
            return
        }
        let places = await vaultPlaces()
        opening = places.isEmpty ? .nothingKnown : .vaultPlaces(places)
    }

    private func appleMap(size: CGSize) -> some View {
        Map(position: $position, bounds: cameraBounds(for: size)) {
            ForEach(markers) { marker in
                Annotation(BaseValue.file(marker.row.path).displayText, coordinate: marker.coordinate, anchor: .center) {
                    pin(for: marker, isSelected: selectedPath == marker.row.path)
                        .onTapGesture { selectedPath = marker.row.path }
                        .accessibilityAddTraits(.isButton)
                }
                .annotationTitles(.hidden)
            }
            if locationControl.showsPerson { UserAnnotation() }
        }
        .mapControls {
            if deviceLocation != nil { MapUserLocationButton() }
            MapCompass()
            MapScaleView()
        }
        // MapKit's location button follows the person; its first use asks for access.
        .onChange(of: position.followsUserLocation) { _, followsPerson in
            if followsPerson { locationButtonWasUsed() }
        }
        .task(id: CameraInputs(configuration: cameraConfiguration, markerLayoutSignature: markerLayoutSignature, opening: opening,
                               width: Int(size.width), height: Int(size.height))) {
            positionCamera(size: size)
        }
    }

    /// Asks for access the first time; granted, the map follows the person, refused, the camera
    /// goes back to where it was and the notice says how to turn access on.
    private func locationButtonWasUsed() {
        guard let deviceLocation else { return }
        let control = locationControl
        Task {
            switch await control.controlWasUsed(with: deviceLocation) {
            case .alreadyAllowed: break
            case .justAllowed: position = .userLocation(fallback: position.fallbackPosition ?? .automatic)
            case .refused: position = position.fallbackPosition ?? .automatic
            }
        }
    }

    private func tiledMap(_ tileTemplates: [BaseMapTileTemplate], size: CGSize) -> some View {
        var layoutHasher = Hasher()
        layoutHasher.combine(markerLayoutSignature)
        layoutHasher.combine(opening)
        layoutHasher.combine(Int(size.width))
        layoutHasher.combine(Int(size.height))
        return BaseTiledMapView(
            tileTemplates: tileTemplates,
            annotations: markers.map { marker in
                BaseMapMarkerAnnotation(path: marker.row.path, coordinate: marker.coordinate, title: BaseValue.file(marker.row.path).displayText)
            },
            cameraTarget: cameraTarget(size: size),
            cameraConfiguration: cameraConfiguration,
            cameraLayout: layoutHasher.finalize(),
            cameraDistances: cameraDistances(for: size),
            selectedPath: $selectedPath,
            pinImage: { path, isSelected in pinImage(for: path, isSelected: isSelected) },
            locationControl: locationControl, deviceLocation: deviceLocation)
        .overlay(alignment: .bottomTrailing) { tileSourceLabel(tileTemplates).padding(10) }
    }

    /// Where the tiles come from, since the map fetches them from there.
    private func tileSourceLabel(_ tileTemplates: [BaseMapTileTemplate]) -> some View {
        var hosts: [String] = []
        for tileTemplate in tileTemplates {
            guard let host = URL(string: tileTemplate.template.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: ""))?.host,
                  !hosts.contains(host) else { continue }
            hosts.append(host)
        }
        return Text("Map tiles: \(hosts.joined(separator: ", "))")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
    }

    private func pinImage(for path: VaultPath, isSelected: Bool) -> CGImage? {
        guard let marker = markers.first(where: { marker in marker.row.path == path }) else { return nil }
        let renderer = ImageRenderer(content: pin(for: marker, isSelected: isSelected))
        renderer.scale = displayScale
        return renderer.cgImage
    }

    // MARK: Camera

    private var cameraConfiguration: CameraConfiguration {
        CameraConfiguration(viewIdentifier: result.view.id, center: result.mapCenter, defaultZoom: options.defaultZoom)
    }

    /// Markers arriving or the view resizing refit the camera only until the person moves
    /// the map; another view or configured camera always places it again.
    private func positionCamera(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let configuration = cameraConfiguration
        if positionedCamera == configuration, position.positionedByUser || position.followsUserLocation { return }
        positionedCamera = configuration
        switch cameraTarget(size: size) {
        case .region(let region): position = .region(region)
        // With no markers, `.automatic` is MapKit's own opening region.
        case .fittingMarkers, .mapKitOpening: position = .automatic
        }
    }

    private func cameraTarget(size: CGSize) -> BaseMapCameraTarget {
        BaseMapCameraTarget.forView(center: result.mapCenter, defaultZoom: options.defaultZoom, markerCoordinates: markers.map(\.coordinate),
                                    opening: opening, size: size)
    }

    /// The average position of `coordinates`. Longitudes wrap at ±180°, so markers on both
    /// sides of the antimeridian average on it rather than on the far side of the globe.
    static func centerCoordinate(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard !coordinates.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let latitudes = coordinates.map(\.latitude)
        var longitudes = coordinates.map(\.longitude)
        if let westernmost = longitudes.min(), let easternmost = longitudes.max(), easternmost - westernmost > 180 {
            longitudes = longitudes.map { longitude in longitude < 0 ? longitude + 360 : longitude }
        }
        let meanLongitude = longitudes.reduce(0, +) / Double(longitudes.count)
        return CLLocationCoordinate2D(latitude: latitudes.reduce(0, +) / Double(latitudes.count),
                                      longitude: meanLongitude > 180 ? meanLongitude - 360 : meanLongitude)
    }

    private static func metersPerPoint(zoom: Double, latitude: Double) -> Double {
        metersPerPointAtZoomZero * cos(latitude * .pi / 180) / pow(2, zoom)
    }

    /// The region a web map shows at `zoom` in a view of `size`. MapKit rejects a region
    /// wider than the globe, which a low zoom in a large view reaches, so the span stops there.
    static func region(center: CLLocationCoordinate2D, zoom: Double, size: CGSize) -> MKCoordinateRegion {
        let scale = metersPerPoint(zoom: zoom, latitude: center.latitude)
        let span = MKCoordinateRegion(center: center, latitudinalMeters: scale * size.height, longitudinalMeters: scale * size.width).span
        let latitudeDelta = span.latitudeDelta.isFinite ? min(span.latitudeDelta, maximumLatitudeDelta) : maximumLatitudeDelta
        let longitudeDelta = span.longitudeDelta.isFinite ? min(span.longitudeDelta, maximumLongitudeDelta) : maximumLongitudeDelta
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }

    static let maximumLatitudeDelta: CLLocationDegrees = 180
    static let maximumLongitudeDelta: CLLocationDegrees = 360

    /// `minZoom` and `maxZoom` become camera distance limits.
    private func cameraBounds(for size: CGSize) -> MapCameraBounds {
        let distances = cameraDistances(for: size)
        return MapCameraBounds(minimumDistance: distances.lowerBound, maximumDistance: distances.upperBound)
    }

    private func cameraDistances(for size: CGSize) -> ClosedRange<CLLocationDistance> {
        Self.cameraDistances(for: size, minimumZoom: options.minimumZoom, maximumZoom: options.maximumZoom)
    }

    /// The nearest camera distance is never under 50 meters, and the farthest never under the nearest:
    /// a range whose lower end is above its upper end traps, as a high minimum zoom made it.
    static func cameraDistances(for size: CGSize, minimumZoom: Double, maximumZoom: Double) -> ClosedRange<CLLocationDistance> {
        let viewHeight = max(Double(size.height), 100)
        let closestDistance = metersPerPoint(zoom: maximumZoom, latitude: 0) * viewHeight
        let farthestDistance = metersPerPoint(zoom: max(minimumZoom, 0), latitude: 0) * viewHeight
        let nearestAllowedDistance = max(closestDistance, 50)
        return nearestAllowedDistance...max(farthestDistance, nearestAllowedDistance * 2)
    }

    // MARK: Markers

    private func pin(for marker: Marker, isSelected: Bool) -> some View {
        let row = marker.row
        let color = row.presentation.markerColor.flatMap { text in BaseMarkerStyle.color(for: text, accent: accent) } ?? accent
        let symbolName = marker.symbolName
        return ZStack {
            Circle()
                .fill(color)
                .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            if let symbolName {
                Image(systemName: symbolName).font(.system(size: isSelected ? 15 : 12, weight: .semibold)).foregroundStyle(.white)
            } else {
                Circle().fill(.white).frame(width: isSelected ? 8 : 6, height: isSelected ? 8 : 6)
            }
        }
        .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
        .animation(GraphiteMotion.animation(.snappy), value: isSelected)
        .accessibilityLabel(BaseValue.file(row.path).displayText)
    }

    private func callout(for row: BaseResultRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    actions.openPath(row.path)
                } label: {
                    Text(BaseValue.file(row.path).displayText).font(.headline).foregroundStyle(.tint).lineLimit(2)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 12)
                Button("Close", systemImage: "xmark.circle.fill") { selectedPath = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
            }
            // The values line up after the longest name, as in a form, rather than each
            // starting where its name ends.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(Array(result.columns.enumerated().filter { _, column in column.property != .file("name") }.prefix(5)), id: \.element.id) { position, column in
                    if !(row.cells[position].value?.isEmptyValue ?? false) {
                        GridRow {
                            Text(column.displayName).font(.caption).foregroundStyle(.secondary)
                            BaseCellView(cell: row.cells[position], lineLimit: 2, actions: actions, holdsTags: column.property.holdsTags).font(.callout)
                        }
                    }
                }
            }
            Button("Open Note", systemImage: "arrow.up.forward.square") { actions.openPath(row.path) }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    @ViewBuilder private var notices: some View {
        let missingCount = result.displayedCount - markers.count
        VStack(alignment: .leading, spacing: 6) {
            if let refusal = locationControl.refusal {
                MapLocationRefusalNotice(refusal: refusal) { locationControl.dismissRefusal() }
            }
            if options.coordinatesProperty == nil {
                noticeLabel("Choose a coordinates property for this map in the base file.", systemImage: "mappin.slash")
            } else if missingCount > 0 {
                noticeLabel("\(missingCount) \(missingCount == 1 ? "file has" : "files have") no valid coordinates", systemImage: "mappin.slash")
            }
            switch background {
            case .style?:
                noticeLabel("This map's background is a map style, which Graphite can't draw; showing Apple Maps.", systemImage: "map")
            case .unusableTiles?:
                noticeLabel("This map's tiles need a web address with {z}, {x} and {y}; showing Apple Maps.", systemImage: "map")
            case .rasterTiles?, nil:
                EmptyView()
            }
        }
    }

    private func noticeLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}
