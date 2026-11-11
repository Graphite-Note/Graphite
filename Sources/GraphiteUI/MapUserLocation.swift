/**
 * File: MapUserLocation.swift
 * ---------------------------
 * Layer: UI
 * Description: What the maps' "my location" control decides when the person uses it, and what a map says when
 *              Graphite may not use the person's location.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import GraphiteCore
import GraphiteApple

extension EnvironmentValues {
    /// Where the device is, for the maps' location control (`ProcessServices.deviceLocation`). Nil
    /// shows no control: a map without it works as before and asks nothing.
    @Entry var deviceLocation: (any DeviceLocation)? = nil
}

/// Why a map cannot show where the person is.
enum MapLocationRefusal: Equatable {
    case refused
    case restricted

    var message: String {
        switch self {
        case .refused:
            #if canImport(UIKit)
            "Graphite may not use your location. To center the map on you, turn on Location in Settings › Graphite."
            #else
            "Graphite may not use your location. To center the map on you, turn on Graphite in System Settings › Privacy & Security › Location Services."
            #endif
        case .restricted:
            "Location is restricted on this device, for example by Screen Time, so the map cannot center on you."
        }
    }

    /// Where the person turns access on; nil when the device decides, not the person.
    var settingsURL: URL? {
        switch self {
        case .refused:
            #if canImport(UIKit)
            URL(string: UIApplication.openSettingsURLString)
            #else
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
            #endif
        case .restricted: nil
        }
    }
}

/// What using the location control came to.
enum MapLocationControlUse: Equatable {
    /// Access was granted before: MapKit follows the person by itself.
    case alreadyAllowed
    /// The person granted access just now: the map starts following them, which MapKit's first
    /// try, made before the answer, could not do.
    case justAllowed
    case refused(MapLocationRefusal)
}

/// One map's location control: what its use decided, and the explanation shown after a refusal.
/// Made with the map at no cost: the device's location is only asked when the person uses the
/// control, so a map whose control is never used asks nothing and runs nothing for it.
@MainActor @Observable
final class MapUserLocationControl {
    /// Shown over the map after the person used the control without access.
    private(set) var refusal: MapLocationRefusal?
    /// Whether the map draws the person's position: after the control was used with access.
    private(set) var showsPerson = false

    /// The person used the control: asks for access the first time, and says what the map does.
    func controlWasUsed(with location: any DeviceLocation) async -> MapLocationControlUse {
        let use: MapLocationControlUse = switch location.access {
        case .granted: .alreadyAllowed
        case .refused: .refused(.refused)
        case .restricted: .refused(.restricted)
        case .notAsked:
            switch await location.requestAccess() {
            case .granted: .justAllowed
            case .refused, .notAsked: .refused(.refused)
            case .restricted: .refused(.restricted)
            }
        }
        switch use {
        case .alreadyAllowed, .justAllowed:
            showsPerson = true
            refusal = nil
        case .refused(let reason):
            refusal = reason
        }
        return use
    }

    func dismissRefusal() { refusal = nil }
}

/// The explanation a map shows when Graphite may not use the person's location, over the map,
/// which keeps working beneath it.
struct MapLocationRefusalNotice: View {
    let refusal: MapLocationRefusal
    let dismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(refusal.message, systemImage: "location.slash")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let settingsURL = refusal.settingsURL {
                Button("Open Settings") { openURL(settingsURL) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button("Close", systemImage: "xmark.circle.fill", action: dismiss)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// The refusal notice of `control`, over a map.
    func mapLocationRefusalNotice(of control: MapUserLocationControl) -> some View {
        overlay(alignment: .top) {
            if let refusal = control.refusal {
                MapLocationRefusalNotice(refusal: refusal) { control.dismissRefusal() }.padding(12)
            }
        }
    }
}
