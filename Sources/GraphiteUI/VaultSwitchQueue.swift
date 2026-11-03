/**
 * File: VaultSwitchQueue.swift
 * ----------------------------
 * Layer: UI
 * Description: Lets one vault switch run at a time, and only the latest request of those waiting.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation

/// Takes turns for opening vaults. A switch awaits several times (the folder's access, its plugins, its
/// saves), so two switches that ran together interleaved at each wait, and the slower one committed last
/// and left the window on the vault the person had not asked for last.
///
/// A switch calls `begin()` first and `end()` when it is done, whatever the outcome. A switch that
/// waited its turn while a newer request arrived is skipped: only the latest request opens its vault.
@MainActor
final class VaultSwitchQueue {
    private var isSwitching = false
    private var latestRequestNumber = 0
    private var waitingSwitches: [CheckedContinuation<Void, Never>] = []

    /// Whether a switch is running, so a request for the vault now open may still be a later choice.
    var isBusy: Bool { isSwitching }

    /// Waits for the switches before this one. False when a newer request has come meanwhile: this switch
    /// is skipped and has nothing to end.
    func begin() async -> Bool {
        latestRequestNumber += 1
        let requestNumber = latestRequestNumber
        if isSwitching {
            await withCheckedContinuation { continuation in waitingSwitches.append(continuation) }
        } else {
            isSwitching = true
        }
        guard requestNumber == latestRequestNumber else {
            end()
            return false
        }
        return true
    }

    /// Gives the turn to the next switch waiting, or frees the queue.
    func end() {
        if waitingSwitches.isEmpty {
            isSwitching = false
        } else {
            waitingSwitches.removeFirst().resume()
        }
    }
}
