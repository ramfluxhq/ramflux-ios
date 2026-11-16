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

/// ImageRenderer cannot flatten ScrollView, List, or TextField, so shell boards
/// are hosted in a window and snapshotted with drawHierarchy.
@MainActor
final class ShellBoardCaptureTests: XCTestCase {
    private struct Board {
        var stem: String
        var scheme: ColorScheme
        var extraDark: Bool
    }

    private struct Shot {
        var name: String
        var scheme: ColorScheme
        var locale: Locale
    }

    /// Every preview stem, with zh-CN, en, and a dark pair when the stem is not already the dark board.
    private static let boards: [Board] = [
        Board(stem: "MOB-B01.light", scheme: .light, extraDark: false),
        Board(stem: "MOB-B01.dark", scheme: .dark, extraDark: false),
        Board(stem: "MOB-B01L.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-B01X.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-C01.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-D01.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-D01E.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-G01.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-G03.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-S01.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-S02.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-S18.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-A01.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-A02.light", scheme: .light, extraDark: true),
        Board(stem: "MOB-N01.light", scheme: .light, extraDark: true),
    ]

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 600
        UIView.setAnimationsEnabled(false)
    }

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
        let expected = Self.boards.flatMap { shots(for: $0, zh: zh, en: en) }
        XCTAssertEqual(expected.count, 84)
        for shot in expected {
            let data = try png(view(for: shot.name), scheme: shot.scheme, locale: shot.locale)
            if data.isEmpty { XCTFail("empty capture \(shot.name)"); return }
            try data.write(to: root.appendingPathComponent(shot.name + ".png"))
        }
        let written = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
            .map { $0.deletingPathExtension().lastPathComponent }
        XCTAssertEqual(Set(written), Set(expected.map(\.name)))
        for board in Self.boards {
            let base = try Data(contentsOf: root.appendingPathComponent(board.stem + ".png"))
            let english = try Data(contentsOf: root.appendingPathComponent(board.stem + "--en.png"))
            let chinese = try Data(contentsOf: root.appendingPathComponent(board.stem + "--zh.png"))
            XCTAssertNotEqual(base, english, board.stem)
            XCTAssertNotEqual(chinese, english, board.stem)
            if board.extraDark {
                let darkEnglish = try Data(contentsOf: root.appendingPathComponent(board.stem + "--en--dark.png"))
                let darkChinese = try Data(contentsOf: root.appendingPathComponent(board.stem + "--zh--dark.png"))
                XCTAssertNotEqual(darkEnglish, darkChinese, board.stem)
            }
        }
        let directory = try Data(contentsOf: root.appendingPathComponent("MOB-D01.light.png"))
        let searchMiss = try Data(contentsOf: root.appendingPathComponent("MOB-D01E.light.png"))
        let hub = try Data(contentsOf: root.appendingPathComponent("MOB-G01.light.png"))
        let editor = try Data(contentsOf: root.appendingPathComponent("MOB-G03.light.png"))
        XCTAssertNotEqual(directory, searchMiss)
        XCTAssertNotEqual(hub, editor)
    }

    private func shots(for board: Board, zh: Locale, en: Locale) -> [Shot] {
        var result = [
            Shot(name: board.stem, scheme: board.scheme, locale: zh),
            Shot(name: board.stem + "--en", scheme: board.scheme, locale: en),
            Shot(name: board.stem + "--zh", scheme: board.scheme, locale: zh),
        ]
        if board.extraDark {
            result.append(Shot(name: board.stem + "--dark", scheme: .dark, locale: zh))
            result.append(Shot(name: board.stem + "--zh--dark", scheme: .dark, locale: zh))
            result.append(Shot(name: board.stem + "--en--dark", scheme: .dark, locale: en))
        }
        return result
    }

    private func view(for name: String) -> some View {
        let stem = name
            .replacingOccurrences(of: "--en--dark", with: "")
            .replacingOccurrences(of: "--zh--dark", with: "")
            .replacingOccurrences(of: "--dark", with: "")
            .replacingOccurrences(of: "--en", with: "")
            .replacingOccurrences(of: "--zh", with: "")
        let messages = ConversationsPreviews.states
        var agents = AgentsState()
        agents.entries = [
            AgentEntry(id: "nova", name: "Nova", detail: "研究搭档 · 协作设置已确认", icon: "orbit"),
            AgentEntry(id: "atlas", name: "Atlas", detail: "规划助手 · 协作设置已确认", icon: "gem"),
            AgentEntry(id: "mira", name: "Mira", detail: "写作伙伴 · 协作已暂停", icon: "user-round"),
        ]
        return Group {
            switch stem {
            case "MOB-B01.light", "MOB-B01.dark":
                phone(.messages, ConversationsScreen(state: messages[3], onAction: { _ in }))
            case "MOB-B01L.light":
                phone(.messages, ConversationsScreen(state: messages[1], onAction: { _ in }))
            case "MOB-B01X.light":
                phone(.messages, ConversationsScreen(state: messages[2], onAction: { _ in }))
            case "MOB-C01.light":
                phone(.groups, GroupsScreen(state: GroupsPreviews.states[4], onAction: { _ in }))
            case "MOB-D01.light":
                phone(.agents, AgentsScreen(state: agents, onAction: { _ in }))
            case "MOB-D01E.light":
                phone(.agents, AgentsScreen(state: AgentsState(), onAction: { _ in }))
            case "MOB-G01.light":
                phone(.more, MoreHubScreen { _ in })
            case "MOB-G03.light":
                NavigationEditorScreen(order: .constant(ShellShortcuts.defaultOrder), hidden: .constant(""), onBack: {})
            case "MOB-S01.light": stage(.launch)
            case "MOB-S02.light": stage(.connection)
            case "MOB-S18.light": stage(.welcome)
            case "MOB-A01.light": stage(.start)
            case "MOB-A02.light": stage(.localUnlock)
            case "MOB-N01.light": stage(.create)
            default:
                EmptyView()
            }
        }
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
        let controller = CaptureController(rootView: AnyView(framed))
        controller.view.backgroundColor = UIColor(theme.bg)
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw ShellCaptureError("no window scene")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        window.backgroundColor = controller.view.backgroundColor
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.frame = bounds
        controller.view.frame = bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let settled = expectation(description: "layout")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        guard let data = image.pngData(), let source = image.cgImage, source.width == 393, source.height == 852 else {
            throw ShellCaptureError("capture is not 393x852")
        }
        return data
    }
}

private final class CaptureController: UIHostingController<AnyView> {
    override var prefersStatusBarHidden: Bool { true }
}

private struct ShellCaptureError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
