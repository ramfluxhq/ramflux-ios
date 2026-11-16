// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData

enum TimelineProjection {
    /// The SDK page is newest first. The timeline is oldest at the top and newest at the bottom.
    static func chronological(_ messages: [MessageRecord]) -> [MessageRecord] {
        Array(messages.reversed())
    }
}
