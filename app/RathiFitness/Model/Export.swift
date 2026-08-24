import Foundation
import SwiftData

/// CSV, for the times you want a spreadsheet rather than an app.
///
/// The snapshot is the machine-readable export and RIA reads it; this is the
/// human one. Every logged set, one row, with everything needed to rebuild the
/// log elsewhere — which is also what makes leaving possible, and an app you
/// cannot leave is one you have to trust rather than one you choose.
enum Export {

    /// One row shape for both kinds of thing, with the cardio columns simply
    /// blank on a lift. Two files would have been tidier to write and worse to
    /// use: "which CSV is my treadmill in" is a question a spreadsheet should
    /// never make you ask, and a blank cell reads as "not applicable" to
    /// everybody without being explained.
    static let header = "date,exercise,slug,modality,assisted,muscle,set,kind,weight_lb,reps,"
        + "rpe,volume_lb,seconds,distance_mi,speed_mph,incline_pct,resistance,avg_hr,note,source"

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
                exercise?.modality ?? Exercise.Modality.strength.rawValue,
                // Without this column `weight_lb` silently mixes two opposite
                // meanings and any sort or average over it is wrong.
                (exercise?.assisted ?? false) ? "true" : "false",
                exercise?.primary.rawValue ?? "",
                String(entry.setIndex),
                entry.setKind.rawValue,
                Fmt.weight(entry.weight),
                String(entry.reps),
                entry.rpe > 0 ? String(format: "%.1f", entry.rpe) : "",
                Fmt.weight(volume),
                // Blank rather than 0: a lift did not do zero seconds, it did
                // not do seconds. A spreadsheet averaging the column would
                // otherwise be told every bench press was a nought-minute run.
                entry.seconds > 0 ? String(entry.seconds) : "",
                entry.distance > 0 ? Fmt.distance(entry.distance) : "",
                entry.speed > 0 ? Fmt.rate(entry.speed) : "",
                entry.incline > 0 ? Fmt.rate(entry.incline) : "",
                entry.resistance > 0 ? Fmt.weight(entry.resistance) : "",
                entry.averageHeartRate > 0 ? String(entry.averageHeartRate) : "",
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

    /// Where every machine is set. Its own file because it is a different shape
    /// of fact — one row per dial per exercise, with no date on it. Folding it
    /// into the set log would repeat "seat: 2" on all four thousand rows.
    static func machinesCSV(from context: ModelContext) throws -> String {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var lines = ["exercise,slug,setting,value,updated"]
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]
        for exercise in exercises.sorted(by: { $0.name < $1.name }) {
            for setting in exercise.settings
            where !setting.value.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append([
                    escape(exercise.name), exercise.slug,
                    setting.setting.rawValue, escape(setting.value),
                    stamp.string(from: setting.updatedAt),
                ].joined(separator: ","))
            }
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
        let machines = dir.appendingPathComponent("machines-\(day).csv")
        try csv(from: context).write(to: sets, atomically: true, encoding: .utf8)
        try weighInsCSV(from: context).write(to: body, atomically: true, encoding: .utf8)
        try machinesCSV(from: context).write(to: machines, atomically: true, encoding: .utf8)
        return [sets, body, machines]
    }
}
