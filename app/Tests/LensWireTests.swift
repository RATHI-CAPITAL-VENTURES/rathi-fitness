import XCTest
@testable import RathiFitness

/// The Web App lens's contract, held three ways: the Swift encoder, the
/// committed fixtures in `wire/fixtures/` (which ria-ar-feed's CI fetches and
/// renders), and `docs/LENS_WIRE.md`. Every row of plan §4 is a fixture here,
/// encoded byte for byte.
///
/// The fixtures are PUBLIC: exercise names come from `Catalogue`, loads from
/// the synthetic list the `wire-fixtures-synthetic` guard checks, and every
/// time is counted from zero — no date, no real timestamp.
///
/// To re-record after a deliberate change, run the tests with
/// `TEST_RUNNER_LENS_WIRE_RECORD=1` (xcodebuild hands `TEST_RUNNER_`-prefixed
/// variables to the test process), then read the diff before committing it.
@MainActor
final class LensWireTests: XCTestCase {

    /// Time zero for every fixture, so `endsAt` is "72 s after zero", never a date.
    static let t0 = Date(timeIntervalSince1970: 0)

    static func resting(_ remaining: Int, of total: Int) -> LensState.Rest {
        .init(RestClock(endsAt: t0.addingTimeInterval(TimeInterval(remaining)), total: TimeInterval(total)), at: t0)
    }

    static let playing = LensMusic.Track(title: "Synthetic Track", artist: "Synthetic Artist", isPlaying: true)
    static let console = "Log it on your phone — its numbers come off the console."

