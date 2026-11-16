/**
 * File: AnsweringDeviceLocation.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A device location that answers as a test says and counts what the maps asked of it, so no test
 *              asks the real location service or shows its question.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

/// Answers for the device's location as a test sets it up, and counts every question: reading
/// the access, asking for it and reading the position.
@MainActor
public final class AnsweringDeviceLocation: DeviceLocation {
    /// The access before any question.
    public private(set) var currentAccess: DeviceLocationAccess
    /// What the person answers when asked.
    public let answer: DeviceLocationAccess
    /// The position the system has once access is granted.
    public let position: BaseCoordinate?
    public private(set) var accessReadCount = 0
    public private(set) var accessRequestCount = 0
    public private(set) var positionReadCount = 0

    public init(access: DeviceLocationAccess, answer: DeviceLocationAccess, position: BaseCoordinate?) {
        currentAccess = access
        self.answer = answer
        self.position = position
    }

    /// Whether a map asked anything of the device's location.
    public var wasAskedAnything: Bool { accessReadCount + accessRequestCount + positionReadCount > 0 }

    public var access: DeviceLocationAccess {
        accessReadCount += 1
        return currentAccess
    }

    public func requestAccess() async -> DeviceLocationAccess {
        accessRequestCount += 1
        if currentAccess == .notAsked { currentAccess = answer }
        return currentAccess
    }

    /// The person changes the access in Settings, as when they turn it on after a refusal.
    public func changeAccessInSettings(to newAccess: DeviceLocationAccess) {
        currentAccess = newAccess
    }

    public var lastKnownPosition: BaseCoordinate? {
        positionReadCount += 1
        return currentAccess == .granted ? position : nil
    }
}
