// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Hands a video view to the engine for a slot; set by `CallsHost` from the repository.
struct CallVideoAttacher: Sendable {
    let attach: @MainActor @Sendable ((any CallVideoSurface)?, CallVideoSlot, String) -> Void
    static let none = CallVideoAttacher { _, _, _ in }
}
extension EnvironmentValues { @Entry var callVideoAttacher = CallVideoAttacher.none }

/// The remote video with the local preview in the trailing corner. Shown only while the engine
/// reports video capability and a stream is on.
struct CallVideoArea: View {
    @Environment(\.rfTheme) private var theme
    let callID: String
    let local: Bool
    let remote: Bool
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if remote { CallVideoView(slot: .remote, callID: callID) } else { theme.surface }
            if local {
                CallVideoView(slot: .local, callID: callID)
                    .frame(width: KitMetrics.conversation * 1.4, height: KitMetrics.conversation * 2)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius_card)).padding(theme.gap)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius_card))
        .accessibilityHidden(true)
    }
}

#if os(iOS)
import UIKit
final class CallVideoSurfaceView: UIView, CallVideoSurface {}
struct CallVideoView: UIViewRepresentable {
    @Environment(\.callVideoAttacher) private var attacher
    let slot: CallVideoSlot
    let callID: String
    final class Coordinator { var detach: (@MainActor () -> Void)? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> CallVideoSurfaceView {
        let view = CallVideoSurfaceView(); view.backgroundColor = .black; attacher.attach(view, slot, callID)
        context.coordinator.detach = { [attacher, slot, callID] in attacher.attach(nil, slot, callID) }
        return view
    }
    func updateUIView(_ view: CallVideoSurfaceView, context: Context) {}
    static func dismantleUIView(_ view: CallVideoSurfaceView, coordinator: Coordinator) { coordinator.detach?() }
}
#else
struct CallVideoView: View {
    let slot: CallVideoSlot
    let callID: String
    var body: some View { Color.black }
}
#endif
