import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Rathi Fitness's design system, in code.
///
/// **Dusk** since v0.19.2: a dusk-blue ground (#1B1E27) with soft coloured light
/// behind it, pastel teal for "ready", a warm peach for "recovering". The one
/// rule that outranks the mood: **a figure you must read fast, such as a
/// weight, a rep count or the rest clock, sits on a solid surface**
/// (`surface` and up, via `rfPanel`), never on the moving light. Glass and
/// bloom are the room; the numbers are not in it.
///
/// Dark only, on purpose (`preferredColorScheme(.dark)` and `UIUserInterfaceStyle`):
/// Dusk is a dark ground with light in it, a gym is not a place to be dazzled,
/// and the pass card is already the one light surface.
///
/// Ported from RIAKit's `RIADesign` (see `~/RIA/DESIGN.md`) and deliberately
/// NOT importing it: RIAKit is a package inside the RIA repo, and a separate
/// app reaching across repos for its colours is a build break waiting to
/// happen. The values below are copied on purpose; `design/ios-first-pass.html`
/// is the picture of them.
///
/// The one rule inherited wholesale: **state is the accent.** RIA is teal while
/// idle and blue-violet while thinking. Here you are the one with a state — the
/// app is teal when you are ready to lift and ember while you are recovering,
/// and `coolHue(_:)` is the whole of that idea.
public enum RFDesign {

    // MARK: - Colour

    /// The ground. Dusk's #1B1E27.
    public static let ground = Color(red: 0.106, green: 0.118, blue: 0.153)       // #1B1E27
    /// Raised solid surface: where readability must win.
    public static let surface = Color(red: 0.149, green: 0.165, blue: 0.208)      // #262A35
    /// Quieter rows.
    public static let surfaceQuiet = Color(red: 0.125, green: 0.141, blue: 0.180) // #20242E
    /// The current row, and anything one step above `surface`.
    public static let surfaceHigh = Color(red: 0.184, green: 0.204, blue: 0.259)  // #2F3442

    public static let speech = Color(red: 0.957, green: 0.961, blue: 0.969)       // #F4F5F7
    /// Soft: secondary text that still has to be read.
    public static let label = Color(red: 0.835, green: 0.847, blue: 0.875)        // #D5D8DF
    /// Faint: labels only. 4.5:1 or better on `ground` and on `surface`
    /// (DuskTests holds it there).
    public static let labelDim = Color(red: 0.682, green: 0.702, blue: 0.745)     // #AEB3BE
    /// Done, expired, past: faint, never fainter than the faint text.
    public static let said = labelDim
    public static let hairline = Color.white.opacity(0.10)
    /// An unfilled track: a pip, a rail, an empty week.
    public static let track = Color.white.opacity(0.14)

    /// Text on a primary action (#0B2A25).
    public static let onAction = Color(red: 0.043, green: 0.165, blue: 0.145)

    // The pass card is the one light surface in the app, and it has to be:
    // a turnstile scanner needs a bright ground behind the code, so that card
    // goes white at full brightness while everything around it stays dark.
    // Its text therefore cannot come from the palette above — white-on-white —
    // and these are the two values it needs. Named here rather than written
    // into the view, because a colour that lives in one screen is how a design
    // system stops being one.
    public static let lightGround = Color.white
    public static let onLight = Color(red: 0.043, green: 0.055, blue: 0.067)
    public static let onLightDim = Color(red: 0.42, green: 0.455, blue: 0.482)

    /// Ready. Her teal (#9EE0D1), where RIA sits at idle.
    public static let ready = Color(red: 0.62, green: 0.88, blue: 0.82)
    /// Just racked the bar. Dusk's warm peach, also the "something is off"
    /// colour: a problem must not read as a mood, so nothing else is this hue.
    public static let ember = Color(hue: emberHue / 360, saturation: 0.55, brightness: 0.97)

    // MARK: - Dusk's light

    public static let bloomViolet = Color(red: 0.36, green: 0.33, blue: 0.59)
    public static let bloomEmber = Color(red: 0.77, green: 0.44, blue: 0.33)
    /// The third pool is the mood: teal at idle, and it follows the cooldown.
    static let bloomMoodSaturation: Double = 0.59
    static let bloomMoodBrightness: Double = 0.67

    // MARK: - The cooldown ramp
    //
    // The one risky idea in the product, and it is eleven lines.
    //
    // Rest fraction in (0 = just racked the bar, 1 = recovered), hue out. It
    // holds ember for the first three quarters and hands over to teal in the
    // last, because a gradual mood ring tells you nothing while a colour that
    // changes decisively near the end is a signal you catch in your peripheral
    // vision — which is the whole point, since you are not looking at the phone.
    //
    // Rejecting the idea costs one line: return `readyHue` unconditionally.

