import XCTest
import UIKit
@testable import RathiFitness

/// Render a code, then read it back. This is the property that actually matters
/// for a pass: whatever we can import, we must be able to display, and whatever
/// we display must be readable by something that isn't us.
final class CodeRoundTripTests: XCTestCase {

    /// Vision needs an inference context, and some simulator runtimes cannot
    /// make one. That is the host's problem, not the code's — skip rather than
    /// report a red suite for it.
    private func skipIfVisionUnavailable(_ error: Error) throws -> Never {
        let text = (error as NSError).localizedDescription
        if text.contains("inference context") {
            throw XCTSkip("Vision has no inference context on this runtime")
        }
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
