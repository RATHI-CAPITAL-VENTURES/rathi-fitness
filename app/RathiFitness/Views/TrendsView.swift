import SwiftUI
import SwiftData
import Charts

/// Body weight and working weight on one screen, because they answer one
/// question: am I getting stronger, or just heavier.
struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeighIn.date) private var weighIns: [WeighIn]
    @Query(sort: \SetEntry.date) private var allSets: [SetEntry]
    @Query private var exercises: [Exercise]
    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]

    @State private var measuring = false

    @State private var selection: Selection = .body
    @State private var range: Range = .month

    enum Selection: Hashable { case body, exercise(String) }
    enum Range: String, CaseIterable, Identifiable {
        case month = "30D", quarter = "3M", year = "1Y", all = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }
    }

    /// The lifts worth putting in a segmented control: the ones with the most
    /// history, so the control does not fill with things done once.
    private var featured: [Exercise] {
        exercises
            .map { ex in (ex, allSets.filter { $0.exercise?.slug == ex.slug }.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RFDesign.md) {
                    Text("Trends")
                        .font(RFDesign.title(34))
                        .foregroundStyle(RFDesign.speech)
                        .padding(.top, RFDesign.sm)

                    LegacyDataBanner()
                    picker
                    if allSets.contains(where: \.isDemo)
                        || weighIns.contains(where: \.isDemo) {
                        // Never let invented numbers pass as his without saying so.
                        Label("Some of this is sample data — Settings › Your data to remove it.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(RFDesign.ui(12))
                            .foregroundStyle(RFDesign.ember)
                    }
                    headline
                    chart
                    rangePicker

                    muscleWork

                    VStack(alignment: .leading, spacing: RFDesign.sm) {
                        HStack {
                            Text("Working weight").rfEyebrow()
                            Spacer()
                            Text("vs 30 days ago").rfEyebrow()
                        }
                        strengthTable
                    }
                    .padding(.top, RFDesign.md)
                    measurements
                }
                .padding(.horizontal, 22)
                .padding(.bottom, RFDesign.xl)
            }
            .scrollIndicators(.hidden)
            .background(RoomBackground())
            .sheet(isPresented: $measuring) {
                MeasureSheet { kind, inches in
                    context.insert(BodyMetric(kind: kind, inches: inches))
                    try? context.save()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: controls

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                segment("Body", active: selection == .body) { selection = .body }
                ForEach(featured) { ex in
                    segment(short(ex.name), active: selection == .exercise(ex.slug)) {
                        selection = .exercise(ex.slug)
                    }
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
        }
        .scrollClipDisabled()
    }

    private func segment(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RFDesign.uiMedium(12.5))
                .foregroundStyle(active ? RFDesign.speech : RFDesign.labelDim)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 8).fill(RFDesign.surfaceHigh)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var rangePicker: some View {
        HStack(spacing: 7) {
            ForEach(Range.allCases) { r in
                Button { range = r } label: {
                    Text(r.rawValue)
                        .font(RFDesign.uiMedium(12.5))
                        .foregroundStyle(range == r ? RFDesign.ready : RFDesign.labelDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if range == r {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(RFDesign.ready.opacity(0.14))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: data

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var series: [Point] {
        let cutoff = range.days.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: .now)
        }
        switch selection {
        case .body:
            return weighIns
                .filter { w in cutoff.map { w.date >= $0 } ?? true }
                .map { Point(date: $0.date, value: $0.pounds) }
        case .exercise(let slug):
            let mine = allSets.filter { $0.exercise?.slug == slug }
                .filter { entry in cutoff.map { entry.date >= $0 } ?? true }
            // One point per session: the top set. A point per set makes a
            // scribble that hides the thing you came to see.
            let byDay = Dictionary(grouping: mine) { Calendar.current.startOfDay(for: $0.date) }
            return byDay.keys.sorted().map {
                Point(date: $0, value: byDay[$0]?.map(\.weight).max() ?? 0)
            }
        }
    }

    private var unit: String { "lb" }

    private var headline: some View {
        let points = series
        let latest = points.last?.value
        let change = (points.count > 1 && latest != nil) ? latest! - points[0].value : nil
        let perWeek: Double? = {
            guard let change, let first = points.first, let last = points.last else { return nil }
            let span = last.date.timeIntervalSince(first.date) / 86_400
            return span >= 1 ? change / span * 7 : nil
        }()
        let goodDirection = selection == .body ? (change ?? 0) <= 0 : (change ?? 0) >= 0

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(latest.map { selection == .body ? Fmt.bodyWeight($0) : Fmt.weight($0) } ?? "—")
                    .font(RFDesign.figure(58))
                    .monospacedDigit()
                    .foregroundStyle(RFDesign.speech)
                Text(unit).rfEyebrow(RFDesign.labelDim, size: 14)
            }
            HStack(spacing: 7) {
                if let change {
                    Text("\(Fmt.signed(change)) \(unit)")
                        .font(RFDesign.ui(13, bold: true))
                        .foregroundStyle(goodDirection ? RFDesign.ready : RFDesign.label)
                }
                Text(subtitle(perWeek: perWeek, count: points.count))
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.labelDim)
            }
        }
    }

    private func subtitle(perWeek: Double?, count: Int) -> String {
        guard count > 1 else { return "not enough readings yet" }
        let window = range == .all ? "all time" : "over \(range.days ?? 0) days"
        guard let perWeek, abs(perWeek) >= 0.05 else { return window }
        return "\(window) · trending \(Fmt.signed(perWeek))/wk"
    }

    @ViewBuilder private var chart: some View {
        let points = series
        if points.count < 2 {
            EmptyNote(title: "Nothing to plot yet.",
                      message: "Log a few sessions — or weigh in a few mornings — and the "
                             + "shape shows up here.")
                .frame(height: 168)
        } else {
            // The floor is computed, not left to Chart. A one-argument AreaMark
            // anchors to zero, which drags the Y domain down to 0 and renders a
            // 3lb cut over 30 days as a flat line — the chart draws, looks fine,
            // and shows nothing. `chartYScale` alone does not fix it; the mark
            // itself has to start somewhere other than zero.
            let lo = (points.map(\.value).min() ?? 0)
            let hi = (points.map(\.value).max() ?? 1)
            let pad = max((hi - lo) * 0.18, selection == .body ? 0.6 : 5)
            let floor = lo - pad
            let ceiling = hi + pad

            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Date", p.date),
                             yStart: .value(unit, floor),
                             yEnd: .value(unit, p.value))
                        .foregroundStyle(.linearGradient(
                            colors: [RFDesign.ready.opacity(0.22), RFDesign.ready.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(selection == .body ? .linear : .stepEnd)
                    LineMark(x: .value("Date", p.date), y: .value(unit, p.value))
                        .foregroundStyle(RFDesign.ready)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                        .interpolationMethod(selection == .body ? .linear : .stepEnd)
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
            .frame(height: 168)
        }
    }

    // MARK: sets per muscle

    /// The standard hypertrophy question — am I doing enough pulling — which
    /// this screen could not answer before. Secondary movers count half.
    @ViewBuilder private var muscleWork: some View {
        let since = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let work = Tally.muscleWork(allSets.map {
            Tally.LoggedSet(date: $0.date, kind: $0.setKind,
                               primary: $0.exercise?.primary ?? .other,
                               secondary: $0.exercise?.secondary ?? [])
        }, since: since)

        if work.isEmpty && !allSets.isEmpty {
            // Silence here reads as "you did no work". The truth is that the
            // lifts have no muscles set, and that is fixable in two taps.
            VStack(alignment: .leading, spacing: 6) {
                Text("Sets per muscle").rfEyebrow()
                Text("None of your exercises say what they work yet. "
                     + "Settings › Edit the plan › an exercise › Muscles.")
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.labelDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, RFDesign.md)
        } else if !work.isEmpty {
            let peak = work.first?.sets ?? 1
            VStack(alignment: .leading, spacing: RFDesign.sm) {
                HStack {
                    Text("Sets per muscle").rfEyebrow()
                    Spacer()
                    Text("last 7 days").rfEyebrow()
                }
                VStack(spacing: 7) {
                    ForEach(work) { row in
                        HStack(spacing: 10) {
                            Text(row.muscle.label)
                                .font(RFDesign.ui(13))
                                .foregroundStyle(RFDesign.speech)
                                .frame(width: 78, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.06))
                                    Capsule().fill(RFDesign.ready.opacity(0.65))
                                        .frame(width: max(3, geo.size.width * row.sets / peak))
                                }
                            }
                            .frame(height: 8)
                            Text(Fmt.weight(row.sets))
                                .font(RFDesign.ui(12))
                                .monospacedDigit()
                                .foregroundStyle(RFDesign.labelDim)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.top, RFDesign.md)
        }
    }

    // MARK: measurements

    private var measurements: some View {
        VStack(alignment: .leading, spacing: RFDesign.sm) {
            HStack {
                Text("Measurements").rfEyebrow()
                Spacer()
                Button { measuring = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(RFDesign.ready)
                }
                .accessibilityLabel("Add a measurement")
            }
            if latestMetrics.isEmpty {
                Text("Waist and arms are the two people actually keep.")
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.labelDim)
            }
            ForEach(latestMetrics, id: \.0) { kind, latest, change in
                HStack {
                    Text(kind.label)
                        .font(RFDesign.uiMedium(14.5))
                        .foregroundStyle(RFDesign.speech)
                    Spacer()
                    Text(String(format: "%.2f in", latest))
                        .font(RFDesign.figure(16, relativeTo: .body))
                        .monospacedDigit()
                        .foregroundStyle(RFDesign.speech)
                    Text(change.map { Fmt.signed($0) } ?? "—")
                        .font(RFDesign.ui(11.5, bold: true))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(RFDesign.labelDim)
                }
                .padding(.vertical, 8)
                Divider().overlay(RFDesign.hairline)
            }
        }
        .padding(.top, RFDesign.lg)
    }

    /// Newest reading per measurement, with the change since the one before it.
    private var latestMetrics: [(MetricKind, Double, Double?)] {
        let grouped = Dictionary(grouping: metrics) { $0.metric }
        return MetricKind.allCases.compactMap { kind in
            guard let rows = grouped[kind]?.sorted(by: { $0.date > $1.date }),
                  let latest = rows.first else { return nil }
            let previous = rows.dropFirst().first
            return (kind, latest.inches, previous.map { latest.inches - $0.inches })
        }
    }

    // MARK: table

    private var strengthTable: some View {
        VStack(spacing: 0) {
            let rows = strengthRows
            if rows.isEmpty {
                Text("No lifts logged yet.")
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.labelDim)
                    .padding(.vertical, 12)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                Button { selection = .exercise(row.slug) } label: {
                    HStack(spacing: 12) {
                        Text(row.name)
                            .font(RFDesign.uiMedium(14.5))
                            .foregroundStyle(RFDesign.speech)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Sparkline(values: row.spark)
                            .frame(width: 58, height: 20)
                        Text(Fmt.weight(row.current))
                            .font(RFDesign.figure(18, relativeTo: .body))
                            .monospacedDigit()
                            .foregroundStyle(RFDesign.speech)
                        Text(row.change.map(Fmt.signed) ?? "—")
                            .font(RFDesign.ui(11.5, bold: true))
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                            .foregroundStyle((row.change ?? 0) > 0 ? RFDesign.ready : RFDesign.labelDim)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < rows.count - 1 { Divider().overlay(RFDesign.hairline) }
            }
        }
    }

    private struct Row { let slug: String; let name: String; let current: Double
                        let change: Double?; let spark: [Double] }

    private var strengthRows: [Row] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        return exercises.compactMap { ex -> Row? in
            let mine = allSets.filter { $0.exercise?.slug == ex.slug }
            guard !mine.isEmpty else { return nil }
            let byDay = Dictionary(grouping: mine) { Calendar.current.startOfDay(for: $0.date) }
            let days = byDay.keys.sorted()
            let tops = days.map { byDay[$0]?.map(\.weight).max() ?? 0 }
            guard let current = tops.last else { return nil }
            // Compare with the last session at or before the cutoff — "30 days
            // ago" is not a day you necessarily trained.
            let baseIndex = days.lastIndex { $0 <= cutoff }
            let change = baseIndex.map { current - tops[$0] }
            return Row(slug: ex.slug, name: ex.name, current: current,
                       change: change, spark: Array(tops.suffix(8)))
        }
        .sorted { $0.current > $1.current }
    }

    private func short(_ name: String) -> String {
        name.replacingOccurrences(of: "Barbell ", with: "")
            .replacingOccurrences(of: " Press", with: "")
            .replacingOccurrences(of: "Back ", with: "")
    }
}

/// A line small enough to sit in a table row. Flat series render flat and
/// centred rather than collapsing to the baseline.
struct Sparkline: View {
    var values: [Double]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count > 1 else {
                    path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                    return
                }
                let lo = values.min() ?? 0, hi = values.max() ?? 1
                let span = (hi - lo) == 0 ? 1 : (hi - lo)
                let inset: CGFloat = 3
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                    let norm = (hi - lo) == 0 ? 0.5 : (v - lo) / span
                    let y = geo.size.height - inset - CGFloat(norm) * (geo.size.height - inset * 2)
                    i == 0 ? path.move(to: CGPoint(x: x, y: y))
                           : path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.white.opacity(0.34),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}


/// One tape-measure reading.
struct MeasureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: MetricKind = .waist
    @State private var text = ""
    var onSave: (MetricKind, Double) -> Void

    private var value: Double? { Double(text.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Where", selection: $kind) {
                    ForEach(MetricKind.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    TextField("32.5", text: $text)
                        .keyboardType(.decimalPad)
                        .font(RFDesign.figure(30, relativeTo: .title))
                        .monospacedDigit()
                    Text("inches").rfEyebrow(RFDesign.labelDim, size: 12)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFDesign.ground.ignoresSafeArea())
            .navigationTitle("Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value, value > 0 { onSave(kind, value) }
                        dismiss()
                    }
                    .disabled(value == nil)
                }
            }
        }
        .presentationDetents([.height(300)])
    }
}
