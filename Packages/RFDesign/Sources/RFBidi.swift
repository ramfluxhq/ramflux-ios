// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import RFLocalization
import SwiftUI

// The string rules for untrusted text, identifiers and sentences live in RFLocalization
// (RFBidi, RFUntrustedText, RFFileName, RFIdentifier, RFSentence) so AppData can apply them
// without depending on the design package. This file adds the SwiftUI mapping.
extension RFBidi {
    /// The base direction of a message from its content: the first strong character after
    /// skipping @mentions, links and inline code. Nil when the text has no strong character
    /// (digits, emoji, punctuation only); the caller keeps the surrounding direction then.
    public static func contentDirection(of text: String) -> LayoutDirection? {
        switch firstStrongDirection(of: text) {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        case nil: nil
        }
    }
}
