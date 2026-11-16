// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import SwiftUI
import CoreText
@testable import RFDesign
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)
@MainActor
struct KitLayoutTests {
    @Test func primaryButtonMatchesTheMasterFrame() {
        let frames = measure(width: 361) { KitButton("按钮", action: {}, tag: "button") }
        #expect(near(frames["button"], 361, 52))
        #expect((frames["button-hit"]?.height ?? 0) >= 44)
    }

    @Test func textButtonHitIsFortyFour() {
        let frames = measure(width: 361) { KitButton("文字按钮", action: {}, kind: .text, tag: "text") }
        #expect(near(frames["text"], nil, 44))
        #expect(near(frames["text-hit"], nil, 44))
    }

    @Test func disabledPrimaryKeepsTheDesignedFrame() {
        let measured = measureHits(width: 361) { KitButton("按钮", action: {}, kind: .disabled, tag: "disabled") }
        #expect(near(measured.frames["disabled"], nil, 52))
        #expect(measured.hits["disabled-hit"] == false)
    }

    @Test func avatarScaleKeepsTheDrawnSize() {
        let sizes: [CGFloat] = [18, 28, 36, 44, 52, 72]
        let frames = measure(width: 80) {
            VStack {
                ForEach(sizes, id: \.self) { size in KitAvatar("A", size: size, kind: .person, tag: "avatar-\(Int(size))") }
            }
        }
        for size in sizes { #expect(near(frames["avatar-\(Int(size))"], size, size)) }
    }

    @Test func switchAndCheckboxKeepTheirDrawnSize() {
        let measured = measureHits(width: 80) {
            VStack {
                KitSwitch(checked: true, tag: "switch")
                KitCheckbox(checked: true, tag: "check")
            }
        }
        #expect(near(measured.frames["switch"], 51, 31))
        #expect((measured.frames["switch-hit"]?.height ?? 0) >= 44)
        #expect(near(measured.frames["check"], 24, 24))
        #expect((measured.frames["check-hit"]?.width ?? 0) >= 44)
    }

    @Test func chromeFramesMatchTheMasters() {
        let frames = measure(width: 393) {
            VStack(spacing: 0) {
                KitStatusBar(time: "9:41", tag: "status")
                KitPageHeader("标题", onBack: {}, tag: "header")
                KitTabBar(tabs: [
                    KitTab(icon: "messages-square", label: "消息", badge: "1"),
                    KitTab(icon: "users-round", label: "群组"),
                    KitTab(icon: "bot", label: "Agents", latin: true),
                    KitTab(icon: "ellipsis", label: "更多"),
                ], selected: 0, onSelect: { _ in }, tag: "tabs")
                KitHomeIndicator(tag: "home")
            }
        }
        #expect(near(frames["status"], 393, 59))
        #expect(near(frames["header"], nil, 60))
        #expect((frames["header-back"]?.width ?? 0) >= 44)
        #expect(near(frames["tabs"], nil, 83))
        #expect((frames["tabs-0"]?.height ?? 0) >= 44)
        #expect(near(frames["home"], 120, 4))
    }

    @Test func searchRowAndSegmentedMatchTheMasters() {
        let frames = measure(width: 361) {
            VStack {
                KitSearchField(value: .constant(""), placeholder: "搜索", tag: "search")
                KitRow("标题", icon: "user-round", tag: "row")
                KitSegmented(labels: ["A", "B"], selected: 0, tag: "segments")
            }
        }
        #expect(near(frames["search"], nil, 36))
        #expect(near(frames["row"], nil, 58))
        #expect(near(frames["segments"], nil, 36))
    }

    @Test func nestedHitsStayFortyFourInsideTheMasterFrame() {
        let frames = measure(width: 393) {
            VStack {
                KitSearchField(value: .constant("x"), placeholder: "搜索", tag: "search")
                KitSegmented(labels: ["A", "B"], selected: 0, tag: "segments")
                KitComposer(value: .constant("x"), placeholder: "消息", sendActive: true, tag: "composer")
                KitReactionBar(reactions: ["👍"], tag: "reactions")
            }
        }
        #expect(near(frames["search"], nil, 36))
        #expect((frames["search-clear"]?.height ?? 0) >= 44)
        #expect(near(frames["search-clear-icon"], 17, 17))
        #expect((frames["segments-0"]?.height ?? 0) >= 44)
        #expect(near(frames["composer"], nil, 60))
        #expect((frames["composer-send"]?.height ?? 0) >= 44)
        #expect(near(frames["composer-send-icon"], 32, 32))
        #expect(near(frames["reactions"], nil, 44))
        #expect((frames["reactions-0"]?.height ?? 0) >= 44)
        #expect(near(frames["reactions-cell-0"], 40, 44))
    }

    @Test func disabledControlsDoNotHit() {
        let measured = measureHits(width: 361) {
            VStack {
                KitSwitch(checked: true, enabled: false, tag: "switch")
                KitButton("按钮", action: {}, kind: .disabled, tag: "disabled")
                KitRow("标题", enabled: false, tag: "row")
            }
        }
        #expect(measured.hits["switch-hit"] == false)
        #expect(near(measured.frames["switch"], 51, 31))
        #expect(measured.hits["disabled-hit"] == false)
        #expect(measured.hits["row"] == false)
    }

    @Test func contextMenuHitAndMasterHeight() {
        let frames = measure(width: 280) {
            KitContextMenu(entries: [
                KitMenuEntry(label: "回复", icon: "reply"),
                KitMenuEntry(label: "复制", icon: "copy"),
                KitMenuEntry(label: "编辑", icon: "pencil"),
                KitMenuEntry(label: "转发", icon: "forward"),
                KitMenuEntry(label: "置顶", icon: "pin"),
                KitMenuEntry(label: "选择", icon: "list-checks"),
                KitMenuEntry(label: "删除", icon: "trash-2", danger: true, groupBefore: true),
            ], tag: "menu")
        }
        #expect(near(frames["menu"], 240, 309))
        #expect((frames["menu-hit-0-0"]?.height ?? 0) >= 44)
    }

    @Test func qrTileStaysTheDesignSquare() {
        let frames = measure(width: 220, dark: true) { KitQrPlaceholder(tag: "qr") }
        #expect(near(frames["qr"], 200, 200))
    }

    @Test func loadingButtonKeepsItsFrameAndShowsASpinner() {
        let frames = measure(width: 361) { KitButton("按钮", action: {}, loading: true, tag: "loading") }
        #expect(near(frames["loading"], 361, 52))
        #expect(frames["loading-spinner"] != nil)
    }

    @Test func iconsCoverTheLucideSet() {
        #expect(KitIconPaths.glyphs.count == 122)
        let check = KitIconPaths.glyphs["check"] ?? []
        #expect(check.contains { ops in ops.contains { op in
            if case .move(let x, let y) = op { return abs(x - 20) < 0.1 && abs(y - 6) < 0.1 }
            return false
        }})
        #expect(KitIconPaths.glyphs["search"] != nil)
        #expect(KitIconPaths.glyphs["bell-off"] != nil)
        #expect(KitIconPaths.glyphs["circle-x"] != nil)
        #expect(KitIconPaths.glyphs["user-round-search"] != nil)
    }

    @Test func pressedFilledButtonUsesTheRuledAlpha() throws {
        let rep = try render(width: 361, pressed: true) { KitButton("按钮", action: {}, tag: "button") }
        let red = try channel(rep, 12, 26)
        #expect(red > 0.18 && red < 0.32, "pressed red \(red)")
    }

    @Test func focusedPrimaryRingUsesTheDarkFocusToken() throws {
        let rep = try render(width: 361) { KitButton("按钮", action: {}, focused: true, tag: "button") }
        let ring = try channel(rep, 1, 26)
        let fill = try channel(rep, 12, 26)
        #expect(ring > 0.7, "ring \(ring)")
        #expect(fill < 0.25, "fill \(fill)")
    }

    @Test func focusedPrimaryRingStaysVisibleInDarkTheme() throws {
        let rep = try render(width: 361, dark: true) { KitButton("按钮", action: {}, focused: true, tag: "button") }
        let ring = try channel(rep, 1, 26)
        let fill = try channel(rep, 12, 26)
        #expect(ring + 0.04 < fill, "dark ring \(ring) fill \(fill)")
    }

    @Test func pressedRowUsesTheSelectedFill() throws {
        let rep = try render(width: 361, pressed: true) { KitRow("标题", icon: "user-round", tag: "row") }
        let red = try channel(rep, 180, 4)
        #expect(red > 0.85 && red < 0.95, "pressed row red \(red)")
    }

    @Test func ownBubbleWrapsInsideTheMaster() {
        let frames = measure(width: 260) {
            KitBubble("收到，我会把问题逐项回复。", time: "10:23", maxWidth: 260, tag: "bubble")
        }
        let size = frames["bubble"] ?? .zero
        #expect(abs(size.width - 260) < 0.5, "width \(size.width)")
        #expect(abs(size.height - 62) < 2.5, "height \(size.height)")
    }

    @Test func bundledWeightsSelectTheAxis() {
        for weight in [CGFloat(400), 500, 600, 700] {
            let font = kitCTFont(size: 17, weight: weight, role: .ui)
            let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
            let axis = NSNumber(value: 0x77676874)
            let actual = variation?[axis]?.doubleValue ?? -1
            #expect(abs(actual - Double(weight)) < 0.5, "ui weight \(weight) resolved \(actual)")
        }
    }
}

