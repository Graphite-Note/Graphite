/**
 * File: CalendarServices.swift
 * ----------------------------
 * Layer: UI
 * Description: The Calendar core plugin's share of the process: the one Calendar and Reminders store every window uses,
 *              and the one listener for their changes, started only once a window has tasks linked to reminders.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import GraphiteApple

/// The Calendar core plugin's share of the process. Apple recommends one event store per app, so every window asks the
/// same `store`. Nothing listens for changes in Calendar or Reminders until a window follows them, which it does only
/// once its vault has tasks linked to reminders, and the listening ends when the last follower is gone.
@MainActor
final class CalendarServices {
    let store: any CalendarStore
    private var followers: [Follower] = []
    private var listening: Task<Void, Never>?

    private struct Follower {
        weak var owner: AnyObject?
        let changed: @MainActor () async -> Void
    }

    init(store: any CalendarStore) {
        self.store = store
    }

    /// Whether anything listens for changes now.
    var isListening: Bool { listening != nil }

    /// Calls `changed` after each change in Calendar or Reminders while `owner` lives, until `stopFollowing(owner)`.
    /// Following again replaces the earlier call.
    func follow(_ owner: AnyObject, changed: @escaping @MainActor () async -> Void) {
        followers.removeAll { follower in follower.owner == nil || follower.owner === owner }
        followers.append(Follower(owner: owner, changed: changed))
        guard listening == nil else { return }
        let changes = store.changes()
        listening = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                await self.tellFollowers()
                if self.followers.isEmpty { break }
            }
            // A listening that was cancelled has been replaced already, or is not wanted.
            if !Task.isCancelled { self?.listening = nil }
        }
    }

    func stopFollowing(_ owner: AnyObject) {
        followers.removeAll { follower in follower.owner == nil || follower.owner === owner }
        if followers.isEmpty {
            listening?.cancel()
            listening = nil
        }
    }

    private func tellFollowers() async {
        followers.removeAll { follower in follower.owner == nil }
        for follower in followers { await follower.changed() }
    }
}
