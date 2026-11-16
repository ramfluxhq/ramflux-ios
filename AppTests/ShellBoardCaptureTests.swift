// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
import AppData
import RFDesign
import FeatureAppShell
import FeatureConversations
import FeatureGroups
import FeatureAgents
import FeatureOnboarding

@MainActor
final class ShellBoardCaptureTests: XCTestCase {
    func testCapturesShellBoards() throws {
        let env = ProcessInfo.processInfo.environment
        let ci = env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true"
        let dir = env["SHELL_CAPTURE_DIR"] ?? (env["SIMULATOR_UDID"] == nil ? nil : "/tmp/shell-ios-captures")
        guard let dir, !dir.isEmpty else {
            if ci { XCTFail("shell capture has no directory in CI") }
            return
        }
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let old = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in old where url.pathExtension == "png" { try FileManager.default.removeItem(at: url) }
        }
        let zh = Locale(identifier: "zh-CN")
        let en = Locale(identifier: "en")
        var shots: [(String, ColorScheme, Locale, AnyView)] = []
        func add(stem: String, scheme: ColorScheme, extraDark: Bool, _ view: some View) {
            let wrapped = AnyView(view)
            shots.append((stem, scheme, zh, wrapped))
            shots.append((stem + "--en", scheme, en, wrapped))
            shots.append((stem + "--zh", scheme, zh, wrapped))
            if extraDark {
                shots.append((stem + "--dark", .dark, zh, wrapped))
                shots.append((stem + "--zh--dark", .dark, zh, wrapped))
                shots.append((stem + "--en--dark", .dark, en, wrapped))
            }
        }
        let messages = ConversationsPreviews.states
        add(stem: "MOB-B01.light", scheme: .light, extraDark: false, phone(.messages, ConversationsScreen(state: messages[3], onAction: { _ in })))
        add(stem: "MOB-B01.dark", scheme: .dark, extraDark: false, phone(.messages, ConversationsScreen(state: messages[3], onAction: { _ in })))
        add(stem: "MOB-B01L.light", scheme: .light, extraDark: true, phone(.messages, ConversationsScreen(state: messages[1], onAction: { _ in })))
        add(stem: "MOB-B01X.light", scheme: .light, extraDark: true, phone(.messages, ConversationsScreen(state: messages[2], onAction: { _ in })))
        add(stem: "MOB-C01.light", scheme: .light, extraDark: true, phone(.groups, GroupsScreen(state: GroupsPreviews.states[4], onAction: { _ in })))
        add(stem: "MOB-D01.light", scheme: .light, extraDark: true, phone(.agents, AgentsScreen(state: AgentsState(), onAction: { _ in })))
        add(stem: "MOB-D01E.light", scheme: .light, extraDark: true, phone(.agents, AgentsScreen(state: AgentsState(), onAction: { _ in })))
        add(stem: "MOB-G01.light", scheme: .light, extraDark: true, phone(.more, MoreHubScreen { _ in }))
        add(stem: "MOB-G03.light", scheme: .light, extraDark: true, phone(.more, MoreHubScreen { _ in }))
        add(stem: "MOB-S01.light", scheme: .light, extraDark: true, stage(.launch))
        add(stem: "MOB-S02.light", scheme: .light, extraDark: true, stage(.connection))
        add(stem: "MOB-S18.light", scheme: .light, extraDark: true, stage(.welcome))
        add(stem: "MOB-A01.light", scheme: .light, extraDark: true, stage(.start))
        add(stem: "MOB-A02.light", scheme: .light, extraDark: true, stage(.localUnlock))
        add(stem: "MOB-N01.light", scheme: .light, extraDark: true, stage(.create))
        for shot in shots {
            let data = try png(shot.3, scheme: shot.1, locale: shot.2)
            if data.isEmpty { XCTFail("empty capture \(shot.0)"); return }
            try data.write(to: root.appendingPathComponent(shot.0 + ".png"))
        }
        let written = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }
        XCTAssertGreaterThanOrEqual(written.count, shots.count)
    }

    private func phone(_ tab: AppTab, _ content: some View) -> some View {
        let state = AppShellState(session: SessionSnapshot(phase: .ready, activeAccountID: "preview-account"), tab: tab, privacyShield: false)
        return AppShellScreen(state: state, onAction: { _ in }, featureContent: AnyView(content))
    }

    private func stage(_ stage: OnboardingStage) -> some View {
        OnboardingScreen(state: OnboardingState(stage: stage), onAction: { _ in })
    }

    private func png(_ view: some View, scheme: ColorScheme, locale: Locale) throws -> Data {
        let theme: RFTheme = scheme == .dark ? .dark : .light
        let framed = view
            .environment(\.colorScheme, scheme)
            .environment(\.locale, locale)
            .environment(\.rfTheme, theme)
            .frame(width: 393, height: 852)
            .background(theme.bg)
            .clipped()
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 393, height: 852)
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { throw ShellCaptureError("renderer produced no image") }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let pixels = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 393, height: 852))
        }
        guard let data = pixels.pngData(), let source = pixels.cgImage, source.width == 393, source.height == 852 else {
            throw ShellCaptureError("capture is not 393x852")
        }
        return data
    }
}

private struct ShellCaptureError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
