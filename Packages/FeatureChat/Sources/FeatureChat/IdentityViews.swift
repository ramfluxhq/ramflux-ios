// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// The sheet in which a changed identity is accepted. This is the only accept control of the app; there is no
/// safety number, code or comparison to show.
public struct IdentityChangeSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let panel: IdentityPanel
    public let onAccept: () -> Void
    public let onLater: () -> Void
    public init(panel: IdentityPanel, onAccept: @escaping () -> Void, onLater: @escaping () -> Void) { self.panel = panel; self.onAccept = onAccept; self.onLater = onLater }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            HStack(spacing: theme.gap) {
                Text(FeatureChatStrings.sentence("identity.sheet.title", [.untrusted(panel.presentedName)], locale: locale)).rfFont(.page)
                if panel.change?.aiFlag == true { KitAIMarker(tag: "identity-ai") }
            }
            if let username = panel.change?.username, !username.isEmpty { Text(untrusted: "@" + username).rfFont(.caption).foregroundStyle(theme.secondary) }
            Text(FeatureChatStrings.sentence("identity.sheet.body", [.untrusted(panel.presentedName)], locale: locale)).rfFont(.body)
            if panel.isWaiting { KitTipBar(FeatureChatStrings.text("identity.sheet.waiting", locale: locale), icon: "loader", loading: true, tag: "identity-waiting") }
            if let message = message { Text(message).rfFont(.caption).foregroundStyle(theme.danger).accessibilityIdentifier("identity-accept-error") }
            KitButton(FeatureChatStrings.text("identity.sheet.accept", locale: locale), action: onAccept, kind: .primary, enabled: acceptEnabled, loading: panel.phase == .accepting, tag: "identity-accept")
            KitButton(FeatureChatStrings.text("identity.sheet.later", locale: locale), action: onLater, kind: .secondary, enabled: panel.phase != .accepting, tag: "identity-later")
        }.padding(theme.gap) } }
    }
    private var acceptEnabled: Bool { panel.change != nil && panel.phase != .accepting && panel.phase != .alreadyHandled }
    private var message: String? {
        switch panel.phase {
        case .alreadyHandled: FeatureChatStrings.text("identity.accept.already", locale: locale)
        case .changedAgain: FeatureChatStrings.text("identity.accept.again", locale: locale)
        case .failed: FeatureChatStrings.text("identity.accept.failed", locale: locale)
        case .idle, .accepting: nil
        }
    }
}

/// The banner above a direct chat while the peer's identity is changed. It has no dismiss control.
struct IdentityBanner: View {
    let panel: IdentityPanel
    let text: String
    let tag: String
    let onReview: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        HStack(alignment: .center, spacing: theme.gap) {
            KitIcon(name: "triangle-alert", size: KitMetrics.tipIcon, tint: theme.warning)
            Text(text).rfFont(.caption).frame(maxWidth: .infinity, alignment: .leading)
            KitButton(FeatureChatStrings.text("identity.changed.review", locale: locale), action: onReview, kind: .primary, size: .compact, enabled: !panel.isWaiting, tag: "identity-review")
        }
        .padding(theme.gap)
        .background(theme.warning_bg, in: RoundedRectangle(cornerRadius: theme.radius_card))
        .padding(.horizontal, KitMetrics.gutter).padding(.top, theme.gap)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(tag)
    }
}

/// The "Encryption" section of a conversation's details and of a contact's profile: the state of the encryption (when
/// the conversation is known), the devices, and the identity row. Review is offered only for a changed identity.
public struct IdentityEncryptionSection: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let panel: IdentityPanel
    public let showsSecurity: Bool
    public let onReview: () -> Void
    public init(panel: IdentityPanel, showsSecurity: Bool, onReview: @escaping () -> Void) { self.panel = panel; self.showsSecurity = showsSecurity; self.onReview = onReview }
    public var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureChatStrings.text("security.section.title", locale: locale)).rfFont(.caption)
            if showsSecurity, let security = panel.security {
                if let line = stateLine(security.state) { Label(line, systemImage: "lock.shield").rfFont(.body) }
                HStack(spacing: theme.gap) {
                    Text(FeatureChatStrings.format("security.devices", security.peerDevices, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                    if security.anyAI { KitAIMarker(tag: "security-ai") }
                }
            }
            switch panel.state {
            case .verified?:
                Label(FeatureChatStrings.text("identity.state.verified", locale: locale), systemImage: "checkmark.shield").rfFont(.body)
            case .changed?:
                Label(FeatureChatStrings.text("identity.state.changed", locale: locale), systemImage: "exclamationmark.triangle").rfFont(.body).foregroundStyle(theme.danger)
                if panel.isWaiting { Text(FeatureChatStrings.text("identity.sheet.waiting", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary) }
                KitButton(FeatureChatStrings.text("identity.changed.review", locale: locale), action: onReview, kind: .secondary, size: .compact, enabled: !panel.isWaiting, tag: "identity-review")
            case .tofu?, .unknown?:
                Text(FeatureChatStrings.text("identity.state.tofu", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            case nil:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("security-section")
    }
    private func stateLine(_ state: ConversationSecurity.State) -> String? {
        switch state {
        case .ok: FeatureChatStrings.text("security.state.ok", locale: locale)
        case .pending: FeatureChatStrings.text("security.state.pending", locale: locale)
        case .reEstablished: FeatureChatStrings.text("security.state.re_established", locale: locale)
        case .unknown: nil
        }
    }
}

/// The centred identity and encryption lines of the timeline.
struct ServiceLineView: View {
    let line: ServiceLine
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        Text(text).rfFont(.caption).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.horizontal, KitMetrics.gutter).padding(.vertical, theme.gap)
            .accessibilityIdentifier("service-" + line.id)
    }
    private var text: String {
        switch line.kind {
        case .identityChanged: FeatureChatStrings.sentence("identity.timeline.changed", [.untrusted(line.name)], locale: locale)
        case .identityAccepted: FeatureChatStrings.sentence("identity.timeline.accepted", [.untrusted(line.name)], locale: locale)
        case .forkRecovered: FeatureChatStrings.text("security.warning.fork_recovered", locale: locale)
        }
    }
}
