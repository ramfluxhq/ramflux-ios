// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

/// The account a lock page or a removal dialog refers to: an initial avatar, the display name and, when two accounts
/// can share a name, the short id line (`xxxx xxxx`, monospaced, secondary). The caller passes already resolved text;
/// the full account id never reaches this row.
public struct KitAccountRow: View {
    let name: String
    let initial: String
    let status: String?
    let shortID: String?
    var large: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(name: String, initial: String, status: String? = nil, shortID: String? = nil, large: Bool = false, tag: String? = nil) {
        self.name = name; self.initial = initial; self.status = status; self.shortID = shortID; self.large = large; self.tag = tag
    }

    public var body: some View {
        HStack(spacing: KitMetrics.rowGap) {
            KitAvatar(initial, size: large ? KitMetrics.avatar52 : KitMetrics.avatar44, kind: .person, tag: tag.map { $0 + "-avatar" })
            VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                Text(untrusted: name).rfFont(large ? .page : .body, weight: .semibold).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier((tag ?? "account-row") + "-name")
                if let status { Text(status).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary).accessibilityIdentifier((tag ?? "account-row") + "-status") }
                if let shortID { KitIdentifierText(shortID, color: theme.secondary, tag: (tag ?? "account-row") + "-short-id") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(tag ?? "account-row")
    }
}
