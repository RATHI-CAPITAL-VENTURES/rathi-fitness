import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Find a scannable code in a picture you already have.
///
/// Most gym codes arrive as a screenshot or a photo of the back of a card, not
/// as something you hold the camera up to — the card is usually at home in a
/// drawer. Vision reads the same four symbologies the scanner and the renderer
/// handle, so a code that can be imported is always a code that can be shown.
enum CodeDetector {

    /// Vision's names for the formats we support, in one place beside the
    /// scanner's and renderer's tables.
    static let symbologies: [(VNBarcodeSymbology, GymPass.Symbology)] = [
        (.qr, .qr), (.code128, .code128), (.pdf417, .pdf417), (.aztec, .aztec),
    ]

    enum Failure: LocalizedError {
        case noImage
        case nothingFound
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .noImage:
                return "That picture couldn't be opened."
            case .nothingFound:
                return "No code in that picture. A screenshot of the pass in your gym's "
                     + "app works best — a photo of a card needs the code flat and in focus."
            case .unsupported(let name):
                return "That's a \(name) code, which this app can't display. "
                     + "QR, Code 128, PDF417 and Aztec all work."
            }
        }
    }

    struct Found {
        let value: String
        let symbology: GymPass.Symbology
    }

    #if canImport(UIKit)
    static func detect(in image: UIImage) async throws -> Found {
        guard let cgImage = image.cgImage else { throw Failure.noImage }
        return try await detect(in: cgImage, orientation: image.imageOrientation)
    }

    static func detect(in cgImage: CGImage,
                       orientation: UIImage.Orientation = .up) async throws -> Found {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error { return continuation.resume(throwing: error) }
                let results = (request.results as? [VNBarcodeObservation]) ?? []
                guard !results.isEmpty else {
                    return continuation.resume(throwing: Failure.nothingFound)
                }
                // Most confident first: a screenshot often catches a stray
                // barcode in an ad or a receipt in the same frame.
                let sorted = results.sorted { $0.confidence > $1.confidence }
                for observation in sorted {
                    guard let value = observation.payloadStringValue, !value.isEmpty
                    else { continue }
                    if let mapped = mapped(observation.symbology) {
                        return continuation.resume(
                            returning: Found(value: value, symbology: mapped))
                    }
                }
                // Something was there, we just cannot draw it back — say which,
                // rather than "no code found", which would send them hunting for
                // a better photo of a code we were never going to accept.
                let name = sorted.first?.symbology.rawValue ?? "unknown"
                continuation.resume(throwing: Failure.unsupported(name))
            }
            request.symbologies = VNDetectBarcodesRequest.supportedSymbologies
            let handler = VNImageRequestHandler(
                cgImage: cgImage, orientation: cgOrientation(orientation))
            do { try handler.perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
    #endif

    static func mapped(_ symbology: VNBarcodeSymbology) -> GymPass.Symbology? {
        symbologies.first { $0.0 == symbology }?.1
    }
}

extension VNDetectBarcodesRequest {
    /// Ask Vision for everything it can read, not only what we can draw.
    ///
    /// Narrowing the request to our four would make an unsupported code report
    /// as "nothing found", and the honest answer — "that's a Data Matrix, which
    /// this app can't show" — is far more use than sending someone to retake a
    /// photo that was fine.
    static var supportedSymbologies: [VNBarcodeSymbology] {
        VNDetectBarcodesRequest().symbologies
    }
}
