/**
 * File: WhatsNewSchedule.swift
 * ----------------------------
 * Layer: Core
 * Description: Whether a launch opens the What's New page: once after an update, never on a new install's
 *              first launch, and which groups of the release history it marks as new.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

/// What a launch does about the What's New page.
public enum WhatsNewAtLaunch: Equatable, Sendable {
    /// Open it. Groups written after `newSince` are marked new; with no moment (the build last
    /// seen is not known) none are, and the page simply starts at the newest version.
    case show(newSince: ReleaseMoment?)
    /// Remember this build as seen without opening anything: a new install, whose first launch
    /// opens the welcome tour, or an update that brought no line for this device.
    case recordSilently
    /// Nothing to do: this build was already seen, or it has no build number.
    case nothing

    /// - Parameters:
    ///   - currentBuild: this build's number (`CFBundleVersion`), `20261128.1405` in a TestFlight build.
    ///   - lastShownBuild: the build whose What's New this device last showed or recorded, nil if none.
    ///   - hasSeenWelcomeTour: whether this device has closed the welcome tour, which tells an update
    ///     from a new install when no build was recorded yet (before What's New existed).
    ///   - history: the release history, already narrowed to this device.
    public static func decide(currentBuild: String?, lastShownBuild: String?, hasSeenWelcomeTour: Bool, history: ReleaseHistory) -> WhatsNewAtLaunch {
        guard let currentBuild, !currentBuild.isEmpty, currentBuild != lastShownBuild else { return .nothing }
        guard let lastShownBuild, !lastShownBuild.isEmpty else {
            return hasSeenWelcomeTour && !history.versions.isEmpty ? .show(newSince: nil) : .recordSilently
        }
        guard let lastShownMoment = ReleaseMoment(buildNumber: lastShownBuild) else {
            return history.versions.isEmpty ? .recordSilently : .show(newSince: nil)
        }
        return history.hasGroups(after: lastShownMoment) ? .show(newSince: lastShownMoment) : .recordSilently
    }
}
