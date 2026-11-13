// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct GroupRecord: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let epoch: UInt64
    public let members: [String]
    public init(id: String, name: String?, epoch: UInt64, members: [String]) { self.id = id; self.name = name; self.epoch = epoch; self.members = members }
}
