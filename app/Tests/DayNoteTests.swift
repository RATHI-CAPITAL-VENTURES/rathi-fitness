import XCTest
import SwiftData
@testable import RathiFitness

/// Locker 214. Today, and not tomorrow.
final class DayNoteTests: XCTestCase {

    private let cal = Calendar.current

    private func at(_ d: Int, _ h: Int = 18) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
    }

    private func context() -> ModelContext {
        ModelContext(Store.makeContainer(inMemory: true))
    }

    private func all(_ context: ModelContext) -> [DayNote] {
        (try? context.fetch(FetchDescriptor<DayNote>())) ?? []
    }

    private func set(_ kind: DayNoteKind, _ text: String, label: String = "",
                     on date: Date, in context: ModelContext) {
        DayNotes.set(kind, text: text, label: label, in: context, now: date, calendar: cal)
    }

    // MARK: it lasts a day

    func testWhatYouNoteIsThereToday() {
        let context = context()
        set(.locker, "214", on: at(14), in: context)

        let today = DayNotes.on(at(14, 21), among: all(context), calendar: cal)

        XCTAssertEqual(today.map(\.text), ["214"])
        XCTAssertEqual(today.first?.heading, "Locker")
    }

    /// The whole reason it is a dated row and not one editable block: nothing
    /// has to run at midnight for Thursday not to show Tuesday's locker.
    func testTomorrowIsBlankWithNothingHavingToClearIt() {
        let context = context()
        set(.locker, "214", on: at(14), in: context)

        XCTAssertTrue(DayNotes.on(at(15), among: all(context), calendar: cal).isEmpty)
    }

    func testThePastKeepsWhatYouWrote() {
        let context = context()
        set(.note, "Left knee — go easy", on: at(14), in: context)
        set(.locker, "9", on: at(15), in: context)

        XCTAssertEqual(DayNotes.on(at(14), among: all(context), calendar: cal).map(\.text),
                       ["Left knee — go easy"])
    }

    // MARK: one of each

    /// Correcting a digit must not grow a second "Locker" chip.
    func testSavingTwiceReplacesRatherThanStacks() throws {
        let context = context()
        set(.locker, "214", on: at(14, 18), in: context)
        set(.locker, "241", on: at(14, 19), in: context)
        try context.save()

        XCTAssertEqual(DayNotes.on(at(14), among: all(context), calendar: cal).map(\.text),
                       ["241"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DayNote>()), 1)
    }

    /// Before the save, too — a deleted row lingers in a fetch until pending
    /// changes are processed, and the strip redraws before that. The array
    /// here is what a view's `@Query` would still be holding: the old row,
    /// deleted but present, beside the new one.
    func testTheReplacedValueIsGoneImmediatelyAndTheNewOneIsThere() {
        let context = context()
        set(.locker, "214", on: at(14, 18), in: context)
        let held = all(context)
        set(.locker, "241", on: at(14, 19), in: context)

        let shown = DayNotes.on(at(14), among: held + all(context).filter { $0.text == "241" },
                                calendar: cal)

        XCTAssertEqual(shown.map(\.text), ["241"], "the old one gone AND the new one shown")
    }

    /// The write fetches for itself. It used to trust the caller's array —
    /// in the app, a `@Query` captured by a sheet's closure — so a stale array
    /// meant a second Locker row rather than a replaced one.
    func testAWriteReplacesWhateverTheCallerWasHolding() throws {
        let context = context()
        set(.locker, "214", on: at(14, 18), in: context)
        try context.save()
        // Nothing handed in: there is no array to be stale.
        DayNotes.set(.locker, text: "241", in: context, now: at(14, 19), calendar: cal)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DayNote>()), 1)
    }

    // MARK: two devices

    /// The model can have no unique attribute (CloudKit), so a locker saved on
    /// the phone and another on an offline iPad arrive as two rows for one
    /// day. Shown as they are: two filled Locker chips, and RIA reading both.
    func testTwoRowsForOneThingShowAsOneAndTheLatestWins() {
        let context = context()
        context.insert(DayNote(kind: .locker, text: "9", date: at(14, 8)))
        context.insert(DayNote(kind: .locker, text: "214", date: at(14, 18)))
        context.insert(DayNote(kind: .other, text: "30", label: "Towel", date: at(14, 8)))
        context.insert(DayNote(kind: .other, text: "31", label: "towel", date: at(14, 18)))
        context.insert(DayNote(kind: .other, text: "Sam", label: "Guest", date: at(14, 9)))

        let today = DayNotes.on(at(14, 20), among: all(context), calendar: cal)

        XCTAssertEqual(today.map(\.text), ["214", "Sam", "31"])
    }

    func testTheSnapshotNeverCarriesTwoLockers() throws {
        let context = context()
        context.insert(DayNote(kind: .locker, text: "9", date: at(14, 8)))
        context.insert(DayNote(kind: .locker, text: "214", date: at(14, 18)))
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: at(14, 20), appVersion: "t")

        XCTAssertEqual(snapshot.dayNotes.items.map(\.text), ["214"])
    }

    /// The next edit cleans up what sync left behind.
    func testSavingClearsEveryDuplicateNotJustOne() throws {
        let context = context()
        context.insert(DayNote(kind: .locker, text: "9", date: at(14, 8)))
        context.insert(DayNote(kind: .locker, text: "214", date: at(14, 18)))
        try context.save()

        set(.locker, "215", on: at(14, 19), in: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DayNote>()), 1)
    }

    func testClearingTheFieldIsTheDelete() throws {
        let context = context()
        set(.parking, "Level 2", on: at(14), in: context)
        set(.parking, "   ", on: at(14, 19), in: context)
        try context.save()

        XCTAssertTrue(DayNotes.on(at(14), among: all(context), calendar: cal).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DayNote>()), 0)
    }

    func testReplacingTodaysLeavesYesterdaysAlone() throws {
        let context = context()
        set(.locker, "9", on: at(13), in: context)
        set(.locker, "214", on: at(14), in: context)
        set(.locker, "215", on: at(14, 19), in: context)
        try context.save()

        XCTAssertEqual(DayNotes.on(at(13), among: all(context), calendar: cal).map(\.text), ["9"])
    }

    // MARK: the "etc"

    func testYourOwnHeadingsCoexist() {
        let context = context()
        set(.other, "31", label: "Towel", on: at(14), in: context)
        set(.other, "Sam", label: "Guest", on: at(14), in: context)

        let today = DayNotes.on(at(14), among: all(context), calendar: cal)

        XCTAssertEqual(today.map(\.heading), ["Guest", "Towel"])
    }

    func testTheSameHeadingReplacesWhateverItsCase() throws {
        let context = context()
        set(.other, "31", label: "Towel", on: at(14, 18), in: context)
        set(.other, "32", label: "towel", on: at(14, 19), in: context)
        try context.save()

        XCTAssertEqual(DayNotes.on(at(14), among: all(context), calendar: cal).map(\.text), ["32"])
    }

    /// Nothing to call it on its chip.
    func testAnOtherWithNoHeadingIsNotSaved() throws {
        let context = context()
        set(.other, "31", label: "  ", on: at(14), in: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DayNote>()), 0)
    }

    func testHeadingsYouHaveUsedAreOfferedMostRecentFirstOnce() {
        let context = context()
        set(.other, "31", label: "Towel", on: at(10), in: context)
        set(.other, "Sam", label: "Guest", on: at(12), in: context)
        set(.other, "30", label: "towel", on: at(13), in: context)
        set(.locker, "214", on: at(13), in: context)

        XCTAssertEqual(DayNotes.pastHeadings(among: all(context)), ["towel", "Guest"])
    }

    // MARK: same as last time

    func testYourUsualLockerIsOffered() {
        let context = context()
        set(.locker, "9", on: at(10), in: context)
        set(.locker, "214", on: at(12), in: context)

        XCTAssertEqual(DayNotes.lastValue(of: .locker, before: at(14),
                                          among: all(context), calendar: cal), "214")
    }

    /// "Same as last time" next to a value you typed ten minutes ago is not a
    /// suggestion, it is an echo.
    func testTodaysOwnValueIsNotLastTime() {
        let context = context()
        set(.locker, "214", on: at(14, 9), in: context)

        XCTAssertNil(DayNotes.lastValue(of: .locker, before: at(14, 18),
                                        among: all(context), calendar: cal))
    }

    /// Yesterday's "knee is sore" offered back as today's is the app putting
    /// words in your mouth.
    func testANoteIsNeverCarriedForward() {
        let context = context()
        set(.note, "Left knee — go easy", on: at(12), in: context)

        XCTAssertNil(DayNotes.lastValue(of: .note, before: at(14),
                                        among: all(context), calendar: cal))
    }

    func testLastTimeForAnOtherIsPerHeading() {
        let context = context()
        set(.other, "31", label: "Towel", on: at(12), in: context)
        set(.other, "Sam", label: "Guest", on: at(13), in: context)

        XCTAssertEqual(DayNotes.lastValue(of: .other, label: "towel", before: at(14),
                                          among: all(context), calendar: cal), "31")
    }

    // MARK: order, and the registry

    func testLockerThenParkingThenNoteThenYourOwn() {
        let context = context()
        set(.other, "31", label: "Towel", on: at(14), in: context)
        set(.note, "Go easy", on: at(14), in: context)
        set(.parking, "L2", on: at(14), in: context)
        set(.locker, "214", on: at(14), in: context)

        XCTAssertEqual(DayNotes.on(at(14), among: all(context), calendar: cal).map(\.heading),
                       ["Locker", "Parking", "Note", "Towel"])
    }

    /// The combination is the obvious next chip and it must not exist:
    /// everything here is written into a file any process on the Mac can read.
    ///
    /// The list is pinned EXACTLY, so adding any kind fails here and has to be
    /// a decision — a word-search alone is a tripwire for the word, and `case
    /// dial` walks past it. The word-search stays as the second line, over the
    /// hints too, since a hint is what tells you what to type.
    func testTheKindsAreExactlyTheseAndNoneIsForASecret() {
        XCTAssertEqual(DayNoteKind.allCases, [.locker, .parking, .note, .other],
                       "a new kind reaches the Mac in cleartext — decide that on purpose")
        let words = DayNoteKind.allCases.flatMap {
            [$0.rawValue, $0.label.lowercased(), $0.hint.lowercased()]
        }
        for secret in ["combo", "combination", "code", "pin", "password", "passcode"] {
            XCTAssertFalse(words.contains { $0.contains(secret) }, secret)
        }
    }

    /// A saved "Towel 31" is a noun. It wore "plus" — the add glyph, on a thing
    /// already added — because the kind's symbol doubled as the add chip's.
    func testASavedNoteNeverWearsTheAddGlyph() {
        for kind in DayNoteKind.allCases {
            XCTAssertNotEqual(kind.symbol, "plus", kind.rawValue)
        }
    }

    func testEveryChipCanBeToldApart() {
        let towel = DayNote(kind: .other, text: "31", label: "Towel")
        let guest = DayNote(kind: .other, text: "Sam", label: "Guest")
        let locker = DayNote(kind: .locker, text: "214")

        XCTAssertNotEqual(DayNotesStrip.identifier(for: towel),
                          DayNotesStrip.identifier(for: guest))
        XCTAssertEqual(DayNotesStrip.identifier(for: locker), "day-note-locker")
        XCTAssertEqual(DayNotesStrip.identifier(for: towel), "day-note-other-towel")

        // Two headings that survive the dedupe as two rows must be two ids.
        // Slugified, "Guest 1" and "Guest-1" were one.
        let a = DayNote(kind: .other, text: "Sam", label: "Guest 1")
        let b = DayNote(kind: .other, text: "Ann", label: "Guest-1")
        XCTAssertNotEqual(DayNotes.key(a.noteKind, a.label), DayNotes.key(b.noteKind, b.label))
        XCTAssertNotEqual(DayNotesStrip.identifier(for: a), DayNotesStrip.identifier(for: b))
    }

    /// Same instant, two rows: the survivor must not depend on the order they
    /// arrive in — the strip's query is sorted and the snapshot's fetch is not.
    func testATieOnTheInstantIsBrokenTheSameWayWhateverTheOrder() {
        let one = DayNote(kind: .locker, text: "9", date: at(14, 18))
        let two = DayNote(kind: .locker, text: "214", date: at(14, 18))

        XCTAssertEqual(DayNotes.on(at(14), among: [one, two], calendar: cal).map(\.text),
                       DayNotes.on(at(14), among: [two, one], calendar: cal).map(\.text))
    }

    func testEveryKindCanDescribeItself() {
        for kind in DayNoteKind.allCases {
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertFalse(kind.symbol.isEmpty)
            XCTAssertFalse(kind.hint.isEmpty)
        }
        XCTAssertEqual(DayNoteKind.allCases.filter { !$0.fitsOnAChip }, [.note])
        XCTAssertEqual(DayNoteKind.allCases.filter { !$0.isSingular }, [.other])
    }

    // MARK: the Mac

    func testTheSnapshotCarriesTodaysAndOnlyTodays() throws {
        let context = context()
        set(.locker, "9", on: at(13), in: context)
        set(.locker, "214", on: at(14), in: context)
        set(.other, "31", label: "Towel", on: at(14), in: context)
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: at(14, 20), appVersion: "t")

        XCTAssertEqual(snapshot.dayNotes.date, Fmt.day(at(14)))
        XCTAssertEqual(snapshot.dayNotes.until, Fmt.iso(cal.startOfDay(for: at(15))),
                       "the instant the PHONE's day ends — what a reader tests")
        XCTAssertEqual(snapshot.dayNotes.items.map(\.heading), ["Locker", "Towel"])
        XCTAssertEqual(snapshot.dayNotes.items.map(\.text), ["214", "31"])
        XCTAssertEqual(snapshot.dayNotes.items.map(\.kind), ["locker", "other"])
    }

    /// `today` is absent on a rest day. The notes must not go with it.
    func testARestDayStillExportsItsNotes() throws {
        let context = context()
        set(.parking, "Level 2", on: at(14), in: context)
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: at(14, 20), appVersion: "t")

        XCTAssertNil(snapshot.today)
        XCTAssertEqual(snapshot.dayNotes.items.map(\.text), ["Level 2"])
    }

    func testTheKeyIsSnakeCaseOnTheWire() throws {
        let context = context()
        set(.locker, "214", on: at(14), in: context)
        try context.save()
        let snapshot = try SnapshotBuilder.build(from: context, now: at(14, 20), appVersion: "t")

        let data = try SnapshotWriter.encoder().encode(snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let block = try XCTUnwrap(json["day_notes"] as? [String: Any])

        XCTAssertEqual(block["date"] as? String, Fmt.day(at(14)))
        XCTAssertEqual((block["items"] as? [[String: Any]])?.first?["text"] as? String, "214")
    }

    func testTheExportIncludesThem() throws {
        let context = context()
        set(.note, "felt heavy, shoulder clicked", on: at(14), in: context)
        set(.locker, "214", on: at(14), in: context)
        try context.save()

        let csv = try Export.dayNotesCSV(from: context)

        XCTAssertTrue(csv.hasPrefix("date,kind,heading,text"))
        XCTAssertTrue(csv.contains("\(Fmt.day(at(14))),locker,Locker,214"))
        XCTAssertTrue(csv.contains("\"felt heavy, shoulder clicked\""),
                      "a comma in a note must not become a second column")
    }
}
