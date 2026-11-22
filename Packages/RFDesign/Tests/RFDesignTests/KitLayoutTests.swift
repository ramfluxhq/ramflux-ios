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
@Suite(.timeLimit(.minutes(3)))
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

    @Test func mirroringTableNamesOnlyDrawnIcons() {
        for name in KitIconMirroring.mirrored { #expect(KitIconPaths.glyphs[name] != nil, "\(name) is not a Kit icon") }
        for name in ["chevron-left", "chevron-right", "reply", "forward"] { #expect(KitIconMirroring.mirrorsInRightToLeft(name)) }
        for name in ["play", "pause", "check", "check-check", "clock-3", "timer", "history", "arrow-up", "plus", "x", "qr-code", "loader-circle"] {
            #expect(!KitIconMirroring.mirrorsInRightToLeft(name), "\(name) must not mirror")
        }
    }

    /// chevron-right points at x = 15 in its 24 pt box. Mirrored, the point is at x = 9.
    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func directionalIconsMirrorWithTheLayout(_ direction: LayoutDirection) throws {
        let rep = try render(width: 24, direction: direction) { KitIcon(name: "chevron-right", size: 24, tint: .black) }
        let tip = try channel(rep, direction == .rightToLeft ? 9 : 15, 12)
        let tail = try channel(rep, direction == .rightToLeft ? 15 : 9, 12)
        #expect(tip < 0.5, "tip \(tip) \(direction)")
        #expect(tail > 0.5, "tail \(tail) \(direction)")
    }

    /// clock-3's hand points to the right (x = 16) in both directions.
    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func neutralIconsKeepTheirDrawing(_ direction: LayoutDirection) throws {
        let rep = try render(width: 24, direction: direction) { KitIcon(name: "clock-3", size: 24, tint: .black) }
        #expect(try channel(rep, 15, 12) < 0.5)
        #expect(try channel(rep, 8, 12) > 0.5)
    }

    @Test func switchKnobFollowsTheLayoutDirection() throws {
        let ltr = try render(width: 51) { KitSwitch(checked: true) }
        let rtl = try render(width: 51, direction: .rightToLeft) { KitSwitch(checked: true) }
        // The knob is the light disc; the track is the dark primary fill.
        let ltrTrailing = try channel(ltr, 36, 15), ltrLeading = try channel(ltr, 14, 15)
        let rtlTrailing = try channel(rtl, 14, 15), rtlLeading = try channel(rtl, 36, 15)
        #expect(ltrTrailing > ltrLeading, "ltr knob \(ltrTrailing) track \(ltrLeading)")
        #expect(rtlTrailing > rtlLeading, "rtl knob \(rtlTrailing) track \(rtlLeading)")
    }

    /// "1 22222222": in left-to-right order the gap between the groups is near the left edge.
    /// Reversed group order would put it near the right edge. SwiftUI currently resolves a
    /// digits-only paragraph left to right even without the isolate, so this guards the view;
    /// BidiTests proves the isolate itself against a forced right-to-left paragraph.
    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func identifierGroupsStayLeftToRight(_ direction: LayoutDirection) throws {
        let rep = try render(width: 200, direction: direction) {
            KitIdentifierText("1 22222222").fixedSize()
        }
        var inked: [Bool] = []
        for x in 0..<200 {
            var dark = false
            for y in stride(from: 2, to: 20, by: 1) where try channel(rep, CGFloat(x), CGFloat(y)) < 0.5 { dark = true; break }
            inked.append(dark)
        }
        guard let first = inked.firstIndex(of: true), let last = inked.lastIndex(of: true) else {
            Issue.record("no ink")
            return
        }
        let gap = (first...last).first { !inked[$0] && $0 > first } ?? last
        #expect(CGFloat(gap - first) < CGFloat(last - first) * 0.3, "gap at \(gap) in \(first)...\(last) \(direction)")
    }

    /// Bubbles take their cap from the container: min(token, fraction x width). Short text hugs.
    @Test(arguments: [CGFloat(320), 393, 744])
    func bubbleWidthFollowsTheContainer(_ width: CGFloat) {
        let frames = measure(width: width) {
            VStack(alignment: .leading) {
                KitBubble("OK", time: "10:23", tag: "short")
                KitBubble(String(repeating: "收到，我会把问题逐项回复。", count: 4), time: "10:23", tag: "long")
            }
        }
        let cap = min(RFTheme.light.mobile_bubble_max, width * KitMetrics.bubbleWidthFraction)
        #expect((frames["short"]?.width ?? 0) < cap * 0.6, "short \(frames["short"]?.width ?? 0)")
        #expect(abs((frames["long"]?.width ?? 0) - cap) < 0.5, "long \(frames["long"]?.width ?? 0) cap \(cap)")
    }

    /// Message text aligns by its own direction: Arabic starts at the right in a left-to-right UI,
    /// English at the left in a right-to-left UI.
    @Test(arguments: [("مرحبا بك", LayoutDirection.leftToRight, true), ("Hello there", .rightToLeft, false), ("Hello there", .leftToRight, false), ("مرحبا بك", .rightToLeft, true)])
    func messageTextAlignsByItsContent(_ text: String, _ direction: LayoutDirection, _ expectRight: Bool) throws {
        let rep = try render(width: 300, direction: direction) { KitMessageText(text, color: .black) }
        var columns: [Int] = []
        for x in stride(from: 0, to: 300, by: 2) {
            for y in stride(from: 4, to: 18, by: 2) where try channel(rep, CGFloat(x), CGFloat(y)) < 0.5 { columns.append(x); break }
        }
        guard let first = columns.first, let last = columns.last else { Issue.record("no ink"); return }
        if expectRight { #expect(first > 150 && last > 280, "ink \(first)...\(last)") } else { #expect(first < 20 && last < 150, "ink \(first)...\(last)") }
    }

    /// A one-letter stem and a wide extension ("i.wwwwwwwww"): the dense ink is the extension. A
    /// Latin stem keeps "stem.ext" order in a right-to-left UI (dense ink on the right); an Arabic
    /// stem reads from the right in either UI direction (dense ink on the left).
    @Test(arguments: [("i.wwwwwwwww", LayoutDirection.rightToLeft, true), ("i.wwwwwwwww", .leftToRight, true), ("م.wwwwwwwww", .leftToRight, false), ("م.wwwwwwwww", .rightToLeft, false)])
    func fileNameRowFollowsTheStemDirection(_ name: String, _ direction: LayoutDirection, _ extensionOnRight: Bool) throws {
        let rep = try render(width: 300, direction: direction) { KitFileName(name, color: .black).fixedSize() }
        var inked: [Int] = []
        for x in 0..<300 {
            for y in stride(from: 4, to: 18, by: 1) where try channel(rep, CGFloat(x), CGFloat(y)) < 0.5 { inked.append(x); break }
        }
        guard let first = inked.first, let last = inked.last else { Issue.record("no ink"); return }
        let third = Double(last - first) / 3
        let left = inked.filter { Double($0 - first) < third }.count
        let right = inked.filter { Double(last - $0) < third }.count
        #expect((right > left) == extensionOnRight, "left \(left) right \(right) \(direction)")
    }

    @Test func messageLinksAreDetected() {
        let attributed = KitMessageText.linked("see https://example.org/a and mail")
        let links = attributed.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.org/a")])
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
private func render(width: CGFloat, dark: Bool = false, pressed: Bool = false, direction: LayoutDirection = .leftToRight, @ViewBuilder content: () -> some View) throws -> NSBitmapImageRep {
    let theme: RFTheme = dark ? .dark : .light
    let view = content()
        .environment(\.layoutDirection, direction)
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
