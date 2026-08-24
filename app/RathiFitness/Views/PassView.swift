import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// The door. One thumb-reach, full brightness, no thinking.
struct PassView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService
    @Query(sort: \GymPass.addedAt) private var passes: [GymPass]

    @State private var editing: GymPass?
    @State private var adding = false
    @State private var previousBrightness: CGFloat?

    private var primary: GymPass? {
        passes.first { $0.isPrimary && !$0.isExpired } ?? passes.first { !$0.isExpired }
    }
    private var others: [GymPass] {
        passes.filter { $0.persistentModelID != primary?.persistentModelID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RFDesign.md) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Pass")
                            .font(RFDesign.title(34))
                            .foregroundStyle(RFDesign.speech)
                        Spacer()
                        Button { adding = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(RFDesign.ready)
                        }
                        .accessibilityLabel("Add a pass")
                    }
                    .padding(.top, RFDesign.sm)

                    if let pass = primary {
                        PassCard(pass: pass)
                            .onTapGesture { editing = pass }
                        brightnessNote
                    } else {
                        EmptyNote(
                            title: "No passes stored.",
                            message: "Add the code your gym scans at the door — QR, barcode, "
                                   + "PDF417 or Aztec. You can scan it off your membership card "
                                   + "with the camera, or type it in.")
                        Button { adding = true } label: {
                            Text("Add a pass")
                                .font(RFDesign.ui(15, bold: true))
                                .foregroundStyle(RFDesign.ground)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(RFDesign.ready,
                                            in: RoundedRectangle(cornerRadius: RFDesign.md))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("add-pass-cta")
                    }

                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Also stored").rfEyebrow()
                            ForEach(others) { pass in
                                Button { editing = pass } label: { PassRow(pass: pass) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, RFDesign.sm)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, RFDesign.xl)
            }
            .scrollIndicators(.hidden)
            .background(RoomBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $adding) {
                PassEditor(pass: nil) { save($0) }
            }
            .sheet(item: $editing) { pass in
                PassEditor(pass: pass) { save($0) } onDelete: {
                    context.delete(pass)
                    try? context.save()
                    snapshots.setNeedsWrite(context)
                }
            }
        }
        .onAppear(perform: raiseBrightness)
        .onDisappear(perform: restoreBrightness)
    }

    private var brightnessNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.max.fill").font(.system(size: 11))
            Text("Brightness raised to 100%")
        }
        .rfEyebrow(RFDesign.labelDim, size: 10.5)
        .frame(maxWidth: .infinity)
    }

    /// Turnstile scanners read reflected light. A dim code fails at the door,
    /// and failing at the door is the only failure this screen has.
    private func raiseBrightness() {
        #if canImport(UIKit)
        guard primary != nil, previousBrightness == nil else { return }
        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0
        #endif
    }

    private func restoreBrightness() {
        #if canImport(UIKit)
        if let previous = previousBrightness {
            UIScreen.main.brightness = previous
            previousBrightness = nil
        }
        #endif
    }

    private func save(_ draft: PassEditor.Draft) {
        if let existing = draft.existing {
            existing.name = draft.name
            existing.location = draft.location
            existing.code = draft.code
            existing.symbology = draft.symbology.rawValue
            existing.memberID = draft.memberID
            existing.isPrimary = draft.isPrimary
            existing.expires = draft.hasExpiry ? draft.expires : nil
            existing.usesLeft = draft.usesLeft
            existing.punches = draft.punches
            existing.punchesNeeded = draft.punchesNeeded
        } else {
            let pass = GymPass(
                name: draft.name, location: draft.location, code: draft.code,
                symbology: draft.symbology, memberID: draft.memberID,
                isPrimary: draft.isPrimary || passes.isEmpty,
                expires: draft.hasExpiry ? draft.expires : nil,
                usesLeft: draft.usesLeft, punches: draft.punches,
                punchesNeeded: draft.punchesNeeded)
            context.insert(pass)
        }
        // Only one card can be the one you hold up at the door.
        if draft.isPrimary {
            for other in passes where other.persistentModelID != draft.existing?.persistentModelID {
                other.isPrimary = false
            }
        }
        try? context.save()
        snapshots.setNeedsWrite(context)
    }
}

/// The one place in the app that abandons the dark ground, and it is not a
/// style choice — see `raiseBrightness`.
struct PassCard: View {
    let pass: GymPass

    var body: some View {
        VStack(spacing: 14) {
            codeImage
            VStack(spacing: 3) {
                Text(pass.name)
                    .font(RFDesign.ui(15, bold: true))
                    .foregroundStyle(RFDesign.onLight)
                if !pass.location.isEmpty {
                    Text(pass.location)
                        .font(RFDesign.ui(12.5))
                        .foregroundStyle(RFDesign.onLightDim)
                }
            }
            if !pass.memberID.isEmpty {
                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .frame(height: 1)
                Text(SnapshotBuilder.mask(pass.memberID))
                    .font(RFDesign.uiMedium(12))
                    .tracking(3)
                    .monospacedDigit()
                    .foregroundStyle(RFDesign.onLight)
            }
            if let state = pass.stateLine {
                Text(state)
                    .font(RFDesign.ui(11.5))
                    .foregroundStyle(RFDesign.onLightDim)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(RFDesign.lightGround, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private var codeImage: some View {
        if let image = CodeImage.generate(pass.code, as: pass.format) {
            Image(uiImage: image)
                .interpolation(.none)       // never blur a code a scanner has to read
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: pass.format.isLinear ? .infinity : 205)
                .frame(height: pass.format.isLinear ? 96 : 205)
                .accessibilityLabel("\(pass.name) check-in code")
        } else {
            Text("This pass has no code stored yet.")
                .font(RFDesign.ui(13))
                .foregroundStyle(RFDesign.onLightDim)
                .frame(height: 120)
        }
    }
}

struct PassRow: View {
    let pass: GymPass

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(RFDesign.label)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.07)))
            VStack(alignment: .leading, spacing: 2) {
                Text(pass.name)
                    .font(RFDesign.uiMedium(15.5))
                    .foregroundStyle(pass.isExpired ? RFDesign.said : RFDesign.speech)
                Text(pass.stateLine ?? pass.location)
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
            }
            Spacer()
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var icon: String {
        pass.format.isLinear ? "barcode" : "qrcode"
    }
}
