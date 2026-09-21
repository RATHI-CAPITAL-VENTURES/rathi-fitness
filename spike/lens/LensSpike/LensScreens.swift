import MWDATDisplay
import UIKit

// No SwiftUI here either — see the note at the top of Glasses.swift.

/// What goes in front of your eye. Each of these is a whole screen: the SDK has
/// no partial update, so "the number changed" means building and sending all of
/// it again.
///
/// The words are from a real workout on purpose. A spike that renders "Test 1"
/// answers whether text appears; it says nothing about whether "Incline
/// Dumbbell Press" fits on a line.
enum LensScreens {

    typealias Tap = @Sendable () -> Void

    /// Question 1. If this shows up, the rest of the spike is worth running.
    static func hello(onPinch: @escaping Tap) -> FlexBox {
        FlexBox(direction: .column, spacing: 12) {
            FlexBox(direction: .column, spacing: 6) {
                Text("PUSH · 2 OF 6", style: .meta, color: .secondary)
                Text("Bench Press", style: .heading)
                Text("185 × 8 · set 2 of 4", style: .body, color: .secondary)
            }
            .padding(24)
            .background(.card)
            ButtonGroup {
                Button(label: "Log set", style: .primary, iconName: .checkmark, onClick: onPinch)
            }
        }
    }

    /// The rest countdown — questions 2, 3 and 5 all run on this one.
    ///
    /// `hero` is the fork in question 3: nil draws the clock as Meta's own
    /// heading text, which is a few bytes; an image draws it the way the phone
    /// would, and costs a bitmap every tick.
    static func rest(
        remaining: Int, caption: String, hero: UIImage?,
        onLog: @escaping Tap, onExtend: @escaping Tap
    ) -> FlexBox {
        FlexBox(direction: .column, spacing: 12) {
            FlexBox(direction: .column, spacing: 6) {
                Text("RESTING · BENCH PRESS", style: .meta, color: .secondary)
                if let hero {
                    Image(image: hero, sizePreset: .fill, cornerRadius: .none)
                } else {
                    Text(clock(remaining), style: .heading)
                }
                Text(caption, style: .body, color: .secondary)
            }
            .padding(24)
            .background(.card)
            ButtonGroup {
                Button(label: "Skip", style: .primary, iconName: .triangleRightVerticalLine, onClick: onLog)
                Button(label: "+30 s", style: .secondary, iconName: .plus, onClick: onExtend)
            }
        }
    }

    /// Question 4: one screen, then silence.
    static func still(title: String, body: String) -> FlexBox {
        FlexBox(direction: .column, spacing: 8) {
            Text(title, style: .heading)
            Text(body, style: .body, color: .secondary)
        }
        .padding(24)
        .background(.card)
    }

    /// Question 6: more rows than 600 pixels can hold. Built the way Meta's
    /// sample builds its menu — a column of tappable cards — so if this clips,
    /// theirs does too.
    static func tallList(onPick: @escaping @Sendable (Int, String) -> Void) -> FlexBox {
        let rows: [(String, String)] = [
            ("Bench Press", "2 of 4"), ("Incline Dumbbell Press", "60 × 10"),
            ("Cable Fly", "35 × 12"), ("Triceps Pushdown", "50 × 12"),
            ("Overhead Press", "95 × 8"), ("Lateral Raise", "15 × 15"),
            ("Dip, assisted", "40 help × 10"), ("Treadmill", "done"),
        ]
        return FlexBox(direction: .column, spacing: 10) {
            for index in rows.indices {
                FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
                    Text("\(index + 1). \(rows[index].0)", style: .body)
                    Text(rows[index].1, style: .meta, color: .secondary)
                }
                .padding(24)
                .background(.card)
                .onTap { onPick(index + 1, rows[index].0) }
            }
        }
    }

    /// Question 7: which button is lit when a screen first appears, and what a
    /// middle-finger tap does from here.
    static func focusProbe(onPick: @escaping @Sendable (String) -> Void) -> FlexBox {
        FlexBox(direction: .column, spacing: 12) {
            FlexBox(direction: .column, spacing: 6) {
                Text("Which button is lit?", style: .heading)
                Text("Note it on the phone. Then tap middle finger to thumb.", style: .body, color: .secondary)
            }
            .padding(24)
            .background(.card)
            ButtonGroup {
                Button(label: "Start", style: .primary, onClick: { onPick("Start") })
                Button(label: "Taken", style: .secondary, onClick: { onPick("Taken") })
                Button(label: "Back", style: .outline, onClick: { onPick("Back") })
            }
        }
    }

    // MARK: - The image path

    /// The clock, drawn by us. 552 wide is the lens's 600 less the card's
    /// padding; one pixel per point, because the glasses have no use for a 3×
    /// bitmap and the radio certainly doesn't.
    static func clockImage(_ remaining: Int) -> UIImage {
        let size = CGSize(width: 552, height: 220)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            // Black is transparent on an additive display, so this is "nothing".
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let base = UIFont.systemFont(ofSize: 190, weight: .regular)
            let serif = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 190) } ?? base
            let text = NSAttributedString(string: clock(remaining), attributes: [
                .font: serif,
                // RFDesign.ready — hue 167.
                .foregroundColor: UIColor(red: 0.294, green: 0.859, blue: 0.737, alpha: 1),
                .kern: -4,
            ])
            let bounds = text.size()
            text.draw(at: CGPoint(x: 0, y: (size.height - bounds.height) / 2))
        }
    }

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
