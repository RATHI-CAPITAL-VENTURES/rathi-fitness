import XCTest
import SwiftData
@testable import RathiFitness

/// Changing your mind about rest, once, instead of once per slot.
///
/// The setting above this one has always refused to touch an existing plan, and
/// that refusal is right — a default that silently rewrites your programme is a
/// default you stop trusting. But the refusal left no way to do the thing on
/// purpose either, so the honest fix is an explicit, counted, confirmed apply
/// rather than loosening the default.
final class PlanRestTests: XCTestCase {

    private func context() -> ModelContext {
        ModelContext(Store.makeContainer(inMemory: true))
    }

    /// `order` is irrelevant to every assertion here, so it is not a parameter.
    @discardableResult
    private func slot(_ context: ModelContext, name: String, modality: Exercise.Modality = .strength,
                      rest: Int, day: PlannedDay) -> PlanItem {
        let exercise = Exercise(name: name, modality: modality)
        context.insert(exercise)
        let item = PlanItem(order: 0, exercise: exercise, targetSets: 3,
                            targetReps: 10, targetWeight: 100, restSeconds: rest)
        item.day = day
        context.insert(item)
        return item
    }

    private func day(_ context: ModelContext, _ name: String) -> PlannedDay {
        let day = PlannedDay(name: name, weekday: 2)
        context.insert(day)
        return day
    }

    // MARK: the write

    func testApplyingRestReachesEveryDayNotJustTheFirst() throws {
        let context = context()
        let push = day(context, "Push"), pull = day(context, "Pull")
        slot(context, name: "Bench", rest: 90, day: push)
        slot(context, name: "Row", rest: 45, day: pull)

        let changed = try PlanDefaults.applyRestToPlan(150, in: context)

        XCTAssertEqual(changed, 2, "both days' slots should be rewritten")
        for item in try context.fetch(FetchDescriptor<PlanItem>()) {
            XCTAssertEqual(item.restSeconds, 150, "\(item.exercise?.name ?? "?") kept its old rest")
        }
    }

    /// The count is what the confirmation puts in front of you, so it has to be
    /// the number of slots that actually move — not the number it looked at.
    func testTheCountIsWhatChangedNotWhatWasInspected() throws {
        let context = context()
        let push = day(context, "Push")
        slot(context, name: "Bench", rest: 90, day: push)
        slot(context, name: "Fly", rest: 120, day: push)

        XCTAssertEqual(try PlanDefaults.applyRestToPlan(120, in: context), 1,
                       "only the slot not already at 120 should count")
    }

    /// Tapping it twice is not two changes. A dialog that reports "set 8
    /// exercises" for a no-op is the app claiming work it did not do.
    func testApplyingTwiceReportsNothingTheSecondTime() throws {
        let context = context()
        let push = day(context, "Push")
        slot(context, name: "Bench", rest: 90, day: push)

        XCTAssertEqual(try PlanDefaults.applyRestToPlan(60, in: context), 1)
        XCTAssertEqual(try PlanDefaults.applyRestToPlan(60, in: context), 0)
    }

    // MARK: the exclusion

    /// The one that makes this safe. `restSeconds` on a cardio slot is the gap
    /// between intervals, and the plan editor creates every treadmill slot with
    /// `0` — so a blanket apply would not reset a rest, it would invent
    /// intervals on a row whose rest column currently reads "—".
    func testCardioKeepsItsOwnRest() throws {
        let context = context()
        let push = day(context, "Push")
        slot(context, name: "Bench", rest: 90, day: push)
        slot(context, name: "Treadmill", modality: .cardio, rest: 0, day: push)

        XCTAssertEqual(try PlanDefaults.applyRestToPlan(180, in: context), 1)

        let treadmill = try context.fetch(FetchDescriptor<PlanItem>())
            .first { $0.exercise?.isCardio == true }
        XCTAssertEqual(treadmill?.restSeconds, 0, "cardio should be left alone")
    }

    /// A cardio interval rest someone set by hand is exactly the setting a
    /// blanket apply must not eat — the zero above could be dismissed as
    /// "unset", this one cannot.
    func testAHandSetCardioIntervalSurvives() throws {
        let context = context()
        let push = day(context, "Push")
        slot(context, name: "Intervals", modality: .cardio, rest: 45, day: push)

        XCTAssertEqual(try PlanDefaults.applyRestToPlan(180, in: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlanItem>()).first?.restSeconds, 45)
    }

    // MARK: the count the dialog shows

    func testTheSlotCountExcludesCardioSoTheDialogDoesNotOverpromise() throws {
        let context = context()
        let push = day(context, "Push")
        slot(context, name: "Bench", rest: 90, day: push)
        slot(context, name: "Row", rest: 90, day: push)
        slot(context, name: "Treadmill", modality: .cardio, rest: 0, day: push)

        XCTAssertEqual(try PlanDefaults.slotsTakingPlanRest(in: context).count, 2)
    }

    func testAnEmptyPlanOffersNothingToApply() throws {
        let context = context()
        XCTAssertEqual(try PlanDefaults.slotsTakingPlanRest(in: context).count, 0)
        XCTAssertEqual(try PlanDefaults.applyRestToPlan(90, in: context), 0)
    }
}
