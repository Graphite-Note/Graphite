/**
 * File: AudioSessionInterruptionHostedTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Reading iOS 26's interruption notification: began, ended with and without the system's
 *              recommendation to resume, and a notification that is no interruption.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(iOS)
import AVFoundation
import XCTest
@testable import GraphiteApple

/// The notifications are made by the test and no audio session is activated, so nothing plays.
final class AudioSessionInterruptionHostedTests: XCTestCase {
    func testAnInterruptionThatBeganIsRead() {
        let notification = interruptionNotification(type: .began, options: nil)
        XCTAssertEqual(AudioSessionInterruption(interruptionNotification: notification), .began)
    }

    func testAnInterruptionThatEndedWithTheRecommendationToResumeIsRead() {
        let notification = interruptionNotification(type: .ended, options: .shouldResume)
        XCTAssertEqual(AudioSessionInterruption(interruptionNotification: notification), .ended(shouldResume: true))
    }

    func testAnInterruptionThatEndedWithoutTheRecommendationIsRead() {
        let withoutOptions = interruptionNotification(type: .ended, options: nil)
        XCTAssertEqual(AudioSessionInterruption(interruptionNotification: withoutOptions), .ended(shouldResume: false))
        let withEmptyOptions = interruptionNotification(type: .ended, options: [])
        XCTAssertEqual(AudioSessionInterruption(interruptionNotification: withEmptyOptions), .ended(shouldResume: false))
    }

    func testAnotherNotificationOrAnUnknownTypeIsNoInterruption() {
        let routeChange = Notification(
            name: AVAudioSession.routeChangeNotification,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        XCTAssertNil(AudioSessionInterruption(interruptionNotification: routeChange))
        let withoutType = Notification(name: AVAudioSession.interruptionNotification, userInfo: [:])
        XCTAssertNil(AudioSessionInterruption(interruptionNotification: withoutType))
        let unknownTypeRawValue: UInt = 99
        let unknownType = Notification(
            name: AVAudioSession.interruptionNotification,
            userInfo: [AVAudioSessionInterruptionTypeKey: unknownTypeRawValue]
        )
        XCTAssertNil(AudioSessionInterruption(interruptionNotification: unknownType))
    }

    func testTheNotificationsObservedMatchTheSystemsVersion() {
        if #available(iOS 27, *) {
            XCTAssertEqual(
                AudioSessionInterruption.notificationNames,
                [AVAudioSession.didBecomeInactiveNotification, AVAudioSession.resumptionRecommendationNotification]
            )
        } else {
            XCTAssertEqual(AudioSessionInterruption.notificationNames, [AVAudioSession.interruptionNotification])
        }
    }

    private func interruptionNotification(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions?
    ) -> Notification {
        var userInfo: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if let options { userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue }
        return Notification(name: AVAudioSession.interruptionNotification, userInfo: userInfo)
    }
}
#endif
