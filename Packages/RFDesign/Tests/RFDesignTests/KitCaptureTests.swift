// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import SwiftUI
@testable import RFDesign
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@Suite(.timeLimit(.minutes(2)))
@MainActor
struct KitCoverageTests {
    @Test func catalogIncludesDarkAndLocalesForEveryComponent() {
        let names = Set(KitCatalog.boards().map(\.name))
        for stem in Self.componentStems {
            for suffix in ["", "--dark", "--en", "--zh"] {
                #expect(names.contains(stem + suffix), "missing \(stem + suffix)")
            }
        }
    }

    @Test func catalogMatchesTheBoardList() {
        let names = Set(KitCatalog.boards().map(\.name))
        let required = Self.requiredBoards
        #expect(Set(required).count == required.count, "duplicate required name")
        let missing = Set(required).subtracting(names).sorted()
        let extra = names.subtracting(required).sorted()
        #expect(missing.isEmpty, "missing \(missing.joined(separator: ", "))")
        #expect(extra.isEmpty, "unexpected \(extra.joined(separator: ", "))")
    }

    @Test func kitBackStringFollowsTheLocale() {
        #expect(RFDesignStrings.text("kit.back", locale: Locale(identifier: "en")) == "Back")
        #expect(RFDesignStrings.text("kit.back", locale: Locale(identifier: "zh-CN")) == "返回")
        #expect(RFDesignStrings.text("kit.call", locale: Locale(identifier: "en")) == "Call")
        #expect(RFDesignStrings.text("kit.call", locale: Locale(identifier: "zh-CN")) == "通话")
    }

    private static let componentStems = [
        "approval-card--default", "avatar--person", "bubble--own", "button--primary",
        "chat-header--default", "checkbox--on", "composer--default", "context-menu--default",
        "date-chip--default", "home-indicator--default", "icon-tile--default", "info-button--default",
        "list-row-conversation--default", "mono-block--default", "page-header--default",
        "pairing-code--default", "qr-placeholder--default", "reaction-bar--default", "row--default",
        "search-field--default", "security-warning--warning", "segmented--default", "sheet--default",
        "status-bar--default", "status-hero--default", "switch--on", "tab-bar--default",
        "text-field--default", "tip-bar--default", "unread-divider--default",
    ]

    /// Literal capture contract. It does not call KitCatalog.boards().
    private static let requiredBoards = [
        "button--primary", "button--secondary", "button--destructive",
        "button--disabled", "button--text", "avatar--person",
        "avatar--person-small-18", "avatar--agent", "avatar--agent-gem",
        "avatar--agent-orbit-small", "switch--on", "switch--off",
        "checkbox--on", "checkbox--off", "segmented--default",
        "status-bar--default", "home-indicator--default", "page-header--default",
        "page-header--info-action", "page-header--no-back", "page-header--no-back-no-title",
        "page-header--large-title", "page-header--large-title-plus-ellipsis", "page-header--large-title-single-action",
        "chat-header--default", "chat-header--agent", "chat-header--channel",
        "chat-header--no-more", "tab-bar--default", "tab-bar--messages-selected-badge",
        "tab-bar--messages-selected-no-badge", "tab-bar--groups-selected", "tab-bar--agents-selected",
        "tab-bar--more-selected", "search-field--default", "search-field--query",
        "search-field--query-with-clear", "text-field--default", "text-field--placeholder",
        "text-field--focused", "text-field--disabled", "text-field--error",
        "text-field--error-message", "row--default", "row--tag",
        "row--selected-check", "icon-tile--default", "info-button--default",
        "list-row-conversation--default", "list-row-conversation--unread-badge", "list-row-conversation--agent",
        "list-row-conversation--channel-pinned", "list-row-conversation--muted-group-badge", "list-row-conversation--read-tick",
        "list-row-conversation--search-result", "bubble--own", "bubble--incoming",
        "bubble--file", "bubble--own-meta-time-ticks", "bubble--own-no-meta",
        "bubble--own-pending-clock", "bubble--own-transient-opacity0", "bubble--incoming-group-sender-agent-tag",
        "composer--default", "composer--attach-disabled", "composer--mode-chip",
        "composer--mode-chip-send-active", "composer--option-row-send-active", "composer--reply-attachment-send-active",
        "date-chip--default", "unread-divider--default", "reaction-bar--default",
        "context-menu--default", "context-menu--restricted", "sheet--default",
        "sheet--no-close", "tip-bar--default", "tip-bar--loading",
        "tip-bar--offline-retry", "tip-bar--shield-action", "tip-bar--timer",
        "security-warning--warning", "security-warning--danger", "security-warning--danger-alert",
        "status-hero--default", "status-hero--success", "status-hero--success-shield",
        "status-hero--neutral-user-search", "status-hero--danger", "status-hero--warning-timeout",
        "status-hero--warning-offline", "approval-card--default", "mono-block--default",
        "pairing-code--default", "qr-placeholder--default", "button--primary--dark",
        "button--secondary--dark", "button--text--dark", "avatar--person--dark",
        "avatar--agent--dark", "segmented--default--dark", "status-bar--default--dark",
        "home-indicator--default--dark", "page-header--default--dark", "page-header--large-title--dark",
        "chat-header--default--dark", "tab-bar--default--dark", "search-field--default--dark",
        "text-field--default--dark", "row--default--dark", "list-row-conversation--default--dark",
        "bubble--own--dark", "bubble--incoming--dark", "bubble--file--dark",
        "composer--default--dark", "date-chip--default--dark", "unread-divider--default--dark",
        "reaction-bar--default--dark", "context-menu--default--dark", "sheet--default--dark",
        "tip-bar--default--dark", "status-hero--default--dark", "mono-block--default--dark",
        "qr-placeholder--default--dark", "button--primary--pressed", "button--primary--focused",
        "button--primary--loading", "button--primary--en", "button--primary--zh",
        "page-header--default--en", "page-header--default--zh", "row--default--en",
        "row--default--zh", "row--default--pressed", "bubble--own--en",
        "tab-bar--messages-selected-badge--en", "search-field--focused", "approval-card--default--dark",
        "approval-card--default--en", "approval-card--default--zh", "avatar--person--en",
        "avatar--person--zh", "bubble--own--zh", "chat-header--default--en",
        "chat-header--default--zh", "checkbox--on--dark", "checkbox--on--en",
        "checkbox--on--zh", "composer--default--en", "composer--default--zh",
        "context-menu--default--en", "context-menu--default--zh", "date-chip--default--en",
        "date-chip--default--zh", "home-indicator--default--en", "home-indicator--default--zh",
        "icon-tile--default--dark", "icon-tile--default--en", "icon-tile--default--zh",
        "info-button--default--dark", "info-button--default--en", "info-button--default--zh",
        "list-row-conversation--default--en", "list-row-conversation--default--zh", "mono-block--default--en",
        "mono-block--default--zh", "pairing-code--default--dark", "pairing-code--default--en",
        "pairing-code--default--zh", "qr-placeholder--default--en", "qr-placeholder--default--zh",
        "reaction-bar--default--en", "reaction-bar--default--zh", "search-field--default--en",
        "search-field--default--zh", "security-warning--warning--dark", "security-warning--warning--en",
        "security-warning--warning--zh", "segmented--default--en", "segmented--default--zh",
        "sheet--default--en", "sheet--default--zh", "status-bar--default--en",
        "status-bar--default--zh", "status-hero--default--en", "status-hero--default--zh",
        "switch--on--dark", "switch--on--en", "switch--on--zh",
        "tab-bar--default--en", "tab-bar--default--zh", "text-field--default--en",
        "text-field--default--zh", "tip-bar--default--en", "tip-bar--default--zh",
        "unread-divider--default--en", "unread-divider--default--zh",
    ]
}