    /// Plan §4, row by row. The names are the fixtures' file names.
    static var screens: [(name: String, screen: LensScreen)] {
        var ready = LensState.strength(exercise: "Bench Press", day: "Push", nextSet: 2, of: 4,
                                       weight: 185, word: "", reps: 8, resting: nil)
        ready.actions = [.logSet, .fewerReps, .back]
        var resting = LensState.strength(exercise: "Bench Press", day: "Push", nextSet: 3, of: 4,
                                         weight: 185, word: "", reps: 8, resting: Self.resting(72, of: 90))
        resting.actions = [.skipRest, .extendRest, .list]
        let done = LensState.strength(exercise: "Bench Press", day: "Push", nextSet: 5, of: 4,
                                      weight: 185, word: "", reps: 8, resting: nil)
        let mirror = LensState.strength(exercise: "Dumbbell Bench Press", day: "Push", nextSet: 1, of: 3,
                                        weight: 45, word: "each", reps: 10, resting: nil)
        let cardio = LensState.cardio(exercise: "Treadmill", day: "Push", seconds: 1_200,
                                      boutsDone: 0, of: 1, resting: nil, canLog: true)
        let cardioUnset = LensState.cardio(exercise: "Treadmill", day: "Push", seconds: 0,
                                           boutsDone: 0, of: 1, resting: nil, canLog: false)
        let cardioResting = LensState.cardio(exercise: "Treadmill", day: "Push", seconds: 300,
                                             boutsDone: 1, of: 3, resting: Self.resting(45, of: 60), canLog: true)
        let cardioDone = LensState.cardio(exercise: "Treadmill", day: "Push", seconds: 300,
                                          boutsDone: 3, of: 3, resting: nil, canLog: true)
        let restSpec = LensMusic.restClock(in: .set(resting))

        return [
            ("set-strength-ready", LensMusic.offering(.set(ready))),
            ("set-strength-resting", LensMusic.offering(.set(resting))),
            ("set-strength-done", LensMusic.offering(.set(done))),
            ("set-strength-mirror", LensMusic.offering(.set(mirror))),
            ("set-cardio-clock", LensMusic.offering(.set(cardio))),
            ("set-cardio-unset", LensMusic.offering(.set(cardioUnset))),
            ("set-cardio-resting", LensMusic.offering(.set(cardioResting))),
            ("set-cardio-done", LensMusic.offering(.set(cardioDone))),
            ("list-today", .list(LensList(
                eyebrow: "PUSH · 1 OF 4 DONE",
                rows: [
                    .init(title: "Bench Press", trailing: "2 of 4", done: false, action: .open(0), progress: 0.5),
                    .init(title: "Lat Pulldown", trailing: "135 × 10", done: false, action: .open(1), progress: 0),
                    .init(title: "Treadmill", trailing: Fmt.minutes(1_200), done: false, action: .open(2), progress: 0),
                    .init(title: "Leg Press", trailing: "done", done: true, action: .open(3), progress: 1),
                ],
                footer: [.close]))),
            ("list-swap", .list(LensList(
                eyebrow: "INSTEAD OF LEG PRESS",
                rows: [
                    .init(title: "Hack Squat", trailing: "usual swap", done: false, action: .open(0)),
                    .init(title: "Goblet Squat", trailing: "same job", done: false, action: .open(1)),
                ],
                footer: [.back]))),
            ("card-exercise", .card(LensCard(
                eyebrow: "PUSH · 1 OF 4", title: "Bench Press",
                specs: [.init(label: "Load", value: "185 × 8"), .init(label: "Sets", value: "4"),
                        .init(label: "Rest", value: Fmt.clock(90)), .init(label: "Bench angle", value: "3")],
                lines: [], actions: [.start, .taken, .back]))),
            ("card-exercise-finished", .card(LensCard(
                eyebrow: "PUSH · 1 OF 4", title: "Bench Press",
                specs: [.init(label: "Load", value: "185 × 8"), .init(label: "Sets", value: "4"),
                        .init(label: "Rest", value: Fmt.clock(90))],
                lines: [], actions: [.back, .start]))),
            ("card-stand-in", .card(LensCard(
                eyebrow: "LEGS · 2 OF 4", title: "Hack Squat",
                specs: [.init(label: "Load", value: "225 × 8"), .init(label: "Sets", value: "3"),
                        .init(label: "Rest", value: Fmt.clock(120))],
                lines: ["Today, instead of Leg Press"], actions: [.start, .taken, .back]))),
            ("card-machine", .card(LensCard(
                eyebrow: "PUSH · 3 OF 4", title: "Treadmill",
                specs: [.init(label: "Time", value: Fmt.minutes(1_200))],
                lines: [console], actions: [.back]))),
            ("card-next-up", .card(LensCard(
                eyebrow: "BENCH PRESS · DONE", title: "Lat Pulldown",
                lines: ["Next · 135 × 10"], actions: [.start, .list]))),
            ("card-wrap-up", .card(LensCard(
                eyebrow: "PUSH", title: "That's the workout", lines: ["4 of 4 done"], actions: [.list]))),
            ("card-wrap-up-machine", .card(LensCard(
                eyebrow: "PUSH", title: "Treadmill is left", lines: ["3 of 4 done", console], actions: [.list]))),
            ("card-music-playing", .card(LensMusic.card(playing, rest: restSpec))),
            ("card-music-paused", .card(LensMusic.card(.init(title: "Synthetic Track", artist: nil, isPlaying: false),
                                                       rest: nil))),
            ("card-music-nothing", .card(LensMusic.card(nil, rest: restSpec))),
            ("card-music-no-playlist", .card(LensMusic.card(nil, rest: nil, canStart: false))),
        ]
    }

    static func message(_ index: Int, _ screen: LensScreen) -> String {
        LensWire.text(LensWire.screenMessage(epoch: "fixture0", seq: index + 1, screen: screen, now: t0)) + "\n"
    }

