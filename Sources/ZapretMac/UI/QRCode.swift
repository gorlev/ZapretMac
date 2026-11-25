import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code for `text`, drawn pixel for pixel so it stays crisp at any size.
/// Scanners need dark modules on a light ground, so it keeps CoreImage's own
/// black on white in dark mode too.
struct QRCode: View {
    let text: String
    var size: CGFloat = 128

    var body: some View {
        if let image = Self.image(for: text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .accessibilityLabel(Text("QR code for \(text)"))
        }
    }

    /// One pixel per module, with CoreImage's quiet zone around it.
    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
