// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFDesign
/// Native B01 large-title projection of the reviewed mobile page header.
struct ConversationsHeader<Actions: View>: View {
    let title: String
    let account: String?
    let theme: RFTheme
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        HStack(spacing: theme.gap / 2) {
            VStack(alignment: .leading) {
                Text(title).font(.custom(theme.font, size: theme.size_mobile_large_title, relativeTo: .largeTitle).weight(.bold))
                if let account { Text(account).font(theme.captionFont).foregroundStyle(theme.secondary).lineLimit(1).truncationMode(.middle) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }.padding(.leading, theme.gap).padding(.trailing, theme.gap / 2).padding(.vertical, theme.gap / 2)
    }
}
