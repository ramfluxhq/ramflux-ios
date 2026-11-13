// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import Foundation


public enum RFThemeRegistry {
    private struct Token: Decodable {
        struct Value: Decodable {
            let components: [Double]?
            let alpha: Double?
            let value: Double?
        }
        let color: Value?
        let dimension: Value?
        let font: String?
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            color = type == "color" ? try container.decode(Value.self, forKey: .value) : nil
            dimension = type == "dimension" ? try container.decode(Value.self, forKey: .value) : nil
            font = type == "fontFamily" ? try container.decode(String.self, forKey: .value) : nil
        }
        enum CodingKeys: String, CodingKey { case type = "$type", value = "$value" }
    }
    private struct Document: Decodable {
        let id: String
        let labelKey: String
        let scheme: String
        let tokens: [String: Token]
        let increasedContrast: [String: String]
    }
    private static let loaded: [NamedTheme] = {
        guard let directory = Bundle.module.url(forResource: "Themes", withExtension: nil),
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return [] }
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap {
            guard let size = try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 262_144, let data = try? Data(contentsOf: $0) else { return nil }
            return try? parse(data)
        }
    }()
    public static var themes: [NamedTheme] { loaded }
    public static func parse(_ data: Data) throws -> NamedTheme {
        guard data.count <= 262_144 else { throw ThemeLoadError.invalidTokens }
        let doc = try JSONDecoder().decode(Document.self, from: data)
        guard !doc.id.isEmpty, doc.id.utf8.count <= 64, doc.id != "system", ["light", "dark"].contains(doc.scheme), doc.tokens.count <= 256 else { throw ThemeLoadError.invalidTokens }
        return NamedTheme(id: doc.id, labelKey: doc.labelKey, isDark: doc.scheme == "dark", tokens: try make(doc.tokens), increasedContrast: try make(doc.tokens, overrides: doc.increasedContrast))
    }
    public static func resolve(_ selection: String, scheme: ColorScheme, increasedContrast: Bool = false) -> RFTheme {
        let id = selection == "system" ? (scheme == .dark ? "dark" : "light") : selection
        if let entry = loaded.first(where: { $0.id == id }) { return increasedContrast ? entry.increasedContrast : entry.tokens }
        return (scheme == .dark ? RFDesign.dark : RFDesign.light).registeredTheme
    }
    private static func make(_ tokens: [String: Token], overrides: [String: String] = [:]) throws -> RFTheme {
        func token(_ key: String) -> Token? { tokens[overrides[key] ?? key] }
        func color(_ key: String) throws -> Color {
            guard let value = token(key)?.color, let c = value.components, c.count == 3, c.allSatisfy({ $0.isFinite && (0...1).contains($0) }), let alpha = value.alpha, alpha.isFinite, (0...1).contains(alpha) else { throw ThemeLoadError.invalidTokens }
            return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: alpha)
        }
        func dimension(_ key: String) throws -> CGFloat {
            guard let value = token(key)?.dimension?.value, value.isFinite, (0...4096).contains(value) else { throw ThemeLoadError.invalidTokens }; return CGFloat(value)
        }
        func font(_ key: String) throws -> String {
            guard let value = token(key)?.font, !value.isEmpty, value.utf8.count <= 128 else { throw ThemeLoadError.invalidTokens }; return DesignFonts.face(for: value)
        }
        return RFTheme(
            accent: try color("accent"),
            agent_av: try color("agent-av"),
            avatar_person: try color("avatar-person"),
            badge: try color("badge"),
            bg: try color("bg"),
            bubble_max: try dimension("bubble-max"),
            chart_1: try color("chart-1"),
            chart_2: try color("chart-2"),
            column_max: try dimension("column-max"),
            composer_min: try dimension("composer-min"),
            control: try color("control"),
            danger: try color("danger"),
            danger_bg: try color("danger-bg"),
            focus: try color("focus"),
            font: try font("font"),
            font_latin: try font("font-latin"),
            font_mono: try font("font-mono"),
            font_serif: try font("font-serif"),
            gap: try dimension("gap"),
            incoming: try color("incoming"),
            incoming_meta: try color("incoming-meta"),
            incoming_quote: try color("incoming-quote"),
            input: try color("input"),
            input_border: try color("input-border"),
            line: try color("line"),
            line_nav: try color("line-nav"),
            line_soft: try color("line-soft"),
            line_strong: try color("line-strong"),
            menu_item_height: try dimension("menu-item-height"),
            mobile_bubble_max: try dimension("mobile-bubble-max"),
            nav: try color("nav"),
            on_accent: try color("on-accent"),
            on_agent_av: try color("on-agent-av"),
            on_avatar_person: try color("on-avatar-person"),
            on_badge: try color("on-badge"),
            on_danger: try color("on-danger"),
            on_primary: try color("on-primary"),
            on_success: try color("on-success"),
            on_tooltip: try color("on-tooltip"),
            outgoing: try color("outgoing"),
            outgoing_meta: try color("outgoing-meta"),
            outgoing_quote: try color("outgoing-quote"),
            outgoing_text: try color("outgoing-text"),
            overlay: try color("overlay"),
            overlay_border: try color("overlay-border"),
            primary: try color("primary"),
            radius_bubble: try dimension("radius-bubble"),
            radius_bubble_joined: try dimension("radius-bubble-joined"),
            radius_button: try dimension("radius-button"),
            radius_card: try dimension("radius-card"),
            radius_chip: try dimension("radius-chip"),
            radius_dialog: try dimension("radius-dialog"),
            radius_full: try dimension("radius-full"),
            radius_input: try dimension("radius-input"),
            radius_lg: try dimension("radius-lg"),
            radius_md: try dimension("radius-md"),
            radius_menu: try dimension("radius-menu"),
            radius_sheet: try dimension("radius-sheet"),
            radius_sm: try dimension("radius-sm"),
            radius_xl: try dimension("radius-xl"),
            radius_xs: try dimension("radius-xs"),
            rail: try color("rail"),
            rail_active: try color("rail-active"),
            row_conversation: try dimension("row-conversation"),
            scrim: try color("scrim"),
            secondary: try color("secondary"),
            selected: try color("selected"),
            shadow: try color("shadow"),
            size_body: try dimension("size-body"),
            size_button: try dimension("size-button"),
            size_caption: try dimension("size-caption"),
            size_meta: try dimension("size-meta"),
            size_metric: try dimension("size-metric"),
            size_mobile_body: try dimension("size-mobile-body"),
            size_mobile_caption: try dimension("size-mobile-caption"),
            size_mobile_large_title: try dimension("size-mobile-large-title"),
            size_page: try dimension("size-page"),
            size_secondary: try dimension("size-secondary"),
            size_subheading: try dimension("size-subheading"),
            size_title: try dimension("size-title"),
            success: try color("success"),
            success_bg: try color("success-bg"),
            surface: try color("surface"),
            surface_white: try color("surface-white"),
            text: try color("text"),
            tooltip: try color("tooltip"),
            warning: try color("warning"),
            warning_bg: try color("warning-bg")
        )
    }
}
