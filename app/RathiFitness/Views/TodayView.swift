import SwiftUI
import SwiftData

/// The day as a list, and the list is the workout.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService
    @EnvironmentObject private var rest: RestTimer
    @EnvironmentObject private var health: HealthBridge

    @Query(sort: \PlannedDay.order) private var days: [PlannedDay]
    @Query(sort: \SetEntry.date, order: .reverse) private var allSets: [SetEntry]
    @Query(sort: \WeighIn.date, order: .reverse) private var weighIns: [WeighIn]
    @Query private var schedules: [Schedule]
    @Query(sort: \Session.startedAt) private var sessions: [Session]
    @Query(sort: \ScheduleEpoch.startedAt) private var epochs: [ScheduleEpoch]
    @Query(sort: \TimeAway.startedAt) private var timeAway: [TimeAway]

    @State private var overrideDay: PlannedDay?
    @State private var showingSettings = false
    @State private var showingPlan = false
    /// 0 is today; 1 and up walk backwards through the days you actually
    /// trained. Calendar days would be the obvious paging unit and the wrong
    /// one — most of them are rest days, so swiping would mostly show nothing.
    @State private var page = 0
    @AppStorage("today.swipeHintSeen") private var swipeHintSeen = false
    /// The slot being swapped, while the picker is up.
    /// When this screen last decided what day it is.
    ///
    /// Almost everything here reads `.now` inside `body`, and nothing re-runs
    /// `body` at midnight: leave the app open past twelve, or resume it next
    /// morning, and the header, the plan and yesterday's locker all sat there a
    /// day behind until something else happened to redraw them. Bumping this
    /// is that something — `body` reads it, so every `.now` below is re-read.
    @State private var dayStamp = Date.now
    @Environment(\.scenePhase) private var scenePhase
    @State private var swapping: PlanItem?
    @AppStorage("today.swapHintSeen") private var swapHintSeen = false
    /// The cardio picker is up ("Add cardio" / "Cardio on its own").
    @State private var addingCardio = false
    /// The machine just picked, pushed straight onto its screen.
    @State private var cardioPick: Exercise?

    private var calendar: Calendar { .current }
    private var config: Rotation.Config { schedules.first?.config ?? Rotation.Config() }

    /// The start of every workout — the input the rotation counts.
    ///
    /// Was every set's date, deduped by day inside `Rotation.index`. Sessions
    /// make the count honest: two workouts on Tuesday advance the rotation
    /// twice, and twenty sets in one of them still advance it once.
    ///
    /// Cardio-only sessions are not in it: see `Workout.rotationDates`.
    private var sessionDates: [Date] { Workout.rotationDates(sessions) }

    private var lastSession: Date? { Workout.lastSessionDate(in: allSets, calendar: calendar) }

    private var isTrainingDay: Bool {
        Rotation.isTrainingDay(.now, config: config, lastSession: lastSession,
                               calendar: calendar)
    }

    /// What is up today.
    ///
    /// Resolved on every read rather than assigned once at appear: the store may
    /// still be seeding when this view first draws, and a one-shot assignment
    /// then latches nil forever.
    private var today: PlannedDay? {
        if let chosen = overrideDay ?? launchArgumentDay { return chosen }
        // The schedule's answer is `Workout.today`'s, so that the glasses —
        // which have no view to ask — reach the same day. The two overrides
        // above are this screen's own and stay here. On a day off, the
        // workout already started today (an optional day) stays on screen.
        return scheduledToday ?? Workout.resumed(among: sessions, calendar: calendar)
    }

    /// What the schedule alone says about today — nil on a day off.
    ///
    /// `-RFRestDay` makes today a day off whatever the calendar says — the
    /// optional day's twin of `-RFDay`, for the UI tests and for looking at a
    /// rest day on a Monday. It changes this screen only; the session a set
    /// opens is still judged against the real schedule.
    private var scheduledToday: PlannedDay? {
        if ProcessInfo.processInfo.arguments.contains("-RFRestDay") { return nil }
        return Workout.today(days: days, config: config, sessionDates: sessionDates,
                             lastSession: lastSession, calendar: calendar)
    }

    /// A workout on a day the schedule left empty. It counts like any other
    /// (the session is marked `optional`), and the header says so.
    ///
    /// Read from the session once there is one — the kind is decided when it
    /// opens and kept, so changing the schedule cannot relabel it. Before the
    /// first set there is no session, and the schedule is all there is to ask.
    private var isOptionalDay: Bool {
        guard let today else { return false }
        if let session = Workout.latestSession(for: today, among: sessions, calendar: calendar) {
            return session.isOptional
        }
        return scheduledToday == nil
    }

    /// What "Start optional day" would start — see `Workout.optionalDay`.
    /// Gated on THIS screen's idea of a day off, so `-RFRestDay` gets the
    /// offer too: a UI test run on a real training day otherwise had none.
    private var offeredOptionalDay: PlannedDay? {
        guard scheduledToday == nil else { return nil }
        return Workout.nextWorkout(days: days, config: config, sessionDates: sessionDates,
                                   calendar: calendar)
    }

    /// The workout the rotation has reached, training day or not — so a rest day
    /// can still say what is coming.
    private var rotationDay: PlannedDay? {
        Workout.rotationDay(days: days, sessionDates: sessionDates, calendar: calendar)
    }

    /// `-RFDay "Push A"` opens that day whatever the calendar says.
    ///
    /// Exists for the UI tests and for looking at a training day on a Thursday.
    /// It only ever selects a day the plan already contains, so the worst it can
    /// do is show you Legs on a Tuesday.
    private var launchArgumentDay: PlannedDay? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-RFDay"), i + 1 < args.count else { return nil }
        return days.first { $0.name == args[i + 1] }
    }
    /// The sets that belong to the workout on screen.
    ///
    /// Day-scoped, the evening half of a two-a-day opened with the morning's
    /// checklist already ticked — every exercise you had shared between the two
    /// showed done before you started. Scoped to the open session, the second
    /// workout opens empty, which is what it is.
    ///
    /// Falls back to the day when nothing is open yet, so a rest-day glance at
    /// what you did still shows it.
    /// Bodyweight as of any date, for valuing assisted work. Built from the
    /// weigh-in query rather than passed around, because both tonnage figures
    /// on this screen have to agree about it.
    private var bodyWeightLog: Tally.BodyWeightLog {
        Tally.BodyWeightLog(weighIns.map { (date: $0.date, pounds: $0.pounds) })
    }

    private var todaysSets: [SetEntry] {
        Workout.todaysSets(in: allSets, openSession: openSession, today: today, calendar: calendar)
    }

    /// The workout in progress for the day on screen, if there is one.
    private var openSession: Session? {
        Workout.openSession(for: today, among: sessions, calendar: calendar)
    }

    /// Every workout finished today. Two on a two-a-day; the reason Today can
    /// say "second workout" rather than pretending the first did not happen.
    private var todaysSessions: [Session] {
        sessions.filter {
            calendar.isDate($0.startedAt, inSameDayAs: .now)
                // A ride on its own is not "workout 2" of anything.
                && $0.countsAsWorkout
                // A session with no sets did not happen. `pruneEmpty` removes
                // them, and this is the belt to its braces: an empty one here
                // made the header say "workout 3" on a one-workout day.
                && !($0.sets ?? []).isEmpty
        }
    }

    /// The workouts you have already done, newest first.
    ///
    /// Was one page per *day*, so a two-a-day collapsed into a single page with
    /// both workouts' exercises run together. Capped because this builds a page
    /// each and nobody swipes back three months.
    private var pastDays: [Session] {
        sessions
            .filter { !calendar.isDate($0.startedAt, inSameDayAs: .now) }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(60)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                todayPage.tag(0)
                ForEach(Array(pastDays.enumerated()),
                        id: \.element.persistentModelID) { index, past in
                    PastDayView(session: past).tag(index + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(RoomBackground(hue: roomHue, energy: roomEnergy))
            .onChange(of: page) { _, new in
                if new != 0 { swipeHintSeen = true }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if page == 0 {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(RFDesign.label)
                        }
                        .accessibilityLabel("Settings")
                    } else {
                        // Sixty swipes back is a long way to come home from.
                        Button { withAnimation { page = 0 } } label: {
                            Label("Today", systemImage: "chevron.left")
                                .font(RFDesign.ui(14, bold: true))
                                .foregroundStyle(RFDesign.ready)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(days) { day in
                            Button(day.name) {
                                overrideDay = day
                                // So the glasses show this workout too, not
                                // the one the schedule had in mind.
                                Workout.chosen = (day.persistentModelID, .now)
                            }
                        }
                        if overrideDay != nil {
                            Button("Back to today") {
                                overrideDay = nil
                                Workout.chosen = nil
                            }
                        }
                        if let session = openSession {
                            Divider()
                            // The escape hatch that lets the same workout happen
                            // twice in a day. Sessions are keyed by planned day,
                            // so a second run at Push A would otherwise join the
                            // first; saying "that one's done" is what separates
                            // them, and it is a truthful thing to say rather
                            // than a setting invented for the edge case.
                            Button {
                                Sessions.close(session, in: context)
                                context.saveOrReport("finishing a workout")
                                snapshots.setNeedsWrite(context)
                                // Straight to Health. The export gate is
                                // "finished", and this is the moment it became
                                // true — waiting for the next cold launch is
                                // how workouts went missing from Fitness.
                                Task { await health.syncNow(context) }
                            } label: {
                                Label("Finish \(session.title)",
                                      systemImage: "checkmark.circle")
                            }
                        }
                        Divider()
                        Button {
                            showingPlan = true
                        } label: {
                            Label("Edit the plan", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "calendar")
                            .foregroundStyle(RFDesign.label)
                    }
                    .accessibilityLabel("Plan")
                    .accessibilityIdentifier("plan-menu")
                }
            }
            // Posted off the main thread, hence the hop. And on becoming active,
            // because a suspended app is not told about a midnight it slept
            // through in any way worth relying on.
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                .receive(on: RunLoop.main)) { _ in dayStamp = .now }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, !calendar.isDate(dayStamp, inSameDayAs: .now) {
                    dayStamp = .now
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingPlan) { PlanView() }
            .sheet(item: $swapping) { item in
                ExercisePickerView(standingInFor: item) { chosen in
                    Swaps.put(chosen, in: item, context: context)
                    context.saveOrReport("swapping an exercise for today")
                    snapshots.setNeedsWrite(context)
                }
            }
            .sheet(isPresented: $addingCardio) {
                ExercisePickerView(cardioOnly: true) { chosen in cardioPick = chosen }
            }
            // On a lifting day it joins the workout as an extra; on a day off it
            // is a session of its own. Decided here, by what is on screen.
            .navigationDestination(item: $cardioPick) { exercise in
                if let day = today {
                    CardioSetView(purpose: .extra(day), exercise: exercise)
                } else {
                    CardioSetView(purpose: .alone, exercise: exercise)
                }
            }
        }
    }

    /// Today, live. Everything you can act on lives here — a past day is a
    /// summary and cannot be logged into, because logging always writes
    /// `Date.now` and a swipeable editable yesterday would put sets in the
    /// wrong day without saying so.
    private var todayPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RFDesign.md + 2) {
                LegacyDataBanner()
                header
                // On a rest day too. You can park at the gym and take a locker
                // on a day the plan says nothing about.
                DayNotesStrip(day: dayStamp)
                if let day = today {
                    progress(for: day)
                    rows(for: day)
                    extras(for: day)
                    cardioOnItsOwn(workout: day)
                    swapHint
                    moved(for: day)
                } else {
                    restDay
                }
                MusicBar()
                consistency
                swipeHint
            }
            .padding(.horizontal, 22)
            .padding(.bottom, RFDesign.xl)
        }
        .scrollIndicators(.hidden)
    }

    /// Shown once, and only when there is actually something back there. A
    /// gesture nobody can discover is a gesture nobody has.
    @ViewBuilder private var swipeHint: some View {
        if !swipeHintSeen, !pastDays.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                Text("Swipe for \(pastDays.count == 1 ? "your last workout" : "past workouts")")
            }
            .rfEyebrow()
            .frame(maxWidth: .infinity)
            .padding(.top, RFDesign.sm)
        }
    }

    /// Same argument as `swipeHint`: a long-press is invisible until you are
    /// told it is there. Gone for good once the picker has been opened once.
    @ViewBuilder private var swapHint: some View {
        if !swapHintSeen {
            Text("Machine taken? Hold an exercise to do something else today.")
                .rfEyebrow()
                .padding(.top, RFDesign.xs)
        }
    }

    /// Twelve weeks of showing up.
    ///
    /// On Today rather than Trends, and on both a training day and a rest day:
    /// it is the one number that answers "am I actually doing this", and the
    /// day you most need to see it is the day you are deciding whether to go.
    /// Hidden until there is a first workout to count from — a band of empty
    /// weeks on a fresh install is the app opening with a reprimand.
    @ViewBuilder private var consistency: some View {
        let band = Tally.consistency(
            // A cardio-only session is not a workout of the plan, so it covers
            // none of it. An optional day does: it is one of the plan's.
            sessions: Workout.workouts(sessions)
                .map { Tally.Done(date: $0.startedAt, workout: $0.dayName) },
            targets: weeklyTargets,
            away: timeAway.map { Tally.Away(from: $0.startedAt, to: $0.endedAt) },
            calendar: calendar)
        if !band.isEmpty {
            ConsistencyBand(consistency: band)
        }
    }

    /// The weekly target as it was, week by week.
    ///
    /// Read from the recorded schedule history rather than the live schedule,
    /// because changing your schedule today must not turn last month's finished
    /// weeks into misses. Falls back to the current schedule when there is no
    /// history yet — a fresh install has nothing to remember.
    private var weeklyTargets: Tally.Targets {
        let recorded = epochs
            .sorted { $0.startedAt < $1.startedAt }
            .map { (from: $0.startedAt, weekly: $0.weeklyTarget) }
        guard recorded.isEmpty else { return Tally.Targets(recorded) }
        return Tally.Targets(constant:
            Rotation.weeklyTarget(config, plannedWorkouts: days.count))
    }

    private var roomHue: Double {
        rest.isResting ? RFDesign.coolHue(rest.progress()) : RFDesign.readyHue
    }
    private var roomEnergy: Double {
        rest.isResting ? RFDesign.roomGlowActive : RFDesign.roomGlow
    }

    // MARK: pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(headerEyebrow).rfEyebrow()
            Text(today?.name ?? "Rest day")
                .font(RFDesign.title(34))
                .foregroundStyle(RFDesign.speech)
            if let day = today {
                Text(subtitle(for: day))
                    .font(RFDesign.ui(13.5))
                    .foregroundStyle(RFDesign.label)
            }
        }
        .padding(.top, RFDesign.sm)
    }

    private var headerEyebrow: String {
        // A second workout says so before anything else. Without it the only
        // difference between "today" and "today again" is a checklist that has
        // mysteriously emptied itself.
        if let nth = workoutNumberToday, nth > 1 {
            return "\(Fmt.weekdayDate(.now)) · workout \(nth)"
        }
        // Before "out of order": on a day off, anything you start is optional,
        // however you got to it.
        if isOptionalDay { return "\(Fmt.weekdayDate(.now)) · optional day" }
        if overrideDay != nil || launchArgumentDay != nil { return "Doing out of order" }
        guard config.mode != .weekday, days.count > 1,
              let index = Rotation.index(on: .now, sessionDates: sessionDates,
                                         dayCount: days.count, calendar: calendar)
        else { return Fmt.weekdayDate(.now) }
        // "Thu 21 Aug · 3 of 4" — where you are in the cycle, which is the thing
        // a rotation makes hard to hold in your head.
        return "\(Fmt.weekdayDate(.now)) · \(index + 1) of \(days.count)"
    }

    /// Which workout of the day the one on screen is, counting from 1.
    ///
    /// `nil` when nothing has been logged today — before the first set there is
    /// no workout to number, and "workout 1" on an empty screen is noise.
    private var workoutNumberToday: Int? {
        guard !todaysSessions.isEmpty else { return nil }
        if let open = openSession,
           let index = todaysSessions.firstIndex(where: {
               $0.persistentModelID == open.persistentModelID
           }) {
            return index + 1
        }
        // Nothing open: the next one you start would be the next number.
        return todaysSessions.count + 1
    }

    private func subtitle(for day: PlannedDay) -> String {
        let items = day.orderedItems
        let sets = items.reduce(0) { $0 + $1.targetSets }
        let minutes = items.reduce(0) { $0 + $1.targetSets * ($1.restSeconds + 40) } / 60
        return "\(items.count) exercises · \(sets) sets · about \(minutes) min"
    }

    private func progress(for day: PlannedDay) -> some View {
        let items = day.orderedItems
        let done = items.filter { isDone($0) }.count
        return VStack(spacing: 7) {
            Rail(fraction: items.isEmpty ? 0 : Double(done) / Double(items.count))
            HStack {
                Text("\(done) of \(items.count) done").rfEyebrow()
                Spacer()
                if let elapsed = elapsedMinutes {
                    Text(elapsed).rfEyebrow(RFDesign.ready)
                }
            }
        }
    }

    /// How long the workout took, or how long it has been running.
    ///
    /// Was `Date.now.timeIntervalSince(todaysSets.last!.date)` — the variable
    /// was even named `first` while taking `.last`, and only produced the right
    /// end because `allSets` happens to sort descending. It measured wall clock
    /// from your first set to **now**, so a workout finished at 08:49 read
    /// "438 min in" at half past three, still counting.
    ///
    /// A finished workout has a duration; a live one has an elapsed time. They
    /// are different sentences and it now says whichever is true.
    ///
    /// Both go through `Tally.gymSeconds`, so this, the past-workout page and
    /// the lifetime total on Trends cannot disagree about when a workout began
    /// — in particular all three count the treadmill you opened with.
    private var elapsedMinutes: String? {
        let logs = todaysSets.map(\.log)
        guard !logs.isEmpty else { return nil }
        if openSession != nil {
            // Still going, so "now" is the far end rather than the last set.
            let running = Tally.gymSeconds(logs + [Tally.Log(date: .now)])
            return "\(Tally.gymTimeText(running)) in"
        }
        return Tally.gymTimeText(max(60, Tally.gymSeconds(logs)))
    }

    private func rows(for day: PlannedDay) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(day.orderedItems.enumerated()), id: \.element.persistentModelID) { i, item in
                // What is in the slot TODAY — the plan's exercise, or whatever
                // is standing in for it. See `Swaps`.
                if let exercise = Swaps.exercise(for: item) {
                    NavigationLink {
                        // Two screens, because a treadmill and a bench share
                        // almost nothing: no plate math, no rep target, and a
                        // clock rather than a weight as the headline figure.
                        if exercise.isCardio {
                            CardioSetView(item: item, exercise: exercise)
                        } else {
                            SetView(item: item, exercise: exercise)
                        }
                    } label: {
                        ExerciseRow(name: exercise.name,
                                    meta: meta(for: item),
                                    trailing: trailing(for: item, exercise: exercise),
                                    state: state(for: item))
                            .accessibilityIdentifier("row-\(exercise.slug)")
                    }
                    .buttonStyle(.plain)
                    .contextMenu { swapMenu(for: item) }
                    if i < day.orderedItems.count - 1 {
                        Divider().overlay(RFDesign.hairline)
                    }
                }
            }
        }
    }

    /// Today only. Editing the plan is the other door, and it is the wrong one
    /// for "the treadmills are all taken" — it changes every week from now on.
    @ViewBuilder private func swapMenu(for item: PlanItem) -> some View {
        Button {
            swapHintSeen = true
            swapping = item
        } label: {
            Label("Do something else today", systemImage: "arrow.left.arrow.right")
        }
        if Swaps.standIn(for: item) != nil, let planned = item.exercise {
            Button {
                Swaps.clear(item, context: context)
                context.saveOrReport("swapping back to the plan")
                snapshots.setNeedsWrite(context)
            } label: {
                Label("Back to \(planned.name)", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var restDay: some View {
        VStack(alignment: .leading, spacing: RFDesign.sm) {
            EmptyNote(title: "Rest day.", message: restMessage)
            if let offer = offeredOptionalDay { optionalOffer(offer) }
            cardioOnItsOwn(workout: nil)
            addCardio("Cardio on its own")
            Button { showingPlan = true } label: {
                Label("Edit the plan", systemImage: "slider.horizontal.3")
                    .font(RFDesign.ui(14, bold: true))
                    .foregroundStyle(RFDesign.ready)
            }
            .buttonStyle(.plain)
        }
    }

    /// "Start optional day" — the workout the next training day would get.
    ///
    /// An invitation, not a reminder: outlined in the ready colour rather than
    /// filled, and nothing anywhere notices if it is ignored. Starting it puts
    /// that workout on screen (and on the glasses, through `Workout.chosen`);
    /// the session it opens on the first set is marked optional.
    private func optionalOffer(_ day: PlannedDay) -> some View {
        Button {
            overrideDay = day
            Workout.chosen = (day.persistentModelID, .now)
        } label: {
            HStack(spacing: RFDesign.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optional day").rfEyebrow()
                    Text("Start \(day.name)")
                        .font(RFDesign.uiMedium(16))
                        .foregroundStyle(RFDesign.ready)
                    Text(optionalLine(for: day))
                        .font(RFDesign.ui(12.5))
                        .foregroundStyle(RFDesign.labelDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RFDesign.ready)
            }
            .padding(RFDesign.md)
            .background {
                RoundedRectangle(cornerRadius: RFDesign.radiusSmall)
                    .stroke(RFDesign.ready.opacity(0.35), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("start-optional-day")
    }

    /// What doing it changes, in a sentence — the two modes really differ.
    private func optionalLine(for day: PlannedDay) -> String {
        guard config.mode == .weekday else {
            return "Next in the rotation. Do it and the days after move up one; "
                 + "skip it and nothing changes."
        }
        let names = calendar.weekdaySymbols
        let weekday = names.indices.contains(day.weekday - 1) ? names[day.weekday - 1] : "Its day"
        return "\(weekday)'s workout, early. \(weekday) keeps it either way."
    }

    /// "Add cardio" and "Cardio on its own" — one button, two meanings, chosen
    /// by whether a workout is on screen (see `navigationDestination`).
    private func addCardio(_ title: String) -> some View {
        Button { addingCardio = true } label: {
            Label(title, systemImage: "plus")
                .font(RFDesign.ui(14, bold: true))
                .foregroundStyle(RFDesign.ready)
                .padding(.vertical, RFDesign.xs)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-cardio")
    }

    /// Cardio added to this workout outside the plan, in its own section so it
    /// can never be read as one of the plan's rows. Done, never pending: it
    /// exists only once it has been logged.
    @ViewBuilder private func extras(for day: PlannedDay) -> some View {
        let bouts = Workout.extras(in: todaysSets)
        VStack(alignment: .leading, spacing: 0) {
            if !bouts.isEmpty {
                Text("Extra · not in the plan").rfEyebrow()
                    .padding(.top, RFDesign.sm)
                cardioRows(bouts) { CardioSetView(purpose: .extra(day), exercise: $0) }
            }
            addCardio("Add cardio")
                .padding(.top, RFDesign.xs)
        }
    }

    /// Today's cardio-only session — what you rode, and the way back into it.
    ///
    /// `workout` is the day's workout when one is on screen. Then a row opens
    /// the bout as an EXTRA in that workout, never `.alone`: an `.alone` bout
    /// used to open a cardio session, which closed the lifting one, and the
    /// next lifted set opened a second workout that advanced the rotation
    /// again. `Workout.cardioHome` routes `.alone` safely too; this keeps the
    /// screen from even offering it.
    @ViewBuilder private func cardioOnItsOwn(workout: PlannedDay?) -> some View {
        let bouts = sessions
            .filter { $0.isCardioOnly && calendar.isDate($0.startedAt, inSameDayAs: .now) }
            .flatMap(\.orderedSets)
        if !bouts.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Cardio today").rfEyebrow().padding(.top, RFDesign.xs)
                cardioRows(bouts) { exercise in
                    if let workout {
                        CardioSetView(purpose: .extra(workout), exercise: exercise)
                    } else {
                        CardioSetView(purpose: .alone, exercise: exercise)
                    }
                }
            }
        }
    }

    /// One row per machine, in the order they were first used.
    private func cardioRows<Destination: View>(
        _ bouts: [SetEntry], destination: @escaping (Exercise) -> Destination
    ) -> some View {
        var order: [Exercise] = []
        for bout in bouts.sorted(by: { $0.date < $1.date }) {
            if let exercise = bout.exercise, !order.contains(where: { $0.slug == exercise.slug }) {
                order.append(exercise)
            }
        }
        return ForEach(order, id: \.persistentModelID) { exercise in
            let mine = bouts.filter { $0.exercise?.slug == exercise.slug }
            NavigationLink { destination(exercise) } label: {
                ExerciseRow(name: exercise.name, meta: Self.boutsLine(mine),
                            trailing: Self.boutsFigure(mine), state: .done)
                    .accessibilityIdentifier("cardio-\(exercise.slug)")
            }
            .buttonStyle(.plain)
        }
    }

    /// The figure on the right: minutes, or miles when no time was entered —
    /// a rower logged by distance alone is not "0 min".
    private static func boutsFigure(_ bouts: [SetEntry]) -> String {
        let seconds = bouts.reduce(0) { $0 + $1.seconds }
        if seconds > 0 { return Fmt.minutes(seconds) }
        return "\(Fmt.distance(bouts.reduce(0) { $0 + $1.distance })) mi"
    }

    /// "2.1 mi · 2 bouts" — what the console said, summed, minus whatever the
    /// figure on the right already says.
    private static func boutsLine(_ bouts: [SetEntry]) -> String {
        var parts: [String] = []
        let miles = bouts.reduce(0) { $0 + $1.distance }
        if miles > 0, bouts.contains(where: { $0.seconds > 0 }) {
            parts.append("\(Fmt.distance(miles)) mi")
        }
        parts.append(bouts.count == 1 ? "1 bout" : "\(bouts.count) bouts")
        return parts.joined(separator: " · ")
    }

    /// What the hour added up to.
    ///
    /// A session is four exercises and a lot of standing around; the tonnage is
    /// the only number that makes it countable. Shown only once there is
    /// something to show — a zero here would be a scoreboard telling you off.
    @ViewBuilder private func moved(for day: PlannedDay) -> some View {
        let sets = todaysSets.map {
            $0.tally(bodyWeight: bodyWeightLog.pounds(on: $0.date))
        }
        // A lifted set, not just any: a treadmill has no tonnage, and with
        // "Add cardio" a workout can now open on one — "Moved today: nothing
        // yet" under it is the scoreboard telling you off.
        if todaysSets.contains(where: { !$0.isCardio }) {
            let comparison = Tally.SessionComparison(
                volume: Tally.volume(sets),
                previousVolume: previousVolume(for: day))
            VStack(alignment: .leading, spacing: 5) {
                Text("Moved today").rfEyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(Tally.volumeText(comparison.volume))
                        .font(RFDesign.figure(34, relativeTo: .title))
                        .foregroundStyle(RFDesign.ready)
                    if let line = comparison.line {
                        Text(line)
                            .font(RFDesign.ui(12.5))
                            .foregroundStyle(RFDesign.labelDim)
                    }
                }
            }
            .padding(.top, RFDesign.xs)
        }
    }

    /// The last time this same workout was done — comparing Push A to Legs
    /// would be a number that moves for no reason.
    ///
    /// **A session, not a day.** This grouped past sets by `startOfDay` and
    /// matched them by exercise SLUG, which was wrong three ways at once and
    /// is why the figure "made no sense":
    ///
    ///  - a day is not a workout. v0.3.1 made `Session` the unit everywhere
    ///    else precisely because a two-a-day is two workouts; here a morning
    ///    and an evening session were added together and compared against as
    ///    one, so today's single workout looked like a collapse.
    ///  - matching by slug pulled in any past set of any exercise that happens
    ///    to appear in today's plan. Bench in both Push A and Push B meant Push
    ///    B's bench counted as "last time you did Push A".
    ///  - it excluded everything dated today, so the second half of a two-a-day
    ///    had nothing to compare against at all.
    ///
    /// Now: the most recent session with this workout's name that is not the
    /// one currently on screen.
    private func previousVolume(for day: PlannedDay) -> Double? {
        // Identity, not date: the session being shown might be open, might be
        // finished, and on a two-a-day there are two of them today.
        let shown = Set(todaysSets.map(\.persistentModelID))
        let previous = sessions
            .filter { $0.dayName == day.name }
            .filter { session in
                !session.orderedSets.contains { shown.contains($0.persistentModelID) }
            }
            .max { $0.startedAt < $1.startedAt }
        guard let previous else { return nil }
        let entries = previous.orderedSets
        guard !entries.isEmpty else { return nil }
        return Tally.volume(entries.map {
            $0.tally(bodyWeight: bodyWeightLog.pounds(on: $0.date))
        })
    }

    /// What is next and when — a rest day is still a place you look to find out
    /// what is coming, and "nothing scheduled" answers neither question.
    private var restMessage: String {
        guard config.mode != .weekday else {
            // The optional day below already says what you could do instead;
            // this says only why there is nothing.
            let weekday = DateFormatter()
            weekday.dateFormat = "EEEE"
            return "Your plan has nothing on \(weekday.string(from: .now))s."
        }
        var parts: [String] = []
        if let next = rotationDay { parts.append("Next up is \(next.name)") }
        if let when = Rotation.nextTrainingDay(
            from: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now,
            config: config, lastSession: lastSession, calendar: calendar) {
            let weekday = DateFormatter()
            weekday.dateFormat = "EEEE"
            parts.append(calendar.isDateInTomorrow(when)
                         ? "tomorrow" : "on \(weekday.string(from: when))")
        }
        let line = parts.isEmpty ? "Nothing scheduled." : parts.joined(separator: ", ") + "."
        return line + " You train \(Rotation.describe(config)) — "
             + "the calendar button starts one early."
    }

    // Body weight used to sit here, under the workout. It is a Trends number:
    // you look at it against a curve, not while deciding whether to add 5 lb to
    // a bench. Today is the checklist and the room you are standing in.
    // Logging one moved to Trends with it — see TrendsView.weighIn.

    // MARK: state

    /// Everything done in this slot today — on the plan's exercise and on
    /// anything that stood in for it. Two sets on the bench and two on the
    /// dumbbells is four of four: see `Swaps.slugsCounting`.
    private func performed(_ item: PlanItem) -> [SetEntry] {
        Workout.performed(item, in: todaysSets)
    }

    /// The slot's numbers as they apply to what is in it today.
    private func prescription(_ item: PlanItem) -> Swaps.Prescription? {
        Swaps.exercise(for: item).map { Swaps.prescription(for: item, doing: $0) }
    }

    /// Sets that move you toward the target. Three warm-ups used to tick an
    /// exercise off — the checklist lying about the one thing it is for.
    private func working(_ item: PlanItem) -> [SetEntry] {
        Workout.working(item, in: todaysSets)
    }

    private func isDone(_ item: PlanItem) -> Bool {
        Workout.isDone(item, in: todaysSets)
    }

    /// What the set screen will say to try, from the last day this lift was
    /// done. The same call the set screen makes, on the same sets.
    private func suggestion(for item: PlanItem, exercise: Exercise) -> Tally.Suggestion? {
        Workout.suggestion(for: item, doing: exercise, in: allSets, calendar: calendar)
    }

    /// The weight a row reads. Not `item.targetWeight`: that is what the plan
    /// records you owning, which lags the set screen's "try 130" by a step
    /// and stays stale for any session the log path never saw. The row shows
    /// the same number the set screen opens on — see `Tally.shownWeight`.
    private func shownWeight(for item: PlanItem, exercise: Exercise) -> Double {
        Tally.shownWeight(plan: Swaps.prescription(for: item, doing: exercise).weight,
                          suggestion: suggestion(for: item, exercise: exercise),
                          // Oldest first: `allSets` is newest-first, and the
                          // rule reads the LAST working set as what you are on.
                          //
                          // THIS exercise's sets only. `performed` is the whole
                          // slot, which is right for counting and wrong for a
                          // weight: two bench sets at 185 put "185" on the
                          // dumbbell row that replaced it, while the set screen
                          // opened on 60.
                          today: performed(item)
                              .filter { $0.exercise?.slug == exercise.slug }
                              .sorted { $0.date < $1.date }
                              .map { $0.tally(bodyWeight: nil) })
    }

    /// The number on the right of a row: the weight for a lift, the time for
    /// cardio. It is the thing you are about to go and do either way.
    private func trailing(for item: PlanItem, exercise: Exercise) -> String {
        guard exercise.isCardio else { return Fmt.weight(shownWeight(for: item, exercise: exercise)) }
        let plan = Swaps.prescription(for: item, doing: exercise)
        if plan.seconds > 0 { return Fmt.minutes(plan.seconds) }
        if plan.distance > 0 { return "\(Fmt.distance(plan.distance)) mi" }
        return "—"
    }

    private func state(for item: PlanItem) -> ExerciseRow.State {
        if isDone(item) { return .done }
        if !performed(item).isEmpty { return .live }
        if rest.exerciseName != nil && rest.exerciseName == Swaps.exercise(for: item)?.name {
            return .live
        }
        return .pending
    }

    /// The plan and the deviation in the same breath.
    private func meta(for item: PlanItem) -> String {
        guard let exercise = Swaps.exercise(for: item) else { return "" }
        let line = exercise.isCardio
            ? cardioMeta(for: item, exercise: exercise)
            : liftMeta(for: item, exercise: exercise)
        // A stand-in says whose place it is in, first — otherwise a bike in
        // the treadmill's slot looks like the plan changed under you.
        if Swaps.isStandIn(exercise, in: item), let planned = item.exercise {
            return "for \(planned.name) · \(line)"
        }
        return line
    }

    private func liftMeta(for item: PlanItem, exercise: Exercise) -> String {
        let target = Swaps.prescription(for: item, doing: exercise)
        let done = working(item)
        let warmups = performed(item).count - done.count
        let unit = exercise.weightUnit
        let weight = Fmt.weight(shownWeight(for: item, exercise: exercise))
        let plan = "\(target.sets) × \(target.reps) · \(weight) \(unit)"
        if done.isEmpty {
            return warmups > 0 ? "\(plan) · \(warmups) warm-up done" : plan
        }
        if done.count >= target.sets {
            // By time, not `setIndex`: that is per exercise, so a slot shared
            // by two of them would print its reps interleaved.
            let reps = done.sorted { $0.date < $1.date }.map { String($0.reps) }
            let hitAll = done.allSatisfy { $0.reps >= target.reps }
            return hitAll ? "\(plan) · all \(done.count) hit"
                          : "\(plan) · got \(reps.joined(separator: ", "))"
        }
        if rest.isResting && rest.exerciseName == exercise.name {
            return "set \(done.count) of \(target.sets) · resting \(Fmt.clock(rest.remaining()))"
        }
        return "set \(done.count) of \(target.sets) done"
            + (warmups > 0 ? " · +\(warmups) warm-up" : "")
    }

    /// Cardio's version: what was asked for, then what actually happened on the
    /// console. No reps, because there are none.
    private func cardioMeta(for item: PlanItem, exercise: Exercise) -> String {
        let target = Swaps.prescription(for: item, doing: exercise)
        let bouts = performed(item)
        if bouts.isEmpty {
            var parts: [String] = []
            if target.seconds > 0 { parts.append(Fmt.minutes(target.seconds)) }
            if target.distance > 0 { parts.append("\(Fmt.distance(target.distance)) mi") }
            if target.incline > 0 { parts.append("\(Fmt.rate(target.incline))% grade") }
            if target.speed > 0 { parts.append("\(Fmt.rate(target.speed)) mph") }
            if target.sets > 1 { parts.append("\(target.sets) intervals") }
            return parts.isEmpty ? "no target" : parts.joined(separator: " · ")
        }
        let seconds = bouts.reduce(0) { $0 + $1.seconds }
        let miles = bouts.reduce(0) { $0 + $1.distance }
        var parts: [String] = []
        if seconds > 0 { parts.append(Fmt.minutes(seconds)) }
        if miles > 0 { parts.append("\(Fmt.distance(miles)) mi") }
        if target.sets > 1 {
            parts.append("\(bouts.count) of \(target.sets)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Logging the scale. One number, a big keypad, and out.
struct WeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var onSave: (Double) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: RFDesign.lg) {
                Text("What did the scale say?")
                    .font(RFDesign.ui(15))
                    .foregroundStyle(RFDesign.label)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("176.4", text: $text)
                        .font(RFDesign.figure(64))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(RFDesign.speech)
                    Text("lb").rfEyebrow(RFDesign.labelDim, size: 14)
                }
                .padding(.horizontal, RFDesign.xl)
                Spacer()
            }
            .padding(.top, RFDesign.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RFDesign.ground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = Double(text.trimmingCharacters(in: .whitespaces)), v > 0 {
                            onSave(v)
                        }
                        dismiss()
                    }
                    .disabled(Double(text.trimmingCharacters(in: .whitespaces)) == nil)
                }
            }
        }
        .presentationDetents([.height(280)])
    }
}
