/**
 * File: ProcessorTime.swift
 * -------------------------
 * Layer: Tests
 * Description: The processor time a test's work used, on its thread or in the whole test process, for timing budgets
 *              that hold on a busy Mac: the time spent waiting for a core while other builds ran is left out, the work
 *              itself is counted.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */
import Darwin

/// A move of the pixel eraser measured with the wall clock took 14 ms against a budget of 4 under a load average of 52,
/// and 1.8 ms alone: the thread had been waiting for a core. Measured in processor time, a test still fails when the code
/// does more work, but not when the machine is busy.
public enum ProcessorTime {
    /// The calling thread's processor time so far, in nanoseconds.
    public static func threadNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }

    /// The processor time of every thread of the test process so far, user and system, in nanoseconds: for work spread over
    /// threads, as a query on the index's readers. The package suite runs one test at a time, so it is that test's.
    public static func processNanoseconds() -> UInt64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func nanoseconds(_ time: timeval) -> UInt64 { UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_usec) * 1_000 }
        return nanoseconds(usage.ru_utime) + nanoseconds(usage.ru_stime)
    }

    /// How many milliseconds of the calling thread's processor time `work` used, with what it returned.
    public static func onThisThread<Value>(_ work: () throws -> Value) rethrows -> (value: Value, milliseconds: Double) {
        let start = threadNanoseconds()
        let value = try work()
        return (value, Double(threadNanoseconds() - start) / 1_000_000)
    }

    /// How many seconds of the test process's processor time `work` used, on any thread, with what it returned.
    public static func inThisProcess<Value>(_ work: () async throws -> Value) async rethrows -> (value: Value, seconds: Double) {
        let start = processNanoseconds()
        let value = try await work()
        return (value, Double(processNanoseconds() - start) / 1_000_000_000)
    }
}
