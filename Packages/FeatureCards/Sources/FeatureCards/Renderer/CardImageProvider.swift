// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RamfluxCore
import AppData

/// How a card's Image node gets its pixels: the host reads the object an Image slot selects and decodes it within the
/// limits. The default draws "Image unavailable", which is what the standalone gallery runtime shows (it resolves no
/// selectors).
public struct CardImageProvider: Sendable {
    public let load: @Sendable (_ surfaceRef: String, _ attachment: JSONValue?) async -> CardImageResult
    public init(load: @escaping @Sendable (_ surfaceRef: String, _ attachment: JSONValue?) async -> CardImageResult) { self.load = load }
    public static let unavailable = CardImageProvider { _, _ in .unavailable }
}

private struct CardImageProviderKey: EnvironmentKey {
    static let defaultValue = CardImageProvider.unavailable
}

public extension EnvironmentValues {
    var cardImageProvider: CardImageProvider {
        get { self[CardImageProviderKey.self] }
        set { self[CardImageProviderKey.self] = newValue }
    }
}
