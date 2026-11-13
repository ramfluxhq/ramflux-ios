// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum CeremonyResult: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case sealed(SecretBytes)
    case frame(JSONValue)
    public var description: String { switch self { case .sealed: "sealed"; case .frame: "frame" } }
    public var debugDescription: String { description }
}
