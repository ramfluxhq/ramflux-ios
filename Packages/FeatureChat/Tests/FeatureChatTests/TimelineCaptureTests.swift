// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import SwiftUI
import Testing
import RFDesign
@testable import FeatureChat
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Renders the mixed-direction timeline across UI direction, width and text size. Images are
/// written only when CHAT_CAPTURE_DIR is set; the render itself always runs.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct TimelineCaptureTests {
    struct Variant: Sendable, CustomStringConvertible {
        var locale: String
        var direction: LayoutDirection
        var width: CGFloat
        var size: DynamicTypeSize
        var description: String {
            "chat-timeline-\(locale)-\(direction == .rightToLeft ? "rtl" : "ltr")-\(Int(width))-\(size == .large ? "large" : "ax3")"
        }
    }

    nonisolated static let variants: [Variant] = [("en", LayoutDirection.leftToRight), ("ar", .rightToLeft)].flatMap { locale, direction in
        [CGFloat(320), 393, 744].flatMap { width in
            [DynamicTypeSize.large, .accessibility3].map { Variant(locale: locale, direction: direction, width: width, size: $0) }
        }
    }

    @Test(arguments: variants)
    func captureMixedDirectionTimeline(_ variant: Variant) throws {
        let state = ChatPreviews.mixedDirection
        let rows = TimelineProjection.items(state.messages, calendar: Calendar(identifier: .gregorian), unreadAnchorID: state.unreadAnchorID)
        let view = VStack(spacing: 8) {
            ForEach(rows, id: \.id) { TimelineRow(item: $0, isGroup: state.isGroup, onAction: { _ in }) }
        }
        .padding(.vertical, 8)
        .frame(width: variant.width)
        .background(RFTheme.light.bg)
        .environment(\.rfTheme, .light)
        .environment(\.locale, Locale(identifier: variant.locale))
        .environment(\.layoutDirection, variant.direction)
        .environment(\.dynamicTypeSize, variant.size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = true
        let data = try png(renderer)
        #expect(!data.isEmpty)
        guard let dir = ProcessInfo.processInfo.environment["CHAT_CAPTURE_DIR"], !dir.isEmpty else { return }
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appendingPathComponent("\(variant).png"))
    }

    private func png(_ renderer: ImageRenderer<some View>) throws -> Data {
        #if canImport(AppKit)
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { throw CaptureError() }
        return data
        #elseif canImport(UIKit)
        guard let data = renderer.uiImage?.pngData() else { throw CaptureError() }
        return data
        #endif
    }
}

private struct CaptureError: Error {}
