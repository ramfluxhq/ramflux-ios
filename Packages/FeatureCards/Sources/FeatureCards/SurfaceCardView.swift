// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Observation
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// What the chat timeline knows about one card: the listed surface, its session display, the state of the last action,
/// the host request the user has to answer (a link to confirm), and the approval requests the runtime accepted a decision
/// for (by request id; they show "Waiting for confirmation" until the signed update replaces them).
public struct CardMessageState: Equatable, Sendable {
    public let surface: CardSurface
    public var display: CardDisplay?
    public var sending: Bool
    public var failure: AppFailure?
    public var pending: CardHostRequest?
    public var decided: Set<String>
    public init(surface: CardSurface, display: CardDisplay? = nil, sending: Bool = false, failure: AppFailure? = nil, pending: CardHostRequest? = nil, decided: Set<String> = []) {
        self.surface = surface; self.display = display; self.sending = sending; self.failure = failure; self.pending = pending; self.decided = decided
    }
}

/// A host slot answer the chat sends through the card session. `link` is the validated https URL a confirmed link opens
/// once the runtime answers `opened`; nothing else is opened by the client.
public struct CardAnswer: Equatable, Sendable {
    public let token: CardEventToken
    public let slotID: String
    public let requestID: String
    public let outcome: CardSlotOutcome
    public let link: URL?
    public init(token: CardEventToken, slotID: String, requestID: String, outcome: CardSlotOutcome, link: URL? = nil) {
        self.token = token; self.slotID = slotID; self.requestID = requestID; self.outcome = outcome; self.link = link
    }
}

/// Host-owned presentation state of one card: selected tabs, open modals and sheets. It survives signed updates by key.
@MainActor @Observable final class CardLocalState {
    var selectedTabs: [String: Int] = [:]
    var openModals: Set<String> = []
    var approvalKey: String?
    var pressedKey: String?
    var expanded: Set<String> = []
    var touched: Set<String> = []
    var tableMode: Set<String> = []
    var linkAnswering = false
}

/// Everything a node needs from its card: the held tree, the phase and the send functions.
struct CardContext {
    let surfaceRef: String
    let tree: CardTree
    let phase: CardPhase
    let closed: Bool
    let outOfSync: Bool
    let sending: Bool
    let local: CardLocalState
    /// True while an approval or link sheet is presented: a Modal may not open and an open one is deferred.
    let securitySheetOpen: Bool
    let onEvent: (String, CardHostEvent) -> Void
    let onAnswer: (CardAnswer) -> Void
    /// Request ids of approvals the runtime accepted a decision for (see `CardMessageState.decided`).
    var decided: Set<String> = []
    /// The runtime lifecycle of the tree (spec 3.4). Closed, retired and superseded cards take no events.
    var lifecycle: CardLifecycle = .open
    /// The author is still writing the card: its controls stay disabled until the final snapshot.
    var generating = false

    var formatLocale: Locale { Locale(identifier: tree.formatLocale) }

    /// Inputs take events while the card is live, refused (a refusal keeps the card usable) or suspended (the first
    /// event resumes it). Consumed, submitting, superseded, closed, retired, generating and unavailable cards are read-only.
    var editable: Bool {
        guard !closed, !outOfSync, !generating, lifecycle == .open else { return false }
        switch phase {
        case .live, .suspended, .refused: return true
        case .submitting, .consumed, .superseded, .unavailable: return false
        }
    }

    /// Buttons send only when the card is editable and no event is in flight.
    var actionable: Bool { editable && !sending }

    func slot(for key: String) -> CardHostSlot? { tree.hostSlots.first { $0.key == key } }
}

/// An agent card in the timeline. The card is drawn from the runtime's native tree; the host owns the header, the lifecycle
/// chrome and the link and approval sheets.
public struct SurfaceCardView: View {
    let card: CardMessageState
    let author: String?
    let isAgent: Bool
    let onEvent: (String, CardHostEvent) -> Void
    let onAnswer: (CardAnswer) -> Void
    let onResync: () -> Void

    @State private var local = CardLocalState()
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme

    public init(card: CardMessageState, author: String? = nil, isAgent: Bool = false, onEvent: @escaping (String, CardHostEvent) -> Void = { _, _ in },
                onAnswer: @escaping (CardAnswer) -> Void = { _ in }, onResync: @escaping () -> Void = {}) {
        self.card = card; self.author = author; self.isAgent = isAgent; self.onEvent = onEvent; self.onAnswer = onAnswer; self.onResync = onResync
    }

