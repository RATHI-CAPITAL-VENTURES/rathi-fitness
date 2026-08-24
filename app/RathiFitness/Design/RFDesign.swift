import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Rathi Fitness's design system, in code.
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

    /// The ground. RIAKit's near-black with a cool cast, unchanged.
    public static let ground = Color(red: 0.027, green: 0.035, blue: 0.043)      // #07090B
    public static let surface = Color(red: 0.063, green: 0.075, blue: 0.086)     // #101316
    public static let surfaceHigh = Color(red: 0.094, green: 0.110, blue: 0.125) // #181C20

    public static let speech = Color.white.opacity(0.95)
    public static let said = Color.white.opacity(0.42)
    public static let label = Color.white.opacity(0.55)
    public static let labelDim = Color.white.opacity(0.34)
    public static let hairline = Color.white.opacity(0.08)

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

    /// Ready. Where RIA sits at idle.
    public static let ready = Color(hue: readyHue / 360, saturation: 0.66, brightness: 0.86)
    /// Just racked the bar.
    public static let ember = Color(hue: emberHue / 360, saturation: 0.92, brightness: 0.98)

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

    public static func coolSaturation(_ progress: Double) -> Double {
        0.92 - 0.26 * min(max(progress, 0), 1)
    }

    /// The colour of a rest that is `progress` of the way done.
    public static func coolColor(_ progress: Double, brightness: Double = 0.86) -> Color {
        Color(hue: coolHue(progress) / 360,
              saturation: coolSaturation(progress),
              brightness: brightness)
    }

    // MARK: - The room
    //
    // RIAKit's radial pool, same two stops and hard cutoff. Here it takes the
    // cooldown hue, so the room itself cools while you rest.

    public static let roomGlow: Double = 0.13
    public static let roomGlowActive: Double = 0.20
    public static let roomRadius: Double = 0.95

    public static func room(hue: Double, energy: Double, size: CGSize) -> RadialGradient {
        let tint = Color(hue: hue / 360, saturation: 0.75, brightness: 1.0)
        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: tint.opacity(energy), location: 0.0),
                .init(color: tint.opacity(energy * 0.28), location: 0.45),
                .init(color: .clear, location: 1.0),
            ]),
            center: .center, startRadius: 0,
            endRadius: min(size.width, size.height) * roomRadius)
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
    // here for is General Sans, quiet on purpose.

    public enum Face {
        public static let serif = "Fraunces-Regular"
        public static let serifBold = "Fraunces-SemiBold"
        public static let sans = "GeneralSans-Regular"
        public static let sansMedium = "GeneralSans-Medium"
        public static let sansBold = "GeneralSans-Semibold"
    }

    /// A number you lifted, weighed, or are waiting on.
    public static func figure(_ size: CGFloat, relativeTo: Font.TextStyle = .largeTitle) -> Font {
        .custom(Face.serifBold, size: size, relativeTo: relativeTo)
    }

    public static func title(_ size: CGFloat = 34) -> Font {
        .custom(Face.serifBold, size: size, relativeTo: .title)
    }

    public static func ui(_ size: CGFloat = 15, bold: Bool = false) -> Font {
        .custom(bold ? Face.sansBold : Face.sans, size: size, relativeTo: .callout)
    }

    public static func uiMedium(_ size: CGFloat = 15) -> Font {
        .custom(Face.sansMedium, size: size, relativeTo: .callout)
    }

    /// Small uppercase chrome. Tracked, because uppercase without tracking is
    /// a typo rather than a label.
    public static func eyebrow(_ size: CGFloat = 11) -> Font {
        .custom(Face.sansBold, size: size, relativeTo: .caption2)
    }
    public static let eyebrowTracking: CGFloat = 1.5

    // MARK: - Spacing & motion (RIAKit's 4pt base)

    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let radius: CGFloat = 18
    public static let radiusSmall: CGFloat = 10

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

/// The pool of light the app sits in. Takes a hue so the set screen can cool it.
struct RoomBackground: View {
    var hue: Double = RFDesign.readyHue
    var energy: Double = RFDesign.roomGlow

    var body: some View {
        GeometryReader { geo in
            RFDesign.ground
                .overlay(RFDesign.room(hue: hue, energy: energy, size: geo.size))
        }
        .ignoresSafeArea()
    }
}
