import Foundation

/// What goes on the bar, per side.
///
/// A registry and one greedy pass over it, rather than a branch per plate —
/// adding a 55 or a fractional set is a line in `standard`, not a new code path.
enum PlateMath {

    /// A commercial gym's rack, heaviest first. Greedy is optimal for this set
    /// (every plate divides into the next one up), which is why it stays greedy.
    static let standard: [Double] = [45, 35, 25, 10, 5, 2.5]

    /// A bar you can pick by name.
    struct Bar: Equatable {
        let pounds: Double
        let label: String
    }

    /// The bars that weigh the same in every gym, heaviest first. One row each;
    /// the picker, its labels and the tests are all read from here.
    ///
    /// Absent on purpose: EZ-curl, trap/hex, safety-squat, Swiss and Smith
    /// machine bars. None of them has a standard weight — a hex bar is anything
    /// from 45 to 70 lb and a counterbalanced Smith bar can be 15 — so a row
    /// here would be a guess wearing a label. The exercise editor takes a typed
    /// weight for those instead.
    static let bars: [Bar] = [
        Bar(pounds: 45, label: "45 lb — standard"),
        Bar(pounds: 35, label: "35 lb — women's"),
        Bar(pounds: 25, label: "25 lb — short"),
        Bar(pounds: 15, label: "15 lb — technique"),
        Bar(pounds: 0, label: "None"),
    ]

    /// The picker's options, always including the bar actually set.
    ///
    /// A typed-in 55 lb hex bar is not in `bars`, and a menu that cannot find
    /// its own current value shows "—" — which reads as "no bar" while the
    /// plate math quietly goes on subtracting 55.
    static func barOptions(including current: Double) -> [Bar] {
        guard !bars.contains(where: { $0.pounds == current }) else { return bars }
        let custom = Bar(pounds: current, label: "\(Fmt.weight(current)) lb — yours")
        return (bars + [custom]).sorted { $0.pounds > $1.pounds }
    }

    struct Loadout: Equatable {
        /// Plates for ONE side, heaviest first, repeats included.
        let perSide: [Double]
        /// Weight the rack cannot express — you asked for 186 with 2.5s as the
        /// smallest plate. Non-zero means the number on screen is a lie unless
        /// you show this.
        let remainder: Double
        /// What you will actually be lifting.
        let achievable: Double

        var isExact: Bool { remainder == 0 }
    }

    /// - Parameters:
    ///   - target: total weight including the bar.
    ///   - bar: the bar itself. 45 for a standard barbell, 35 for a women's bar.
    static func loadout(target: Double, bar: Double,
                        available: [Double] = standard) -> Loadout {
        guard target > bar else {
            return Loadout(perSide: [], remainder: max(0, target - bar), achievable: bar)
        }
        var side = (target - bar) / 2
        var plates: [Double] = []
        for plate in available.sorted(by: >) {
            while side >= plate - 0.0001 {
                plates.append(plate)
                side -= plate
            }
        }
        let remainder = side < 0.0001 ? 0 : side * 2
        let achievable = target - remainder
        return Loadout(perSide: plates, remainder: remainder, achievable: achievable)
    }

    /// Plates collapsed to `(plate, count)` for display: `45 × 2, 25`.
    static func grouped(_ perSide: [Double]) -> [(plate: Double, count: Int)] {
        var out: [(Double, Int)] = []
        for p in perSide {
            if let last = out.last, last.0 == p { out[out.count - 1].1 += 1 }
            else { out.append((p, 1)) }
        }
        return out.map { (plate: $0.0, count: $0.1) }
    }

    /// The next weight up or down that the rack can actually make. Used by the
    /// steppers so `+` never lands on a number you cannot load.
    static func step(from weight: Double, by delta: Double, bar: Double,
                     available: [Double] = standard) -> Double {
        let smallest = (available.min() ?? 2.5) * 2
        let raw = weight + delta
        guard raw > bar else { return bar }
        let steps = ((raw - bar) / smallest).rounded()
        return bar + steps * smallest
    }
}
