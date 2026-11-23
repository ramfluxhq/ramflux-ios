// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppData
import RFDesign

/// This account's contact card: a QR code of the card link, the card text through the identifier
/// component, and the share sheet. A peer adds the card to reach this account through its home node.
struct MyContactCardView: View {
    let card: ContactCardExport
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureContactsStrings.text("contacts.myCard.explain", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            if let image = Self.qr(card.link) {
                Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                    .frame(maxWidth: 280).padding(theme.gap).background(Color.white, in: RoundedRectangle(cornerRadius: theme.radius_md))
                    .frame(maxWidth: .infinity)
                    .accessibilityElement().accessibilityLabel(Text(FeatureContactsStrings.text("contacts.myCard.qr", locale: locale)))
                    .accessibilityIdentifier("contacts-my-card-qr")
            }
            ShareLink(item: card.link) { Label(FeatureContactsStrings.text("contacts.myCard.share", locale: locale), systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("contacts-my-card-share")
            Text(FeatureContactsStrings.text("contacts.myCard.text", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            KitIdentifierText(card.card, tag: "contacts-my-card-text").textSelection(.enabled)
        }
    }
    /// A QR code of `text`, drawn at one pixel per module (scaled up without smoothing).
    static func qr(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }
}
