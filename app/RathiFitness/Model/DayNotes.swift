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
    ///
    /// **One per key, latest wins.** `set` keeps it to one row per kind per day
    /// on this device, but nothing can on two: the model has no unique
    /// attribute (CloudKit forbids them), so a locker saved on the phone and
    /// another on an offline iPad arrive as two rows for one day. Shown as
    /// they are, that is two filled "Locker" chips and two lines read out by
    /// RIA — confidently wrong by sync instead of by midnight. Deduped HERE,
    /// the one read path, so the strip, the snapshot, the export and a past
    /// day all agree on which one is real.
    static func on(_ date: Date, among all: [DayNote],
                   calendar: Calendar = .current) -> [DayNote] {
        var latest: [String: DayNote] = [:]
        for note in all where !note.isDeleted
            && calendar.isDate(note.date, inSameDayAs: date)
            && !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let key = Self.key(note.noteKind, note.label)
            if let seen = latest[key], seen.date >= note.date { continue }
            latest[key] = note
        }
        return latest.values.sorted {
            ($0.noteKind.order, $0.heading, $0.date) < ($1.noteKind.order, $1.heading, $1.date)
        }
    }

    /// What makes two rows "the same note": the kind, and for `other` its
    /// heading whatever the case.
    static func key(_ kind: DayNoteKind, _ label: String) -> String {
        kind.isSingular ? kind.rawValue
            : kind.rawValue + "·" + label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Write `text` as today's `kind`. An empty `text` removes it — clearing
    /// the field IS the delete, so there is no second gesture to find.
    ///
    /// One row per kind per day, and for `other` one per heading: saving twice
    /// replaces rather than stacks, or the strip would grow a second "Locker"
    /// chip every time you corrected a digit.
    ///
    /// Fetches for itself. It took the caller's array, which in the app is a
    /// view's `@Query` captured by a sheet's closure — so whether a write
    /// replaced or DUPLICATED depended on when SwiftUI last ran that closure.
    /// A write should not be right by courtesy of the view layer.
    static func set(_ kind: DayNoteKind, text: String, label: String = "",
                    in context: ModelContext,
                    now: Date = .now, calendar: Calendar = .current) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = (try? context.fetch(FetchDescriptor<DayNote>())) ?? []
        let target = key(kind, heading)
        for old in all where !old.isDeleted
            && calendar.isDate(old.date, inSameDayAs: now)
            && key(old.noteKind, old.label) == target {
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
