/**
 * File: PlayerTimeObservationTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: A time observer is removed from the player that issued it, as AVPlayer requires (HUNT-103).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import AVFoundation
import XCTest
@testable import GraphiteUI

/// A player that makes no sound and, like `AVPlayer`, counts a removal of an observer it did not issue as the
/// error that makes `AVPlayer` raise an exception.
private final class SilentObservablePlayer: PeriodicTimeObservablePlayer {
    private struct ObserverToken: Hashable {
        let issuer: UUID
        let number: Int
    }

    private let identifier = UUID()
    private(set) var issuedObserverCount = 0
    private var activeObserverTokens: Set<ObserverToken> = []
    private(set) var foreignRemovalCount = 0

    var activeObserverCount: Int { activeObserverTokens.count }

    func addPeriodicTimeObserver(forInterval interval: CMTime, queue: DispatchQueue?, using block: @escaping @Sendable (CMTime) -> Void) -> Any {
        issuedObserverCount += 1
        let token = ObserverToken(issuer: identifier, number: issuedObserverCount)
        activeObserverTokens.insert(token)
        return token
    }

    func removeTimeObserver(_ observer: Any) {
        guard let token = observer as? ObserverToken, activeObserverTokens.remove(token) != nil else {
            foreignRemovalCount += 1
            return
        }
    }
}

@MainActor
final class PlayerTimeObservationTests: XCTestCase {
    /// A row that moves to another recording observes the new player; the observer of the old one has to be
    /// removed from the old one. Removing it from the new one crashed reading view.
    func testObservingAnotherPlayerRemovesTheObserverFromThePlayerThatIssuedIt() {
        let firstPlayer = SilentObservablePlayer()
        let secondPlayer = SilentObservablePlayer()
        let observation = PlayerTimeObservation()

        observation.start(on: firstPlayer, intervalSeconds: 0.5) { _ in }
        observation.start(on: secondPlayer, intervalSeconds: 0.5) { _ in }

        XCTAssertTrue(firstPlayer.activeObserverCount == 0, "the old player has no observer left")
        XCTAssertEqual(secondPlayer.activeObserverCount, 1)
        XCTAssertEqual(firstPlayer.foreignRemovalCount + secondPlayer.foreignRemovalCount, 0, "no player was asked to remove another's observer")
    }

    func testStoppingRemovesTheObserverOnceFromItsPlayer() {
        let player = SilentObservablePlayer()
        let observation = PlayerTimeObservation()
        observation.start(on: player, intervalSeconds: 0.5) { _ in }

        observation.stop()
        observation.stop()

        XCTAssertTrue(player.activeObserverCount == 0)
        XCTAssertEqual(player.foreignRemovalCount, 0)
    }

    func testObservingTheSamePlayerAgainKeepsOneObserver() {
        let player = SilentObservablePlayer()
        let observation = PlayerTimeObservation()

        observation.start(on: player, intervalSeconds: 0.5) { _ in }
        observation.start(on: player, intervalSeconds: 0.5) { _ in }

        XCTAssertEqual(player.activeObserverCount, 1)
        XCTAssertEqual(player.issuedObserverCount, 2)
    }
}
