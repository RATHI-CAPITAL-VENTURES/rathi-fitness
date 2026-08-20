import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Renders a pass into the symbology its gym actually uses.
///
/// One entry per format rather than a branch per format, so supporting the next
/// one is a row here. All four are a CIFilter that already ships with the OS —
/// there is no cost to covering the set, and there is a real cost to discovering
/// at a turnstile that yours is the one that was left out.
enum CodeImage {

    private static let context = CIContext()

    static func generate(_ value: String, as symbology: GymPass.Symbology,
                         scale: CGFloat = 12) -> UIImage? {
        guard !value.isEmpty, let data = value.data(using: .ascii, allowLossyConversion: true)
        else { return nil }

        let output: CIImage?
        switch symbology {
        case .qr:
            let f = CIFilter.qrCodeGenerator()
            f.message = data
            // High correction: this gets scanned through a phone case, at an
            // angle, by a reader older than the phone.
            f.correctionLevel = "H"
            output = f.outputImage
        case .code128:
            let f = CIFilter.code128BarcodeGenerator()
            f.message = data
            f.quietSpace = 8
            output = f.outputImage
        case .pdf417:
            let f = CIFilter.pdf417BarcodeGenerator()
            f.message = data
            output = f.outputImage
        case .aztec:
            let f = CIFilter.aztecCodeGenerator()
            f.message = data
            output = f.outputImage
        }

        guard let output else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
