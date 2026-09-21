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
/// mention and the compiled interface does; so everything that is not a button
/// is drawn (`LensArt`, below), and everything that has to be *pinched* stays
/// Meta's, because a button inside a bitmap cannot be highlighted.
///
/// The price of the first drawing was measured before it was paid: a 552 × 220
/// numeral took about 155 ms to send against 47 ms for plain text. The ring is
/// about twice those pixels and has NOT been measured on the hardware — which
/// is why Settings → Glasses shows how long the last frame took.
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
                if let art = LensArt.row(row) {
                    // Drawn, but INSIDE Meta's card frame and not instead of it.
                    // Which row is lit is the glasses' business — the app is
                    // never told — so the highlight has to be theirs, and the
                    // frame is the part of a row they know how to light.
                    FlexBox(direction: .column) {
                        Image(image: art, sizePreset: .fill, cornerRadius: .medium)
                    }
                    .padding(4)
                    .background(.card)
                    .onTap { onPinch(row.action) }
                } else {
                    FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
                        Text(row.title, style: .body, color: row.done ? .secondary : .primary)
                        Text(row.trailing, style: .meta, color: .secondary)
                    }
                    .padding(20)
                    .background(.card)
                    .onTap { onPinch(row.action) }
                }
            }
            if !list.footer.isEmpty { buttons(list.footer, onPinch: onPinch) }
        }
    }

    static func view(for card: LensCard, onPinch: @escaping Pinch) -> FlexBox {
        let art = LensArt.card(card)
        return FlexBox(direction: .column, spacing: 12) {
            FlexBox(direction: .column, spacing: 6) {
                if let art {
                    Image(image: art, sizePreset: .fill, cornerRadius: .none)
                } else {
                    Text(card.eyebrow, style: .meta, color: .secondary)
                    Text(card.title, style: .heading)
                    for spec in card.specs {
                        Text("\(spec.label) · \(spec.value)", style: .body)
                    }
                    for line in card.lines {
                        Text(line, style: .body, color: .secondary)
                    }
                }
            }
            .padding(24)
            .background(art == nil ? .card : .none)
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
        // The whole block above the buttons is one drawing: where you are, the
        // ring, the number inside it. It is the phone's CooldownRing, which is
        // the most recognisable thing this app owns.
        let hero = LensArt.set(state)
        return FlexBox(direction: .column, spacing: 12) {
            FlexBox(direction: .column, spacing: 6) {
                if let hero {
                    Image(image: hero, sizePreset: .fill, cornerRadius: .none)
                } else {
                    Text(state.eyebrow, style: .meta, color: .secondary)
                    Text(state.title, style: .body)
                    Text(state.hero, style: .heading)
                    Text(state.detail, style: .body, color: .secondary)
                }
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
}

// MARK: - What is drawn

/// Everything on the lens that is not a button.
///
/// Meta's vocabulary has three sizes of its own typeface and a grey card. It
/// also has `Image(image:)`, which the documentation does not mention and the
/// compiled interface does — so the parts that carry the app's character are
/// drawn here, in Fraunces and Inter and the cooldown's own colour, and sent as
/// bitmaps. Buttons are NOT drawn: a button in a picture cannot be lit or
/// pinched, and which one is lit is the glasses' business, never told to the app.
///
/// Every bitmap is opaque black at one pixel per point. Black is what an
/// additive display cannot show, so it is "nothing"; transparency is not safe
/// to assume (an SDK that re-encodes to JPEG turns clear pixels white); and the
/// glasses have no use for a 3× image the radio has to carry.
///
/// Everything returns nil if the fonts are not in the bundle, and the renderer
/// falls back to Meta's own text rather than draw in the wrong face.
enum LensArt {

    /// The lens is 600 wide; the renderer pads 24 each side.
    static let width: CGFloat = 552
    static let setHeight: CGFloat = 420
    static let rowHeight: CGFloat = 64
    static let ringRadius: CGFloat = 140
    static let ringStroke: CGFloat = 10

    private static let speech = UIColor(white: 1, alpha: 0.95)
    private static let label = UIColor(white: 1, alpha: 0.60)
    private static let dim = UIColor(white: 1, alpha: 0.36)
    private static let track = UIColor(white: 1, alpha: 0.14)

    private struct Faces {
        let serif: UIFont, serifBold: UIFont, sansMedium: UIFont, sansBold: UIFont
        init?() {
            guard let serif = UIFont(name: RFDesign.Face.serif, size: 10),
                  let serifBold = UIFont(name: RFDesign.Face.serifBold, size: 10),
                  let sansMedium = UIFont(name: RFDesign.Face.sansMedium, size: 10),
                  let sansBold = UIFont(name: RFDesign.Face.sansBold, size: 10) else { return nil }
            (self.serif, self.serifBold, self.sansMedium, self.sansBold) = (serif, serifBold, sansMedium, sansBold)
        }
    }

    // MARK: a set — the ring

    static func set(_ state: LensState) -> UIImage? {
        guard let faces = Faces() else { return nil }
        let size = CGSize(width: width, height: setHeight)
        return render(size) { context in
            caps(state.eyebrow, faces.sansBold, 17, label).draw(at: .zero)
            line(state.title, faces.sansMedium, from: 27, downTo: 19, within: width, speech)
                .draw(at: CGPoint(x: 0, y: 26))

            let center = CGPoint(x: width / 2, y: 72 + ringRadius + ringStroke / 2)
            let accent: UIColor
            switch state.tone {
            case .ready, .done:
                accent = RFDesign.readyUIColor
                ring(context, center, from: 0, to: 1, accent)
            case .resting(let progress):
                // The ring FILLS as you recover, in the colour of how recovered
                // you are: ember for three quarters of the rest, then teal.
                accent = RFDesign.coolUIColor(progress)
                ring(context, center, from: 0, to: 1, track)
                if progress > 0 { ring(context, center, from: 0, to: progress, accent) }
            }
            inside(state, accent, faces, center)

            let detail = line(state.detail, faces.sansMedium, from: 22, downTo: 17, within: width, label)
            detail.draw(at: CGPoint(x: (width - detail.size().width) / 2, y: setHeight - 30))
        }
    }

    private static func ring(_ context: UIGraphicsImageRendererContext, _ center: CGPoint,
                             from start: Double, to end: Double, _ color: UIColor) {
        let path = UIBezierPath(arcCenter: center, radius: ringRadius,
                                startAngle: -.pi / 2 + 2 * .pi * start,
                                endAngle: -.pi / 2 + 2 * .pi * end, clockwise: true)
        path.lineWidth = ringStroke
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// What sits inside the ring: a small caption, then the number.
    private static func inside(_ state: LensState, _ accent: UIColor, _ faces: Faces, _ center: CGPoint) {
        let room = (ringRadius - ringStroke) * 2 - 36      // across, clear of the stroke
        var stack: [NSAttributedString] = []
        switch state.tone {
        case .ready:
            let (big, small) = split(state.hero)
            stack = [caps("Ready", faces.sansBold, 16, accent),
                     line(big, faces.serifBold, from: 124, downTo: 44, within: room, speech, kern: true)]
            if let small { stack.append(line(small, faces.serif, from: 46, downTo: 28, within: room, label)) }
        case .resting:
            stack = [caps("Cooldown", faces.sansBold, 16, label),
                     line(state.hero, faces.serifBold, from: 116, downTo: 44, within: room, accent, kern: true)]
        case .done:
            stack = [line(state.hero, faces.serifBold, from: 84, downTo: 40, within: room, accent)]
        }
        // Set solid, as a block, about the ring's centre. A serif's line box is
        // far taller than its digits, so lines are packed by a share of their
        // size rather than by what `size()` claims.
        let heights = stack.map { $0.size().height * 0.82 }
        var y = center.y - heights.reduce(0, +) / 2
        for (text, height) in zip(stack, heights) {
            let bounds = text.size()
            text.draw(at: CGPoint(x: center.x - bounds.width / 2, y: y - (bounds.height - height) / 2))
            y += height
        }
    }

    /// "185 × 8" is a number and what to do with it; "12 reps" likewise. The
    /// ring gives the first the room and sets the second beneath it.
    static func split(_ hero: String) -> (big: String, small: String?) {
        if let cross = hero.range(of: " × ") {
            return (String(hero[..<cross.lowerBound]), "× " + hero[cross.upperBound...])
        }
        let parts = hero.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : (hero, nil)
    }

    // MARK: a card — the ledger

    static func card(_ card: LensCard) -> UIImage? {
        guard let faces = Faces() else { return nil }
        let title = line(card.title, faces.serifBold, from: 48, downTo: 30, within: width, speech, kern: true)
        let sentences = card.lines.map { wrapped($0, faces.sansMedium, 22, label) }
        let sentenceHeights = sentences.map { ceil($0.boundingRect(
            with: CGSize(width: width, height: 200), options: [.usesLineFragmentOrigin], context: nil).height) }

        let titleHeight = ceil(title.size().height)
        var height: CGFloat = 30 + titleHeight + 12
        height += CGFloat(card.specs.count) * 48
        height += sentenceHeights.reduce(0) { $0 + $1 + 10 } + (sentences.isEmpty ? 0 : 6)

        return render(CGSize(width: width, height: max(height, 120))) { context in
            caps(card.eyebrow, faces.sansBold, 17, label).draw(at: .zero)
            title.draw(at: CGPoint(x: 0, y: 30))
            var y = 30 + titleHeight + 12
            for spec in card.specs {
                let name = caps(spec.label, faces.sansBold, 16, dim)
                let value = line(spec.value, faces.serif, from: 32, downTo: 22, within: width * 0.6, speech)
                let (nameSize, valueSize) = (name.size(), value.size())
                name.draw(at: CGPoint(x: 0, y: y + 34 - nameSize.height))
                value.draw(at: CGPoint(x: width - valueSize.width, y: y + 38 - valueSize.height))
                // A dotted leader: the eye finds the number by following it.
                let dots = UIBezierPath()
                dots.move(to: CGPoint(x: nameSize.width + 12, y: y + 30))
                dots.addLine(to: CGPoint(x: width - valueSize.width - 12, y: y + 30))
                dots.lineWidth = 2
                dots.lineCapStyle = .round
                dots.setLineDash([0, 7], count: 2, phase: 0)
                UIColor(white: 1, alpha: 0.26).setStroke()
                dots.stroke()
                _ = context
                y += 48
            }
            if !sentences.isEmpty { y += 6 }
            for (sentence, tall) in zip(sentences, sentenceHeights) {
                sentence.draw(with: CGRect(x: 0, y: y, width: width, height: tall),
                              options: [.usesLineFragmentOrigin], context: nil)
                y += tall + 10
            }
        }
    }

    // MARK: a row — name, how far, what

    static func row(_ row: LensList.Row) -> UIImage? {
        guard let faces = Faces() else { return nil }
        return render(CGSize(width: width, height: rowHeight)) { _ in
            var left: CGFloat = 16
            if let progress = row.progress {
                let center = CGPoint(x: left + 18, y: rowHeight / 2)
                small(center, from: 0, to: 1, UIColor(white: 1, alpha: 0.18))
                if progress > 0 { small(center, from: 0, to: min(1, progress), RFDesign.readyUIColor) }
                if row.done { check(center) }
                left += 36 + 16
            }
            let trailing = line(row.trailing, faces.serif, from: 24, downTo: 18, within: 190, label)
            let trailingSize = trailing.size()
            trailing.draw(at: CGPoint(x: width - 16 - trailingSize.width, y: (rowHeight - trailingSize.height) / 2))

            let room = width - 16 - trailingSize.width - 14 - left
            let name = line(row.title, faces.sansMedium, from: 26, downTo: 19, within: room, row.done ? dim : speech)
            let nameSize = name.size()
            // Clipped rather than spilling under the figure, for a name no size fits.
            name.draw(with: CGRect(x: left, y: (rowHeight - nameSize.height) / 2, width: room, height: nameSize.height),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
    }

    private static func small(_ center: CGPoint, from start: Double, to end: Double, _ color: UIColor) {
        let path = UIBezierPath(arcCenter: center, radius: 14, startAngle: -.pi / 2 + 2 * .pi * start,
                                endAngle: -.pi / 2 + 2 * .pi * end, clockwise: true)
        path.lineWidth = 4
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func check(_ center: CGPoint) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x - 6, y: center.y + 0.5))
        path.addLine(to: CGPoint(x: center.x - 2, y: center.y + 4.5))
        path.addLine(to: CGPoint(x: center.x + 6, y: center.y - 4.5))
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        RFDesign.readyUIColor.setStroke()
        path.stroke()
    }

    // MARK: type

    /// Small capitals, tracked: where you are.
    private static func caps(_ text: String, _ face: UIFont, _ size: CGFloat, _ color: UIColor) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: face.withSize(size), .foregroundColor: color, .kern: size * 0.14,
        ])
    }

    /// One line, as large as fits. "1:12" and "182.5" are both heroes; a fixed
    /// size would crop the second or waste the first. At the floor it is drawn
    /// regardless — cropped small beats absent.
    static func line(_ text: String, _ face: UIFont, from largest: CGFloat, downTo smallest: CGFloat,
                     within room: CGFloat, _ color: UIColor, kern: Bool = false) -> NSAttributedString {
        var size = largest
        while true {
            let drawn = NSAttributedString(string: text, attributes: [
                .font: face.withSize(size), .foregroundColor: color, .kern: kern ? -size / 45 : 0,
            ])
            if drawn.size().width <= room || size <= smallest { return drawn }
            size -= 2
        }
    }

    private static func wrapped(_ text: String, _ face: UIFont, _ size: CGFloat, _ color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        return NSAttributedString(string: text, attributes: [
            .font: face.withSize(size), .foregroundColor: color, .paragraphStyle: paragraph,
        ])
    }

    private static func render(_ size: CGSize, _ draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(context)
        }
    }
}
