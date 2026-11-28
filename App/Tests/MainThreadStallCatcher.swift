/**
 * File: MainThreadStallCatcher.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Catches where the main thread is when it shows no frame for a while: a thread of its own stops the main
 *              thread for an instant, reads its stack and lets it go, whether the main thread was working or waiting.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 28/11/2026
 */
#if os(iOS) && arch(arm64)
import Foundation
import QuartzCore
import Darwin

/// A sample of the main thread taken only while it is late: a frame the display link expected has not come for
/// `stallSeconds`. Instruments' Time Profiler sees a thread only while it runs, so a main thread waiting for a lock
/// or for another thread shows nothing there; this reads the stack in either case and says which it was.
///
/// The main thread is stopped while its stack is read, so nothing is allocated meanwhile (it may hold the allocator's
/// lock): the addresses go into a buffer made beforehand and are named only after the main thread goes on.
// Unchecked: the frame time is written by the main thread and read by the watch queue as a plain word, and the captures
// are behind a lock.
final class MainThreadStallCatcher: @unchecked Sendable {
    struct Capture {
        /// When the last frame came, on `CACurrentMediaTime`'s clock; captures of one stall share it.
        let lastFrameTime: CFTimeInterval
        let capturedAt: CFTimeInterval
        /// True when the main thread was running, false when it waited.
        let wasRunning: Bool
        let returnAddresses: [UInt]
    }

    private let stallSeconds: CFTimeInterval
    private let mainThread: thread_act_t
    private let lastFrameTime = UnsafeMutablePointer<CFTimeInterval>.allocate(capacity: 1)
    private let addressBuffer = UnsafeMutablePointer<UInt>.allocate(capacity: MainThreadStallCatcher.deepestStack)
    private var displayLink: CADisplayLink?
    /// Looks every 5 ms, on a queue of its own, so the main thread is caught whatever it does.
    private let watchQueue = DispatchQueue(label: "MainThreadStallCatcher", qos: .userInteractive)
    private var watchTimer: DispatchSourceTimer?
    /// Touched only on `watchQueue`.
    private var lastCaptureTime: CFTimeInterval = 0
    private let capturesLock = NSLock()
    private var storedCaptures: [Capture] = []
    private static let deepestStack = 96

    /// Starts watching; call on the main thread.
    @MainActor
    init(stallSeconds: CFTimeInterval = 0.1) {
        self.stallSeconds = stallSeconds
        mainThread = mach_thread_self()
        lastFrameTime.pointee = CACurrentMediaTime()
        let displayLink = CADisplayLink(target: FrameTarget(lastFrameTime: lastFrameTime), selector: #selector(FrameTarget.frame(_:)))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        watchTimer = Self.startWatching(self, on: watchQueue)
    }

    /// Stops watching and returns what was caught; call on the main thread.
    @MainActor
    func stop() -> [Capture] {
        displayLink?.invalidate()
        displayLink = nil
        watchTimer?.cancel()
        watchTimer = nil
        // Waits for a look under way to end.
        watchQueue.sync {}
        mach_port_deallocate(mach_task_self_, mainThread)
        capturesLock.lock()
        defer { capturesLock.unlock() }
        return storedCaptures
    }

    deinit {
        lastFrameTime.deallocate()
        addressBuffer.deallocate()
    }

    /// The watch timer, made outside the main actor: a closure written in the main actor's `init` would be the main
    /// actor's, and Swift stops the process when the timer runs it on the watch queue.
    private nonisolated static func startWatching(_ catcher: MainThreadStallCatcher, on queue: DispatchQueue) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
        timer.setEventHandler { [catcher] in catcher.look() }
        timer.resume()
        return timer
    }

    private func look() {
        let frameTime = lastFrameTime.pointee
        let now = CACurrentMediaTime()
        guard now - frameTime > stallSeconds, now - lastCaptureTime > 0.04 else { return }
        lastCaptureTime = now
        guard let capture = captureMainThread(lastFrameTime: frameTime, at: now) else { return }
        capturesLock.lock()
        storedCaptures.append(capture)
        capturesLock.unlock()
    }

