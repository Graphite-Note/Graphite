/**
 * File: DeviceLocation.swift
 * --------------------------
 * Layer: Apple
 * Description: Where the device is, for the maps' location control: whether the person lets Graphite use it, the
 *              question asked once when the control is first used, and the last position the system knows.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import CoreLocation
import GraphiteCore

/// Whether the person lets Graphite use where the device is.
public enum DeviceLocationAccess: Equatable, Sendable {
    /// Never asked: the first use of a map's location control asks.
    case notAsked
    /// While Graphite is in use.
    case granted
    /// The person said no, or turned it off in Settings.
    case refused
    /// The device does not allow it, as with Screen Time or a device profile, whatever the person chooses.
    case restricted
}

/// Where the device is, for a map's location control. A protocol because the hosted tests answer
/// for it: they never ask the real location service and never show its question.
///
/// Reading `access` or `lastKnownPosition` never shows a question and starts no location updates;
/// only `requestAccess` asks, and only when the person has never answered.
@MainActor
public protocol DeviceLocation: AnyObject {
    var access: DeviceLocationAccess { get }
    /// Asks for access while Graphite is in use (never always) when the person has never answered,
    /// and returns the answer; otherwise returns the answer given before, without asking.
    func requestAccess() async -> DeviceLocationAccess
    /// The last position the system has for Graphite, without asking for a new one; nil without
    /// access or when Graphite never had a position.
    var lastKnownPosition: BaseCoordinate? { get }
}

/// The system's location service. The location manager is made at the first question, so a launch
/// whose maps never use their location control makes none, and nothing here starts location
/// updates: MapKit's map view follows the person itself once access is granted.
@MainActor
public final class LiveDeviceLocation: NSObject, DeviceLocation {
    private var locationManager: CLLocationManager?
    /// Callers of `requestAccess` waiting for the person's answer; one question serves them all.
    private var accessWaiters: [CheckedContinuation<DeviceLocationAccess, Never>] = []

    public nonisolated override init() {}

    public var access: DeviceLocationAccess { Self.access(of: madeLocationManager().authorizationStatus) }

    public func requestAccess() async -> DeviceLocationAccess {
        let manager = madeLocationManager()
        let currentAccess = Self.access(of: manager.authorizationStatus)
        guard currentAccess == .notAsked else { return currentAccess }
        return await withCheckedContinuation { continuation in
            accessWaiters.append(continuation)
            if accessWaiters.count == 1 { manager.requestWhenInUseAuthorization() }
        }
    }

    public var lastKnownPosition: BaseCoordinate? {
        let manager = madeLocationManager()
        guard Self.access(of: manager.authorizationStatus) == .granted, let location = manager.location else { return nil }
        return BaseCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func madeLocationManager() -> CLLocationManager {
        if let locationManager { return locationManager }
        let manager = CLLocationManager()
        manager.delegate = self
        locationManager = manager
        return manager
    }

    private func accessChanged(to newAccess: DeviceLocationAccess) {
        // The manager reports its state once when it is made, before any answer.
        guard newAccess != .notAsked else { return }
        let waiters = accessWaiters
        accessWaiters = []
        for waiter in waiters { waiter.resume(returning: newAccess) }
    }

    nonisolated static func access(of status: CLAuthorizationStatus) -> DeviceLocationAccess {
        switch status {
        case .notDetermined: .notAsked
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied: .refused
        case .restricted: .restricted
        @unknown default: .refused
        }
    }
}

extension LiveDeviceLocation: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newAccess = Self.access(of: manager.authorizationStatus)
        Task { @MainActor [weak self] in self?.accessChanged(to: newAccess) }
    }
}
