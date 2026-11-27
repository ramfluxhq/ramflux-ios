// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RFLocalization

/// Link checks for card buttons, mirroring `ramflux-protocol` `a2ui::link::validate_url`.
public enum SurfaceLink {
    public static func validate(_ raw: String) -> URL? {
        guard raw.utf8.count <= 2048, !raw.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || RFBidi.isEmbeddingOrIsolate($0) || RFBidi.isMark($0) }) else { return nil }
        guard let components = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)), components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil, authorityHasNoAt(raw),
              var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, labels.count > 1, !["localhost", "local"].contains(labels.last.map(String.init) ?? ""),
              labels.allSatisfy({ label in !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-") && label.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 122) || $0 == 45 } }),
              !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return components.url
    }
    /// The host shown in the confirmation (lowercased, no trailing dot).
    public static func host(_ url: URL) -> String { var host = url.host()?.lowercased() ?? ""; if host.hasSuffix(".") { host.removeLast() }; return host }
    private static func authorityHasNoAt(_ raw: String) -> Bool {
        guard let colon = raw.firstIndex(of: ":") else { return false }
        let rest = raw[raw.index(after: colon)...].drop { $0 == "/" || $0 == "\\" }
        let authority = rest.prefix { !"/\\?#".contains($0) }
        return !authority.contains("@")
    }
}
