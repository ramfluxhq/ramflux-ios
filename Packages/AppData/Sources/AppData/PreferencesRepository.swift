// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public struct AppearanceMode: RawRepresentable, Hashable, Sendable, CaseIterable {
    public let rawValue: String
    public init?(rawValue: String) {
        guard !rawValue.isEmpty, rawValue.utf8.count <= 64, rawValue.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }; self.rawValue = rawValue
    }
    private init(_ value: String) { rawValue = value }
    public static let system = Self("system"), light = Self("light"), dark = Self("dark")
    public static let allCases = [system, light, dark]
}
public protocol PreferencesRepository: Sendable {
    func appearance() async -> AppearanceMode
    func setAppearance(_ mode: AppearanceMode) async -> RepositoryResult<AppearanceMode>
}
public actor NativePreferencesRepository: PreferencesRepository {
    private let suite: String?
    public init(suite: String? = nil) { self.suite = suite }
    private var defaults: UserDefaults { suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard }
    public func appearance() -> AppearanceMode { defaults.string(forKey: "appearance").flatMap(AppearanceMode.init(rawValue:)) ?? .system }
    public func setAppearance(_ mode: AppearanceMode) -> RepositoryResult<AppearanceMode> { defaults.set(mode.rawValue, forKey: "appearance"); return .success(mode) }
}
