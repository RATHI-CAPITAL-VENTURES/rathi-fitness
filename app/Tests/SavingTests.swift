import XCTest
import SwiftData
@testable import RathiFitness

/// A write that does not land has to say so.
///
/// The twenty-one `try? context.save()` calls this replaces were untestable by
/// construction: there was no return value, no log line and no state to assert
/// on, so "did that save?" had no answer anywhere in the app. These tests exist
/// as much to pin that seam open as to check the behaviour.
final class SavingTests: XCTestCase {

    private struct Refused: LocalizedError {
        var errorDescription: String? { "the store said no" }
    }

    private func context() -> ModelContext {
        ModelContext(Store.makeContainer(inMemory: true))
    }

    // MARK: the reporter

    func testRecordingAFailureKeepsWhatWasBeingDone() {
        let saves = Saves()
        saves.record(what: "adding a day", error: Refused())

        XCTAssertEqual(saves.failure?.what, "adding a day")
        XCTAssertEqual(saves.failure?.reason, "the store said no")
        XCTAssertEqual(saves.failures.count, 1)
    }

    /// The site is what turns a banner into something you can act on — it is
    /// the half of the log line that says where to look.
    func testAFailureRemembersWhereItHappened() {
        let saves = Saves()
        saves.record(what: "logging a set", error: Refused())
        XCTAssertTrue(saves.failure?.site.contains("SavingTests") ?? false,
                      "the failure should name its call site, got \(saves.failure?.site ?? "nil")")
    }

    /// Only the newest is shown, because if saving is broken it is broken for
    /// everything and twenty identical banners say nothing extra.
    func testOnlyTheNewestFailureIsShownButNoneAreForgotten() {
        let saves = Saves()
        saves.record(what: "adding a day", error: Refused())
        saves.record(what: "logging a set", error: Refused())

        XCTAssertEqual(saves.failure?.what, "logging a set")
        XCTAssertEqual(saves.failures.count, 2)
        XCTAssertEqual(saves.failures.map(\.what), ["adding a day", "logging a set"])
    }

    func testAcknowledgingHidesTheBannerWithoutErasingTheHistory() {
        let saves = Saves()
        saves.record(what: "adding a day", error: Refused())
        saves.acknowledge()

        XCTAssertNil(saves.failure, "the banner should go away when dismissed")
        XCTAssertEqual(saves.failures.count, 1, "but the failure still happened")
    }

    func testForgettingClearsBoth() {
        let saves = Saves()
        saves.record(what: "adding a day", error: Refused())
        saves.forget()

        XCTAssertNil(saves.failure)
        XCTAssertTrue(saves.failures.isEmpty)
    }

    // MARK: the save itself

    func testAGoodSaveReportsNothingAndSaysItWorked() throws {
        let saves = Saves()
        let context = context()
        context.insert(PlannedDay(name: "Day 4", weekday: 0, order: 3))

        XCTAssertTrue(context.saveOrReport("adding a day", to: saves))
        XCTAssertNil(saves.failure, "a save that worked has nothing to report")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedDay>()), 1)
    }

    // MARK: the operations that are a save in everything but name

    func testReportingFailureHandsBackTheValueWhenNothingGoesWrong() {
        let saves = Saves()
        let result = reportingFailure("exporting your data", to: saves) { 7 }

        XCTAssertEqual(result, 7)
        XCTAssertNil(saves.failure)
    }

    func testReportingFailureReportsAndReturnsNilWhenItThrows() {
        let saves = Saves()
        let result: Int? = reportingFailure("exporting your data", to: saves) {
            throw Refused()
        }

        XCTAssertNil(result)
        XCTAssertEqual(saves.failure?.what, "exporting your data")
        XCTAssertEqual(saves.failure?.reason, "the store said no")
    }

    /// The phrase is the message, so it has to read as one. Every call site
    /// completes "save failed while ___" — a bare "saving" tells the user only
    /// what they already knew.
    func testEveryCallSitePhraseCompletesTheSentence() throws {
        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/
            .deletingLastPathComponent()          // app/
            .appendingPathComponent("RathiFitness")

        let files = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "should have found the app sources")

        let pattern = try NSRegularExpression(
            pattern: #"(?:saveOrReport|reportingFailure)\(\s*"([^"]+)""#)
        var phrases: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let r = Range(match.range(at: 1), in: text) else { continue }
                phrases.append(String(text[r]))
            }
        }

        XCTAssertGreaterThanOrEqual(phrases.count, 20,
                                    "every former `try? context.save()` should be named")
        for phrase in phrases {
            XCTAssertTrue(phrase.hasSuffix("ing")
                          || phrase.contains("ing "),
                          "\"\(phrase)\" should be a gerund phrase — it completes "
                          + "\"save failed while ___\"")
            XCTAssertNotEqual(phrase, "saving",
                              "\"saving\" tells the user only what they already know")
        }
    }
}
