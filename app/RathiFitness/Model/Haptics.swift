import Foundation
#if canImport(CoreHaptics)
import CoreHaptics
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The taps.
///
/// A gym app talks to you through a phone that is face-down on a bench, in a
/// pocket, or clipped to a treadmill. Sound is optional there — the plates are
/// loud and the AirPods may be out — so every cue the app gives has to exist as
/// a *pattern you can feel* as well as one you can hear.
///
/// `UINotificationFeedbackGenerator` is not enough for that. It has three
/// patterns, they are the system's, and "rest is over" would be indistinguishable
/// from a text message arriving. Core Haptics lets us author the shapes, so the
/// countdown is three light taps and the handover is a swell — different enough
/// to read through a jacket.
///
/// One engine, because the hardware is one engine. It is started lazily and
/// restarted on the two documented ways it dies (app backgrounded, media
/// services reset); a silent haptic is a cosmetic failure, never a crash.
@MainActor
final class Haptics {
    static let shared = Haptics()

    /// The vocabulary. One case per thing the app has to say — adding a cue is
    /// a case and a pattern, not a new call site full of `if`s.
    enum Cue: String, CaseIterable {
        /// Each of the last three seconds of a cooldown.
        case tick
        /// A set went into the log.
        case logged
        /// The cooldown handed back to you.
        case restOver
        /// That set was a record.
        case record
        /// An AirPods gesture was received and understood.
        case gesture
        /// An AirPods gesture arrived and there was nothing to do with it.
        case refused
    }

    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    private var supported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }
    #endif

    private init() {}

    /// Warm the engine before the first cue, so the first tap is not the one
    /// that arrives 200ms late.
    func prepare() {
        #if canImport(CoreHaptics)
        guard supported, engine == nil else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        // Both of these fire in normal use: the engine stops when the app is
        // backgrounded and is reset when another process takes the hardware.
        engine?.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.engine = nil }
        }
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        try? engine?.start()
        #endif
    }

    func play(_ cue: Cue) {
        #if canImport(CoreHaptics)
        if supported {
            if engine == nil { prepare() }
            do {
                try engine?.start()
                let pattern = try CHHapticPattern(events: events(for: cue), parameters: [])
                let player = try engine?.makePlayer(with: pattern)
                try player?.start(atTime: CHHapticTimeImmediate)
                return
            } catch {
                // Fall through to the system generators below.
            }
        }
        #endif
        fallback(cue)
    }

    #if canImport(CoreHaptics)
    /// The patterns, written as (time, sharpness, intensity) so they can be read
    /// as rhythm rather than as API calls.
    private func events(for cue: Cue) -> [CHHapticEvent] {
        switch cue {
        case .tick:
            return [transient(at: 0, sharpness: 0.9, intensity: 0.45)]
        case .gesture:
            return [transient(at: 0, sharpness: 0.7, intensity: 0.6)]
        case .logged:
            // Two taps, close: "got it".
            return [transient(at: 0, sharpness: 0.5, intensity: 0.8),
                    transient(at: 0.09, sharpness: 0.5, intensity: 0.55)]
        case .restOver:
            // A swell into two firm taps. This is the one that has to be
            // tellable from a notification while the phone is in a pocket.
            return [continuous(from: 0, duration: 0.35, sharpness: 0.25, intensity: 0.55),
                    transient(at: 0.36, sharpness: 0.8, intensity: 1.0),
                    transient(at: 0.50, sharpness: 0.8, intensity: 1.0)]
        case .record:
            // Three rising taps. Reserved for a PR so it stays rare enough to mean something.
            return [transient(at: 0, sharpness: 0.4, intensity: 0.6),
                    transient(at: 0.10, sharpness: 0.6, intensity: 0.8),
                    transient(at: 0.22, sharpness: 0.9, intensity: 1.0)]
        case .refused:
            return [transient(at: 0, sharpness: 0.2, intensity: 0.35),
                    transient(at: 0.13, sharpness: 0.2, intensity: 0.35)]
        }
    }

    private func transient(at t: TimeInterval, sharpness: Float, intensity: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticSharpness, value: sharpness),
            .init(parameterID: .hapticIntensity, value: intensity),
        ], relativeTime: t)
    }

    private func continuous(from t: TimeInterval, duration: TimeInterval,
                            sharpness: Float, intensity: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticSharpness, value: sharpness),
            .init(parameterID: .hapticIntensity, value: intensity),
        ], relativeTime: t, duration: duration)
    }
    #endif

    /// Older hardware, the simulator, and any engine failure. Coarser, but the
    /// cue still lands — silence would be the app appearing to have missed it.
    private func fallback(_ cue: Cue) {
        #if canImport(UIKit)
        switch cue {
        case .tick, .gesture:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .logged:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .restOver, .record:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .refused:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}
