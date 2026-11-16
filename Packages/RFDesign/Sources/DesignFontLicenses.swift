// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

public struct DesignFontLicense: Equatable, Sendable {
    public let name: String
    public let text: String
    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}

public enum DesignFontLicenses {
    public static let files: [(name: String, resource: String)] = [
        ("Hanken Grotesk", "HankenGrotesk.ttf.OFL"),
        ("JetBrains Mono", "JetBrainsMono.ttf.OFL"),
        ("Noto Sans SC", "NotoSansSC.ttf.OFL"),
    ]
    private static let byteCap = 65_536

    public static func load() -> [DesignFontLicense] { load(bundle: .module) }

    public static func load(bundle: Bundle) -> [DesignFontLicense] {
        files.compactMap { entry in
            guard let url = bundle.url(forResource: entry.resource, withExtension: "txt", subdirectory: "Fonts"),
                  let text = readBounded(url), !text.isEmpty else { return nil }
            return DesignFontLicense(name: entry.name, text: text)
        }
    }

    private static func readBounded(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: byteCap), !data.isEmpty else { return nil }
        let end = try? handle.read(upToCount: 1)
        guard end?.isEmpty != false else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
