// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import SwiftUI
@testable import RFDesign
struct ThemeTests {
    @Test func everyTokenFileLoadsAndAdditionalThemeNeedsNoSwiftChange() throws {
        #expect(Set(RFThemeRegistry.themes.map(\.id)) == ["light", "dark"])
        let url = try #require(Bundle.module.url(forResource: "light", withExtension: "json", subdirectory: "Themes"))
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["id"] = "alternate"; object["labelKey"] = "theme.alternate"
        let extra = try RFThemeRegistry.parse(JSONSerialization.data(withJSONObject: object))
        #expect(extra.id == "alternate"); #expect(extra.tokens.radius_button == RFTheme.light.radius_button)
        #expect(RFThemeRegistry.resolve("system", scheme: .dark).font == RFTheme.dark.font)
    }
    @Test func shippedTextAndControlPairsMeetContrastInBothThemes() throws {
        for id in ["light", "dark"] {
            let url = try #require(Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Themes"))
            let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let tokens = try #require(object["tokens"] as? [String: [String: Any]])
            func luminance(_ key: String) throws -> Double {
                let value = try #require(tokens[key]?["$value"] as? [String: Any])
                let components = try #require(value["components"] as? [Double]); #expect(components.count == 3)
                return zip(components, [0.2126, 0.7152, 0.0722]).reduce(0) { sum, item in
                    let channel = item.0 <= 0.04045 ? item.0 / 12.92 : pow((item.0 + 0.055) / 1.055, 2.4)
                    return sum + channel * item.1
                }
            }
            for (foreground, background) in [("text", "bg"), ("secondary", "bg"), ("on-primary", "primary"), ("text", "input"), ("danger", "danger-bg")] {
                let a = try luminance(foreground), b = try luminance(background)
                #expect((max(a,b) + 0.05) / (min(a,b) + 0.05) >= 4.5)
            }
        }
    }
}
