// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import AppData

public struct ChatTimeline: UIViewControllerRepresentable {
    @Environment(\.locale) private var locale
    public let onAction: (ChatAction) -> Void
    public let messages: [MessageRecord]
    public init(messages: [MessageRecord], onAction: @escaping (ChatAction) -> Void = { _ in }) { self.messages = messages; self.onAction = onAction }
    public func makeUIViewController(context: Context) -> TimelineController { TimelineController() }
    public func updateUIViewController(_ controller: TimelineController, context: Context) { controller.onAction = onAction; controller.update(messages) }
}
#endif