#if canImport(AppKit)
@MainActor
private final class Probe {
    var frames: [String: CGSize] = [:]
    var hits: [String: Bool] = [:]
}

@MainActor
private func measure(width: CGFloat, dark: Bool = false, @ViewBuilder content: () -> some View) -> [String: CGSize] {
    measureHits(width: width, dark: dark, content: content).frames
}

@MainActor
private func measureHits(width: CGFloat, dark: Bool = false, @ViewBuilder content: () -> some View) -> (frames: [String: CGSize], hits: [String: Bool]) {
    let probe = Probe()
    let root = content()
        .environment(\.rfTheme, dark ? .dark : .light)
        .environment(\.kitSpinnerAnimated, false)
        .frame(width: width, alignment: .topLeading)
        .onPreferenceChange(KitFrames.self) { probe.frames = $0 }
        .onPreferenceChange(KitHits.self) { probe.hits = $0 }
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: width, height: 1400)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    host.layoutSubtreeIfNeeded()
    return (probe.frames, probe.hits)
}
#endif

#if canImport(AppKit)
@MainActor
private func render(width: CGFloat, dark: Bool = false, pressed: Bool = false, @ViewBuilder content: () -> some View) throws -> NSBitmapImageRep {
    let theme: RFTheme = dark ? .dark : .light
    let view = content()
        .environment(\.rfTheme, theme)
        .environment(\.kitPreviewPressed, pressed)
        .environment(\.kitSpinnerAnimated, false)
        .frame(width: width, alignment: .topLeading)
        .background(theme.bg)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(width: width, height: 220)
    renderer.isOpaque = true
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        throw KitRenderError()
    }
    return rep
}

private struct KitRenderError: Error {}

@MainActor
private func channel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) throws -> CGFloat {
    let scale = CGFloat(rep.pixelsWide) / max(rep.size.width, 1)
    let px = Int((x * scale).rounded())
    let py = Int((y * scale).rounded())
    guard let color = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { throw KitRenderError() }
    return color.redComponent
}
#endif

private func near(_ size: CGSize?, _ width: CGFloat?, _ height: CGFloat?) -> Bool {
    guard let size else { return false }
    if let width, abs(size.width - width) > 0.5 { return false }
    if let height, abs(size.height - height) > 0.5 { return false }
    return true
}
#endif
