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

@MainActor
struct KitCaptureTests {
    @Test func catalogIncludesTheRuledStates() {
        let names = Set(KitCatalog.boards().map(\.name))
        for name in [
            "button--primary--pressed", "button--primary--focused", "button--primary--loading",
            "button--primary--en", "button--primary--zh", "row--default--pressed",
            "text-field--disabled", "text-field--focused", "search-field--focused",
            "button--disabled", "page-header--default--zh",
        ] {
            #expect(names.contains(name), "missing \(name)")
        }
        #expect(names.count > 110)
    }

    @Test func kitBackStringFollowsTheLocale() {
        #expect(RFDesignStrings.text("kit.back", locale: Locale(identifier: "en")) == "Back")
        #expect(RFDesignStrings.text("kit.back", locale: Locale(identifier: "zh-CN")) == "返回")
    }

    @Test func captureKitBoards() throws {
        let env = ProcessInfo.processInfo.environment
        let dir = env["KIT_CAPTURE_DIR"]
            ?? env["TEST_RUNNER_KIT_CAPTURE_DIR"]
            ?? (env["SIMULATOR_UDID"] == nil ? nil : "/tmp/kit-ios-captures")
        guard let dir, !dir.isEmpty else { return }
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for board in KitCatalog.boards() {
            let data = try KitRaster.png(board)
            try data.write(to: root.appendingPathComponent("\(board.name).png"))
        }
    }
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
