/**
 * File: PlayerTimeObservation.swift
 * ---------------------------------
 * Layer: UI
 * Description: One periodic time observer of one player, removed from the player it was added to.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import AVFoundation

/// What a time observation needs of a player; `AVPlayer` is the production conformer, and tests use a
/// fake that makes no sound.
@MainActor
protocol PeriodicTimeObservablePlayer: AnyObject {
    /// Calls `handler` at `interval` while the observation lasts. The result ends the observation, on this player.
    func observePeriodically(every interval: CMTime, handler: @escaping @Sendable (CMTime) -> Void) -> () -> Void
}

extension AVPlayer: PeriodicTimeObservablePlayer {
    func observePeriodically(every interval: CMTime, handler: @escaping @Sendable (CMTime) -> Void) -> () -> Void {
        let observer = addPeriodicTimeObserver(forInterval: interval, queue: .main, using: handler)
        return { [weak self] in self?.removeTimeObserver(observer) }
    }
}

/// A periodic time observer together with the player that issued it.
///
/// `AVPlayer` raises an exception when it is asked to remove an observer another player added, so a row
/// that moves to a different recording must remove the observer from the player it was added to, never
/// from the player it shows now.
@MainActor
final class PlayerTimeObservation {
    private var endObservation: (() -> Void)?

    /// Observes `player`, first ending the observation of the player observed before.
    func start(on player: any PeriodicTimeObservablePlayer, intervalSeconds: Double, handler: @escaping @Sendable (CMTime) -> Void) {
        stop()
        endObservation = player.observePeriodically(every: CMTime(seconds: intervalSeconds, preferredTimescale: 600), handler: handler)
    }

    /// Ends the observation, on the player that has it. Does nothing when there is none.
    func stop() {
        endObservation?()
        endObservation = nil
    }
}
