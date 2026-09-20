import SwiftUI
import Charts

/// The workout a set belongs to, as a sortable key.
///
/// Both charts that use this have always said "one point per session" in their
/// own comments and then grouped by `startOfDay`, because a day was the only
/// thing there was to group by. A two-a-day therefore showed as one point,
/// taking the heavier of the two workouts and hiding the other entirely.
///
/// Falls back to the day for a set with no session — CloudKit can deliver rows
/// from a device on an older build, and dropping them from a chart would be a
/// quieter version of the same bug.
extension SetEntry {
    var workoutKey: Date {
        session?.startedAt ?? Calendar.current.startOfDay(for: date)
    }
}

extension Array where Element == SetEntry {
    /// These sets as a trend line — the right one for what the exercise is.
    /// One call so the Trends tab and the set screen cannot plot the same lift
    /// two different ways.
    func trend(for exercise: Exercise) -> Tally.Trend {
        if exercise.isCardio {
            return Tally.cardioTrend(map {
                (workout: $0.workoutKey,
                 bout: Tally.Bout(seconds: $0.seconds, distance: $0.distance))
            })
        }
        // No bodyweight: a trend reads weight, never volume.
        return Tally.liftTrend(map { (workout: $0.workoutKey, set: $0.tally(bodyWeight: nil)) })
    }
}

/// The line itself. Lifted out of `TrendsView` unchanged so the set screen
/// draws the SAME chart rather than a second one that drifts.
struct TrendChart: View {
    let points: [Tally.TrendPoint]
    let unit: String
    /// A working weight holds until you change it, so it steps. A body weight
    /// or a distance is a reading, so it is joined.
    var stepped = true
    /// The least room to leave above and below, in the chart's own unit.
    var minimumPad: Double = 5
    var height: CGFloat = 168

    var body: some View {
        // The floor is computed, not left to Chart. A one-argument AreaMark
        // anchors to zero, which drags the Y domain down to 0 and renders a
        // 3lb cut over 30 days as a flat line — the chart draws, looks fine,
        // and shows nothing. `chartYScale` alone does not fix it; the mark
        // itself has to start somewhere other than zero.
        let lo = points.map(\.value).min() ?? 0
        let hi = points.map(\.value).max() ?? 1
        let pad = max((hi - lo) * 0.18, minimumPad)
        let floor = lo - pad
        let ceiling = hi + pad
        let method: InterpolationMethod = stepped ? .stepEnd : .linear

        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Date", p.date),
                         yStart: .value(unit, floor),
                         yEnd: .value(unit, p.value))
                    .foregroundStyle(.linearGradient(
                        colors: [RFDesign.ready.opacity(0.22), RFDesign.ready.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(method)
                LineMark(x: .value("Date", p.date), y: .value(unit, p.value))
                    .foregroundStyle(RFDesign.ready)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .interpolationMethod(method)
            }
            // The endpoint is the point you opened the screen for.
            if let last = points.last {
                PointMark(x: .value("Date", last.date), y: .value(unit, last.value))
                    .foregroundStyle(RFDesign.ready)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: floor...ceiling)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel()
                    .font(RFDesign.ui(10))
                    .foregroundStyle(RFDesign.labelDim)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel()
                    .font(RFDesign.ui(10))
                    .foregroundStyle(RFDesign.labelDim)
            }
        }
        .frame(height: height)
    }
}

/// One exercise's curve, for the foot of its set screen.
///
/// "Last three" says 45, 50, 55. This says whether that is a run or the whole
/// story — and because today's workout is a point on it, the line moves when
/// you log the set, which is the one moment the number is worth looking at.
///
/// Absent until there are two workouts to join. An empty chart frame at the
/// bottom of a screen you are reading between sets is furniture, and "No
/// history yet." is already said directly above it.
struct ExerciseTrend: View {
    let exercise: Exercise
    /// Every set of this exercise, any order.
    let sets: [SetEntry]

    var body: some View {
        let trend = sets.trend(for: exercise)
        if trend.points.count >= 2 {
            // `sm`, not `xs`: the chart's top axis label sits at its very top
            // edge, and at `xs` "190" read as a second line of the summary.
            VStack(alignment: .leading, spacing: RFDesign.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(exercise.name) · trend").rfEyebrow()
                    Spacer(minLength: 8)
                    if let line = summary(of: trend) {
                        Text(line)
                            .font(RFDesign.ui(12.5, bold: true))
                            .monospacedDigit()
                            .foregroundStyle(trend.isProgress ? RFDesign.ready : RFDesign.label)
                    }
                }
                TrendChart(points: trend.points, unit: trend.measure.unit,
                           stepped: !exercise.isCardio,
                           minimumPad: exercise.isCardio ? 0.5 : 5,
                           height: 132)
                    .accessibilityIdentifier("exercise-trend")
            }
        }
    }

    /// "+10 lb · 26 days". Nothing when it has not moved — "+0 lb" is a line
    /// of text reporting the absence of news.
    private func summary(of trend: Tally.Trend) -> String? {
        guard let change = trend.change, abs(change) >= 0.05 else { return nil }
        let amount = trend.measure == .miles
            ? (change > 0 ? "+" : "−") + Fmt.distance(abs(change))
            : Fmt.signed(change)
        let span = trend.days
        let over = span >= 14 ? "\(span / 7) weeks" : "\(max(span, 1)) day\(span == 1 ? "" : "s")"
        return "\(amount) \(trend.measure.unit) · \(over)"
    }
}
