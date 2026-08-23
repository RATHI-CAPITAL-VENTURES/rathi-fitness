import Foundation

/// Number and time formatting, in one place so two screens cannot disagree
/// about whether 185.0 has a decimal point.
enum Fmt {
    /// Weights print as integers when they are integers. `185`, not `185.0`;
    /// `2.5` keeps its half.
    static func weight(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// Body weight always carries one decimal — a scale that reads 176.4 and an
    /// app that reads 176 disagree, and the app is the one that looks broken.
    static func bodyWeight(_ v: Double) -> String { String(format: "%.1f", v) }

    /// A number as a speech synthesiser should read it.
    ///
    /// `185` said as text is fine; `137.5` is read "one hundred thirty seven
    /// point five", which is four syllables of noise when what you needed was
    /// "a hundred thirty seven and a half". Halves are the only fraction a
    /// weight room has, so they are the only one spelled out.
    static func spoken(_ v: Double) -> String {
        let whole = Int(v.rounded(.towardZero))
        let fraction = abs(v - Double(whole))
        if fraction < 0.05 { return String(whole) }
        if abs(fraction - 0.5) < 0.05 { return "\(whole) and a half" }
        return weight(v)
    }

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// A cardio duration the way a console shows it. `1320` → `22:00`.
    static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return "\(s / 3600):" + String(format: "%02d:%02d", (s % 3600) / 60, s % 60)
        }
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// The same duration in words, for a summary line. `1320` → `22 min`.
    static func minutes(_ seconds: Int) -> String {
        let m = Int((Double(seconds) / 60).rounded())
        if m >= 60 {
            let h = m / 60
            let rest = m % 60
            return rest == 0 ? "\(h) h" : "\(h) h \(rest) min"
        }
        return "\(m) min"
    }

    /// Distances keep two decimals under ten miles and one above — 0.75 mi is a
    /// real answer, 13.10 mi is a spurious one.
    static func distance(_ miles: Double) -> String {
        miles < 10 ? String(format: "%.2f", miles) : String(format: "%.1f", miles)
    }

    /// One decimal, for speeds and inclines. 6.5 mph, 3.0%.
    static func rate(_ v: Double) -> String { String(format: "%.1f", v) }

    /// A cardio metric formatted the way its own console would show it.
    static func metric(_ value: Double, _ metric: CardioMetric) -> String {
        switch metric {
        case .duration: return duration(Int(value))
        case .distance: return distance(value)
        case .speed, .incline: return rate(value)
        case .resistance, .heartRate: return String(Int(value.rounded()))
        }
    }

    static func signed(_ v: Double) -> String {
        if abs(v) < 0.05 { return "—" }
        return (v > 0 ? "+" : "−") + weight(abs(v))
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d)
    }

    static func weekdayDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: d)
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
}
