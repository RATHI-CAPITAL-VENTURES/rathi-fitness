import Foundation

/// The Web App lens's wire format, v1 — the contract with the page and the
/// relay in ria-ar-feed. `docs/LENS_WIRE.md` is its prose and
/// `wire/fixtures/*.json` its examples; `LensWireTests` holds the three
/// together byte for byte, and the `wire-schema` guard holds the version.
///
/// No SDK, no socket here: a `LensScreen` in, JSON text out, and an action
/// name back. Hand-serialised rather than `JSONEncoder`, because the fixtures
/// are compared as bytes and `"rest": null` has to be written, not omitted.
enum LensWire {

    /// Bump only for a change the other side cannot ignore. Inside v1 every
    /// change is additive: unknown fields are ignored by both ends.
    static let version = 1

    // MARK: - JSON, deterministically

    indirect enum JSON: Equatable {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([JSON])
        case object([String: JSON])
    }

    /// Compact, keys sorted, UTF-8 left as is. The same value always gives the
    /// same bytes, which is what makes a fixture comparable.
    static func text(_ json: JSON) -> String {
        var out = ""
        write(json, into: &out)
        return out
    }

    private static func write(_ json: JSON, into out: inout String) {
        switch json {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d):
            if d.isFinite, d == d.rounded(), abs(d) < 1e15 { out += String(Int(d)) } else { out += String(d) }
        case .string(let s): quote(s, into: &out)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                write(item, into: &out)
            }
            out += "]"
        case .object(let fields):
            out += "{"
            for (i, key) in fields.keys.sorted().enumerated() {
                if i > 0 { out += "," }
                quote(key, into: &out)
                out += ":"
                write(fields[key]!, into: &out)
            }
            out += "}"
        }
    }

    private static func quote(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }

    // MARK: - Actions

    /// Every `LensAction`, by its wire name. A registry rather than a switch in
    /// each direction, so encoding and decoding cannot disagree. `open(n)` is
    /// the one with a payload and travels as `{"open": n}`.
    static let actionNames: [(action: LensAction, name: String)] = [
        (.logSet, "logSet"), (.skipRest, "skipRest"), (.extendRest, "extendRest"),
        (.fewerReps, "fewerReps"), (.start, "start"), (.taken, "taken"), (.back, "back"),
        (.list, "list"), (.close, "close"), (.music, "music"), (.play, "play"),
        (.pause, "pause"), (.nextTrack, "nextTrack"),
    ]

    static func action(_ action: LensAction) -> JSON {
        if case .open(let row) = action { return .object(["open": .int(row)]) }
        return .string(actionNames.first { $0.action == action }!.name)
    }

    /// From a decoded JSON value (`JSONSerialization`), or nil for anything
    /// that is not one of ours — an unknown action is refused, never guessed.
    static func action(from value: Any?) -> LensAction? {
        if let name = value as? String { return actionNames.first { $0.name == name }?.action }
        if let object = value as? [String: Any], object.count == 1,
           let row = object["open"] as? Int, row >= 0 { return .open(row) }
        return nil
    }

    // MARK: - Screens

    static func ms(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1000).rounded()) }

    /// A running rest. `endsAt` is the phone's clock (identity, diagnostics);
    /// the lens counts from `remainingMsAtSend`, which needs no shared clock.
    static func rest(_ clock: RestClock, now: Date) -> JSON {
        .object([
            "endsAt": .int(ms(clock.endsAt)),
            "totalMs": .int(Int((clock.total * 1000).rounded())),
            "remainingMsAtSend": .int(max(0, Int((clock.endsAt.timeIntervalSince(now) * 1000).rounded()))),
        ])
    }

    static func screen(_ screen: LensScreen, now: Date) -> JSON {
        switch screen {
        case .set(let state):
            var fields: [String: JSON] = [
                "kind": .string("set"),
                "eyebrow": .string(state.eyebrow),
                "title": .string(state.title),
                "detail": .string(state.detail),
                "actions": .array(state.actions.map(action)),
                "rest": .null,
            ]
            switch state.tone {
            case .ready: fields["tone"] = .string("ready")
            case .resting: fields["tone"] = .string("resting")
            case .done: fields["tone"] = .string("done")
            }
            if case .resting = state.tone, let clock = state.rest {
                // The page ticks this one itself, so the numeral is not sent.
                fields["rest"] = rest(clock, now: now)
            } else {
                fields["hero"] = .string(state.hero)
            }
            return .object(fields)

        case .list(let list):
            return .object([
                "kind": .string("list"),
                "eyebrow": .string(list.eyebrow),
                "rows": .array(list.rows.map { row in
                    .object([
                        "title": .string(row.title),
                        "trailing": .string(row.trailing),
                        "done": .bool(row.done),
                        // Three places: a ring a few pixels across, and bytes
                        // that do not wobble in the last digit.
                        "progress": row.progress.map { .double(($0 * 1000).rounded() / 1000) } ?? .null,
                        "action": action(row.action),
                    ])
                }),
                "footer": .array(list.footer.map(action)),
            ])

        case .card(let card):
            return .object([
                "kind": .string("card"),
                "eyebrow": .string(card.eyebrow),
                "title": .string(card.title),
                "specs": .array(card.specs.map { spec in
                    if let clock = spec.rest {
                        return .object(["label": .string(spec.label), "rest": rest(clock, now: now)])
                    }
                    return .object(["label": .string(spec.label), "value": .string(spec.value)])
                }),
                "lines": .array(card.lines.map(JSON.string)),
                "actions": .array(card.actions.map(action)),
            ])
        }
    }

    // MARK: - Messages the phone sends

    static func screenMessage(epoch: String, seq: Int, screen value: LensScreen, now: Date) -> JSON {
        .object(["v": .int(version), "type": .string("screen"), "epoch": .string(epoch),
                 "seq": .int(seq), "screen": screen(value, now: now)])
    }

    /// Nothing of ours belongs on the lens. Not in plan §3; see LENS_WIRE.md.
    static func idleMessage(epoch: String, seq: Int, reason: String, text: String) -> JSON {
        .object(["v": .int(version), "type": .string("idle"), "epoch": .string(epoch),
                 "seq": .int(seq), "reason": .string(reason), "text": .string(text)])
    }

    static func hello(version appVersion: String) -> JSON {
        .object(["v": .int(version), "type": .string("hello"), "version": .string(appVersion)])
    }

    /// Every 5 s: the room's clock comes back in the `pong`, and the current
    /// ticket rides along so the page knows the phone is still behind it.
    static func ping(id: Int, t: Int, epoch: String, seq: Int?) -> JSON {
        .object(["v": .int(version), "type": .string("ping"), "id": .int(id), "t": .int(t),
                 "epoch": .string(epoch), "seq": seq.map(JSON.int) ?? .null])
    }

    static func ack(id: String, accepted: Bool, why: String?) -> JSON {
        .object(["v": .int(version), "type": .string("ack"), "id": .string(id),
                 "accepted": .bool(accepted), "why": why.map(JSON.string) ?? .null])
    }

    /// Inbound text as a dictionary, or nil if it is not a v1 object of ours.
    /// A message with no `v` is read as v1 (the room's own replies may omit it);
    /// any other version is refused rather than half-understood.
    static func decode(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] is String else { return nil }
        if let v = object["v"] as? Int, v != version { return nil }
        return object
    }
}