    static let emberHue: Double = 18
    static let handoffHue: Double = 44
    static let readyHue: Double = 167
    /// Fraction of the rest spent in the warm band before the handover starts.
    static let warmHold: Double = 0.75

    public static func coolHue(_ progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        if p < warmHold { return emberHue + (handoffHue - emberHue) * (p / warmHold) }
        let t = (p - warmHold) / (1 - warmHold)
        return handoffHue + (readyHue - handoffHue) * (t * t * (3 - 2 * t))   // smoothstep
    }

    /// The LENS's saturation (the glasses' bitmap and the Web App lens page both
    /// read it, and the wire fixtures pin it): saturated, because an additive
    /// display turns a pastel into white. Unchanged by Dusk.
    public static func coolSaturation(_ progress: Double) -> Double {
        0.92 - 0.26 * min(max(progress, 0), 1)
    }

    /// The phone's: pastel at both ends, peach (.55) cooling to Dusk's teal (.30).
    public static func duskSaturation(_ progress: Double) -> Double {
        0.55 - 0.25 * min(max(progress, 0), 1)
    }

    /// The colour of a rest that is `progress` of the way done.
    public static func coolColor(_ progress: Double, brightness: Double = 0.88) -> Color {
        Color(hue: coolHue(progress) / 360,
              saturation: duskSaturation(progress),
              brightness: brightness)
    }

    // MARK: - For the lens
    //
    // The glasses face draws its big numeral into a bitmap, and the file that
    // does it cannot import SwiftUI — Meta's display module exports its own
    // `Text`, `Button` and `Image`. These hand it the same colours as UIKit
    // values, so the lens has no second definition of ember or teal to drift.

    #if canImport(UIKit)
    // NOT Dusk's pastels. The lens is additive: a pale colour on a display that
    // adds light reads as white, so it keeps the saturated ramp it shipped with.
    // The hues are shared (`coolHue`), the saturation is the lens's own.
    public static var readyUIColor: UIColor {
        UIColor(hue: readyHue / 360, saturation: 0.66, brightness: 0.86, alpha: 1)
    }
    public static var speechUIColor: UIColor { UIColor(white: 1, alpha: 0.95) }

    public static func coolUIColor(_ progress: Double) -> UIColor {
        // Full brightness, unlike the phone's: the lens is additive, so a
        // dimmer colour is not a moodier one, only a fainter one.
        let p = min(max(progress, 0), 1)
        return UIColor(hue: coolHue(p) / 360, saturation: coolSaturation(p),
                       brightness: 1, alpha: 1)
    }
    #endif

    // MARK: - The room
    //
    // Three soft pools behind everything (violet, ember, and the mood). The mood
    // takes the cooldown hue, so the room itself cools while you rest.

    /// Strength of the mood bloom: Dusk's .24 at rest, .42 while recovering.
    public static let roomGlow: Double = 0.24
    public static let roomGlowActive: Double = 0.42

    /// One soft pool. `size` is its diameter.
    static func bloom(_ color: Color, _ strength: Double, _ size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(strength), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }

    // MARK: - Plate colours
    //
    // Not a palette — a lookup table you already know by sight. These appear on
    // plate math and NOWHERE else in the app. Adding a sixth use of them is how
    // they stop meaning "this is what goes on the bar".

    public static func plateColor(_ pounds: Double) -> Color {
        switch pounds {
        case 45: return Color(red: 0.839, green: 0.271, blue: 0.271)
        case 35: return Color(red: 0.239, green: 0.482, blue: 0.839)
        case 25: return Color(red: 0.878, green: 0.698, blue: 0.235)
        case 10: return Color(red: 0.298, green: 0.663, blue: 0.420)
        default: return Color(red: 0.851, green: 0.867, blue: 0.878)
        }
    }

    // MARK: - Typography
    //
    // RIA's rule is that the serif is HER voice and the only thing allowed to be
    // large. Ported: the serif is YOUR NUMBERS. The weight on the bar, the
    // clock, the number on the scale. Everything that is not a number you came
    // here for is Inter, quiet on purpose.
    //
    // Inter and not General Sans since v0.4.5, for a licence rather than a
    // taste: General Sans ships under the Fontshare EULA, which forbids
    // "uploading them in a public server", and this repo is public. Inter is
    // SIL OFL 1.1 — redistributable with its licence file, which is beside it.
    // It is also the closer face for the job: drawn for user interfaces at
    // small sizes, which is the whole of what the sans does here (11-15pt
    // chrome that is meant to recede behind the numbers).

