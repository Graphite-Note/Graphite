/**
 * File: SynthesizedInputCapability.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Whether a hosted test's synthesized touches and accessibility activations reach the system's own
 *              controls: they do on iOS 27, and on iOS 26 some take none of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(iOS)
import XCTest

/// On iOS 26 some controls take no synthesized touch or accessibility activation from a hosted test: a SwiftUI button in
/// the sidebar's list, a row of the file tree, a presentation's slide, an alert's action (the activation reports that it
/// ran and runs nothing). Real touches reach them, as an XCUITest of the installed app shows. A test whose next step
/// needs such a control stops there on iOS 26, after the checks before it, and says what was checked by hand instead.
enum SynthesizedInputCapability {
    static func requireItReachesSystemControls(_ whatIsLeftOut: String) throws {
        if #available(iOS 27, *) { return }
        throw XCTSkip("On iOS 26 a hosted test's synthesized input does not reach this control. \(whatIsLeftOut)")
    }
}
#endif
