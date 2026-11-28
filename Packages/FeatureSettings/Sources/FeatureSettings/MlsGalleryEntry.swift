// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_MLS_GALLERY
import SwiftUI

/// Debug only: where the "MLS gallery" link of Settings > About leads. The app injects the gallery view, so Settings
/// needs no dependency on the screens the gallery shows. Compiled only with `RAMFLUX_MLS_GALLERY` (Debug).
public struct MlsGalleryDestinationKey: EnvironmentKey {
    public static let defaultValue: (@MainActor @Sendable () -> AnyView)? = nil
}
public extension EnvironmentValues {
    var mlsGalleryDestination: (@MainActor @Sendable () -> AnyView)? {
        get { self[MlsGalleryDestinationKey.self] }
        set { self[MlsGalleryDestinationKey.self] = newValue }
    }
}
#endif
