// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum SecretField: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case text(SecretBytes)
    case words([SecretBytes])
    public var description: String { switch self { case .text: "text"; case .words: "words" } }
    public var debugDescription: String { description }
    func erase() { switch self { case .text(let secret): secret.erase(); case .words(let words): words.forEach { $0.erase() } } }
}
