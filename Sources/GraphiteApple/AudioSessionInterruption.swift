/**
 * File: AudioSessionInterruption.swift
 * ------------------------------------
 * Layer: Apple
 * Description: What the audio session's notifications say about an interruption: it began when the system
 *              deactivated the session, and it ended with the system's recommendation on resuming.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

#if os(iOS)
import AVFoundation

/// An interruption of the audio session, read from its notifications, which replaced the
/// interruption notification in iOS 27; on iOS 26 it is read from that notification. A session Graphite deactivates itself is no interruption.
public enum AudioSessionInterruption: Sendable, Equatable {
    /// The system deactivated the session: a call, another app's audio, or the app suspended.
    case began
    /// The interruption ended; the system recommends resuming or not.
    case ended(shouldResume: Bool)

    /// The notifications to observe, which `init(_:)` reads. Before iOS 27 the session posts
    /// one interruption notification for both.
    public static var notificationNames: [Notification.Name] {
        if #available(iOS 27, *) {
            return [AVAudioSession.didBecomeInactiveNotification, AVAudioSession.resumptionRecommendationNotification]
        }
        return [AVAudioSession.interruptionNotification]
    }

    /// Nil for another notification, and for a deactivation Graphite asked for.
    public init?(_ notification: Notification) {
        guard #available(iOS 27, *) else {
            self.init(interruptionNotification: notification)
            return
        }
        switch notification.name {
        case AVAudioSession.didBecomeInactiveNotification:
            let deactivation = notification.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
            guard deactivation?.source == .system else { return nil }
            self = .began
        case AVAudioSession.resumptionRecommendationNotification:
            let resumption = notification.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
            self = .ended(shouldResume: resumption?.recommendation == .shouldResume)
        default:
            return nil
        }
    }

    /// Reads the interruption notification iOS 26 posts, which only the system sends.
    init?(interruptionNotification notification: Notification) {
        guard notification.name == AVAudioSession.interruptionNotification,
              let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return nil }
        switch type {
        case .began:
            self = .began
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            self = .ended(shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
}
#endif
