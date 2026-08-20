import Foundation
import SwiftData

/// CSV, for the times you want a spreadsheet rather than an app.
///
/// The snapshot is the machine-readable export and RIA reads it; this is the
/// human one. Every logged set, one row, with everything needed to rebuild the
/// log elsewhere — which is also what makes leaving possible, and an app you
/// cannot leave is one you have to trust rather than one you choose.
enum Export {

    static let header = "date,exercise,slug,muscle,set,kind,weight_lb,reps,rpe,volume_lb,note,source"

    static func csv(from context: ModelContext) throws -> String {
        let sets = try context.fetch(
            FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.date, order: .forward)]))
        var lines = [header]
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]

        for entry in sets {
            let exercise = entry.exercise
            let volume = entry.setKind.counts ? entry.weight * Double(entry.reps) : 0
            lines.append([
                stamp.string(from: entry.date),
                escape(exercise?.name ?? ""),
                exercise?.slug ?? "",
                exercise?.primary.rawValue ?? "",
                String(entry.setIndex),
                entry.setKind.rawValue,
                Fmt.weight(entry.weight),
                String(entry.reps),
                entry.rpe > 0 ? String(format: "%.1f", entry.rpe) : "",
                Fmt.weight(volume),
                escape(entry.note),
                entry.source,
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func weighInsCSV(from context: ModelContext) throws -> String {
        let rows = try context.fetch(
            FetchDescriptor<WeighIn>(sortBy: [SortDescriptor(\.date, order: .forward)]))
        let metrics = try context.fetch(
            FetchDescriptor<BodyMetric>(sortBy: [SortDescriptor(\.date, order: .forward)]))
        var lines = ["date,metric,value,unit,source"]
        let stamp = ISO8601DateFormatter()
        for row in rows {
            lines.append("\(stamp.string(from: row.date)),body_weight,"
                         + "\(Fmt.bodyWeight(row.pounds)),lb,\(row.source)")
        }
        for row in metrics {
            lines.append("\(stamp.string(from: row.date)),\(row.metric.rawValue),"
                         + "\(String(format: "%.2f", row.inches)),in,user")
        }
        return lines.joined(separator: "\n")
    }

    /// RFC 4180: quote anything containing a comma, quote or newline, and double
    /// any embedded quotes. A note saying `felt heavy, shoulder clicked` would
    /// otherwise silently become two columns.
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n")
        else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Write both files somewhere shareable and hand back the URLs.
    static func write(from context: ModelContext) throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rathi-fitness-export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let day = Fmt.day(.now)
        let sets = dir.appendingPathComponent("sets-\(day).csv")
        let body = dir.appendingPathComponent("body-\(day).csv")
        try csv(from: context).write(to: sets, atomically: true, encoding: .utf8)
        try weighInsCSV(from: context).write(to: body, atomically: true, encoding: .utf8)
        return [sets, body]
    }
}
