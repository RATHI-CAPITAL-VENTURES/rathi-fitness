import Foundation
import SwiftData

/// Every rule about `DayNote`, in one place so Today, a past workout, the
/// snapshot and the export cannot each hold a different idea of what "today's
/// notes" are.
enum DayNotes {

    /// The notes that belong to `date`, in display order.
    ///
    /// Sorted totally — kind, then heading, then time — because this feeds the
    /// snapshot, and an order that depends on fetch order makes identical
    /// writes differ byte for byte and churn in iCloud.
    static func on(_ date: Date, among all: [DayNote],
                   calendar: Calendar = .current) -> [DayNote] {
        all.filter { !$0.isDeleted && calendar.isDate($0.date, inSameDayAs: date)
                     && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.noteKind.order, $0.heading, $0.date) < ($1.noteKind.order, $1.heading, $1.date) }
    }

    /// Write `text` as today's `kind`. An empty `text` removes it — clearing
    /// the field IS the delete, so there is no second gesture to find.
    ///
    /// One row per kind per day, and for `other` one per heading: saving twice
    /// replaces rather than stacks, or the strip would grow a second "Locker"
    /// chip every time you corrected a digit.
    static func set(_ kind: DayNoteKind, text: String, label: String = "",
                    among all: [DayNote], in context: ModelContext,
                    now: Date = .now, calendar: Calendar = .current) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = label.trimmingCharacters(in: .whitespacesAndNewlines)
        for old in all where !old.isDeleted
            && calendar.isDate(old.date, inSameDayAs: now)
            && old.noteKind == kind
            && (kind.isSingular || old.label.caseInsensitiveCompare(heading) == .orderedSame) {
            context.delete(old)
        }
        guard !clean.isEmpty else { return }
        // An `other` with no heading has nothing to be called on its chip.
        guard kind.isSingular || !heading.isEmpty else { return }
        context.insert(DayNote(kind: kind, text: clean,
                               label: kind == .other ? heading : "", date: now))
    }

    /// What this was the last time, before `date` — "same as last time".
    ///
    /// For the things that repeat: you park on the same level and, at a gym
    /// with assigned lockers, take the same one. Never for a `note`, which is
    /// about a day and would be wrong to carry: yesterday's "knee is sore"
    /// offered back as today's is the app putting words in your mouth.
    static func lastValue(of kind: DayNoteKind, label: String = "", before date: Date,
                          among all: [DayNote], calendar: Calendar = .current) -> String? {
        guard kind != .note else { return nil }
        let start = calendar.startOfDay(for: date)
        return all
            .filter { !$0.isDeleted && $0.date < start && $0.noteKind == kind
                      && (kind.isSingular || $0.label.caseInsensitiveCompare(label) == .orderedSame)
                      && !$0.text.isEmpty }
            .max { $0.date < $1.date }?
            .text
    }

    /// Headings you have used for `other` before, most recent first — so
    /// "Towel" is a chip the second time rather than something to retype.
    static func pastHeadings(among all: [DayNote]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for note in all.sorted(by: { $0.date > $1.date })
        where !note.isDeleted && note.noteKind == .other && !note.label.isEmpty {
            if seen.insert(note.label.lowercased()).inserted { out.append(note.label) }
        }
        return out
    }
}
