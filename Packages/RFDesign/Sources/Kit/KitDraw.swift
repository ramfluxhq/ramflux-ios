// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import CoreText
import SwiftUI

public struct KitFrames: PreferenceKey {
    public static let defaultValue: [String: CGSize] = [:]
    public static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

public struct KitHits: PreferenceKey {
    public static let defaultValue: [String: Bool] = [:]
    public static func reduce(value: inout [String: Bool], nextValue: () -> [String: Bool]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension EnvironmentValues {
    @Entry var kitPreviewPressed = false
    @Entry var kitSpinnerAnimated = true
    /// ImageRenderer cannot flatten a platform text field, so captures draw the same string with `KitLabel`.
    @Entry var kitCapturing = false
}

extension View {
    func kitTag(_ id: String?) -> some View { modifier(KitTag(id: id)) }

    func kitHairline(_ color: Color, top: Bool = false) -> some View {
        overlay(alignment: top ? .top : .bottom) {
            Rectangle().fill(color).frame(height: KitMetrics.hairline)
        }
    }
}

private struct KitTag: ViewModifier {
    var id: String?
    @ViewBuilder func body(content: Content) -> some View {
        if let id {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(key: KitFrames.self, value: [id: proxy.size])
                }
            }
            .accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

func kitPath(_ ops: [KitIconOp]) -> Path {
    var path = Path()
    for op in ops {
        switch op {
        case .move(let x, let y): path.move(to: CGPoint(x: x, y: y))
        case .line(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
        case .cubic(let x1, let y1, let x2, let y2, let x, let y):
            path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
        case .close: path.closeSubpath()
        }
    }
    return path
}

/// A hand-drawn Lucide icon. Directional icons mirror under right-to-left layout according to
/// `KitIconMirroring`; callers cannot override it.
public struct KitIcon: View {
    var name: String
    var size: CGFloat
    var tint: Color
    public init(name: String, size: CGFloat, tint: Color) {
        self.name = name
        self.size = size
        self.tint = tint
    }
    public var body: some View {
        Canvas { context, _ in
            guard let paths = KitIconPaths.glyphs[name] else { return }
            let scale = size / 24
            let stroke = StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round)
            for ops in paths {
                context.stroke(kitPath(ops).applying(CGAffineTransform(scaleX: scale, y: scale)), with: .color(tint), style: stroke)
            }
        }
        .frame(width: size, height: size)
        .flipsForRightToLeftLayoutDirection(KitIconMirroring.mirrorsInRightToLeft(name))
        .accessibilityHidden(true)
    }
}

struct KitSpinner: View {
    var size: CGFloat
    var tint: Color
    var spinning: Bool?
    var tag: String?
    @Environment(\.kitSpinnerAnimated) private var animated
    @State private var turns = false
    private var active: Bool { spinning ?? animated }
    var body: some View {
        KitIcon(name: "loader-circle", size: size, tint: tint)
            .rotationEffect(.degrees(active && turns ? 360 : 0))
            .animation(active ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .none, value: turns)
            .kitTag(tag)
            .onAppear { turns = active }
    }
}

func kitChannels(_ color: Color) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    #if canImport(UIKit)
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    if UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) { return (red, green, blue, alpha) }
    return (0, 0, 0, 0)
    #else
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return (0, 0, 0, 0) }
    return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
    #endif
}

func kitSame(_ lhs: Color, _ rhs: Color) -> Bool {
    let left = kitChannels(lhs)
    let right = kitChannels(rhs)
    return abs(left.0 - right.0) < 0.004 && abs(left.1 - right.1) < 0.004 && abs(left.2 - right.2) < 0.004 && abs(left.3 - right.3) < 0.004
}

func kitFocusRing(fill: Color, theme: RFTheme) -> Color {
    if kitSame(fill, theme.focus) {
        return kitSame(RFDesign.dark.focus, fill) ? RFDesign.light.focus : RFDesign.dark.focus
    }
    return theme.focus
}

struct KitHit<Content: View>: View {
    var enabled: Bool = true
    var label: String = ""
    var hitTag: String?
    var selected: Bool = false
    var onPress: ((Bool) -> Void)?
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        KitHitLayout {
            content()
            Color.clear
                .frame(width: 0, height: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .allowsHitTesting(enabled)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier(hitTag ?? "")
                .kitTag(hitTag)
                .preference(key: KitHits.self, value: hitTag.map { [$0: enabled] } ?? [:])
                .gesture(press)
        }
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in if enabled { onPress?(true) } }
            .onEnded { _ in
                guard enabled else { return }
                onPress?(false)
                action()
            }
    }
}

private struct KitHitLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let drawn = content.sizeThatFits(proposal)
        content.place(at: CGPoint(x: bounds.midX - drawn.width / 2, y: bounds.midY - drawn.height / 2), proposal: ProposedViewSize(drawn))
        guard subviews.count > 1 else { return }
        let hit = subviews[1]
        let width = max(drawn.width, KitMetrics.hit)
        let height = max(drawn.height, KitMetrics.hit)
        hit.place(
            at: CGPoint(x: bounds.midX - width / 2, y: bounds.midY - height / 2),
            proposal: ProposedViewSize(width: width, height: height)
        )
    }
}

struct KitIconHit: View {
    var icon: String
    var size: CGFloat
    var tint: Color
    var label: String
    var tag: String?
    var action: () -> Void
    var body: some View {
        KitHit(enabled: true, label: label, hitTag: tag, action: action) {
            KitIcon(name: icon, size: size, tint: tint)
                .frame(width: KitMetrics.iconButton, height: KitMetrics.iconButton)
        }
    }
}

public struct KitIconButton: View {
    var icon: String
    var label: String
    var action: () -> Void
    var enabled: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(_ icon: String, label: String, action: @escaping () -> Void, enabled: Bool = true, tag: String? = nil) {
        self.icon = icon
        self.label = label
        self.action = action
        self.enabled = enabled
        self.tag = tag
    }

    public var body: some View {
        let tint = enabled ? theme.text : theme.control
        if enabled {
            KitIconHit(icon: icon, size: KitMetrics.iconAction, tint: tint, label: label, tag: tag, action: action)
        } else {
            KitIcon(name: icon, size: KitMetrics.iconAction, tint: tint)
                .frame(width: KitMetrics.iconButton, height: KitMetrics.iconButton)
                .accessibilityElement()
                .accessibilityLabel(label)
                .kitTag(tag)
        }
    }
}
