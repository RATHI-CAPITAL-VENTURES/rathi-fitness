import MWDATDisplay
import UIKit

// No SwiftUI in this file, and that is structural rather than tidy: Meta's
// display module exports `Text`, `Button` and `Image`, and the two sets of
// names cannot share a file without every use being qualified. Colours arrive
// from RFDesign as UIKit values for the same reason.

/// A `LensState` in Meta's vocabulary.
///
/// That vocabulary is small — a flex box, three sizes of text, buttons, icons
/// from a fixed set of 116, and an image. No custom fonts, no drawing. The one
/// way out is that `Image` takes a `UIImage`, which the documentation does not
/// mention and the compiled interface does; so the big number is drawn here, in
/// the app's own serif and the cooldown's own colour, and everything that has
/// to be *pinched* stays a native button, because a button inside a bitmap
/// cannot be highlighted.
///
/// The price was measured before it was paid: a screen with a drawn numeral
/// takes about 155 ms to send against 47 ms for plain text, both well inside a
/// one-second tick. See docs/DECISIONS.md.
enum LensRenderer {

    typealias Pinch = @Sendable (LensAction) -> Void

    static func view(for screen: LensScreen, onPinch: @escaping Pinch) -> FlexBox {
        switch screen {
        case .set(let state): return view(for: state, onPinch: onPinch)
        case .list(let list): return view(for: list, onPinch: onPinch)
        case .card(let card): return view(for: card, onPinch: onPinch)
        }
    }

    /// Rows, built the way Meta's own sample builds its menu — a column of
    /// tappable cards — because that is the shape that was seen to scroll.
    static func view(for list: LensList, onPinch: @escaping Pinch) -> FlexBox {
        FlexBox(direction: .column, spacing: 10) {
            Text(list.eyebrow, style: .meta, color: .secondary)
            for row in list.rows {
                FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
                    Text(row.title, style: .body, color: row.done ? .secondary : .primary)
                    Text(row.trailing, style: .meta, color: .secondary)
                }
                .padding(20)
                .background(.card)
                .onTap { onPinch(row.action) }
            }
            if !list.footer.isEmpty { buttons(list.footer, onPinch: onPinch) }
        }
    }

    static func view(for card: LensCard, onPinch: @escaping Pinch) -> FlexBox {
        FlexBox(direction: .column, spacing: 12) {
            FlexBox(direction: .column, spacing: 6) {
                Text(card.eyebrow, style: .meta, color: .secondary)
                Text(card.title, style: .heading)
                for line in card.lines {
                    Text(line, style: .body, color: .secondary)
                }
            }
            .padding(24)
            .background(.card)
            if !card.actions.isEmpty { buttons(card.actions, onPinch: onPinch) }
        }
    }

    /// The first button is the one the glasses light on arrival, so it is the
    /// one drawn as the answer.
    private static func buttons(_ actions: [LensAction], onPinch: @escaping Pinch) -> ButtonGroup {
        ButtonGroup {
            for (index, action) in actions.enumerated() {
                Button(label: action.label,
                       style: index == 0 ? .primary : .secondary,
                       iconName: icon(for: action),
                       onClick: { onPinch(action) })
            }
        }
    }

    /// One whole screen. The SDK has no partial update, so this is called again
    /// for every second of a rest.
    static func view(for state: LensState, onPinch: @escaping Pinch) -> FlexBox {
        let hero = heroImage(state.hero, tone: state.tone)
        return FlexBox(direction: .column, spacing: 12) {
            FlexBox(direction: .column, spacing: 6) {
                Text(state.eyebrow, style: .meta, color: .secondary)
                Text(state.title, style: .body)
                if let hero {
                    Image(image: hero, sizePreset: .fill, cornerRadius: .none)
                } else {
                    Text(state.hero, style: .heading)
                }
                Text(state.detail, style: .body, color: .secondary)
            }
            .padding(24)
            // No card behind a drawn numeral. The bitmap is opaque black —
            // transparency is not safe to assume, since an SDK that re-encodes
            // to JPEG would turn clear pixels white — and black inside Meta's
            // grey panel is a visible hole, where black on nothing is nothing.
            .background(hero == nil ? .card : .none)
            if !state.actions.isEmpty { buttons(state.actions, onPinch: onPinch) }
        }
    }

    /// Meta's glyph for each action. A switch rather than a field on
    /// `LensAction` so that file stays free of Meta's types — and exhaustive, so
    /// a fourth action does not compile until it has an icon.
    static func icon(for action: LensAction) -> IconName? {
        switch action {
        case .logSet, .start: return .checkmark
        case .skipRest: return .triangleRightVerticalLine
        case .extendRest: return .plus
        case .back: return .arrowLeft
        case .close: return .x
        case .list: return .threeHorizontalLines
        case .taken: return .twoArrowsClockwise
        // A minus sign is not among Meta's 116 glyphs, and a wrong one is worse
        // than none: the label already says "−1 rep".
        case .fewerReps, .open: return nil
        }
    }

    // MARK: - The numeral

    /// 552 is the lens's 600 less the card's padding. One pixel per point: the
    /// glasses have no use for a 3× bitmap and the radio certainly doesn't.
    static let heroSize = CGSize(width: 552, height: 190)

    /// Nil when the serif is not in the bundle, so the caller falls back to
    /// Meta's heading text rather than sending a number in the wrong face.
    static func heroImage(_ text: String, tone: LensState.Tone) -> UIImage? {
        guard let serif = UIFont(name: RFDesign.Face.serifBold, size: 100) else { return nil }
        let color: UIColor
        switch tone {
        case .ready, .done: color = RFDesign.readyUIColor
        case .resting(let progress): color = RFDesign.coolUIColor(progress)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: heroSize, format: format).image { context in
            // Black is what an additive display cannot show, so it is "nothing".
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: heroSize))

            let drawn = fitted(text, in: serif, color: color)
            let bounds = drawn.size()
            // Never above the canvas: a serif's line box is taller than its
            // digits, and a negative origin would shave the tops off them.
            drawn.draw(at: CGPoint(x: 0, y: max(0, (heroSize.height - bounds.height) / 2)))
        }
    }

    static let largestNumeral: CGFloat = 170
    static let smallestNumeral: CGFloat = 28

    /// As large as fits, both ways. "1:12" and "182.5 × 12" are both heroes; a
    /// fixed size would crop the second or waste the first. Height is checked
    /// as well as width because the tallest size that fits across does not
    /// necessarily fit down.
    static func fitted(_ text: String, in face: UIFont, color: UIColor) -> NSAttributedString {
        var size = largestNumeral
        while true {
            let drawn = NSAttributedString(string: text, attributes: [
                .font: face.withSize(size), .foregroundColor: color, .kern: -size / 45,
            ])
            let bounds = drawn.size()
            let fits = bounds.width <= heroSize.width && bounds.height <= heroSize.height
            // At the floor it is drawn regardless. Cropped small beats absent,
            // and nothing a set screen can produce gets anywhere near here.
            if fits || size <= smallestNumeral { return drawn }
            size -= 4
        }
    }
}
