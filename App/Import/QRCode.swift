import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Makes the QR code the import screen shows, with CoreImage's built-in
/// generator (no third-party code).
enum QRCode {

    /// Black modules on white, each `scale` pixels square, with the
    /// generator's own quiet zone. Medium error correction (about 15%)
    /// copes with glare on a TV screen without making the code too dense.
    static func image(for text: String, scale: CGFloat = 12) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

/// A QR code drawn on its own white tile, for the import and export screens.
struct QRCodeTile: View {
    let text: String
    let size: CGFloat
    let failureText: String
    let accessibilityLabel: String

    var body: some View {
        Group {
            if let image = QRCode.image(for: text) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(failureText)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: size, height: size)
        .padding(32)
        // Scanners need dark modules on a light background, even in dark mode:
        // the light panel colour in both
        .background(Color(red: 0xF8 / 255, green: 0xFA / 255, blue: 0xF6 / 255),
                    in: .rect(cornerRadius: UTMetrics.cardRadius, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }
}