    static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("wire/fixtures")
    }

    static var recording: Bool { ProcessInfo.processInfo.environment["LENS_WIRE_RECORD"] == "1" }

    private func check(_ name: String, _ text: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = Self.fixtures.appendingPathComponent("\(name).json")
        if Self.recording {
            try FileManager.default.createDirectory(at: Self.fixtures, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let committed = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text, committed, "\(name) no longer encodes to its fixture — the contract moved", file: file, line: line)
    }

    // MARK: - Every §4 row, byte for byte

    func testEveryScreenEncodesToItsFixture() throws {
        for (index, row) in Self.screens.enumerated() {
            try check("screen-\(row.name)", Self.message(index, row.screen))
        }
    }

    /// No orphans: a fixture nobody encodes any more is a contract nobody keeps.
    func testEveryFixtureHasAScreen() throws {
        let names = Set(Self.screens.map { "screen-\($0.name).json" } + ["coolhue.json"])
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path).filter { $0.hasSuffix(".json") }
        XCTAssertEqual(Set(files), names)
    }

    /// Plan §3: all fourteen `LensAction`s are on the wire, none excluded.
    func testEveryActionIsOnTheWireAndInAFixture() {
        let sent = Set(Self.screens.flatMap { $0.screen.actions }.map { action -> String in
            if case .open = action { return "open" }
            return LensWire.text(LensWire.action(action))
        })
        let every = LensWire.actionNames.map { "\"\($0.name)\"" } + ["open"]
        XCTAssertEqual(LensWire.actionNames.count + 1, 14)
        XCTAssertEqual(sent, Set(every))
    }

    func testAnActionComesBackAsItself() {
        for (action, name) in LensWire.actionNames {
            XCTAssertEqual(LensWire.action(from: name), action)
        }
        XCTAssertEqual(LensWire.action(from: ["open": 3]), .open(3))
        XCTAssertNil(LensWire.action(from: ["open": -1]))
        XCTAssertNil(LensWire.action(from: "logset"), "an unknown action is refused, never guessed")
        XCTAssertNil(LensWire.action(from: 7))
    }

    // MARK: - Rest timing as data

    /// The two running clocks travel as `rest`, never as text: the resting set
    /// sends no numeral, and the music card's Rest has no value.
    func testARunningClockTravelsAsADeadline() throws {
        let resting = Self.screens.first { $0.name == "set-strength-resting" }!.screen
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(LensWire.text(LensWire.screen(resting, now: Self.t0)).utf8)) as? [String: Any])
        XCTAssertNil(json["hero"])
        let rest = try XCTUnwrap(json["rest"] as? [String: Any])
        XCTAssertEqual(rest["remainingMsAtSend"] as? Int, 72_000)
        XCTAssertEqual(rest["totalMs"] as? Int, 90_000)
        XCTAssertEqual(rest["endsAt"] as? Int, 72_000)

        let ready = Self.screens.first { $0.name == "set-strength-ready" }!.screen
        XCTAssertTrue(LensWire.text(LensWire.screen(ready, now: Self.t0)).contains("\"rest\":null"))
    }

    /// The `Rest` spec on an exercise card is the PLANNED length, a fixed fact,
    /// and stays text. Only the music card's ticks.
    func testOnlyTheMusicCardsRestTicks() {
        let card = Self.screens.first { $0.name == "card-exercise" }!.screen
        XCTAssertTrue(LensWire.text(LensWire.screen(card, now: Self.t0)).contains("{\"label\":\"Rest\",\"value\":\"1:30\"}"))
        let music = Self.screens.first { $0.name == "card-music-playing" }!.screen
        XCTAssertTrue(LensWire.text(LensWire.screen(music, now: Self.t0))
            .contains("{\"label\":\"Rest\",\"rest\":{\"endsAt\":72000,\"remainingMsAtSend\":72000,\"totalMs\":90000}}"))
    }

    func testRemainingIsCountedFromTheSend() {
        let clock = RestClock(endsAt: Self.t0.addingTimeInterval(60), total: 90)
        let later = Self.t0.addingTimeInterval(59.7)
        XCTAssertEqual(LensWire.rest(clock, now: later), .object([
            "endsAt": .int(60_000), "totalMs": .int(90_000), "remainingMsAtSend": .int(300)]))
        XCTAssertEqual(LensWire.rest(clock, now: Self.t0.addingTimeInterval(61)),
                       .object(["endsAt": .int(60_000), "totalMs": .int(90_000), "remainingMsAtSend": .int(0)]),
                       "never negative: an overdue rest is READY on the page, not minus a second")
    }

    // MARK: - The native lens is unchanged

    /// The same timer state gives the same native screen whether the rest came
    /// from `RestTimer.remaining` (as before) or from a clock. Only the new
    /// `rest` field differs, and nothing native reads it.
    func testAClockGivesTheSameNativeScreen() {
        let start = Date(timeIntervalSince1970: 50_000)
        let clock = RestClock(endsAt: start.addingTimeInterval(90), total: 90)
        for offset in [0.0, 0.2, 17.5, 44.99, 45.0, 89.9, 90, 95] {
            let now = start.addingTimeInterval(offset)
            let remaining = max(0, Int(clock.endsAt.timeIntervalSince(now).rounded(.up)))
            for (legacy, timed) in [
                (LensState.strength(exercise: "Bench Press", day: "Push", nextSet: 2, of: 4, weight: 185, word: "",
                                    reps: 8, resting: .init(remaining: remaining, total: 90)),
                 LensState.strength(exercise: "Bench Press", day: "Push", nextSet: 2, of: 4, weight: 185, word: "",
                                    reps: 8, resting: .init(clock, at: now))),
                (LensState.cardio(exercise: "Treadmill", day: nil, seconds: 60, boutsDone: 1, of: 3,
                                  resting: .init(remaining: remaining, total: 90), canLog: true),
                 LensState.cardio(exercise: "Treadmill", day: nil, seconds: 60, boutsDone: 1, of: 3,
                                  resting: .init(clock, at: now), canLog: true)),
            ] {
                XCTAssertEqual(timed.rest, clock)
                var stripped = timed
                stripped.rest = nil
                XCTAssertEqual(stripped, legacy, "at +\(offset) s")
            }
        }
    }

    private func bench(_ clock: RestClock, at now: Date) -> LensScreen {
        .set(.strength(exercise: "Bench Press", day: "Push", nextSet: 2, of: 4, weight: 185, word: "",
                       reps: 8, resting: .init(clock, at: now)))
    }

    /// Two calls inside one second compare equal in both projections; a second
    /// later the native screen has moved and the clock-free one has not.
    func testTheClockFreeScreenOnlyMovesWhenTheDeadlineDoes() {
        let start = Date(timeIntervalSince1970: 50_000)
        let clock = RestClock(endsAt: start.addingTimeInterval(90), total: 90)
        let a = bench(clock, at: start.addingTimeInterval(10.1))
        let b = bench(clock, at: start.addingTimeInterval(10.6))
        let c = bench(clock, at: start.addingTimeInterval(11.6))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.clockFree, b.clockFree)
        XCTAssertNotEqual(a, c, "the native lens is still sent every second")
        XCTAssertEqual(a.clockFree, c.clockFree, "the web lens is not")

        var extended = clock
        extended.endsAt += 30
        extended.total += 30
        XCTAssertNotEqual(bench(extended, at: start.addingTimeInterval(10.1)).clockFree, a.clockFree,
                          "+30 s moves the deadline, which is a change worth sending")
    }

    func testTheMusicCardsClockIsClockFreeToo() {
        let start = Date(timeIntervalSince1970: 50_000)
        let clock = RestClock(endsAt: start.addingTimeInterval(90), total: 90)
        let card = { (now: Date) in
            LensScreen.card(LensMusic.card(Self.playing, rest: LensMusic.restClock(in: self.bench(clock, at: now))))
        }
        XCTAssertNotEqual(card(start), card(start.addingTimeInterval(5)))
        XCTAssertEqual(card(start).clockFree, card(start.addingTimeInterval(5)).clockFree)
    }

    // MARK: - Colour parity

    /// `coolHue` and `coolSaturation`, sampled, for the page's JS port to be
    /// checked against (plan §4, colour parity).
    func testTheCoolingColourIsEmittedForThePage() throws {
        let samples: [LensWire.JSON] = stride(from: 0, through: 20, by: 1).map { step in
            let p = Double(step) / 20
            return .object([
                "progress": .double(p),
                "hue": .double((RFDesign.coolHue(p) * 10_000).rounded() / 10_000),
                "saturation": .double((RFDesign.coolSaturation(p) * 10_000).rounded() / 10_000),
            ])
        }
        try check("coolhue", LensWire.text(.object(["v": .int(LensWire.version), "samples": .array(samples)])) + "\n")
    }

    // MARK: - JSON

    func testTextIsDeterministicAndEscaped() {
        XCTAssertEqual(LensWire.text(.object(["b": .int(1), "a": .string("q\"\\\n×")])),
                       "{\"a\":\"q\\\"\\\\\\n×\",\"b\":1}")
        XCTAssertEqual(LensWire.text(.double(0.5)), "0.5")
        XCTAssertEqual(LensWire.text(.double(1)), "1")
    }

    func testOnlyVersionOneIsRead() {
        XCTAssertNotNil(LensWire.decode("{\"type\":\"pong\",\"roomNow\":1}"))
        XCTAssertNotNil(LensWire.decode("{\"v\":1,\"type\":\"pong\"}"))
        XCTAssertNil(LensWire.decode("{\"v\":2,\"type\":\"pong\"}"))
        XCTAssertNil(LensWire.decode("{\"v\":1}"))
        XCTAssertNil(LensWire.decode("not json"))
    }
}

