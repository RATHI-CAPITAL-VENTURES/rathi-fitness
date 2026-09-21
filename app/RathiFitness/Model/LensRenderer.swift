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
            if !state.actions.isEmpty {
                ButtonGroup {
                    for (index, action) in state.actions.enumerated() {
                        Button(
                            label: action.label,
                            // The first button is the one the glasses light on
                            // arrival, so it is the one drawn as the answer.
                            style: index == 0 ? .primary : .secondary,
                            iconName: icon(for: action),
                            onClick: { onPinch(action) })
                    }
                }
            }
        }
    }

    /// Meta's glyph for each action. A switch rather than a field on
    /// `LensAction` so that file stays free of Meta's types — and exhaustive, so
    /// a fourth action does not compile until it has an icon.
    static func icon(for action: LensAction) -> IconName {
        switch action {
        case .logSet: return .checkmark
        case .skipRest: return .triangleRightVerticalLine
        case .extendRest: return .plus
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

            // As large as fits. "1:12" and "182.5 × 12" are both heroes, and a
            // fixed size would either crop the second or waste the first.
            var size: CGFloat = 170
            var drawn = NSAttributedString()
            while size > 40 {
                drawn = NSAttributedString(string: text, attributes: [
                    .font: serif.withSize(size), .foregroundColor: color, .kern: -size / 45,
                ])
                if drawn.size().width <= heroSize.width { break }
                size -= 6
            }
            let bounds = drawn.size()
            drawn.draw(at: CGPoint(x: 0, y: (heroSize.height - bounds.height) / 2))
        }
    }
}
