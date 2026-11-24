/**
 * File: MainThreadSampler.swift
 * -----------------------------
 * Layer: Tests
 * Description: Reads the main thread's stack every millisecond, each sample stamped with its time, so a test can name what
 *              the main thread did in the frames that came late, inclusive of every function on the stack.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */
#if os(iOS) && arch(arm64)
import Foundation
import QuartzCore
import Darwin

/// A sampling profiler of the main thread inside the test: a timer on a queue of its own stops the main thread, walks its
/// frame pointers into a buffer made beforehand (nothing is allocated while it is stopped), and lets it go. `MainThreadStallCatcher`
/// reads a stack only once a frame is late, which in a frame that ends late after 15 ms of work finds the main thread
/// waiting again; this one keeps every sample, so the work of any stretch of time can be named afterwards.
// Unchecked: the buffers are written only on the sampling queue, and read once it has stopped.
final class MainThreadSampler: @unchecked Sendable {
    private static let deepestStack = 64
    private let capacity: Int
    private let mainThread: thread_act_t
    private let times: UnsafeMutablePointer<CFTimeInterval>
    private let depths: UnsafeMutablePointer<Int>
    private let addresses: UnsafeMutablePointer<UInt>
    private var count = 0
    private let queue = DispatchQueue(label: "MainThreadSampler", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    /// Starts sampling; call on the main thread. `capacity` samples are kept, a millisecond apart.
    @MainActor
    init(capacity: Int = 60_000) {
        self.capacity = capacity
        mainThread = mach_thread_self()
        times = .allocate(capacity: capacity)
        depths = .allocate(capacity: capacity)
        addresses = .allocate(capacity: capacity * Self.deepestStack)
        timer = Self.startSampling(self, on: queue)
    }

    deinit {
        times.deallocate()
        depths.deallocate()
        addresses.deallocate()
    }

    /// Stops sampling; call on the main thread.
    @MainActor
    func stop() {
        timer?.cancel()
        timer = nil
        queue.sync {}
        mach_port_deallocate(mach_task_self_, mainThread)
    }

    /// What the main thread spent the samples taken within `stretches` in, most samples first, each sample a millisecond:
    /// the functions of the app's own image on its stack (each counted once a sample, so a caller holds its callees' time),
    /// and the function it was in at that moment, by image.
    func heaviestFunctions(in stretches: [ClosedRange<CFTimeInterval>], limit: Int = 30) -> String {
        var appFunctions: [String: Int] = [:]
        var leaves: [String: Int] = [:]
        var sampleCount = 0
        var names: [UInt: (image: String, symbol: String)] = [:]
        let appImage = (Bundle.main.executablePath.map { path in (path as NSString).lastPathComponent }) ?? "Graphite"
        for index in 0..<count where stretches.contains(where: { stretch in stretch.contains(times[index]) }) {
            sampleCount += 1
            var seen: Set<String> = []
            for frame in 0..<depths[index] {
                let address = addresses[index * Self.deepestStack + frame]
                let name = names[address] ?? Self.name(of: address)
                names[address] = name
                if frame == 0 { leaves["\(name.image) \(name.symbol)", default: 0] += 1 }
                if name.image.hasPrefix(appImage), seen.insert(name.symbol).inserted { appFunctions[name.symbol, default: 0] += 1 }
            }
        }
        func listed(_ counts: [String: Int]) -> String {
            counts.sorted { left, right in left.value > right.value }.prefix(limit).map { name, samples in "  \(samples) \(name)" }.joined(separator: "\n")
        }
        return "\(sampleCount) samples of 1 ms; in the app's own code:\n" + listed(appFunctions) + "\n at the top of the stack:\n" + listed(leaves)
    }

    private nonisolated static func startSampling(_ sampler: MainThreadSampler, on queue: DispatchQueue) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .microseconds(200))
        timer.setEventHandler { [sampler] in sampler.sample() }
        timer.resume()
        return timer
    }

    private func sample() {
        guard count < capacity else { return }
        let base = addresses + count * Self.deepestStack
        let now = CACurrentMediaTime()
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return }
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
            base[0] = UInt(state.__pc) & addressMask
            depth = 1
            var framePointer = UInt(state.__fp) & addressMask
            while depth < Self.deepestStack, framePointer != 0, framePointer % 8 == 0 {
                guard let frame = UnsafePointer<UInt>(bitPattern: framePointer) else { break }
                let returnAddress = frame[1] & addressMask
                let callerFramePointer = frame[0] & addressMask
                if returnAddress == 0 { break }
                base[depth] = returnAddress
                depth += 1
                if callerFramePointer <= framePointer { break }
                framePointer = callerFramePointer
            }
        }
        thread_resume(mainThread)
        times[count] = now
        depths[count] = depth
        count += 1
    }

    private static func name(of address: UInt) -> (image: String, symbol: String) {
        var information = Dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: address), &information) != 0 else { return ("?", "?") }
        let image = information.dli_fname.map { path in (String(cString: path) as NSString).lastPathComponent } ?? "?"
        let symbol = information.dli_sname.map { name in String(cString: name) } ?? "?"
        return (image, symbol)
    }
}
#endif
