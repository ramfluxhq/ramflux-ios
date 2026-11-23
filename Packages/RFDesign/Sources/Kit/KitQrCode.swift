// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import CoreImage

/// A scannable QR code in the frame of `KitQrPlaceholder` (M/QR placeholder): always dark modules on a
/// white quiet zone, in both themes, so any camera can read it. The image is made once by `render`.
public struct KitQrCode: View {
    var image: CGImage
    var label: String
    var tag: String?
    public init(_ image: CGImage, label: String, tag: String? = nil) { self.image = image; self.label = label; self.tag = tag }
    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: RFDesign.light.radius_md)
        Image(decorative: image, scale: 1)
            .interpolation(.none).resizable().scaledToFit()
            .padding(KitMetrics.gutter / 2)
            .frame(width: KitMetrics.qr, height: KitMetrics.qr)
            .background(RFDesign.light.surface_white, in: shape)
            .overlay { shape.strokeBorder(RFDesign.light.line_strong, lineWidth: KitMetrics.stroke) }
            .accessibilityElement().accessibilityLabel(label).accessibilityAddTraits(.isImage)
            .kitTag(tag)
    }
    /// Encodes `bytes` as a QR code (error correction M, or L when M cannot hold them), one pixel per module.
    /// Returns nil when the bytes do not fit in a single code. The bytes are lent to Core Image without a
    /// copy made here; Core Image's own buffers and the returned image cannot be erased by the caller.
    nonisolated public static func render(_ bytes: UnsafeRawBufferPointer) -> CGImage? {
        guard let base = bytes.baseAddress, !bytes.isEmpty else { return nil }
        let message = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: bytes.count, deallocator: .none)
        let context = CIContext(options: [.cacheIntermediates: false])
        for level in ["M", "L"] {
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
            filter.setValue(message, forKey: "inputMessage")
            filter.setValue(level, forKey: "inputCorrectionLevel")
            if let output = filter.outputImage, let image = context.createCGImage(output, from: output.extent) { return image }
        }
        return nil
    }
}
