// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RFLocalization
public enum FeatureDeliveryStrings {
    public static func text(_ key: String, locale: Locale = .current) -> String {
        CatalogLookup.text(key, bundle: .module, locale: locale)
    }
}
