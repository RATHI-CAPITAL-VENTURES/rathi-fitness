import SwiftUI

/// The pieces `Form` was giving us, drawn in the app's own hand.
///
/// Settings and the plan editor were the only two screens built out of stock
/// `Form`/`List`, and they were the only two that did not look like this app —
/// which was measurable rather than a matter of taste. Between them they used
/// **zero** of `rfEyebrow`, `RFDesign.figure`, `RFDesign.title` or the hairline;
/// Today alone uses twelve. `.scrollContentBackground(.hidden)` hides the list's
/// background and nothing else: the rows keep their own corner radius, their own
/// separators inset from the margin, and San Francisco — in an app whose one
/// typographic rule is that the serif is your numbers.
///
/// So the container was the problem, and this file is the replacement. Five
/// small views, every value from `RFDesign`, and everything after these two
/// screens gets them for nothing.
///
/// **Where `List` survives**: the day and exercise lists keep it, because
/// `onMove` and `onDelete` are real features and reimplementing drag-to-reorder
/// to win a font is a bad trade. Those rows use the type below with
/// `.listRowBackground(Color.clear)` and their own hairline instead.
enum SettingsKit {
    /// The horizontal margin every other screen in the app uses.
    static let margin: CGFloat = 22
}

/// A section: eyebrow, rows, and the small print underneath.
struct SettingsSection<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).rfEyebrow()
                .padding(.bottom, RFDesign.xs)
            content
            if let footer {
                Text(footer)
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }
        }
    }
}

/// One row. A label, an optional second line, and whatever goes on the right.
///
/// The hairline reaches both margins rather than stopping short of the label
/// the way a system separator does — which is most of why a `Form` reads as
/// somebody else's screen inside this one.
struct SettingRow<Trailing: View>: View {
    var label: String
    var detail: String?
    var showsDivider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(RFDesign.uiMedium(15))
                        .foregroundStyle(RFDesign.speech)
                    if let detail {
                        Text(detail)
                            .font(RFDesign.ui(12.5))
                            .foregroundStyle(RFDesign.labelDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 13)
            if showsDivider { Divider().overlay(RFDesign.hairline) }
        }
    }
}

/// A number you set. Serif, because in this app numbers are the voice.
struct SettingFigure: View {
    var value: String
    var unit: String?
    var tint: Color = RFDesign.speech

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(RFDesign.figure(19, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(tint)
            if let unit { Text(unit).rfEyebrow(RFDesign.labelDim, size: 9.5) }
        }
    }
}

/// Label on the left, − figure + on the right.
struct StepperRow: View {
    var label: String
    var detail: String?
    var value: Int
    var unit: String?
    var range: ClosedRange<Int>
    var step: Int = 1
    var format: ((Int) -> String)?
    var showsDivider = true
    var onChange: (Int) -> Void

    var body: some View {
        SettingRow(label: label, detail: detail, showsDivider: showsDivider) {
            HStack(spacing: 12) {
                nudge("minus", enabled: value - step >= range.lowerBound) {
                    onChange(max(range.lowerBound, value - step))
                }
                SettingFigure(value: format?(value) ?? String(value), unit: unit)
                    .frame(minWidth: 52)
                nudge("plus", enabled: value + step <= range.upperBound) {
                    onChange(min(range.upperBound, value + step))
                }
            }
        }
    }

    private func nudge(_ symbol: String, enabled: Bool,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? RFDesign.speech : RFDesign.labelDim)
                .frame(width: 32, height: 32)
                .background(Circle().fill(RFDesign.surface))
                .overlay(Circle().stroke(RFDesign.hairline, lineWidth: 1))
                .frame(width: 44, height: 44)   // the target, not the disc
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "Decrease \(label)" : "Increase \(label)")
    }
}

/// The app's switch. `Toggle`'s own is a system green that appears nowhere else.
struct TogglePill: View {
    var isOn: Bool
    var tint: Color = RFDesign.ready
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? tint : Color.white.opacity(0.13))
                .frame(width: 44, height: 26)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? RFDesign.ground : Color.white.opacity(0.5))
                        .frame(width: 20, height: 20)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .animation(RFDesign.quick, value: isOn)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

