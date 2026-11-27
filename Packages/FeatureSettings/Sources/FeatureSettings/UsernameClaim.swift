// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The claim sheet of the Username page: the name is typed first, then the recovery phrase authorizes it.
/// The phrase itself is never part of this state; it goes straight from the secure form to the repository.
public struct UsernameClaim: Equatable, Sendable {
    public enum Step: Equatable, Sendable { case name, phrase }
    public var name: String
    public var step: Step
    public init(name: String = "", step: Step = .name) { self.name = name; self.step = step }
}
