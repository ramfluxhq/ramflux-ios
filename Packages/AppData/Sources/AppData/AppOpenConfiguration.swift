// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// Host-provisioned values for the SDK's open configuration, read from the app's build configuration.
public enum AppOpenConfiguration {
    /// The username directory pin from the `RamfluxUsernameDirectory*` Info.plist keys, which the build fills from
    /// `RAMFLUX_USERNAME_DIRECTORY_URL`, `_ID`, `_PUBLIC_KEY` and `_GENERATION`. Nil when the build has none: the SDK
    /// then refuses username calls with a typed `directory_unavailable`. No address is compiled in.
    public static func usernameDirectory(info: [String: Any]?) -> UsernameDirectoryPin? {
        func text(_ key: String) -> String { (info?["RamfluxUsernameDirectory" + key] as? String)?.trimmingCharacters(in: .whitespaces) ?? "" }
        guard let generation = UInt64(text("Generation")) else { return nil }
        return UsernameDirectoryPin(url: text("URL"), id: text("ID"), publicKey: text("PublicKey"), generation: generation)
    }
    /// The SDK diagnostic log is on in debug builds only (`info` level, class `realrun`, which the shipped library
    /// treats as `release` unless it was built with the real-run feature). Release builds keep the SDK default.
    public static var diagnostics: DiagnosticSettings? {
        #if DEBUG
        DiagnosticSettings(level: .debug, buildClass: .realrun)
        #else
        nil
        #endif
    }
}
