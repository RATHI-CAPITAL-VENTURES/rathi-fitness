import Combine
import XCTest
@testable import RathiFitness

/// A Short's sound pauses the workout music; READY brings it back — only if
/// the Short is what paused it (owner decision 2). The worst thing this can do
/// is start music the person stopped, or fight a phone call for the speaker.
@MainActor
final class FeedAudioTests: XCTestCase {

    private var playing = true
    private var resting = true
    private var calls: [String] = []
    private var feed: FeedAudio!

    override func setUp() {
        playing = true
        resting = true
        calls = []
        feed = FeedAudio(isPlaying: { [unowned self] in self.playing },
                         isResting: { [unowned self] in self.resting },
                         pause: { [unowned self] in self.calls.append("pause"); self.playing = false },
                         play: { [unowned self] in self.calls.append("play"); self.playing = true })
    }

    func testASoundPausesTheMusicAndReadyBringsItBack() {
        feed.lensSound(on: true)
        XCTAssertEqual(calls, ["pause"])
        XCTAssertTrue(feed.pausedByUs)
        feed.playbackChanged(isPlaying: false)          // MusicKit reports our own pause
        XCTAssertTrue(feed.pausedByUs, "our own pause does not forget the claim")
        feed.restEnded()
        XCTAssertEqual(calls, ["pause", "play"])
        XCTAssertFalse(feed.pausedByUs)
    }

    func testSoundOffBringsItBackToo() {
        feed.lensSound(on: true)
        feed.lensSound(on: false)
        XCTAssertEqual(calls, ["pause", "play"])
        feed.restEnded()
        XCTAssertEqual(calls, ["pause", "play"], "paid back once")
    }

    /// The rule the mutation check targets: music the person paused is not ours.
    func testMusicTheUserPausedIsNeverResumed() {
        playing = false                                  // paused by hand before the Short
        feed.lensSound(on: true)
        XCTAssertEqual(calls, [], "nothing to pause")
        feed.lensSound(on: false)
        feed.restEnded()
        XCTAssertEqual(calls, [], "and nothing to resume: we did not pause it")
    }

    func testPlayingItYourselfMidFeedHandsItBack() {
        feed.lensSound(on: true)
        feed.playbackChanged(isPlaying: true)            // you pressed play
        playing = true
        XCTAssertFalse(feed.pausedByUs)
        playing = false                                  // and later paused it again yourself
        feed.playbackChanged(isPlaying: false)
        feed.restEnded()
        XCTAssertEqual(calls, ["pause"], "READY does not override what you chose")
    }

    func testACallMidFeedIsNeverFoughtFor() {
        feed.lensSound(on: true)
        feed.interruption(began: true)
        feed.restEnded()
        XCTAssertEqual(calls, ["pause"], "nothing is resumed into a call")
        feed.interruption(began: false)
        feed.lensSound(on: false)
        XCTAssertEqual(calls, ["pause"], "nor after it: the claim went with the call")
    }

    func testNoPauseDuringAnInterruption() {
        feed.interruption(began: true)
        feed.lensSound(on: true)
        XCTAssertEqual(calls, [])
    }

    /// Siri sends `began` and never `ended`. That must not switch the feature
    /// off for the rest of the workout.
    func testASiriInterruptionThatNeverEndsDoesNotStickForever() {
        feed.interruption(began: true)
        feed.restEnded()
        feed.lensSound(on: true)
        XCTAssertEqual(calls, ["pause"], "the next rest works again")
        feed.restEnded()
        feed.interruption(began: true)
        feed.playbackChanged(isPlaying: true)            // music back after Siri
        feed.lensSound(on: true)
        XCTAssertEqual(calls, ["pause", "play", "pause"])
    }

    func testOnlyDuringARest() {
        resting = false
        feed.lensSound(on: true)
        XCTAssertEqual(calls, [], "a Short outside a rest is not ours to arbitrate")
    }

    func testASecondSoundOnDoesNotPauseTwice() {
        feed.lensSound(on: true)
        feed.lensSound(on: true)
        XCTAssertEqual(calls, ["pause"])
    }

    // MARK: - Through the wire, and pairing

