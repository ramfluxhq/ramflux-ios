// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public enum KitAvatarKind { case person, agent, channel }

public struct KitAvatar: View {
    var label: String
    var size: CGFloat
    var kind: KitAvatarKind
    var icon: String
    var ring: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(_ label: String, size: CGFloat, kind: KitAvatarKind, icon: String = "orbit", ring: Bool = false, tag: String? = nil) {
        self.label = label
        self.size = size
        self.kind = kind
        self.icon = icon
        self.ring = ring
        self.tag = tag
    }

    public var body: some View {
        let radius = kind == .agent ? kitAgentRadius(size) : size / 2
        let fill: Color = switch kind {
        case .person: theme.avatar_person
        case .agent: theme.agent_av
        case .channel: theme.surface
        }
        let shape = RoundedRectangle(cornerRadius: radius)
        ZStack {
            switch kind {
            case .person:
                if label.isEmpty {
                    KitIcon(name: icon, size: kitAgentGlyph(size), tint: theme.secondary)
                } else {
                    KitLabel(label, size: kitPersonInitial(size), weight: .semibold, color: theme.text, line: KitMetrics.lineTitle)
                }
            case .agent:
                KitIcon(name: icon, size: kitAgentGlyph(size), tint: theme.on_agent_av)
            case .channel:
                KitIcon(name: "hash", size: kitAgentGlyph(size), tint: theme.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(fill, in: shape)
        .overlay { if ring { shape.strokeBorder(theme.text, lineWidth: KitMetrics.emphasis) } }
        .clipShape(shape)
        .kitTag(tag)
    }
}
