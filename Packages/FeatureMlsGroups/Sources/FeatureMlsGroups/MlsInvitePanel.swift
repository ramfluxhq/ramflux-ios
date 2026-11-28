// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import CoreGraphics
import AppData
import FeatureChat
import RFDesign
import RFLocalization
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

/// The invite panel: a secret note, the link (monospace, middle-truncated, left to right), Copy, Share, a QR code, the
/// duration and uses presets, "New link", and the list with badges. Revoke asks first and shows "Revoked" only after the reply.
/// Every member may create invites (r4 item 9). Copy and Share happen only on a tap.
public struct MlsInvitePanel: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: MlsGroupModel
    let onClose: () -> Void
    @State private var days = 7
    @State private var uses = 100
    @State private var copied: String?
    @State private var revokeTarget: String?
    @State private var qr: CGImage?
    public init(model: MlsGroupModel, onClose: @escaping () -> Void) { self.model = model; self.onClose = onClose }
    private var live: MlsInvite? { model.invites.invites.first { !$0.revoked && !$0.isExpired(now: nowMillis) } }
    private var nowMillis: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureMlsGroupsStrings.text("group.invite.title", locale: locale)).rfFont(.page)
            Text(FeatureMlsGroupsStrings.text("group.invite.secretNote", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            if let invite = live {
                linkBlock(invite)
                if let qr { KitQrCode(qr, label: FeatureMlsGroupsStrings.text("group.invite.qr", locale: locale), tag: "mls-invite-qr").frame(maxWidth: .infinity) }
            }
            presets
            if let error = model.invites.error { Text(MlsChatText.error(error, locale: locale)).rfFont(.caption).foregroundStyle(theme.danger).accessibilityIdentifier("mls-invite-error") }
            Text(FeatureMlsGroupsStrings.text("group.invite.list", locale: locale)).rfFont(.body, weight: .semibold)
            if model.invites.loading { ProgressView() }
            ForEach(model.invites.invites) { invite in row(invite) }
            KitButton(FeatureMlsGroupsStrings.text("group.common.close", locale: locale), action: onClose, kind: .text, tag: "mls-invite-close")
        }.padding(theme.gap) } }
        .task { model.loadInvites() }
        .task(id: live?.inviteID) { qr = live.flatMap(Self.qrImage) }
        .confirmationDialog(FeatureMlsGroupsStrings.text("group.invite.revokeConfirm.title", locale: locale), isPresented: Binding(get: { revokeTarget != nil }, set: { if !$0 { revokeTarget = nil } }), titleVisibility: .visible) {
            Button(FeatureMlsGroupsStrings.text("group.invite.revoke", locale: locale), role: .destructive) { if let id = revokeTarget { model.revoke(id) }; revokeTarget = nil }
            Button(FeatureMlsGroupsStrings.text("group.common.cancel", locale: locale), role: .cancel) { revokeTarget = nil }
        } message: { Text(FeatureMlsGroupsStrings.text("group.invite.revokeConfirm.body", locale: locale)) }
    }
    @ViewBuilder private func linkBlock(_ invite: MlsInvite) -> some View {
        Text(verbatim: RFBidi.isolateLeftToRight(invite.link)).font(.system(.footnote, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            .padding(theme.gap).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
            .accessibilityIdentifier("mls-invite-link")
        HStack(spacing: theme.gap) {
            KitButton(FeatureMlsGroupsStrings.text(copied == invite.inviteID ? "group.invite.copied" : "group.invite.copy", locale: locale), action: { copy(invite) }, kind: .secondary, size: .compact, tag: "mls-invite-copy")
            ShareLink(item: invite.link) { Text(FeatureMlsGroupsStrings.text("group.invite.share", locale: locale)).rfFont(.body) }.accessibilityIdentifier("mls-invite-share")
        }
    }
    private var presets: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureMlsGroupsStrings.text("group.invite.duration", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            Picker("", selection: $days) { ForEach([1, 7, 30], id: \.self) { Text(FeatureMlsGroupsStrings.format("group.invite.duration.day", $0, locale: locale)).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("mls-invite-days")
            Text(FeatureMlsGroupsStrings.text("group.invite.uses", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            Picker("", selection: $uses) { ForEach([1, 10, 100], id: \.self) { Text(FeatureMlsGroupsStrings.format("group.invite.maxUses", $0, locale: locale)).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("mls-invite-uses")
            KitButton(FeatureMlsGroupsStrings.text("group.invite.new", locale: locale), action: { model.createInvite(maxUses: uses, ttlSeconds: days * 86_400) }, kind: .secondary, enabled: !model.invites.creating, loading: model.invites.creating, tag: "mls-invite-new")
        }
    }
    @ViewBuilder private func row(_ invite: MlsInvite) -> some View {
        let expired = invite.isExpired(now: nowMillis)
        HStack(alignment: .center, spacing: theme.gap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FeatureMlsGroupsStrings.format("group.invite.maxUses", invite.maxUses, locale: locale)).rfFont(.caption)
                if let left = invite.usesLeft { Text(FeatureMlsGroupsStrings.format("group.invite.usesLeft", left, invite.maxUses, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary) }
                Text(FeatureMlsGroupsStrings.format("group.invite.expires", MlsGroupsText.dateTime(invite.expiresAt, locale: locale), locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            }
            Spacer(minLength: 0)
            if invite.revoked { badge("group.invite.revoked", "mls-invite-badge-revoked-" + invite.inviteID) }
            else if expired { badge("group.invite.expired", "mls-invite-badge-expired-" + invite.inviteID) }
            else if model.invites.revoking.contains(invite.inviteID) { ProgressView().controlSize(.small) }
            else { Button(FeatureMlsGroupsStrings.text("group.invite.revoke", locale: locale)) { revokeTarget = invite.inviteID }.rfFont(.caption).foregroundStyle(theme.danger).accessibilityIdentifier("mls-invite-revoke-" + invite.inviteID) }
        }
    }
    private func badge(_ key: String, _ id: String) -> some View {
        Text(FeatureMlsGroupsStrings.text(key, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).padding(.horizontal, 8).padding(.vertical, 2).background(theme.surface, in: Capsule()).accessibilityIdentifier(id)
    }
    /// Copies on the tap only: local to this device, and gone after 120 seconds (S1).
    private func copy(_ invite: MlsInvite) {
        #if canImport(UIKit)
        UIPasteboard.general.setItems([[UTType.plainText.identifier: invite.link]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
        #endif
        copied = invite.inviteID
    }
    private static func qrImage(_ invite: MlsInvite) -> CGImage? {
        Array(invite.link.utf8).withUnsafeBytes { KitQrCode.render($0) }
    }
}