struct ToggleRow: View {
    var label: String
    var detail: String?
    var isOn: Bool
    var tint: Color = RFDesign.ready
    var showsDivider = true
    var action: () -> Void

    var body: some View {
        SettingRow(label: label, detail: detail, showsDivider: showsDivider) {
            TogglePill(isOn: isOn, tint: tint, action: action)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// A row that goes somewhere.
struct DisclosureRow<Destination: View>: View {
    var label: String
    var detail: String?
    var value: String?
    var showsDivider = true
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingRow(label: label, detail: detail, showsDivider: showsDivider) {
                HStack(spacing: 7) {
                    if let value {
                        Text(value)
                            .font(RFDesign.ui(14))
                            .foregroundStyle(RFDesign.label)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RFDesign.labelDim)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// A row that does something, rather than going somewhere.
/// An action row's appearance, with no button around it.
///
/// Exists so that a row which has to sit inside something already interactive
/// — a `Button`, a `NavigationLink`, a `List` row that handles its own tap —
/// has a correct thing to reach for.
///
/// Without it there was no correct thing. `ActionRow` is a `Button`, so using
/// one as another `Button`'s label nests two of them, and the obvious way out
/// is `.allowsHitTesting(false)` on the inner one. That does not hand the tap
/// outward: it strips the outer control of the only hit-testable content it
/// had, and both go dead. That shipped as "Add a day" in the plan editor and
/// was live in every release through v0.1.1 — see
/// `docs/retros/2026-08-27-silent-saves.md`. `guards.d/dead-controls.sh` now
/// fails the build on the nesting; this is what to do instead.
struct ActionRowLabel: View {
    var label: String
    var detail: String?
    var symbol: String?
    var tint: Color = RFDesign.ready
    var showsDivider = true

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
            }
            Text(label).font(RFDesign.uiMedium(15))
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.labelDim)
            }
        }
        .foregroundStyle(tint)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsDivider { Divider().overlay(RFDesign.hairline) }
        }
    }
}

struct ActionRow: View {
    var label: String
    var detail: String?
    var symbol: String?
    var tint: Color = RFDesign.ready
    var showsDivider = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionRowLabel(label: label, detail: detail, symbol: symbol,
                           tint: tint, showsDivider: showsDivider)
        }
        .buttonStyle(.plain)
    }
}

/// A one-of-many choice, as a menu rather than a pushed list — every option in
/// this app is a short phrase, and a push to choose between four of them is a
/// screen you have to come back from.
struct ChoiceRow<Value: Hashable>: View {
    var label: String
    var detail: String?
    var value: Value
    var options: [(value: Value, title: String)]
    var showsDivider = true
    var onChange: (Value) -> Void

    private var current: String {
        options.first { $0.value == value }?.title ?? "—"
    }

    var body: some View {
        SettingRow(label: label, detail: detail, showsDivider: showsDivider) {
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button(option.title) { onChange(option.value) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(current)
                        .font(RFDesign.uiMedium(14))
                        .foregroundStyle(RFDesign.ready)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(RFDesign.labelDim)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
        }
    }
}

/// A line of the "right now" block at the top of Settings.
///
/// Settings grew to eleven sections, all of them things you set once. The
/// question you actually open the screen with is "is Health still connected" —
/// so that gets answered before anything you can change.
struct StatusLine: View {
    var label: String
    var value: String
    var lit: Bool
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(lit ? RFDesign.ready : Color.white.opacity(0.18))
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(RFDesign.uiMedium(14))
                    .foregroundStyle(RFDesign.speech)
                Spacer(minLength: 8)
                Text(value)
                    .font(RFDesign.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(RFDesign.labelDim)
            }
            .padding(.vertical, 9)
            if showsDivider { Divider().overlay(RFDesign.hairline) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The screen these all sit on: the app's ground, the app's margins, the app's
/// title. Replaces `Form` wholesale.
struct SettingsScaffold<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RFDesign.lg + 4) {
                content
            }
            .padding(.horizontal, SettingsKit.margin)
            .padding(.top, RFDesign.sm)
            .padding(.bottom, RFDesign.xl)
        }
        .scrollIndicators(.hidden)
        .background(RoomBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
