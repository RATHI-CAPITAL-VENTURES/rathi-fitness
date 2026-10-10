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
    private var callActive = false
    private var queued = true
    private var clock = Date(timeIntervalSince1970: 1_000)
    private var calls: [String] = []
    private var feed: FeedAudio!

    override func setUp() {
        playing = true
        resting = true
        callActive = false
        queued = true
        calls = []
        feed = makeFeed(playLandsAtOnce: true)
    }

    /// `playLandsAtOnce: false` is MusicKit: `play()` returns and the player
    /// reports playing a moment later.
    private func makeFeed(playLandsAtOnce: Bool) -> FeedAudio {
        FeedAudio(isPlaying: { [unowned self] in self.playing },
                  hasTrack: { [unowned self] in self.queued },
                  isResting: { [unowned self] in self.resting },
                  isCallActive: { [unowned self] in self.callActive },
                  pause: { [unowned self] in self.calls.append("pause"); self.playing = false },
                  play: { [unowned self] in self.calls.append("play"); if playLandsAtOnce { self.playing = true } },
                  now: { [unowned self] in self.clock })
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

    /// The rule: music the person paused is not ours.
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
        playing = true
        feed.playbackChanged(isPlaying: true)            // you pressed play
        XCTAssertFalse(feed.pausedByUs)
        playing = false                                  // and later paused it again yourself
        feed.playbackChanged(isPlaying: false)
        feed.restEnded()
        XCTAssertEqual(calls, ["pause"], "READY does not override what you chose")
    }

    func testASecondSoundOnDoesNotPauseTwice() {
        feed.lensSound(on: true)
        feed.lensSound(on: true)
        XCTAssertEqual(calls, ["pause"])
    }

    func testOnlyDuringARest() {
        resting = false
        feed.lensSound(on: true)
        XCTAssertEqual(calls, [], "a Short outside a rest is not ours to arbitrate")
    }

    func testNothingQueuedIsNotStartedFromScratch() {
        feed.lensSound(on: true)
        queued = false
        feed.restEnded()
        XCTAssertEqual(calls, ["pause"], "no favourite playlist started in place of the song")
    }

    func testTheClaimIsAnnouncedForTheReadyCue() {
        var claims: [Bool] = []
        feed.claimChanged = { claims.append($0) }
        feed.lensSound(on: true)
        feed.restEnded()
        XCTAssertEqual(claims, [true, false])
    }

    // MARK: - Off, then on, inside MusicKit's play latency (review, item 1)

    /// Off starts a resume; on arrives before MusicKit reports playing. The
    /// Short must win: the play lands and is paused, and READY brings it back.
    /// Mutation: without the `resuming` window this fails — the music plays
    /// over the Short.
    func testOnWhileOurResumeIsInTheAirStillPauses() {
        feed = makeFeed(playLandsAtOnce: false)
        feed.lensSound(on: true)
        feed.lensSound(on: false)                        // resume asked, not landed
        XCTAssertEqual(calls, ["pause", "play"])
        XCTAssertFalse(playing)
        feed.lensSound(on: true)                         // the Short is unmuted again
        XCTAssertTrue(feed.pausedByUs, "the claim is taken although the music reads not-playing")
        playing = true
        feed.playbackChanged(isPlaying: true)            // the play lands
        XCTAssertEqual(calls, ["pause", "play", "pause"], "and is paused as it lands")
        XCTAssertTrue(feed.pausedByUs)
        feed.restEnded()
        XCTAssertEqual(calls, ["pause", "play", "pause", "play"])
    }

    func testOurOwnResumeLandingIsNotTheUserPressingPlay() {
        feed = makeFeed(playLandsAtOnce: false)
        feed.lensSound(on: true)
        feed.restEnded()
        playing = true
        feed.playbackChanged(isPlaying: true)
        XCTAssertFalse(feed.resuming)
        XCTAssertEqual(calls, ["pause", "play"])
    }

    func testOnThenOffBeforeTheResumeLandsLeavesNothingPending() {
        feed = makeFeed(playLandsAtOnce: false)
        feed.lensSound(on: true)
        feed.lensSound(on: false)
        feed.lensSound(on: true)
        feed.lensSound(on: false)
        playing = true
        feed.playbackChanged(isPlaying: true)
        XCTAssertEqual(calls, ["pause", "play"], "nothing paused when the play lands")
        XCTAssertFalse(feed.pausedByUs)
    }

    func testAResumeThatNeverLandsStopsCounting() {
        feed = makeFeed(playLandsAtOnce: false)
        feed.lensSound(on: true)
        feed.lensSound(on: false)                        // MusicKit fails; nothing lands
        clock += FeedAudio.resumePatience + 1
        feed.lensSound(on: true)
        XCTAssertFalse(feed.pausedByUs, "music that is not playing is not claimed")
    }

    // MARK: - Calls and Siri (review, item 2)

    /// The owner's rule: the music comes back at READY. A Siri query is a
    /// plain interruption with no call, and must not cancel that.
    /// Mutation: dropping the claim on every interruption fails this.
    func testSiriDoesNotCancelTheResume() {
        feed.lensSound(on: true)
        feed.interruption(began: true, system: true)     // Siri: no call
        feed.restEnded()
        XCTAssertEqual(calls, ["pause", "play"])
    }

    func testACallDropsTheClaim() {
        feed.lensSound(on: true)
        callActive = true
        feed.interruption(began: true, system: true)
        callActive = false                               // the call ends before READY
        feed.restEnded()
        XCTAssertEqual(calls, ["pause"], "nothing restarts after a call")
    }

    func testNothingIsResumedIntoACall() {
        feed.lensSound(on: true)
        callActive = true                                // a call, with no interruption seen
        feed.restEnded()
        XCTAssertEqual(calls, ["pause"])
    }

    /// Only the plain kind counts: the app being suspended or a route going
    /// away say nothing about who wants the speaker.
    /// Mutation: ignoring `system` fails this.
    func testOnlyAPlainInterruptionCounts() {
        feed.lensSound(on: true)
        callActive = true
        feed.interruption(began: true, system: false)
        callActive = false
        feed.restEnded()
        XCTAssertEqual(calls, ["pause", "play"])
    }

    func testTheInterruptionReasonsAreSorted() {
        XCTAssertTrue(GlassesFace.isSystemInterruption(nil))
        XCTAssertTrue(GlassesFace.isSystemInterruption(.default))
        XCTAssertFalse(GlassesFace.isSystemInterruption(.routeDisconnected))
        XCTAssertFalse(GlassesFace.isSystemInterruption(.builtInMicMuted))
    }

    // MARK: - The production pipelines (review, item 4)

    /// With a real `RestTimer`: start, extend, restart mid-rest, stop — READY
    /// exactly once. Then a second rest, a second READY.
    func testReadyFiresOncePerRestWithARealTimer() {
        let rest = RestTimer()
        var readies = 0
        let watch = FeedAudio.readyPublisher(rest.$endsAt.eraseToAnyPublisher()).sink { readies += 1 }
        defer { watch.cancel(); rest.stop() }
        XCTAssertEqual(readies, 0, "no READY before any rest")
        rest.start(seconds: 90, exercise: "Bench Press")
        rest.extend(by: 30)
        rest.start(seconds: 60, exercise: "Bench Press")  // restarted mid-rest
        XCTAssertEqual(readies, 0)
        rest.stop()
        XCTAssertEqual(readies, 1)
        rest.stop()
        XCTAssertEqual(readies, 1, "stopping nothing is not READY")
        rest.start(seconds: 60, exercise: "Bench Press")
        rest.stop()
        XCTAssertEqual(readies, 2)
    }

    func testPlaybackIsMappedOncePerChange() {
        let now = PassthroughSubject<MusicController.NowPlaying?, Never>()
        var seen: [Bool] = []
        let watch = FeedAudio.playbackPublisher(now.eraseToAnyPublisher()).sink { seen.append($0) }
        defer { watch.cancel() }
        now.send(nil)
        now.send(.init(title: "A", artist: nil, isPlaying: true))
        now.send(.init(title: "B", artist: nil, isPlaying: true))   // next track, still playing
        now.send(.init(title: "B", artist: nil, isPlaying: false))
        now.send(nil)
        XCTAssertEqual(seen, [false, true, false])
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
        face.feedAudio(isPlaying: { [unowned self] in self.playing }, hasTrack: { true }, isResting: { true },
                       pause: { [unowned self] in self.calls.append("pause"); self.playing = false },
                       play: { [unowned self] in self.calls.append("play"); self.playing = true },
                       playback: Empty().eraseToAnyPublisher(), restEnded: Empty().eraseToAnyPublisher())
        await host.beat()
        sockets.last!.deliver(["type": "hello-ok", "lenses": 1])
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
        face.feedAudio(isPlaying: { [unowned self] in self.playing }, hasTrack: { true }, isResting: { true },
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
}

/// `AudioHub.holdForLens` — the keep-alive — under the feed's pause. Pins
/// AudioHub, not `FeedAudio`: our pause stops the in-app music, which was one
/// of the things holding a locked phone awake, and the keep-alive must carry
/// on through it.
@MainActor
final class LensKeepAliveTests: XCTestCase {

    /// Our pause stops the in-app music, which was what held the process in
    /// the background. The keep-alive must carry on through it.
    func testThePhoneStaysAwakeWhileWePauseTheMusic() throws {
        let hub = AudioHub.shared
        hub.holdForLens(true)
        defer { hub.holdForLens(false); hub.ownMusicIsPlaying = false }
        try XCTSkipUnless(hub.isHoldingForLens, "no audio engine in this run (-RFSilent)")
        hub.ownMusicIsPlaying = true
        let feed = FeedAudio(isPlaying: { true }, isResting: { true },
                             pause: { hub.ownMusicIsPlaying = false },     // what MusicController's pause reports
                             play: { hub.ownMusicIsPlaying = true })
        feed.lensSound(on: true)
        XCTAssertTrue(hub.isHoldingForLens, "the keep-alive is not released by our pause")
        hub.lensWatchdog()
        XCTAssertTrue(hub.isLensSilencePlaying, "and the silence is playing while the music is not")
    }
}
