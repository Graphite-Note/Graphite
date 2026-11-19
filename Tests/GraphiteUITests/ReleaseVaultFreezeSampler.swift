/**
 * File: ReleaseVaultFreezeSampler.swift
 * -------------------------------------
 * Layer: Tests
 * Description: On the Mac, a watch off the main thread that samples the test process with `/usr/bin/sample` while the
 *              main thread is stuck, so a freeze the release pass finds comes with the stacks that caused it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

#if os(macOS)
import Foundation

/// Docs/Release-test-vault-todo.md, section 2: the pass found freezes of 2.5 and 4.7 s that did not come back on demand,
/// and a freeze measured afterwards says how long but not where. The sampler asks the main queue for a beat every tenth
/// of a second from a queue of its own; when no beat has come for `stuckThreshold`, it runs `sample` on the process for
/// `sampleSeconds`, once per freeze, and writes the report into `folder`. The pass names the report in its finding.
// @unchecked Sendable: the watch queue's timer and the main queue's beats share `lastBeat`, `isSamplingThisFreeze` and
// `reports`, each read and written only under `lock`.
final class ReleaseVaultFreezeSampler: @unchecked Sendable {
    static let stuckThreshold = 1.0
    static let sampleSeconds = 3
    private static let beatInterval = DispatchTimeInterval.milliseconds(100)

    private let folder: URL
    private let watchQueue = DispatchQueue(label: "ReleaseVaultFreezeSampler.watch")
    private let lock = NSLock()
    private var lastBeat = ProcessInfo.processInfo.systemUptime
    private var isSamplingThisFreeze = false
    private var timer: DispatchSourceTimer?
    private var reports: [(startedAt: Date, location: URL)] = []
    private var beatGaps: [(endedAt: Date, length: TimeInterval)] = []

    init(folder: URL) {
        self.folder = folder
    }

    func start() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let timer = DispatchSource.makeTimerSource(queue: watchQueue)
        timer.schedule(deadline: .now() + Self.beatInterval, repeating: Self.beatInterval)
        timer.setEventHandler { [weak self] in self?.checkAndAskForBeat() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// The reports written since `instant`, for the freeze a measurement that began then has found.
    func reports(since instant: Date) -> [URL] {
        lock.withLock { reports.filter { report in report.startedAt >= instant.addingTimeInterval(-Self.stuckThreshold) }.map(\.location) }
    }

    /// The longest time the main queue went without running a beat, among the gaps that ended since `instant`: the main
    /// thread's own freeze, whatever the pass's polls saw.
    func longestBeatGap(since instant: Date) -> TimeInterval {
        lock.withLock { beatGaps.filter { gap in gap.endedAt >= instant }.map(\.length).max() ?? 0 }
    }

    private func checkAndAskForBeat() {
        let now = ProcessInfo.processInfo.systemUptime
        let shouldSample = lock.withLock {
            let isStuck = now - lastBeat > Self.stuckThreshold
            if !isStuck { isSamplingThisFreeze = false }
            guard isStuck, !isSamplingThisFreeze else { return false }
            isSamplingThisFreeze = true
            return true
        }
        if shouldSample { sampleProcess() }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let beat = ProcessInfo.processInfo.systemUptime
            lock.withLock {
                // A beat is asked for every tenth of a second; a gap well over that is the main queue held up.
                if beat - lastBeat > 0.3 { beatGaps.append((Date(), beat - lastBeat)) }
                lastBeat = beat
            }
        }
    }

    /// Runs off the watch queue, so the beats are still counted while `sample` takes its seconds.
    private func sampleProcess() {
        let startedAt = Date()
        let stamp = ISO8601DateFormatter().string(from: startedAt).replacingOccurrences(of: ":", with: "-")
        let location = folder.appendingPathComponent("freeze-sample-\(stamp).txt")
        let sampling = Process()
        sampling.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        // Every 10 ms: sampling every millisecond slowed a large test process so much that 3 s of samples took 14 s.
        sampling.arguments = [String(ProcessInfo.processInfo.processIdentifier), String(Self.sampleSeconds), "10", "-mayDie", "-file", location.path]
        sampling.standardOutput = FileHandle.nullDevice
        sampling.standardError = FileHandle.nullDevice
        do {
            try sampling.run()
            lock.withLock { reports.append((startedAt, location)) }
            print("GRAPHITE-RELEASE-FREEZE-SAMPLE \(location.path)")
        } catch {
            print("GRAPHITE-RELEASE-FREEZE-SAMPLE not taken: \(error)")
        }
    }
}
#endif
