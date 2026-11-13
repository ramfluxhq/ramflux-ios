// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public enum AppearanceMode: String, Equatable, Sendable, CaseIterable { case system, light, dark }
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
