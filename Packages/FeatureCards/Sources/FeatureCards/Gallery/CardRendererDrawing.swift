// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_CARD_GALLERY
import AppData
import SwiftUI

/// The gallery's drawing: each fixture tree is drawn by the production renderer (`CardRootView`), so the screenshots show
/// real cards and check B reads what the renderer draws (`CardRenderCoverage`).
public struct CardRendererDrawing: CardGalleryDrawing {
    public init() {}

    public func undrawn(_ tree: CardTree) -> [String] {
        let placeholders = tree.nodes.values.filter { !CardRenderCoverage.nodeKinds.contains($0.kind) }.map(\.key)
        let slots = tree.hostSlots.filter { !CardRenderCoverage.slotKinds.contains($0.kind) }.map { "slot:\($0.kind)" }
        return (placeholders + slots).sorted()
    }

    @MainActor public func view(for tree: CardTree, onEvent: @escaping (String, CardHostEvent) -> Void) -> AnyView {
        AnyView(CardGalleryPreview(tree: tree, onEvent: onEvent))
    }
}

/// One fixture tree drawn by the renderer, live: every input and button sends its event through `onEvent`. The gallery
/// holds no host request, so link answers are dropped here; approval confirmation uses the same sheet as a card.
struct CardGalleryPreview: View {
    let tree: CardTree
    let onEvent: (String, CardHostEvent) -> Void
    @State private var local = CardLocalState()

    var body: some View {
        ScrollView {
            if let root = tree.root {
                let context = CardContext(surfaceRef: "fixture", tree: tree, phase: .live, closed: false, outOfSync: false, sending: false,
                                          local: local, securitySheetOpen: local.approvalKey != nil, onEvent: onEvent, onAnswer: { _ in },
                                          lifecycle: tree.lifecycle, generating: tree.generating)
                CardRootView(node: root, context: context)
                    .modifier(CardApprovalSheetModifier(context: context))
                    .environment(\.layoutDirection, tree.direction == "rtl" ? .rightToLeft : .leftToRight)
                    .padding(16)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
#endif
