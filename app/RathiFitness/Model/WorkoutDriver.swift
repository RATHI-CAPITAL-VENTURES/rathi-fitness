import Foundation
import SwiftData

/// The workout, driven from the glasses.
///
/// When a set screen is open on the phone the lens mirrors it, and none of this
/// runs. When none is — the phone is locked in a pocket — this decides what the
/// lens shows: today's exercises as a list, one of them as a card, and then the
/// same set-and-rest loop the phone has, moving on to the next exercise by
/// itself. A whole session without touching the phone.
///
/// It owns no workout logic. Which day it is, what is done, what weight to open
/// on and how a set is written are all `Workout`'s, shared with the views; what
/// could stand in for a taken machine is `Swaps`'. This is only the part that
/// had no home before: knowing where on the lens you are.
///
/// **Lifts only, on purpose.** A cardio bout's numbers — distance, speed,
/// incline, heart rate — come off the machine's console afterwards, and the
/// lens cannot type. Logging "as planned" would write a run you may not have
/// run. So a machine's card says what the plan asks and sends you to the phone,
/// where (mirrored) it still shows on the lens.
@MainActor
final class WorkoutDriver {

    /// Where on the lens you are.
    enum Place: Equatable {
        case list
        case card(PersistentIdentifier)
        case lifting(PersistentIdentifier)
        case swapping(PersistentIdentifier)
    }

    private(set) var place: Place = .list

    private let context: ModelContext
    private let rest: RestTimer
    private let snapshots: SnapshotService?
    private let calendar: Calendar

    // The numbers of the set in hand. The phone keeps these in `SetView`'s
    // `@State`; with no view, they live here.
    private(set) var weight: Double = 0
    private(set) var reps: Int = 0

    /// What each row of the list on the lens stood for, in order, so that
    /// `.open(2)` means the row that was third when it was drawn.
    private var rowItems: [PersistentIdentifier] = []
    private var rowStandIns: [Exercise] = []

    init(context: ModelContext, rest: RestTimer, snapshots: SnapshotService? = nil,
         calendar: Calendar = .current) {
        self.context = context
        self.rest = rest
        self.snapshots = snapshots
        self.calendar = calendar
    }

    // MARK: - When it has the lens at all

    /// How long after you last did anything the lens keeps showing the workout.
    static let attention: TimeInterval = 15 * 60
    /// Mid-workout, the gap between sets that still counts as "mid-workout".
    static let workoutGap: TimeInterval = 30 * 60

    private var liveUntil = Date.distantPast

    /// Why the lens is not ours right now, in words — for Settings. The first
    /// time this was tried on the glasses nothing appeared, and there was no
    /// way to tell "rest day" from "not started" from "broken".
    private(set) var idleReason = "Open the app at the gym to start."

    /// You are here: the app came to the front, a pinch arrived, a set screen
    /// just closed.
    func touch(at now: Date = .now) {
        liveUntil = now.addingTimeInterval(Self.attention)
        closed = false
        board = nil
        emptyUntil = .distantPast
    }

    /// Closed from the lens. Stays closed — even mid-workout — until the PHONE
    /// says otherwise: a pinch cannot be what reopens it, because the point of
    /// closing is that the lens is no longer ours to draw buttons on.
    private var closed = false

    /// A set screen on the phone just closed. Whatever it logged happened
    /// without this class, so the numbers in hand may be stale: you started the
    /// bench at 185 on the lens, opened it on the phone, moved to 205 and logged
    /// — and the lens, left alone, would write your next set at 185. Found in
    /// review. The opening is worked out again from what is now in the store.
    func screenClosed(at now: Date = .now) {
        touch(at: now)
        guard case .lifting(let id) = place, let board = load(at: now),
              let item = item(id, in: board), let exercise = Swaps.exercise(for: item) else { return }
        let opening = Workout.opening(for: item, doing: exercise, doneHere: doneHere(exercise, board),
                                      in: board.allSets, calendar: calendar)
        weight = opening.weight
        reps = opening.reps
    }

    /// The glasses give an app the WHOLE lens for as long as its session lasts.
    /// An app that took it whenever the glasses happened to be on — walking to
    /// work, cooking — would be one you uninstall. So the workout is on the
    /// lens only around a workout: shortly after you touched the app, or while
    /// a workout is open and its last set is recent.
    private func isLive(_ board: Board, at now: Date) -> Bool {
        if closed { return false }
        if now < liveUntil { return true }
        guard board.session != nil, let last = board.todaysSets.map(\.date).max() else { return false }
        return now.timeIntervalSince(last) < Self.workoutGap
    }

