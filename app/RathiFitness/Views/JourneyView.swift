import SwiftUI

/// Everything you have lifted past, and everything still ahead.
///
/// The legacy card on Trends answers "how far am I" in one line. This answers
/// "what have I already done", which is a different question and the one worth
/// coming back to — a tier you crossed in August is a fact about you, and until
/// now the app knew it and never said so.
struct JourneyView: View {
    let total: Double
    let crossings: [Tally.Crossing]

    private var passed: [Tally.Crossing] { crossings.filter(\.isPassed) }
    private var next: Tally.Crossing? { crossings.first { !$0.isPassed } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                // Newest first: what you just did is what you came to look at,
                // and the ancient tiers are the ones you scroll past.
                ForEach(Array(crossings.reversed().enumerated()), id: \.element.id) { i, crossing in
                    row(crossing, isNext: crossing.id == next?.id)
                    if i < crossings.count - 1 { Divider().overlay(RFDesign.hairline) }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, RFDesign.xl)
        }
        .scrollIndicators(.hidden)
        .background(RoomBackground())
        .navigationTitle("Your journey")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Everything you have lifted").rfEyebrow()
            Text(Tally.volumeText(total))
                .font(RFDesign.figure(40))
                .monospacedDigit()
                .foregroundStyle(RFDesign.speech)
            Text(passed.count == 1 ? "1 of \(crossings.count) passed"
                                   : "\(passed.count) of \(crossings.count) passed")
                .font(RFDesign.ui(13))
                .foregroundStyle(RFDesign.labelDim)
        }
        .padding(.top, RFDesign.sm)
        .padding(.bottom, RFDesign.lg)
    }

    private func row(_ crossing: Tally.Crossing, isNext: Bool) -> some View {
        HStack(spacing: 14) {
            // Locked tiers are dimmed rather than hidden or silhouetted: seeing
            // what a Space Shuttle badge looks like is most of the reason to
            // want one, and blanking it out would be a worse tease than a
            // faded picture of the real thing.
            Image(crossing.milestone.art)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .opacity(crossing.isPassed ? 1 : 0.22)
                .saturation(crossing.isPassed ? 1 : 0.25)

            VStack(alignment: .leading, spacing: 2) {
                Text(crossing.milestone.name)
                    .font(RFDesign.uiMedium(15))
                    .foregroundStyle(crossing.isPassed ? RFDesign.speech : RFDesign.labelDim)
                Text(Tally.volumeText(crossing.milestone.pounds))
                    .font(RFDesign.ui(12.5))
                    .monospacedDigit()
                    .foregroundStyle(RFDesign.labelDim)
            }

            Spacer(minLength: 8)

            if let on = crossing.crossedOn {
                Text(Fmt.shortDate(on))
                    .font(RFDesign.ui(12.5))
                    .monospacedDigit()
                    .foregroundStyle(RFDesign.ready)
            } else if isNext {
                // Only the next one says how far. Every locked tier quoting a
                // distance turns a ladder into a list of things you have failed
                // to do.
                Text("\(Tally.volumeText(max(0, crossing.milestone.pounds - total))) to go")
                    .font(RFDesign.ui(12))
                    .foregroundStyle(RFDesign.label)
            }
        }
        .padding(.vertical, 11)
    }
}
