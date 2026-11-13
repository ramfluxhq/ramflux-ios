// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum ChatPreviews {
    public static let states = [ChatState(), ChatState(loading: true), ChatState(failure: .offline), ChatState(messages: [
        MessageRecord(id: "one", sender: "Alex", kind: .text("Let us review this together."), isOwn: false),
        MessageRecord(id: "two", sender: "", kind: .text("I will take a look."), isOwn: true, receipt: "Device: delivered"),
        MessageRecord(id: "three", sender: "", kind: .deleted, isOwn: false),
    ])]
}
#Preview("Chat") { ChatScreen(state: ChatPreviews.states[3], onAction: { _ in }) }
