import SwiftUI
import SwiftData

/// Today only: the locker, where you parked, a note.
///
/// A strip of chips under the day's header. What you have set is filled and
/// reads as itself — "Locker 214" — because the whole point is to glance at it
/// holding a towel; what you have not is an outline you can tap to fill in.
/// Tomorrow every chip is an outline again, and nothing had to run for that to
/// be true: see `DayNote`.
struct DayNotesStrip: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService
    @Query(sort: \DayNote.date) private var all: [DayNote]

    @State private var editing: Draft?

    /// What the sheet is editing. A value, not the model row: "add a locker"
    /// has no row yet, and handing the sheet an unsaved `DayNote` would put an
    /// empty one in the store the moment it was cancelled.
    struct Draft: Identifiable {
        var kind: DayNoteKind
        var label: String
        var text: String
        var id: String { kind.rawValue + "·" + label }
    }

    private var todays: [DayNote] { DayNotes.on(.now, among: all) }

    /// Named kinds you have not filled in yet, offered as outlines.
    private var unset: [DayNoteKind] {
        let have = Set(todays.map(\.noteKind))
        return DayNoteKind.allCases.filter { $0.isSingular && !have.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RFDesign.sm) {
            Text("Today only").rfEyebrow()
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(todays.filter { $0.noteKind.fitsOnAChip },
                            id: \.persistentModelID) { note in
                        chipButton(text: "\(note.heading) \(note.text)",
                                   symbol: note.noteKind.symbol, filled: true,
                                   id: "day-note-\(note.noteKind.rawValue)") {
                            editing = Draft(kind: note.noteKind, label: note.label,
                                            text: note.text)
                        }
                    }
                    ForEach(unset) { kind in
                        chipButton(text: kind.label, symbol: kind.symbol, filled: false,
                                   id: "day-note-add-\(kind.rawValue)") {
                            editing = Draft(kind: kind, label: "", text: "")
                        }
                    }
                    // Always last, always available: the "etc".
                    chipButton(text: "Other", symbol: DayNoteKind.other.symbol, filled: false,
                               id: "day-note-add-other") {
                        editing = Draft(kind: .other, label: "", text: "")
                    }
                }
            }
            .scrollIndicators(.hidden)

            // A note is a sentence, not a value, so it gets a line rather than
            // a chip that truncates it to "Left kn…".
            ForEach(todays.filter { !$0.noteKind.fitsOnAChip },
                    id: \.persistentModelID) { note in
                Button {
                    editing = Draft(kind: note.noteKind, label: note.label, text: note.text)
                } label: {
                    Text(note.text)
                        .font(RFDesign.ui(13.5))
                        .foregroundStyle(RFDesign.speech)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-note-text")
            }
        }
        .sheet(item: $editing) { draft in
            DayNoteSheet(
                draft: draft,
                suggestion: DayNotes.lastValue(of: draft.kind, label: draft.label,
                                               before: .now, among: all),
                pastHeadings: DayNotes.pastHeadings(among: all),
                lastValueFor: { DayNotes.lastValue(of: .other, label: $0,
                                                   before: .now, among: all) }
            ) { saved in
                DayNotes.set(saved.kind, text: saved.text, label: saved.label,
                             among: all, in: context)
                context.saveOrReport("saving a note for today")
                snapshots.setNeedsWrite(context)
            }
        }
    }

    private func chipButton(text: String, symbol: String, filled: Bool, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Chip(text: text, symbol: symbol,
                 tint: filled ? RFDesign.ready : RFDesign.label, filled: filled)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// One thing to remember, typed with one thumb.
struct DayNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DayNotesStrip.Draft
    @FocusState private var focused: Bool
    private let wasSet: Bool
    let suggestion: String?
    let pastHeadings: [String]
    let lastValueFor: (String) -> String?
    var onSave: (DayNotesStrip.Draft) -> Void

    init(draft: DayNotesStrip.Draft, suggestion: String?, pastHeadings: [String],
         lastValueFor: @escaping (String) -> String?,
         onSave: @escaping (DayNotesStrip.Draft) -> Void) {
        _draft = State(initialValue: draft)
        wasSet = !draft.text.isEmpty
        self.suggestion = suggestion
        self.pastHeadings = pastHeadings
        self.lastValueFor = lastValueFor
        self.onSave = onSave
    }

    private var needsHeading: Bool { draft.kind == .other }
    private var canSave: Bool {
        !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!needsHeading
                || !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// For a named kind, last time's value. For `other`, last time's value
    /// under the heading typed so far — "Towel" brings back "31".
    private var offered: String? {
        let value = needsHeading ? lastValueFor(draft.label) : suggestion
        guard let value, value != draft.text else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: RFDesign.sm) {
                if needsHeading {
                    TextField("What is it? — Towel, Guest, Key", text: $draft.label)
                        .font(RFDesign.uiMedium(15))
                        .textFieldStyle(.plain)
                        .padding(RFDesign.md)
                        .background(RFDesign.surface,
                                    in: RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
                        // Fixed once saved. The heading is what a row is keyed
                        // by, so renaming in place would leave the old one
                        // behind under its old name; remove and re-add instead.
                        .disabled(wasSet)
                        .opacity(wasSet ? 0.55 : 1)
                        .accessibilityIdentifier("day-note-heading")
                    if !pastHeadings.isEmpty && !wasSet {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(pastHeadings, id: \.self) { heading in
                                    Button { draft.label = heading } label: {
                                        Chip(text: heading,
                                             filled: draft.label.caseInsensitiveCompare(heading)
                                                == .orderedSame)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                TextField(draft.kind.hint, text: $draft.text,
                          axis: draft.kind.fitsOnAChip ? .horizontal : .vertical)
                    .font(RFDesign.ui(16))
                    .lineLimit(draft.kind.fitsOnAChip ? 1 : 4, reservesSpace: !draft.kind.fitsOnAChip)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(RFDesign.md)
                    .background(RFDesign.surface,
                                in: RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
                    .accessibilityIdentifier("day-note-field")
                if let offered {
                    Button { draft.text = offered } label: {
                        Chip(text: "Same as last time — \(offered)",
                             symbol: "arrow.uturn.backward", tint: RFDesign.ready)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("day-note-same")
                }
                Text("For today. Tomorrow this is blank again, and the past keeps what "
                     + "you wrote. Readable on your Mac, so RIA can tell you your "
                     + "locker — which is also why a lock's combination does not "
                     + "belong here.")
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
                    .fixedSize(horizontal: false, vertical: true)
                if wasSet {
                    // Clearing the field and saving is the delete; this is the
                    // same thing with its name on it.
                    Button {
                        draft.text = ""
                        onSave(draft)
                        dismiss()
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(RFDesign.ui(14, bold: true))
                            .foregroundStyle(RFDesign.ember)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, RFDesign.xs)
                    .accessibilityIdentifier("day-note-remove")
                }
                Spacer()
            }
            .padding(RFDesign.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RFDesign.ground.ignoresSafeArea())
            .navigationTitle(needsHeading && draft.label.isEmpty ? "Today only"
                             : (needsHeading ? draft.label : draft.kind.label))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(draft); dismiss() }
                        .disabled(!canSave)
                }
            }
            .onAppear { focused = !needsHeading || !draft.label.isEmpty }
        }
        .presentationDetents([.height(needsHeading ? 400 : 340)])
    }
}
