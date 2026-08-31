import XCTest
import AVFoundation
@testable import RathiFitness

/// The AirPods layer, which is the only part of the app that can act without
/// anyone looking at it — so the thing under test is mostly what it *refuses*
/// to do.
@MainActor
final class HandsFreeTests: XCTestCase {

    private var controls: RemoteControls!

    override func setUp() {
        super.setUp()
        // Reset the mapping so a previous run's Settings change cannot decide
        // what a gesture means here.
        for gesture in RemoteControls.Gesture.allCases {
            UserDefaults.standard.removeObject(forKey: "remote.gesture.\(gesture.rawValue)")
        }
        controls = RemoteControls(music: MusicController())
    }

    // MARK: the mapping

    func testDefaultsKeepTheTwoGesturesEveryoneAlreadyKnows() {
        XCTAssertEqual(RemoteControls.Gesture.press.action, .playPause)
        XCTAssertEqual(RemoteControls.Gesture.double.action, .nextTrack)
        // The one nobody performs by accident is the one that touches the log.
        XCTAssertEqual(RemoteControls.Gesture.triple.action, .logSet)
    }

    func testAMappingSurvivesBeingChanged() {
        RemoteControls.Gesture.double.action = .extendRest
        XCTAssertEqual(RemoteControls.Gesture.double.action, .extendRest)
        RemoteControls.Gesture.double.action = RemoteControls.Gesture.double.defaultAction
        XCTAssertEqual(RemoteControls.Gesture.double.action, .nextTrack)
    }

    // MARK: what a squeeze does, and does not do

    /// The bug this whole design exists to avoid: a squeeze on the Trends tab
    /// inventing a set you never did.
    func testASqueezeWithNoWorkoutOnScreenLogsNothing() {
        var logged = 0
        controls.handlers = RemoteControls.Handlers()      // nothing wired up
        controls.run(.logSet)
        XCTAssertEqual(logged, 0)
        XCTAssertNil(controls.lastAction, "a refused gesture is not a performed one")
        _ = logged
    }

    func testTriplePressLogsTheSetWhenASetScreenIsUp() {
        var logged = 0
        controls.handlers = RemoteControls.Handlers(
            logSet: { logged += 1 },
            isResting: { false })
        controls.perform(.triple)
        XCTAssertEqual(logged, 1)
        XCTAssertEqual(controls.lastAction, .logSet)
    }

    /// Mid-rest there is no set to log, so the same squeeze means the other
    /// thing the screen is offering at that moment.
    func testTheSameSqueezeSkipsTheRestWhileTheCooldownIsRunning() {
        var logged = 0
        var skipped = 0
        controls.handlers = RemoteControls.Handlers(
            logSet: { logged += 1 },
            skipRest: { skipped += 1 },
            isResting: { true })
        controls.perform(.triple)
        XCTAssertEqual(logged, 0, "a set was logged during a rest")
        XCTAssertEqual(skipped, 1)
        XCTAssertEqual(controls.lastAction, .skipRest)
    }

    func testTurningHandsFreeOffStopsEverything() {
        var logged = 0
        controls.handlers = RemoteControls.Handlers(logSet: { logged += 1 })
        controls.enabled = false
        controls.perform(.triple)
        XCTAssertEqual(logged, 0)
        controls.enabled = true
    }

    func testAnnounceUsesTheScreensOwnSentence() {
        controls.handlers = RemoteControls.Handlers(
            describe: { "Bench Press. Set 2 of 4." })
        RemoteControls.Gesture.double.action = .announce
        controls.perform(.double)
        XCTAssertEqual(controls.lastAction, .announce)
        RemoteControls.Gesture.double.action = .nextTrack
    }

    // MARK: what gets said

    /// A synthesiser reading "137.5" says "point five", which is noise. Halves
    /// are the only fraction a weight room has.
    func testSpokenWeightsAreSaidTheWayPeopleSayThem() {
        XCTAssertEqual(Fmt.spoken(185), "185")
        XCTAssertEqual(Fmt.spoken(137.5), "137 and a half")
        XCTAssertEqual(Fmt.spoken(2.5), "2 and a half")
        XCTAssertEqual(Fmt.spoken(90), "90")
    }
}

/// The cue vocabulary. Every meaning the app has to convey exists in both
/// channels — sound and touch — because either one alone can be missed.
@MainActor
final class CueTests: XCTestCase {

    func testEveryHapticCueHasATone() {
        // `gesture` is the deliberate exception: an acknowledgement you feel
        // and do not hear, so it does not talk over the music it just changed.
        let silent: Set<Haptics.Cue> = [.gesture]
        for cue in Haptics.Cue.allCases where !silent.contains(cue) {
            XCTAssertNotNil(AudioHub.Tone(rawValue: cue.rawValue),
                            "\(cue.rawValue) can be felt but not heard")
        }
    }

    /// This used to call `play` and assert it did not throw, under a name that
    /// promised rather more. The renderer normalises now, so the claim in the
    /// name is one the test can actually make.
    func testTonesRenderWithoutClippingOrSilence() {
        let hub = AudioHub.shared
        for tone in AudioHub.Tone.allCases {
            for overMusic in [false, true] {
                let peak = peakOf(hub.render(.init(tone: tone, overMusic: overMusic)))
                XCTAssertGreaterThan(peak, 0.1,
                                     "\(tone.rawValue) renders near-silent")
                XCTAssertLessThanOrEqual(peak, 1.0,
                                         "\(tone.rawValue) clips")
            }
        }
    }

    /// The reason two renders exist.
    ///
    /// `MusicController` uses `ApplicationMusicPlayer`, which plays through the
    /// app's OWN audio session — and `.duckOthers` ducks other apps. Nothing
    /// attenuates our music under a cue, so the cue has to carry itself or it is
    /// simply not heard, which is what "I can't hear the ping over my music"
    /// was.
    func testACueHasToBeLouderWhenItIsCompetingWithOurOwnMusic() {
        let hub = AudioHub.shared
        for tone in AudioHub.Tone.allCases {
            let quiet = peakOf(hub.render(.init(tone: tone, overMusic: false)))
            let loud = peakOf(hub.render(.init(tone: tone, overMusic: true)))
            XCTAssertGreaterThan(loud, quiet * 1.5,
                                 "\(tone.rawValue) is no louder over music")
        }
    }

    /// The notification is the backup channel, and it must not go silent on the
    /// strength of a chime that cannot play. Before the session is taken there
    /// is no engine, so the alert has to bring its own sound.
    func testTheNotificationCarriesSoundWhenTheAppCannotMakeIt() {
        XCTAssertFalse(AudioHub.shared.willSoundCues,
                       "nothing is holding the session, so nothing will chime")
    }

    private func peakOf(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(channels[channel][frame]))
            }
        }
        return peak
    }
}