    func testFeedAudioFromTheRoomReachesTheMusic() async {
        var sockets: [FakeSocket] = []
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let web = WebLens(socket: { let s = FakeSocket(); sockets.append(s); return s },
                          keepAlive: FakeKeepAlive(), key: { "phone-key-0123456789" },
                          now: { clock }, appVersion: "0.19.0", runsTimer: false)
        let host = LensHost(pumps: false)
        host.use(web)
        host.host(source: { .list(LensList(eyebrow: "PUSH", rows: [], footer: [.close])) },
                  onPinch: { _ in }, idle: { "" }, onScreenClosed: {})
        let face = GlassesFace(host: host, native: NativeLens(), web: web)
        face.feedAudio(isPlaying: { [unowned self] in self.playing }, isResting: { true },
                       pause: { [unowned self] in self.calls.append("pause"); self.playing = false },
                       play: { [unowned self] in self.calls.append("play"); self.playing = true },
                       playback: Empty().eraseToAnyPublisher(), restEnded: Empty().eraseToAnyPublisher())
        await host.beat()
        clock += 0.1
        sockets.last!.deliver(["v": 1, "type": "feedAudio", "on": true, "relayedAt": 1])
        XCTAssertEqual(calls, ["pause"])
        sockets.last!.deliver(["v": 1, "type": "feedAudio", "on": "yes"])
        XCTAssertEqual(calls, ["pause"], "only a boolean `on` counts")
        sockets.last!.deliver(["v": 1, "type": "feedAudio", "on": false])
        XCTAssertEqual(calls, ["pause", "play"])
    }

    func testRestEndingIsREADYFromThePhone() {
        let rest = PassthroughSubject<Void, Never>()
        let face = GlassesFace(host: LensHost(pumps: false), native: NativeLens(),
                               web: WebLens(socket: { FakeSocket() }, key: { nil }, runsTimer: false))
        face.feedAudio(isPlaying: { [unowned self] in self.playing }, isResting: { true },
                       pause: { [unowned self] in self.calls.append("pause"); self.playing = false },
                       play: { [unowned self] in self.calls.append("play"); self.playing = true },
                       playback: Empty().eraseToAnyPublisher(), restEnded: rest.eraseToAnyPublisher())
        face.feed?.lensSound(on: true)
        rest.send(())
        XCTAssertEqual(calls, ["pause", "play"])
    }

    /// Pairing is choosing the Web App: the owner paired, the lens stayed
    /// Native, and the glasses said "No workout".
    func testPairingSwitchesTheLensToTheWebApp() {
        let saved = UserDefaults.standard.string(forKey: "glasses.lens")
        let savedOn = UserDefaults.standard.object(forKey: "glasses.enabled")
        defer {
            UserDefaults.standard.set(saved, forKey: "glasses.lens")
            UserDefaults.standard.set(savedOn, forKey: "glasses.enabled")
        }
        UserDefaults.standard.set("native", forKey: "glasses.lens")
        UserDefaults.standard.set(false, forKey: "glasses.enabled")
        var stored: [LensPairing.Paired] = []
        let face = GlassesFace(host: LensHost(pumps: false), native: NativeLens(),
                               web: WebLens(socket: { FakeSocket() }, key: { stored.last?.key }, runsTimer: false))
        face.storeKey = { stored.append($0); return true }
        XCTAssertEqual(face.lens, .native)
        XCTAssertFalse(face.pair("MEMBER 0042 1234"), "not a pairing code")
        XCTAssertEqual(face.lens, .native, "a failed scan changes nothing")
        XCTAssertTrue(face.pair("rflens1:abcdefghij0123456789_-"))
        XCTAssertEqual(face.lens, .web)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "glasses.lens"), "web")
        face.lens = .native
        XCTAssertEqual(face.lens, .native, "choosing Native afterwards is still yours")
    }

    func testANoKeyStoreFailureLeavesTheLensAlone() {
        let saved = UserDefaults.standard.string(forKey: "glasses.lens")
        defer { UserDefaults.standard.set(saved, forKey: "glasses.lens") }
        UserDefaults.standard.set("native", forKey: "glasses.lens")
        let face = GlassesFace(host: LensHost(pumps: false), native: NativeLens(),
                               web: WebLens(socket: { FakeSocket() }, key: { nil }, runsTimer: false))
        face.storeKey = { _ in false }
        XCTAssertFalse(face.pair("rflens1:abcdefghij0123456789_-"))
        XCTAssertEqual(face.lens, .native)
    }

    // MARK: - The phone stays awake

    /// Our pause stops the in-app music, which was what held the process in
    /// the background. The keep-alive must carry on through it.
    func testThePhoneStaysAwakeWhileWePauseTheMusic() throws {
        let hub = AudioHub.shared
        hub.holdForLens(true)
        defer { hub.holdForLens(false); hub.ownMusicIsPlaying = false }
        try XCTSkipUnless(hub.isHoldingForLens, "no audio engine in this run (-RFSilent)")
        hub.ownMusicIsPlaying = true
        feed = FeedAudio(isPlaying: { true }, isResting: { true },
                         pause: { hub.ownMusicIsPlaying = false },     // what MusicController's pause reports
                         play: { hub.ownMusicIsPlaying = true })
        feed.lensSound(on: true)
        XCTAssertTrue(hub.isHoldingForLens, "the keep-alive is not released by our pause")
        hub.lensWatchdog()
        XCTAssertTrue(hub.isLensSilencePlaying, "and the silence is playing while the music is not")
    }
}
