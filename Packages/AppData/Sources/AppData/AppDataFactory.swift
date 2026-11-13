// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum AppDataFactory {
    /// Source-only builds explicitly refuse account operations. No fixture is linked into the app.
    public static func sessionRepository() -> any SessionRepository {
        #if RF_NATIVE_SDK
        do {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return UnavailableSessionRepository() }
            let root = support.appendingPathComponent("ramflux", isDirectory: true)
            return NativeSessionRepository(client: RamfluxClient(transport: try NativeCore(dataRoot: root)), dataRoot: root)
        } catch { return UnavailableSessionRepository() }
        #else
        return UnavailableSessionRepository()
        #endif
    }
}
