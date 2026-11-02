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
protocol PeriodicTimeObservablePlayer: AnyObject {
    func addPeriodicTimeObserver(forInterval interval: CMTime, queue: DispatchQueue?, using block: @escaping @Sendable (CMTime) -> Void) -> Any
    func removeTimeObserver(_ observer: Any)
}

extension AVPlayer: PeriodicTimeObservablePlayer {}

/// A periodic time observer together with the player that issued it.
///
/// `AVPlayer` raises an exception when it is asked to remove an observer another player added, so a row
/// that moves to a different recording must remove the observer from the player it was added to, never
/// from the player it shows now.
@MainActor
final class PlayerTimeObservation {
    private var observedPlayer: (any PeriodicTimeObservablePlayer)?
    private var observerToken: Any?

    /// Observes `player`, first ending the observation of the player observed before.
    func start(on player: any PeriodicTimeObservablePlayer, intervalSeconds: Double, handler: @escaping @Sendable (CMTime) -> Void) {
        stop()
        observerToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: intervalSeconds, preferredTimescale: 600), queue: .main, using: handler)
        observedPlayer = player
    }

    /// Ends the observation, on the player that has it. Does nothing when there is none.
    func stop() {
        if let observedPlayer, let observerToken { observedPlayer.removeTimeObserver(observerToken) }
        observedPlayer = nil
        observerToken = nil
    }
}