/// Pairing: what the scanner may hand over, and the deep link that adds the
/// Web App to the glasses.
final class LensPairingTests: XCTestCase {

    func testAPairingCodeIsReadOnlyWithItsPrefix() {
        let key = "abcdefghij0123456789_-"
        XCTAssertEqual(LensPairing.parse("rflens1:\(key)"), .init(key: key, fragment: nil))
        XCTAssertEqual(LensPairing.parse("  rflens1:\(key)\n"), .init(key: key, fragment: nil))
        XCTAssertNil(LensPairing.parse(key), "a bare key is refused: a gym pass's code can look like one")
        XCTAssertEqual(LensPairing.parse("rflens1:\(key)#k=a&lk=b"), .init(key: key, fragment: "k=a&lk=b"))
    }

    /// Exactly what ria-ar-feed's `bin/pair-phone` prints: three
    /// `secrets.token_urlsafe(32)` keys (43 characters each), the phone's
    /// before the `#`, the Web App's fragment after it.
    func testWhatPairPhonePrintsIsRead() {
        let phone = "Zk3_9Qx-Lw0pT7rNcV2bYhJ8sMdA4eUoG6iKqF1lR5w"
        let feed = "a8Fh2-kLmN0pQrStUvWxYz_1234567890ABCDEFGHIJ"
        let lens = "Qw-Er_Ty1Ui2Op3As4Df5Gh6Jk7Lz8Xc9Vb0NmMnBvC"
        XCTAssertEqual([phone, feed, lens].map(\.count), [43, 43, 43])
        let paired = LensPairing.parse("rflens1:\(phone)#k=\(feed)&lk=\(lens)")
        XCTAssertEqual(paired, .init(key: phone, fragment: "k=\(feed)&lk=\(lens)"))
        XCTAssertEqual(LensPairing.addToGlasses(fragment: paired!.fragment!)?.absoluteString,
                       "fb-viewapp://web_app_deep_link?appName=Fitness&appUrl=https%3A%2F%2Ffeed.app.ishanrathi.com%2F%23k%3D\(feed)%26lk%3D\(lens)")
    }

    /// The camera reads every QR it sees. A gym pass or a URL is not a key.
    func testAnythingElseIsNotAKey() {
        XCTAssertNil(LensPairing.parse("rflens1:short"))
        XCTAssertNil(LensPairing.parse("https://feed.app.ishanrathi.com/#k=abc"))
        XCTAssertNil(LensPairing.parse("MEMBER 0042 1234 5678"))
        XCTAssertNil(LensPairing.parse(""))
    }

    /// Pinned to RIA's `bin/glasses-url`: its `urlencode` gives exactly this
    /// for this URL (run 2026-10-10). Meta AI does not recognise anything looser.
    func testAddToGlassesIsEncodedTheWayGlassesUrlDoes() {
        let link = LensPairing.addToGlasses(fragment: "k=abc_DEF-123&lk=xyz.789~")
        XCTAssertEqual(link?.absoluteString,
                       "fb-viewapp://web_app_deep_link?appName=Fitness&appUrl="
                       + "https%3A%2F%2Ffeed.app.ishanrathi.com%2F%23k%3Dabc_DEF-123%26lk%3Dxyz.789~")
        XCTAssertEqual(LensPairing.encode("a b/é"), "a%20b%2F%C3%A9")
    }
}
