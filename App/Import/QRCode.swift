import CoreImage
import CoreImage.CIFilterBuiltins

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
