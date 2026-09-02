import XCTest
import UIKit
@testable import RathiFitness

/// The faces named in `RFDesign` are really in the bundle and really registered.
///
/// `Font.custom(_:size:)` does not fail when a face is missing — it falls back
/// to the system font, silently. So a renamed file, a face dropped from
/// `UIAppFonts`, or a licence swap that misses one weight all look like a
/// slightly-off screenshot rather than a bug, and only if someone happens to be
/// looking at that screen.
///
/// Written when the sans changed from General Sans to Inter (v0.4.5) and there
/// was nothing that would have noticed if one of the three weights had been
/// left behind.
final class TypographyTests: XCTestCase {

    private var faces: [(String, String)] {
        [("serif", RFDesign.Face.serif),
         ("serifBold", RFDesign.Face.serifBold),
         ("sans", RFDesign.Face.sans),
         ("sansMedium", RFDesign.Face.sansMedium),
         ("sansBold", RFDesign.Face.sansBold)]
    }

    func testEveryNamedFaceActuallyLoads() {
        for (role, name) in faces {
            XCTAssertNotNil(UIFont(name: name, size: 15),
                            "\(role) names \"\(name)\", which is not a registered font — "
                          + "SwiftUI would fall back to the system face without saying so")
        }
    }

    /// A face can load and still be the wrong one: ask for a name iOS does not
    /// have and UIKit hands back something, so the assertion above needs a
    /// second half that checks identity rather than existence.
    func testALoadedFaceIsTheFaceThatWasAsked() {
        for (role, name) in faces {
            let font = UIFont(name: name, size: 15)
            XCTAssertEqual(font?.fontName, name,
                           "\(role) resolved to \(font?.fontName ?? "nil"), not \(name)")
        }
    }

    /// Every file listed in `UIAppFonts` is in the bundle. The plist and the
    /// `Resources/Fonts` directory are two lists that have to agree, and nothing
    /// derives one from the other.
    func testEveryRegisteredFontFileIsPresent() throws {
        let listed = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String],
            "the app should register its fonts in UIAppFonts")
        XCTAssertFalse(listed.isEmpty)
        for file in listed {
            let name = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: ext),
                            "\(file) is registered in UIAppFonts but not in the bundle")
        }
    }

    /// The licences ship with the fonts.
    ///
    /// Both families are SIL OFL 1.1, which permits redistribution **provided
    /// the licence travels with the font** — and this repo is public, so that
    /// is a condition being relied on rather than a formality. The previous
    /// sans was under a EULA that forbade publishing it at all; this test is
    /// the cheap check that the replacement's terms are still being met.
    func testTheFontLicencesAreBundled() {
        for licence in ["Fraunces-LICENSE", "Inter-LICENSE"] {
            XCTAssertNotNil(Bundle.main.url(forResource: licence, withExtension: "txt"),
                            "\(licence).txt should ship beside the fonts it covers")
        }
    }
}
