// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// What the chat timeline knows about one surface: the record, edited inputs, and the state of
/// the last action.
public struct SurfaceCardState: Equatable, Sendable {
    public let surface: SurfaceRecord
    public var drafts: [String: SurfaceInput]
    public var sending: Bool
    public var failure: AppFailure?
    public init(surface: SurfaceRecord, drafts: [String: SurfaceInput] = [:], sending: Bool = false, failure: AppFailure? = nil) {
        self.surface = surface; self.drafts = drafts; self.sending = sending; self.failure = failure
    }
}

/// An agent surface in the timeline (no mobile board yet; built from the Kit card surfaces).
/// Content renders only when the surface is renderable; otherwise the fallback text is shown.
/// Controls are enabled only while it is actionable and no action is in flight. Unsupported
/// components show a placeholder; agent text is untrusted and streaming text
/// is marked while the agent is still appending. A link button shows its destination host and
/// opens only after the user confirms that host.
public struct SurfaceCardView: View {
    let card: SurfaceCardState
    let onInput: (String, SurfaceInput) -> Void
    let onButton: (String) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var pendingLink: URL?
    public init(card: SurfaceCardState, onInput: @escaping (String, SurfaceInput) -> Void, onButton: @escaping (String) -> Void) { self.card = card; self.onInput = onInput; self.onButton = onButton }
    private var surface: SurfaceRecord { card.surface }
    private var enabled: Bool { surface.actionable && !card.sending }
    public var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            if surface.renderable, let root = surface.components["root"] {
                node(root, depth: 0)
            } else {
                Text(untrusted: surface.fallbackText.isEmpty ? FeatureCardsStrings.text("cards.contentUnavailable", locale: locale) : surface.fallbackText).rfFont(.body)
            }
            if surface.closed { note("cards.closed") } else if surface.outOfSync { note("cards.outOfSync") }
            if card.sending { ProgressView(FeatureCardsStrings.text("cards.sending", locale: locale)).rfFont(.caption) }
            if let failure = card.failure { Text(failure.message(locale: locale)).rfFont(.caption).foregroundStyle(theme.danger) }
        }
        .padding(theme.gap)
        .frame(maxWidth: 320, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_bubble))
        .accessibilityElement(children: .contain)
        .confirmationDialog(pendingLink.map { FeatureCardsStrings.sentence("cards.link.confirm.title", [.identifier(SurfaceLink.host($0))], locale: locale) } ?? "",
                            isPresented: Binding(get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } }), titleVisibility: .visible, presenting: pendingLink) { url in
            Button(FeatureCardsStrings.text("cards.link.open", locale: locale)) { pendingLink = nil; openURL(url) }
            Button(FeatureCardsStrings.text("cards.link.cancel", locale: locale), role: .cancel) { pendingLink = nil }
        } message: { _ in
            Text(FeatureCardsStrings.text("cards.link.confirm.message", locale: locale))
        }
    }
    private func note(_ key: String) -> some View { Text(FeatureCardsStrings.text(key, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary) }

    private func node(_ component: SurfaceComponent, depth: Int) -> AnyView {
        guard depth < 16 else { return AnyView(unsupported("depth")) }
        switch component.kind {
        case .text(let value, let caption):
            if let text = surface.text(value) {
                return AnyView(HStack(alignment: .firstTextBaseline, spacing: theme.gap / 2) {
                    Text(untrusted: text).rfFont(caption ? .caption : .body)
                    if surface.streaming(value) { ProgressView().controlSize(.mini).accessibilityLabel(Text(FeatureCardsStrings.text("cards.streaming", locale: locale))) }
                })
            }
            return AnyView(placeholder("cards.unsupportedValue"))
        case .stack(let children, let horizontal):
            let views = children.compactMap { surface.components[$0] }.map { node($0, depth: depth + 1) }
            return horizontal
                ? AnyView(HStack(spacing: theme.gap) { ForEach(views.indices, id: \.self) { views[$0] } })
                : AnyView(VStack(alignment: .leading, spacing: theme.gap) { ForEach(views.indices, id: \.self) { views[$0] } })
        case .card(let child):
            return surface.components[child].map { node($0, depth: depth + 1) } ?? AnyView(placeholder("cards.unsupportedValue"))
        case .divider: return AnyView(Divider())
        case .button(let child, let primary, let action):
            let label = surface.components[child].flatMap { if case .text(let value, _) = $0.kind { surface.text(value) } else { nil } } ?? ""
            switch action {
            case .event:
                return AnyView(KitButton(label, action: { onButton(component.id) }, kind: primary ? .primary : .secondary, size: .compact, enabled: enabled, loading: card.sending, tag: "surface-" + component.id))
            case .link(let target):
                // Opening a page changes nothing in the conversation, so a closed card may still link.
                guard let url = surface.linkURL(target) else { return AnyView(placeholder("cards.link")) }
                return AnyView(VStack(alignment: .leading, spacing: theme.gap / 2) {
                    KitButton(label, action: { pendingLink = url }, kind: primary ? .primary : .secondary, size: .compact, enabled: surface.renderable, tag: "surface-" + component.id)
                    HStack(spacing: theme.gap / 2) {
                        KitIcon(name: "link", size: KitMetrics.iconInfo, tint: theme.secondary)
                        KitIdentifierText(SurfaceLink.host(url), color: theme.secondary)
                    }
                })
            case .unsupported:
                return AnyView(placeholder("cards.unsupportedValue"))
            }
        case .textField(let label, let path, let placeholder, let multiline, let obscured):
            guard let path else { return AnyView(self.placeholder("cards.unsupportedValue")) }
            let binding = Binding<String>(get: { if case .text(let text)? = card.drafts[path] ?? surface.input(at: path) { text } else { "" } }, set: { onInput(path, .text(String($0.prefix(4_096)))) })
            return AnyView(VStack(alignment: .leading, spacing: theme.gap / 2) {
                if let label = surface.text(label) { Text(untrusted: label).rfFont(.caption) }
                Group {
                    if obscured { SecureField(surface.text(placeholder) ?? "", text: binding) } else { TextField(surface.text(placeholder) ?? "", text: binding, axis: multiline ? .vertical : .horizontal) }
                }
                .rfFont(.body).padding(theme.gap / 2).background(theme.bg, in: RoundedRectangle(cornerRadius: theme.radius_sm)).disabled(!enabled)
            })
        case .checkBox(let label, let path):
            guard let path else { return AnyView(placeholder("cards.unsupportedValue")) }
            let checked = if case .flag(let flag)? = card.drafts[path] ?? surface.input(at: path) { flag } else { false }
            return AnyView(HStack(spacing: theme.gap) {
                Text(untrusted: surface.text(label) ?? "").rfFont(.body).frame(maxWidth: .infinity, alignment: .leading)
                KitSwitch(checked: checked, onChecked: { onInput(path, .flag($0)) }, enabled: enabled, label: surface.text(label) ?? "", tag: "surface-" + component.id)
            })
        case .choice(let label, let options, let path, let multiple):
            guard let path else { return AnyView(placeholder("cards.unsupportedValue")) }
            let selected = if case .choices(let values)? = card.drafts[path] ?? surface.input(at: path) { values } else { [String]() }
            return AnyView(VStack(alignment: .leading, spacing: theme.gap / 2) {
                if let label = surface.text(label) { Text(untrusted: label).rfFont(.caption) }
                ForEach(options, id: \.value) { option in
                    let on = selected.contains(option.value)
                    Button {
                        let next = multiple ? (on ? selected.filter { $0 != option.value } : selected + [option.value]) : [option.value]
                        onInput(path, .choices(next))
                    } label: {
                        HStack(spacing: theme.gap) {
                            KitIcon(name: on ? "square-check" : "square", size: KitMetrics.iconInfo, tint: on ? theme.accent : theme.secondary)
                            Text(untrusted: surface.text(option.label) ?? option.value).rfFont(.body)
                        }
                    }
                    .buttonStyle(.plain).disabled(!enabled)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            })
        case .approval(let requestRef, let explanation):
            // The catalogue defines no decision event for Approval; decisions are made in the
            // task or approval flow, so the card is shown without actions.
            return AnyView(KitApprovalCard(requester: "", status: FeatureCardsStrings.text(surface.closed ? "cards.closed" : "cards.approval.pending", locale: locale),
                                           title: surface.text(explanation) ?? surface.fallbackText, scopeLabel: FeatureCardsStrings.text("cards.approval.request", locale: locale),
                                           scopeDetail: requestRef, decline: "", approve: "", actions: false, tag: "surface-approval-" + component.id))
        case .unsupported(let kind): return AnyView(unsupported(kind))
        }
    }
    private func placeholder(_ key: String) -> some View {
        Text(FeatureCardsStrings.text(key, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            .padding(theme.gap / 2).overlay(RoundedRectangle(cornerRadius: theme.radius_sm).stroke(theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }
    private func unsupported(_ kind: String) -> some View {
        VStack(alignment: .leading, spacing: theme.gap / 2) {
            placeholder("cards.unsupported")
            Text(untrusted: surface.fallbackText).rfFont(.caption)
        }
    }
}
