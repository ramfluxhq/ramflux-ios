// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct AttachmentRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let mime: String?
    public init(id: String, name: String, mime: String? = nil) { self.id = id; self.name = name; self.mime = mime }
}