    // MARK: - What the store says

    private struct Board {
        var day: PlannedDay
        var items: [PlanItem]
        var session: Session?
        var allSets: [SetEntry]
        var todaysSets: [SetEntry]
    }

    private var board: Board?
    private var boardAt = Date.distantPast
    /// The hand-picked day the cached board was built for. A new pick on the
    /// phone has to show on the lens now, not when the cache next expires.
    private var boardChoice: PersistentIdentifier?
    /// "Nothing is planned today" is cached too. It was not, at first, and a
    /// rest day with the glasses on fetched every set ever logged once a second
    /// to keep arriving at the same nothing.
    private var emptyUntil = Date.distantPast

    /// Read, at most, every fifteen seconds — the lens asks once a second, and
    /// "every set ever logged" is not a fetch to run at that rate. Anything
    /// this class writes drops the cache itself; the staleness only ever
    /// covers a set logged on the phone while the lens was not the one driving.
    private func load(at now: Date) -> Board? {
        if let board, now.timeIntervalSince(boardAt) < 15, boardChoice == Workout.chosen?.day { return board }
        if boardChoice != Workout.chosen?.day {
            place = .list
            emptyUntil = .distantPast
        }
        boardChoice = Workout.chosen?.day
        if now < emptyUntil { return nil }
        let days = (try? context.fetch(FetchDescriptor<PlannedDay>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        let allSets = (try? context.fetch(FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let config = (try? context.fetch(FetchDescriptor<Schedule>()))?.first?.config ?? Rotation.Config()

        // The day picked with the calendar button on Today, if it was picked
        // today. Without this the lens and the phone disagree about which
        // workout it is the moment you train off-schedule.
        let chosen = Workout.chosenDay(among: days, now: now, calendar: calendar)
        guard let day = chosen ?? Workout.today(
            days: days, config: config, sessionDates: sessions.map(\.startedAt),
            lastSession: Workout.lastSessionDate(in: allSets, now: now, calendar: calendar),
            now: now, calendar: calendar)
        else {
            board = nil
            emptyUntil = now.addingTimeInterval(60)
            idleReason = "Nothing is planned today. Pick a workout with the calendar button on Today."
            return nil
        }
        let session = Workout.openSession(for: day, among: sessions, now: now, calendar: calendar)
        let fresh = Board(
            day: day, items: day.orderedItems, session: session, allSets: allSets,
            todaysSets: Workout.todaysSets(in: allSets, openSession: session, today: day,
                                           now: now, calendar: calendar))
        board = fresh
        boardAt = now
        return fresh
    }

    // MARK: - What the lens shows

    /// Nil means "nothing of ours belongs on the lens right now" — a rest day,
    /// or no workout anywhere near. `GlassesFace` hands the lens back.
    func screen(at now: Date = .now) -> LensScreen? {
        guard let board = load(at: now) else { return nil }
        guard isLive(board, at: now) else {
            idleReason = closed
                ? "Closed from your glasses. Open the app to bring the workout back."
                : "Open the app to bring the workout back — the lens is only taken around a workout."
            return nil
        }

        switch place {
        case .list:
            return .list(list(board))
        case .card(let id):
            guard let item = item(id, in: board), let exercise = Swaps.exercise(for: item) else { return home(board) }
            return .card(card(item, exercise, board))
        case .lifting(let id):
            guard let item = item(id, in: board), let exercise = Swaps.exercise(for: item),
                  !exercise.isCardio else { return home(board) }
            return lifting(item, exercise, board, at: now)
        case .swapping(let id):
            guard item(id, in: board) != nil, let swapping else { return home(board) }
            return .list(swapping)
        }
    }

    private func home(_ board: Board) -> LensScreen {
        place = .list
        return .list(list(board))
    }

    private func item(_ id: PersistentIdentifier, in board: Board) -> PlanItem? {
        board.items.first { $0.persistentModelID == id }
    }

    /// Today's plan. The order is a decision, because the first row arrives lit:
    /// what you are part-way through, then what is left in the plan's own order,
    /// then what is finished. The usual case is one pinch, no swiping.
    private func list(_ board: Board) -> LensList {
        let slots = board.items.filter { Swaps.exercise(for: $0) != nil }
        let done = slots.filter { Workout.isDone($0, in: board.todaysSets) }
        let started = slots.filter { slot in
            !done.contains { $0 === slot } && !Workout.performed(slot, in: board.todaysSets).isEmpty
        }
        let pending = slots.filter { slot in
            !done.contains { $0 === slot } && !started.contains { $0 === slot }
        }
        let ordered = started + pending + done

        let rows = ordered.enumerated().map { index, slot -> LensList.Row in
            let exercise = Swaps.exercise(for: slot)!
            let finished = done.contains { $0 === slot }
            let sets = max(1, Swaps.prescription(for: slot, doing: exercise).sets)
            let worked = exercise.isCardio
                ? Workout.performed(slot, in: board.todaysSets).count
                : Workout.working(slot, in: board.todaysSets).count
            return LensList.Row(title: exercise.name,
                                trailing: finished ? "done" : trailing(slot, exercise, board),
                                done: finished, action: .open(index),
                                progress: finished ? 1 : min(1, Double(worked) / Double(sets)))
        }
        let list = LensList(
            eyebrow: "\(board.day.name.uppercased()) · \(done.count) OF \(slots.count) DONE",
            // The only way to quit from the glasses. Last, so it is never the
            // row that arrives lit.
            rows: rows, footer: [.close])
        // What `.open(n)` means is fixed when the list CHANGES, not every time
        // it is asked for: the lens only repaints on a change, so until then
        // the rows the wearer is looking at are the rows this must resolve.
        if list != lastList {
            lastList = list
            rowItems = ordered.map(\.persistentModelID)
        }
        return list
    }

    private var lastList: LensList?

    /// The right-hand side of a row: how far through, else what you will lift.
    private func trailing(_ item: PlanItem, _ exercise: Exercise, _ board: Board) -> String {
        let plan = Swaps.prescription(for: item, doing: exercise)
        if exercise.isCardio {
            return plan.seconds > 0 ? Fmt.minutes(plan.seconds) : "cardio"
        }
        let worked = Workout.working(item, in: board.todaysSets).count
        if worked > 0 { return "\(worked) of \(plan.sets)" }
        let opening = Workout.opening(for: item, doing: exercise, doneHere: [],
                                      in: board.allSets, calendar: calendar)
        return opening.weight > 0 ? "\(Fmt.weight(opening.weight)) × \(opening.reps)" : "\(opening.reps) reps"
    }

    private func card(_ item: PlanItem, _ exercise: Exercise, _ board: Board) -> LensCard {
        let plan = Swaps.prescription(for: item, doing: exercise)
        let position = (board.items.firstIndex { $0 === item } ?? 0) + 1
        var lines: [String] = []
        if Swaps.isStandIn(exercise, in: item), let planned = item.exercise {
            lines.append("Today, instead of \(planned.name)")
        }
        // Where the seat goes is the thing you need BEFORE you start, and the
        // reason a card exists between the list and the first set.
        let settings = exercise.settings.map { LensCard.Spec(label: $0.setting.label, value: $0.value) }

        if exercise.isCardio {
            let time = plan.seconds > 0 ? [LensCard.Spec(label: "Time", value: Fmt.minutes(plan.seconds))] : []
            lines.append("Log it on your phone — its numbers come off the console.")
            return LensCard(eyebrow: eyebrow(board, position), title: exercise.name,
                            specs: time + settings, lines: lines, actions: [.back])
        }
        let opening = Workout.opening(for: item, doing: exercise, doneHere: doneHere(exercise, board),
                                      in: board.allSets, calendar: calendar)
        let load = opening.weight > 0 ? "\(Fmt.weight(opening.weight)) × \(opening.reps)" : "\(opening.reps) reps"
        let specs = [LensCard.Spec(label: "Load", value: load),
                     LensCard.Spec(label: "Sets", value: "\(plan.sets)"),
                     LensCard.Spec(label: "Rest", value: Fmt.clock(plan.restSeconds))]
        let finished = Workout.isDone(item, in: board.todaysSets)
        return LensCard(eyebrow: eyebrow(board, position), title: exercise.name,
                        specs: specs + settings, lines: lines,
                        // A finished lift can still be opened — a fifth set is
                        // your call — but it is not what arrives lit.
                        actions: finished ? [.back, .start] : [.start, .taken, .back])
    }

    private func eyebrow(_ board: Board, _ position: Int) -> String {
        "\(board.day.name.uppercased()) · \(position) OF \(board.items.count)"
    }

    private func lifting(_ item: PlanItem, _ exercise: Exercise, _ board: Board, at now: Date) -> LensScreen {
        let plan = Swaps.prescription(for: item, doing: exercise)
        let nextSet = Workout.working(item, in: progress(board)).count + 1
        let resting = rest.isResting && rest.exerciseName == exercise.name
        var state = LensState.strength(
            exercise: exercise.name, day: board.day.name, nextSet: nextSet, of: plan.sets,
            weight: weight, unit: exercise.weightUnit, reps: reps,
            resting: resting ? .init(remaining: rest.remaining(at: now), total: rest.total) : nil)

        switch state.tone {
        case .ready:
            // Log first, because it is the one that arrives lit.
            state.actions = reps > 1 ? [.logSet, .fewerReps, .back] : [.logSet, .back]
        case .resting:
            // Skip stays first — it is what you want nine rests in ten — but a
            // rest is also when you look around for the next machine. Found on
            // the first real use: after the last set the lens showed only Skip
            // and +30 s, and there was no way back to the list until the clock
            // ran out.
            state.actions = [.skipRest, .extendRest, .list]
        case .done:
            // Finished and rested: say what is next rather than sit on "Done".
            if let next = nextUp(after: item, board), let upcoming = Swaps.exercise(for: next) {
                return .card(LensCard(
                    eyebrow: "\(exercise.name.uppercased()) · DONE", title: upcoming.name,
                    lines: ["Next · " + trailing(next, upcoming, board)],
                    actions: [.start, .list]))
            }
            return .card(wrapUp(board))
        }
        return .set(state)
    }

    /// What is left when there is no lift left. Counted over the same slots, the
    /// same way, as the list — the first version said "3 of 3 done" here with
    /// the treadmill untouched, while the list behind it said 2 of 3.
    private func wrapUp(_ board: Board) -> LensCard {
        let slots = board.items.filter { Swaps.exercise(for: $0) != nil }
        let left = slots.filter { !Workout.isDone($0, in: board.todaysSets) }
        let count = "\(slots.count - left.count) of \(slots.count) done"
        guard let machine = left.first.flatMap({ Swaps.exercise(for: $0) }) else {
            return LensCard(eyebrow: board.day.name.uppercased(), title: "That's the workout",
                            lines: [count], actions: [.list])
        }
        return LensCard(eyebrow: board.day.name.uppercased(), title: "\(machine.name) is left",
                        lines: [count, "Log it on your phone — its numbers come off the console."],
                        actions: [.list])
    }

    /// The sets that count toward THIS workout's progress: the open session's,
    /// or none. Not `todaysSets`, which falls back to the whole calendar day
    /// when nothing is open — right for a glance at what you did, and wrong
    /// here: finish Push in the morning, close it, come back in the evening, and
    /// the lens refused to log anything because the morning had "done" it all.
    /// The phone's set screen has always counted by session; now this does.
    private func progress(_ board: Board) -> [SetEntry] {
        board.session == nil ? [] : board.todaysSets
    }

    /// The next unfinished lift in the plan's order — wrapping, so skipping one
    /// and coming back to it works — and never a machine, which the lens cannot
    /// log.
    private func nextUp(after item: PlanItem, _ board: Board) -> PlanItem? {
        guard let here = board.items.firstIndex(where: { $0 === item }) else { return nil }
        let rotated = Array(board.items[(here + 1)...] + board.items[..<here])
        return rotated.first {
            guard let exercise = Swaps.exercise(for: $0), !exercise.isCardio else { return false }
            return !Workout.isDone($0, in: progress(board))
        }
    }

    /// What could stand in, `Swaps`' ranking: what you usually do instead, then
    /// anything that does the same job. Five, because the lens has no search
    /// and a list you have to scroll to the end of is not an answer to "the
    /// machine is taken".
    /// Built once, on the way in — not once a second while it is up. Ranking
    /// every exercise in the catalogue to redraw an unchanged list is the same
    /// waste as the rest-day fetch, at a smaller size.
    private var swapping: LensList?

    private func swapList(_ item: PlanItem) -> LensList {
        let everything = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let found = Swaps.candidates(for: item, among: everything, calendar: calendar)
        let usual = Set(found.usual.map(\.slug))
        rowStandIns = Array((found.usual + found.alike).prefix(5))
        let rows = rowStandIns.enumerated().map { index, exercise in
            LensList.Row(title: exercise.name,
                         trailing: usual.contains(exercise.slug) ? "usual swap" : "same job",
                         done: false, action: .open(index))
        }
        let planned = item.exercise?.name ?? "this"
        return LensList(eyebrow: "INSTEAD OF \(planned.uppercased())", rows: rows, footer: [.back])
    }

    private func doneHere(_ exercise: Exercise, _ board: Board) -> [SetEntry] {
        guard let session = board.session else { return [] }
        return board.allSets
            .filter { $0.exercise?.slug == exercise.slug
                && $0.session?.persistentModelID == session.persistentModelID }
            .sorted { $0.setIndex < $1.setIndex }
    }

    // MARK: - What a pinch does

    func pinched(_ action: LensAction, at now: Date = .now) {
        if action == .close {
            closed = true
            place = .list
            return
        }
        // Not `touch`: that reopens a closed lens, and only the phone may.
        liveUntil = now.addingTimeInterval(Self.attention)
        board = nil
        guard let board = load(at: now) else { return }

        switch (place, action) {
        case (.list, .open(let row)):
            guard rowItems.indices.contains(row) else { return }
            place = .card(rowItems[row])

        case (.card(let id), .start), (.lifting(let id), .start):
            // From a "next up" card the id is the exercise just finished.
            let target: PlanItem?
            if case .lifting = place, let done = item(id, in: board) { target = nextUp(after: done, board) }
            else { target = item(id, in: board) }
            guard let target, let exercise = Swaps.exercise(for: target), !exercise.isCardio else { return }
            begin(target, exercise, board)

        case (.card(let id), .taken):
            guard let item = item(id, in: board) else { return }
            swapping = swapList(item)
            place = .swapping(id)
        case (.card, .back), (.card, .list), (.lifting, .list):
            place = .list

        case (.lifting(let id), .logSet):
            guard let item = item(id, in: board), let exercise = Swaps.exercise(for: item),
                  // Unreachable today — nothing puts a machine in `.lifting` —
                  // and this is the function that would write a weight and reps
                  // against a treadmill if something ever did.
                  !exercise.isCardio else { return }
            log(item, exercise, board, at: now)
        case (.lifting, .fewerReps):
            // Never below one, and never UP: a zero-rep slot used to go to 1.
            if reps > 1 { reps -= 1 }
        case (.lifting, .skipRest):
            rest.stop()
        case (.lifting, .extendRest):
            rest.extend(by: 30)
        case (.lifting(let id), .back):
            place = .card(id)

        case (.swapping(let id), .open(let row)):
            guard let item = item(id, in: board), rowStandIns.indices.contains(row) else { return }
            Swaps.put(rowStandIns[row], in: item, context: context, now: now, calendar: calendar)
            context.saveOrReport("swapping an exercise for today")
            snapshots?.setNeedsWrite(context)
            self.board = nil
            place = .card(id)
        case (.swapping(let id), .back):
            place = .card(id)

        default:
            // A button from a screen this is no longer on. `LensGate` refuses
            // nearly all of these before they get here; the rest do nothing.
            return
        }
    }

    private func begin(_ item: PlanItem, _ exercise: Exercise, _ board: Board) {
        let opening = Workout.opening(for: item, doing: exercise, doneHere: doneHere(exercise, board),
                                      in: board.allSets, calendar: calendar)
        weight = opening.weight
        reps = opening.reps
        place = .lifting(item.persistentModelID)
    }

    private func log(_ item: PlanItem, _ exercise: Exercise, _ board: Board, at now: Date) {
        // Not while resting, and not past the last set: the lens offers neither,
        // and a pinch that arrives anyway is not a set.
        let plan = Swaps.prescription(for: item, doing: exercise)
        guard !(rest.isResting && rest.exerciseName == exercise.name),
              Workout.working(item, in: progress(board)).count < plan.sets else { return }

        // Judged and confirmed before the write, as on the phone: the history
        // must not contain this set, and the buzz should not wait on a save.
        let mine = board.allSets.filter { $0.exercise?.slug == exercise.slug }
        Workout.confirm(record: Workout.record(weight: weight, reps: reps, kind: .working,
                                               exercise: exercise, history: mine))
        Workout.logStrength(
            item: item, exercise: exercise, weight: weight, reps: reps, kind: .working,
            setIndex: doneHere(exercise, board).count + 1, at: now, in: context)
        snapshots?.setNeedsWrite(context)
        let pause = Workout.rest(after: item, doing: exercise)
        rest.start(seconds: pause.seconds, exercise: exercise.name)
        // The next set opens on the plan's reps again, as the phone's does —
        // "−1 rep" was about the set you just did, not the one coming.
        reps = plan.reps
        self.board = nil
    }
}
