// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import RamfluxCore

/// The SDK-verified kind of a participant (`verified_classification`): `person` and `ai_agent` come only
/// from the current signed custody record; a self-declared kind, a missing publication or a stale head
/// is `unknown`. Agents are treated exactly like people; the only difference is the AI marker.
public enum PrincipalClassification: String, Sendable, Equatable {
    case person, aiAgent = "ai_agent", unknown
    public init(sdk value: JSONValue?) { self = value?.string.flatMap(Self.init(rawValue:)) ?? .unknown }
    public var isAIAgent: Bool { self == .aiAgent }
}
