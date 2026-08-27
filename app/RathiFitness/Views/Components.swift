import SwiftUI

/// The cooldown ring. The largest thing in the app, because it is read at arm's
/// length by someone out of breath.
struct CooldownRing: View {
    var progress: Double
    var remaining: Int
    var caption: String
    var diameter: CGFloat = 230
    var lineWidth: CGFloat = 9

    private var hue: Double { RFDesign.coolHue(progress) }
    private var tint: Color { RFDesign.coolColor(progress) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, 1 - progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(Fmt.clock(remaining))
                    .font(RFDesign.figure(diameter * 0.243))
                    .monospacedDigit()
                    .foregroundStyle(RFDesign.coolColor(progress, brightness: 0.97))
                Text(caption)
                    .rfEyebrow(RFDesign.coolColor(progress, brightness: 0.78), size: 10)
                    .tracking(2)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.linear(duration: 0.25), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue("\(remaining) seconds remaining")
    }
}

/// Sets as a shape rather than a sentence. Read mid-workout without counting.
struct SetPips: View {
    var total: Int
    var done: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(i < done ? RFDesign.ready : Color.white.opacity(0.13))
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) sets done")
    }
}

/// Plate math, in plate colours. The only place those colours appear.
struct PlateChips: View {
    var loadout: PlateMath.Loadout
    var bar: Double

    var body: some View {
        HStack(spacing: 6) {
            if loadout.perSide.isEmpty {
                Text("just the bar")
                    .font(RFDesign.ui(12))
                    .foregroundStyle(RFDesign.labelDim)
            } else {
                ForEach(Array(PlateMath.grouped(loadout.perSide).enumerated()), id: \.offset) { _, g in
                    HStack(spacing: 3) {
                        Text(Fmt.weight(g.plate))
                            .font(RFDesign.ui(11.5, bold: true))
                            .foregroundStyle(RFDesign.ground)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RFDesign.plateColor(g.plate),
                                        in: RoundedRectangle(cornerRadius: 4))
                        if g.count > 1 {
                            Text("×\(g.count)")
                                .font(RFDesign.ui(11))
                                .foregroundStyle(RFDesign.labelDim)
                        }
                    }
                }
                Text("+ \(Fmt.weight(bar)) bar")
                    .font(RFDesign.ui(11.5))
                    .foregroundStyle(RFDesign.labelDim)
            }
            if !loadout.isExact {
                // Never let the big number claim a weight the rack cannot make.
                Text("· nearest \(Fmt.weight(loadout.achievable))")
                    .font(RFDesign.ui(11.5))
                    .foregroundStyle(RFDesign.ember)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row of the day's plan.
struct ExerciseRow: View {
    var name: String
    var meta: String
    var trailing: String
    var state: State

    enum State { case done, live, pending }

    var body: some View {
        HStack(spacing: 13) {
            tick
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(RFDesign.uiMedium(15.5))
                    .foregroundStyle(state == .done ? RFDesign.said
                                     : state == .live ? RFDesign.ready : RFDesign.speech)
                Text(meta)
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(RFDesign.figure(17, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(state == .live ? RFDesign.ready : RFDesign.label)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var tick: some View {
        switch state {
        case .done:
            ZStack {
                Circle().fill(RFDesign.ready)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RFDesign.ground)
            }
            .frame(width: 22, height: 22)
        case .live:
            Circle()
                .stroke(RFDesign.ready, lineWidth: 1.5)
                .overlay(Circle().fill(RFDesign.ready).frame(width: 8, height: 8))
                .frame(width: 22, height: 22)
        case .pending:
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                .frame(width: 22, height: 22)
        }
    }
}

/// A thin progress rail, used for the day.
struct Rail: View {
    var fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(RFDesign.ready)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

/// The primary action. Quiet while you are resting; loud when you are not — the
/// loudest thing on screen should never be the control that undoes the screen.
struct PrimaryButton: View {
    var title: String
    var tint: Color
    var filled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(RFDesign.ui(16, bold: true))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(filled ? RFDesign.ground : tint)
                .background {
                    RoundedRectangle(cornerRadius: RFDesign.md)
                        .fill(filled ? tint : Color.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: RFDesign.md)
                                .stroke(filled ? Color.clear : tint.opacity(0.7), lineWidth: 1)
                        }
                }
                // Without this the button is only as tappable as it is OPAQUE.
                // `filled: false` fills with `Color.clear`, so the hit area was
                // the glyphs and a one-pixel stroke — a 54-point bar you can see
                // and mostly cannot press. It is the unfilled variant that
                // "Skip to set N" and "Done" use, which is to say the button you
                // reach for with a bar in your other hand.
                .contentShape(RoundedRectangle(cornerRadius: RFDesign.md))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(RFDesign.ui(15, bold: true))
                .foregroundStyle(RFDesign.label)
                .frame(width: 104, height: 54)
                .background {
                    RoundedRectangle(cornerRadius: RFDesign.md)
                        .stroke(RFDesign.hairline, lineWidth: 1)
                }
                // Never filled at all, so the same applies with nothing to
                // soften it: "Undo" and "+30s" were an outline around dead space.
                .contentShape(RoundedRectangle(cornerRadius: RFDesign.md))
        }
        .buttonStyle(.plain)
    }
}

/// An empty state that says what to do, not that something is missing.
struct EmptyNote: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RFDesign.uiMedium(15))
                .foregroundStyle(RFDesign.speech)
            Text(message)
                .font(RFDesign.ui(13.5))
                .foregroundStyle(RFDesign.labelDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RFDesign.md)
        .background(RFDesign.surface, in: RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
    }
}
