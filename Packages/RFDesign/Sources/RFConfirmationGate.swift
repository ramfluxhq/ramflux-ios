// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
/// One explicit activation per presentation. Keys never grant confirmation authority.
struct RFConfirmationGate {
    enum Source { case tap, accessibility, hardwareKey }
    private(set) var consumed = false
    mutating func activate(_ source: Source, enabled: Bool) -> Bool {
        guard enabled, !consumed, source != .hardwareKey else { return false }
        consumed = true
        return true
    }
}