    //
    // Dusk: the system face for everything, figures in its bold with tabular
    // numerals so a weight does not shift as it changes. Fraunces is RIA's own
    // voice in Dusk and Rathi Fitness has none, so it is not set on the phone.
    // The faces below stay: the lens bitmap still draws with them
    // (`LensRenderer`), and `TypographyTests` still checks they are registered.

    public enum Face {
        public static let serif = "Fraunces-Regular"
        public static let serifBold = "Fraunces-SemiBold"
        public static let sans = "Inter-Regular"
        public static let sansMedium = "Inter-Medium"
        public static let sansBold = "Inter-SemiBold"
    }

    private static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }

    /// The system face at `size`, scaling with Dynamic Type like
    /// `Font.custom(_:size:relativeTo:)` did, optionally with tabular digits.
    private static func system(_ size: CGFloat, _ weight: UIFont.Weight,
                               relativeTo style: Font.TextStyle,
                               tabular: Bool = false) -> Font {
        var base = UIFont.systemFont(ofSize: size, weight: weight)
        if tabular {
            let tabularDigits: [UIFontDescriptor.FeatureKey: Int] = [
                .type: kNumberSpacingType,
                .selector: kMonospacedNumbersSelector,
            ]
            base = UIFont(descriptor: base.fontDescriptor.addingAttributes(
                [.featureSettings: [tabularDigits]]), size: size)
        }
        return Font(UIFontMetrics(forTextStyle: uiStyle(style)).scaledFont(for: base))
    }

    /// A number you lifted, weighed, or are waiting on.
    public static func figure(_ size: CGFloat, relativeTo: Font.TextStyle = .largeTitle) -> Font {
        system(size, .bold, relativeTo: relativeTo, tabular: true)
    }

    public static func title(_ size: CGFloat = 34) -> Font {
        system(size, .bold, relativeTo: .title)
    }

    public static func ui(_ size: CGFloat = 15, bold: Bool = false) -> Font {
        system(size, bold ? .semibold : .regular, relativeTo: .callout)
    }

    public static func uiMedium(_ size: CGFloat = 15) -> Font {
        system(size, .medium, relativeTo: .callout)
    }

    /// Small uppercase chrome. Tracked, because uppercase without tracking is
    /// a typo rather than a label.
    public static func eyebrow(_ size: CGFloat = 11) -> Font {
        system(size, .semibold, relativeTo: .caption2)
    }
    public static let eyebrowTracking: CGFloat = 1.5

    // MARK: - Spacing & motion (RIAKit's 4pt base)

    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let radius: CGFloat = 20
    public static let radiusSmall: CGFloat = 12

    public static let quick = Animation.easeOut(duration: 0.18)
    public static let settle = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

// MARK: - Small shared modifiers

extension View {
    /// An uppercase, tracked chrome label. One place, so they cannot drift.
    func rfEyebrow(_ color: Color = RFDesign.labelDim, size: CGFloat = 11) -> some View {
        self.font(RFDesign.eyebrow(size))
            .tracking(RFDesign.eyebrowTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// Dusk's room: the ground and three soft pools of light. Takes the mood hue so
/// the set screen can cool it. Nothing you read quickly is ever drawn on this.
struct RoomBackground: View {
    var hue: Double = RFDesign.readyHue
    var energy: Double = RFDesign.roomGlow

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let mood = Color(hue: hue / 360, saturation: RFDesign.bloomMoodSaturation,
                             brightness: RFDesign.bloomMoodBrightness)
            ZStack {
                RFDesign.ground
                RFDesign.bloom(RFDesign.bloomViolet, 0.6, 760).position(x: w * 0.2, y: h * 0.12)
                RFDesign.bloom(RFDesign.bloomEmber, 0.35, 760).position(x: w * 0.3, y: h + 60)
                RFDesign.bloom(mood, energy, 820).position(x: w - 160, y: h * 0.5)
            }
            .clipped()
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// A raised solid surface: lit along its top edge, with a soft shadow. For
    /// anything read fast (weights, reps, the rest clock), where the room's
    /// light must not reach.
    func rfPanel(_ radius: CGFloat = RFDesign.radius,
                 fill: Color = RFDesign.surface) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.03)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
    }

    /// A surface pressed into the ground, for places you type.
    func rfRecessed(_ radius: CGFloat = RFDesign.radiusSmall) -> some View {
        background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(LinearGradient(colors: [.black.opacity(0.3), .white.opacity(0.08)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
    }
}
