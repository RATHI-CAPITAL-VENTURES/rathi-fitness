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