    /// Stops the main thread, reads its frame pointers' chain and its run state, and lets it go.
    private func captureMainThread(lastFrameTime: CFTimeInterval, at now: CFTimeInterval) -> Capture? {
        // Read before the thread is stopped, which a stopped thread's run state would say instead.
        var information = thread_basic_info()
        var informationCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(informationCount)) { integers in
                thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), integers, &informationCount)
            }
        }
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return nil }
        var state = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        let stateResult = withUnsafeMutablePointer(to: &state) { pointer in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) { words in
                thread_get_state(mainThread, ARM_THREAD_STATE64, words, &stateCount)
            }
        }
        var depth = 0
        if stateResult == KERN_SUCCESS {
            let addressMask: UInt = 0x0000_FFFF_FFFF_FFFF
            addressBuffer[0] = UInt(state.__pc) & addressMask
            addressBuffer[1] = UInt(state.__lr) & addressMask
            depth = 2
            var framePointer = UInt(state.__fp) & addressMask
            while depth < Self.deepestStack, framePointer != 0, framePointer % 8 == 0 {
                guard let frame = UnsafePointer<UInt>(bitPattern: framePointer) else { break }
                let returnAddress = frame[1] & addressMask
                let callerFramePointer = frame[0] & addressMask
                if returnAddress == 0 { break }
                addressBuffer[depth] = returnAddress
                depth += 1
                if callerFramePointer <= framePointer { break }
                framePointer = callerFramePointer
            }
        }
        thread_resume(mainThread)
        guard depth > 0 else { return nil }
        return Capture(lastFrameTime: lastFrameTime, capturedAt: now, wasRunning: information.run_state == TH_STATE_RUNNING,
                       returnAddresses: Array(UnsafeBufferPointer(start: addressBuffer, count: depth)))
    }

    /// Each stall caught, its length so far at the last capture, how many captures found the main thread running, and
    /// the stack of its last capture, named by image and symbol, frames of the system's run loop left out.
    static func report(_ captures: [Capture], deepestFrames: Int = 28) -> String {
        guard !captures.isEmpty else { return "no stall caught" }
        let stalls = Dictionary(grouping: captures, by: \.lastFrameTime).sorted { left, right in left.key < right.key }
        return stalls.map { lastFrameTime, stallCaptures in
            let last = stallCaptures.max { left, right in left.capturedAt < right.capturedAt }!
            let running = stallCaptures.filter(\.wasRunning).count
            let frames = last.returnAddresses.prefix(deepestFrames).map(Self.name(of:))
            let middle = stallCaptures.sorted { left, right in left.capturedAt < right.capturedAt }[stallCaptures.count / 2]
            let middleFrames = middle === last ? [] : middle.returnAddresses.prefix(12).map(Self.name(of:))
            return "stall of at least \(Int((last.capturedAt - lastFrameTime) * 1_000)) ms, \(stallCaptures.count) captures, "
                + "\(running) running:\n    " + frames.joined(separator: "\n    ")
                + (middleFrames.isEmpty ? "" : "\n  its middle capture:\n    " + middleFrames.joined(separator: "\n    "))
        }.joined(separator: "\n")
    }

    private static func name(of address: UInt) -> String {
        var information = Dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: address), &information) != 0 else { return String(format: "0x%lx", address) }
        let image = information.dli_fname.map { path in (String(cString: path) as NSString).lastPathComponent } ?? "?"
        let symbol = information.dli_sname.map { name in String(cString: name) } ?? "?"
        let offset = information.dli_saddr.map { start in Int(address) - Int(bitPattern: start) } ?? 0
        return "\(image) \(symbol) + \(offset)"
    }
}

private extension MainThreadStallCatcher.Capture {
    static func === (left: Self, right: Self) -> Bool { left.capturedAt == right.capturedAt }
}

/// The display link's target, which only notes when each frame came.
private final class FrameTarget: NSObject {
    private let lastFrameTime: UnsafeMutablePointer<CFTimeInterval>

    init(lastFrameTime: UnsafeMutablePointer<CFTimeInterval>) {
        self.lastFrameTime = lastFrameTime
    }

    @objc func frame(_ link: CADisplayLink) {
        lastFrameTime.pointee = CACurrentMediaTime()
    }
}
#elseif os(iOS)
import QuartzCore

/// The same calls on a processor whose registers the catcher does not read (an Intel simulator in a build for every
/// architecture): it catches nothing, so a test that records stalls still builds and runs there and reports none.
final class MainThreadStallCatcher: @unchecked Sendable {
    struct Capture {
        let lastFrameTime: CFTimeInterval
        let capturedAt: CFTimeInterval
        let wasRunning: Bool
        let returnAddresses: [UInt]
    }

    init(stallSeconds: CFTimeInterval = 0.1) {}

    func stop() -> [Capture] { [] }

    static func report(_ captures: [Capture], deepestFrames: Int = 28) -> String {
        "stalls are caught only on arm64"
    }
}
#endif