    public var body: some View {
        let tree = card.display?.renderAllowed == true ? card.display?.tree : nil
        VStack(alignment: .leading, spacing: theme.gap) {
            if isAgent || !(author ?? "").isEmpty { header }
            if let display = card.display, let tree, display.renderAllowed {
                CardLifecycleChrome(phase: display.phase, closed: card.surface.closed, lifecycle: display.lifecycle,
                                    generating: display.generating, outOfSync: card.surface.outOfSync, onResync: onResync)
                if let root = tree.root {
                    let context = CardContext(surfaceRef: card.surface.surfaceRef, tree: tree, phase: display.phase, closed: card.surface.closed,
                                              outOfSync: card.surface.outOfSync, sending: card.sending, local: local,
                                              securitySheetOpen: local.approvalKey != nil || isLinkPending,
                                              onEvent: onEvent, onAnswer: onAnswer, decided: card.decided,
                                              lifecycle: display.lifecycle, generating: display.generating)
                    CardRootView(node: root, context: context)
                        .environment(\.layoutDirection, tree.direction == "rtl" ? .rightToLeft : .leftToRight)
                        .modifier(CardApprovalSheetModifier(context: context))
                        .onChange(of: tree.signedVersion) { _, _ in local.openModals = []; local.approvalKey = nil }
                }
            } else {
                Text(fallback).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
            }
            if let failure = card.failure { Text(failure.message(locale: locale)).rfFont(.caption).foregroundStyle(theme.danger) }
        }
        .padding(theme.gap)
        .frame(maxWidth: 640, alignment: .leading)
        .opacity(card.display?.phase == .submitting ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.12), value: card.display?.phase == .submitting)
        .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
        .overlay { RoundedRectangle(cornerRadius: theme.radius_card).strokeBorder(theme.line, lineWidth: KitMetrics.stroke) }
        .accessibilityElement(children: .contain)
        .onChange(of: card.pending) { _, _ in local.linkAnswering = false }
        .sheet(item: linkBinding) { item in
            CardLinkSheet(item: item, author: author, onOpen: { answerLink(item, .confirm) }, onCancel: { answerLink(item, .cancel) })
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let author, !author.isEmpty { Text(untrusted: author).rfFont(.size(theme.size_secondary), weight: .semibold).foregroundStyle(theme.text) }
            if isAgent { KitAIMarker() }
            Spacer(minLength: 0)
        }
    }

    private var fallback: String {
        let text = card.display?.fallbackText ?? ""
        return text.isEmpty ? FeatureCardsStrings.text("cards.contentUnavailable", locale: locale) : text
    }

    private var isLinkPending: Bool {
        if case .openURL? = card.pending { return true }
        return false
    }

    /// The link sheet is shown for the pending `open_url` request; dismissing it by swipe answers cancel once.
    private var linkBinding: Binding<CardLinkItem?> {
        Binding(
            get: {
                guard case .openURL(let url, let requestID, let slotID, let token)? = card.pending else { return nil }
                return CardLinkItem(url: url, requestID: requestID, slotID: slotID, token: token)
            },
            set: { value in
                guard value == nil, let pending = card.pending, case .openURL(_, let requestID, let slotID, let token) = pending else { return }
                if !local.linkAnswering {
                    onAnswer(CardAnswer(token: token, slotID: slotID, requestID: requestID, outcome: .cancel))
                }
                local.linkAnswering = false
            })
    }

    private func answerLink(_ item: CardLinkItem, _ outcome: CardSlotOutcome) {
        local.linkAnswering = true
        let link = outcome == .confirm ? SurfaceLink.validate(item.url) : nil
        onAnswer(CardAnswer(token: item.token, slotID: item.slotID, requestID: item.requestID, outcome: outcome, link: link))
    }
}

/// One pending link confirmation, identified by its request.
struct CardLinkItem: Identifiable {
    let url: String
    let requestID: String
    let slotID: String
    let token: CardEventToken
    var id: String { requestID }
}

/// Renders the root node. A root Card is the card itself, so its children draw without an inset.
struct CardRootView: View {
    let node: CardNode
    let context: CardContext

    var body: some View {
        if node.kind == "Card" {
            CardChildren(node: node, context: context)
        } else {
            CardNodeView(node: node, context: context)
        }
    }
}
