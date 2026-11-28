// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// The banners above a group timeline (D-M3-2, D-M3-3): the catch-up banner and the warnings, critical first, at most two at
/// once and a "+N" control that opens the rest in group info. The critical ones (fork alarm, rejoining, rejected head
/// commit) cannot be hidden; the others can, for the session. Nothing here calls the SDK: the actions send intents that the
/// session turns into one explicit call (Skip opens its dialog first, Undo opens its confirmation first).
struct MlsBannersView: View {
    let mls: MlsChatState
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        let shown = Array(mls.banners.prefix(MlsBannerPlan.visibleLimit))
        let more = mls.banners.count - shown.count
        VStack(spacing: theme.gap / 2) {
            ForEach(shown) { banner in bannerView(banner) }
            if more > 0 {
                Button { onAction(.detailsRequested) } label: { Text(FeatureChatStrings.format("group.warning.more", more, locale: locale)).rfFont(.caption) }
                    .accessibilityIdentifier("mls-warning-more")
            }
        }.padding(.horizontal, KitMetrics.gutter).padding(.top, theme.gap / 2)
    }
    @ViewBuilder private func bannerView(_ banner: MlsBanner) -> some View {
        switch banner.kind {
        case .catchUp(let view): catchUpBanner(view)
        case .warning(let code): warningBanner(banner, code)
        }
    }
    private func catchUpBanner(_ view: MlsCatchUpView) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KitTipBar(MlsChatText.catchUp(view, locale: locale), icon: "refresh-cw", tag: "mls-catchup-banner")
            if case .running(_, _, let skipping, let error) = view {
                if let error { Text(MlsChatText.error(error, locale: locale)).rfFont(.caption).foregroundStyle(theme.danger).accessibilityIdentifier("mls-catchup-error") }
                if skipping { Text(FeatureChatStrings.text("group.skip.skipping", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-catchup-skipping") }
                else { Button(FeatureChatStrings.text("group.catchup.skip", locale: locale)) { onAction(.mlsSkipCatchUp) }.rfFont(.caption).accessibilityIdentifier("mls-catchup-skip") }
            }
        }
    }
    private func warningBanner(_ banner: MlsBanner, _ code: MlsWarningCode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KitTipBar(MlsChatText.warning(code, locale: locale), icon: banner.severity == .critical ? "triangle-alert" : "info", tag: "mls-warning-" + code.name)
            HStack(spacing: theme.gap) {
                switch code {
                case .undecryptable:
                    Button(FeatureChatStrings.text("group.warning.undecryptable.show", locale: locale)) { onAction(.mlsShowUndecryptable) }.accessibilityIdentifier("mls-warning-action-" + code.name)
                case .admissionNeedsOnline:
                    Button(MlsChatText.hintInvite(locale: locale)) { onAction(.mlsOpenInvite) }.accessibilityIdentifier("mls-warning-action-" + code.name)
                case .headCommitRejected(let seq?):
                    Button(FeatureChatStrings.text("group.warning.headCommitRejected.action", locale: locale)) { onAction(.mlsVoid(seq)) }.accessibilityIdentifier("mls-warning-action-" + code.name)
                default: EmptyView()
                }
                if banner.canHide { Button(FeatureChatStrings.text("group.warning.hide", locale: locale)) { onAction(.mlsHideBanner(code.key)) }.accessibilityIdentifier("mls-warning-hide-" + code.name) }
            }.rfFont(.caption)
            if case .admissionNeedsOnline = code { Text(MlsChatText.hintMobile(locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-warning-hint-" + code.name) }
        }
    }
}
