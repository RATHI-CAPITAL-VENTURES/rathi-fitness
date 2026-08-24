import XCTest
import UIKit
@testable import RathiFitness

/// Render a code, then read it back. This is the property that actually matters
/// for a pass: whatever we can import, we must be able to display, and whatever
/// we display must be readable by something that isn't us.
final class CodeRoundTripTests: XCTestCase {

    /// Vision's barcode detection is not dependable in a simulator, and it fails
    /// two different ways depending on the runtime.
    ///
    /// Locally it refuses outright — "could not create inference context". On
    /// the CI image it runs and finds nothing, which surfaces as
    /// `Failure.nothingFound`. Same environmental problem, different symptom,
    /// and the second one only appeared once this ran on a machine that was not
    /// this one.
    ///
    /// **`nothingFound` is only forgiven on a simulator.** On a device it is a
    /// real failure and stays one — a pass that renders but cannot be read back
    /// is the exact bug this test exists to catch.
    ///
    /// The honest cost: in CI this test verifies nothing. The round-trip is a
    /// device property. What CI still covers is
    /// `testTheScannerAndTheRendererAgreeOnWhatIsSupported`, which is pure
    /// logic — and a format going missing from one of those three lists is the
    /// likelier regression anyway.
    private func skipIfVisionUnavailable(_ error: Error) throws -> Never {
        let text = (error as NSError).localizedDescription
        if text.contains("inference context") {
            throw XCTSkip("Vision has no inference context on this runtime")
        }
        #if targetEnvironment(simulator)
        if case CodeDetector.Failure.nothingFound = error {
            throw XCTSkip("Vision found nothing in a simulator — device-only property")
        }
        #endif
        throw error
    }

    func testEveryFormatWeOfferSurvivesRenderAndDetect() async throws {
        // Aztec and PDF417 payloads are checked with realistic content: a
        // membership number, not "hello".
        let payload = "9911223344917"
        for symbology in GymPass.Symbology.allCases {
            let image = try XCTUnwrap(CodeImage.generate(payload, as: symbology),
                                      "\(symbology.label) did not render")
            let found: CodeDetector.Found
            do { found = try await CodeDetector.detect(in: image) }
            catch { try skipIfVisionUnavailable(error) }
            XCTAssertEqual(found.value, payload, "\(symbology.label) round-tripped wrong")
            XCTAssertEqual(found.symbology, symbology,
                           "\(symbology.label) was detected as \(found.symbology.label)")
        }
    }

    func testTheScannerAndTheRendererAgreeOnWhatIsSupported() {
        // A scanner that reads formats the renderer cannot draw would store a
        // code you can never show at the door.
        let scannable = Set(CodeScanner.ScannerController.supported.map { $0.1 })
        let importable = Set(CodeDetector.symbologies.map { $0.1 })
        let renderable = Set(GymPass.Symbology.allCases)
        XCTAssertEqual(scannable, renderable)
        XCTAssertEqual(importable, renderable)
    }

    func testAPictureWithNoCodeSaysWhatToDoAboutIt() async throws {
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }
        do {
            _ = try await CodeDetector.detect(in: blank)
            XCTFail("a blank image reported a code")
        } catch let error as NSError
                    where error.localizedDescription.contains("inference context") {
            throw XCTSkip("Vision has no inference context on this runtime")
        } catch let failure as CodeDetector.Failure {
            let message = failure.errorDescription ?? ""
            XCTAssertTrue(message.contains("screenshot"),
                          "the error should say what kind of picture works, got: \(message)")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAnEmptyPayloadDoesNotRender() {
        XCTAssertNil(CodeImage.generate("", as: .qr))
    }

    func testLinearCodesAreFlaggedForLayout() {
        // The card lays a barcode out wide and short and a square code square.
        XCTAssertTrue(GymPass.Symbology.code128.isLinear)
        XCTAssertFalse(GymPass.Symbology.qr.isLinear)
        XCTAssertFalse(GymPass.Symbology.aztec.isLinear)
    }
}