@Suite(.timeLimit(.minutes(8)))
@MainActor
struct KitCaptureTests {
    @Test func captureKitBoards() throws {
        let env = ProcessInfo.processInfo.environment
        let ci = env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true"
        let dir = env["KIT_CAPTURE_DIR"]
            ?? env["TEST_RUNNER_KIT_CAPTURE_DIR"]
            ?? (env["SIMULATOR_UDID"] == nil ? nil : "/tmp/kit-ios-captures")
        guard let dir, !dir.isEmpty else {
            if ci { throw KitCaptureDirectoryError("kit capture has no directory in CI") }
            return
        }
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let old = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in old where url.pathExtension == "png" {
                try FileManager.default.removeItem(at: url)
            }
        }
        let boards = KitCatalog.boards()
        for board in boards {
            let data = try KitRaster.png(board)
            if data.isEmpty { throw KitCaptureDirectoryError("empty capture \(board.name)") }
            try data.write(to: root.appendingPathComponent("\(board.name).png"))
        }
        let written = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
        if written.count < boards.count {
            throw KitCaptureDirectoryError("captured \(written.count) of \(boards.count)")
        }
    }
}

private struct KitCaptureDirectoryError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

@MainActor
enum KitRaster {
    static func png(_ board: KitBoard) throws -> Data {
        let theme: RFTheme = board.dark ? .dark : .light
        let root = board.body
            .environment(\.rfTheme, theme)
            .environment(\.kitPreviewPressed, board.pressed)
            .environment(\.kitSpinnerAnimated, false)
            .environment(\.locale, Locale(identifier: board.name.hasSuffix("--en") ? "en" : "zh-CN"))
            .environment(\.kitCapturing, true)
            .background(theme.bg)
        let proposed = board.width ?? 800
        let sized = board.width == nil
            ? AnyView(root.fixedSize())
            : AnyView(root.frame(width: board.width, alignment: .topLeading).fixedSize(horizontal: false, vertical: true))
        let fit = measure(sized, proposed: proposed)
        let width = max(1, fit.width.rounded())
        let height = max(1, fit.height.rounded())
        let pinned = sized.frame(width: width, height: height, alignment: .topLeading)
        return try encode(AnyView(pinned), width: Int(width), height: Int(height))
    }

    private static func measure(_ view: AnyView, proposed: CGFloat) -> CGSize {
        #if canImport(AppKit)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: proposed, height: 2400)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
        #elseif canImport(UIKit)
        let host = UIHostingController(rootView: view)
        host.view.bounds = CGRect(x: 0, y: 0, width: proposed, height: 2400)
        host.view.layoutIfNeeded()
        return host.sizeThatFits(in: CGSize(width: proposed, height: 4000))
        #else
        return CGSize(width: proposed, height: 1)
        #endif
    }

    private static func encode(_ view: AnyView, width: Int, height: Int) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
        renderer.isOpaque = true
        #if canImport(AppKit)
        guard let image = renderer.nsImage else { throw KitRasterError() }
        return try flatten(image, width: width, height: height)
        #elseif canImport(UIKit)
        guard let image = renderer.uiImage else { throw KitRasterError() }
        return try flatten(image, width: width, height: height)
        #else
        throw KitRasterError()
        #endif
    }

    #if canImport(AppKit)
    private static func flatten(_ image: NSImage, width: Int, height: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw KitRasterError() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw KitRasterError() }
        return data
    }
    #endif

    #if canImport(UIKit)
    private static func flatten(_ image: UIImage, width: Int, height: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let canvas = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return canvas.pngData { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    #endif
}

private struct KitRasterError: Error {}
