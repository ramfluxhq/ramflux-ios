// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum BackupIntent: Equatable, Sendable, Identifiable {
    case create, verify(URL), install(BackupRecord)
    public var id: String { switch self { case .create: "create"; case .verify(let url): "verify:" + url.lastPathComponent; case .install(let job): "install:" + job.id } }
}
