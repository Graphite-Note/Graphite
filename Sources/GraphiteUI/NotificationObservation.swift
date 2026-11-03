/**
 * File: NotificationObservation.swift
 * -----------------------------------
 * Layer: UI
 * Description: A notification registration that ends when its owner lets go of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation

/// A block observer of `NotificationCenter` that is removed when this value is released, so an owner that
/// holds it for as long as it listens cannot leave the registration behind.
final class NotificationObservation {
    private let token: NSObjectProtocol

    init(name: Notification.Name, object: AnyObject? = nil, queue: OperationQueue? = nil, using block: @escaping @Sendable (Notification) -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: object, queue: queue, using: block)
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}
