// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
import AppData
import RFDesign
import FeatureAppShell
import FeatureChat
import FeatureConversations
import FeatureGroups
import FeatureAgents
import FeatureOnboarding

/// Renders every board over the full CaptureMatrix and writes
/// `<board>-<locale>-<width>-<textSize>-<theme>.png` into SHELL_CAPTURE_DIR.
/// `scripts/compare-boards.py` compares the 393-wide default-size captures with
/// the design references and checks the rest for clipping.
///
/// ImageRenderer cannot flatten ScrollView, List, TextField or the UIKit
/// timeline, so boards are hosted in a window and snapshotted with drawHierarchy.
@MainActor
final class ShellBoardCaptureTests: XCTestCase {
    /// Board keys as in shell-previews/manifest.json. Boards without a fixture
    /// stay reference-only until a screen exists for them. MOB-D01E (agents
    /// search miss) has none: the search query is view-private state.
    private static let boards = [
        "MOB-B01", "MOB-B01L", "MOB-B01X", "MOB-B12", "MOB-B02", "MOB-B02E",
        "MOB-C01", "MOB-C15", "MOB-D01", "MOB-D20", "MOB-G01", "MOB-G03",
        "MOB-S01", "MOB-S02", "MOB-S18", "MOB-A01", "MOB-A02", "MOB-N01",
    ]

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 600
        UIView.setAnimationsEnabled(false)
    }

    func testCapturesBoardMatrix() throws {
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
        var expected: [String] = []
        for board in Self.boards {
            for locale in CaptureMatrix.locales {
                for canvas in CaptureMatrix.canvases {
                    for textSize in CaptureMatrix.textSizes {
                        for theme in CaptureMatrix.themes {
                            let name = CaptureMatrix.captureName(board: board, locale: locale, canvas: canvas, textSize: textSize, theme: theme)
                            let data = try png(view(for: board, language: FixtureLanguage(localeID: locale.id)), locale: locale, canvas: canvas, textSize: textSize, theme: theme, reservesHome: reservesHome(board))
                            if data.isEmpty { XCTFail("empty capture \(name)"); return }
                            try data.write(to: root.appendingPathComponent(name + ".png"))
                            expected.append(name)
                        }
                    }
                }
            }
        }
        let perBoard = CaptureMatrix.locales.count * CaptureMatrix.canvases.count * CaptureMatrix.textSizes.count * CaptureMatrix.themes.count
        XCTAssertEqual(expected.count, Self.boards.count * perBoard)
        let written = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
            .map { $0.deletingPathExtension().lastPathComponent }
        XCTAssertEqual(Set(written), Set(expected))
        // Each dimension must change the rendering, or the matrix measures nothing.
        func data(_ board: String, _ locale: String, _ theme: String = "light") throws -> Data {
            try Data(contentsOf: root.appendingPathComponent("\(board)-\(locale)-393-default-\(theme).png"))
        }
        for board in Self.boards {
            XCTAssertNotEqual(try data(board, "zh-CN"), try data(board, "en"), board)
            XCTAssertNotEqual(try data(board, "en"), try data(board, "ar"), board)
            XCTAssertNotEqual(try data(board, "en"), try data(board, "en", "dark"), board)
        }
        XCTAssertNotEqual(try data("MOB-D01", "zh-CN"), try data("MOB-D20", "zh-CN"))
        XCTAssertNotEqual(try data("MOB-C01", "zh-CN"), try data("MOB-C15", "zh-CN"))
        XCTAssertNotEqual(try data("MOB-G01", "zh-CN"), try data("MOB-G03", "zh-CN"))
        XCTAssertNotEqual(try data("MOB-B02", "zh-CN"), try data("MOB-B02E", "zh-CN"))
    }

    private func view(for board: String, language: FixtureLanguage) -> some View {
        Group {
            switch board {
            case "MOB-B01", "MOB-B01L", "MOB-B01X", "MOB-B12":
                phone(.messages, ConversationsScreen(state: BoardFixtures.conversations(board, language), onAction: { _ in }))
            case "MOB-B02", "MOB-B02E":
                ChatScreen(state: BoardFixtures.chat(board, language), onAction: { _ in })
            case "MOB-C01":
                phone(.groups, GroupsScreen(state: BoardFixtures.groups(language), onAction: { _ in }))
            case "MOB-D01":
                phone(.agents, AgentsScreen(state: BoardFixtures.agents(language), onAction: { _ in }))
            case "MOB-C15":
                phone(.groups, GroupsScreen(state: BoardFixtures.groupsNoneYet(), onAction: { _ in }))
            case "MOB-D20":
                phone(.agents, AgentsScreen(state: AgentsState(), onAction: { _ in }))
            case "MOB-G01":
                phone(.more, MoreHubScreen { _ in })
            case "MOB-G03":
                NavigationEditorScreen(order: .constant(ShellShortcuts.defaultOrder), hidden: .constant(""), onBack: {})
            case "MOB-S01": stage(.launch, language)
            case "MOB-S02": stage(.connection, language)
            case "MOB-S18": stage(.welcome, language)
            case "MOB-A01": stage(.start, language)
            case "MOB-A02": stage(.localUnlock, language)
            case "MOB-N01": stage(.create, language)
            default:
                EmptyView()
            }
        }
    }

    private func phone(_ tab: AppTab, _ content: some View) -> some View {
        let state = AppShellState(session: SessionSnapshot(phase: .ready, activeAccountID: "preview-account"), tab: tab, privacyShield: false)
        return AppShellScreen(state: state, onAction: { _ in }, featureContent: AnyView(content))
    }

    private func stage(_ stage: OnboardingStage, _ language: FixtureLanguage) -> some View {
        var state = OnboardingState(stage: stage)
        if stage == .create {
            state.name = BoardFixtures.accountTitle(language)
            let node = NodeRecord(
                id: "official",
                origin: "https://node.ramflux.example",
                isDefault: true,
                enabled: true,
                isConfirmed: true,
                pinSource: "builtin"
            )
            state.nodes = [node]
            state.selectedNodeID = node.id
        }
        return OnboardingScreen(state: state, onAction: { _ in })
    }

    /// Boards without a tab bar keep 34 pt clear of the home indicator. Tab roots
    /// already fill that band with the 83 pt bar.
    private func reservesHome(_ board: String) -> Bool {
        board.hasPrefix("MOB-G03") || board.hasPrefix("MOB-S") || board.hasPrefix("MOB-A") || board.hasPrefix("MOB-N") || board.hasPrefix("MOB-B02")
    }

    private func png(_ view: some View, locale: CaptureMatrix.CaptureLocale, canvas: CaptureMatrix.Canvas, textSize: CaptureMatrix.TextSize, theme captureTheme: CaptureMatrix.Theme, reservesHome: Bool) throws -> Data {
        let scheme = captureTheme.scheme
        let theme: RFTheme = scheme == .dark ? .dark : .light
        let bounds = CGRect(origin: .zero, size: canvas.size)
        let framed = VStack(spacing: 0) {
            KitStatusBar(time: "9:41", tag: "capture-status")
            view
                .padding(.bottom, reservesHome ? 34 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            KitHomeIndicator(tag: "capture-home").padding(.bottom, 12).allowsHitTesting(false)
        }
        .environment(\.colorScheme, scheme)
        .environment(\.locale, locale.locale)
        .environment(\.layoutDirection, locale.layoutDirection)
        .environment(\.dynamicTypeSize, textSize.size)
        .environment(\.rfTheme, theme)
        .ignoresSafeArea()
        .frame(width: bounds.width, height: bounds.height)
        .background(theme.bg)
        let controller = CaptureController(rootView: AnyView(framed))
        controller.safeAreaRegions = []
        controller.view.backgroundColor = UIColor(theme.bg)
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw ShellCaptureError("no window scene")
        }
        let settled = expectation(description: "layout")
        settled.assertForOverFulfill = false
        controller.onLayout = { settled.fulfill() }
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
        // Fulfilled from viewDidLayoutSubviews. 30s is the per-board deadline;
        // the test allowance of 600s covers the matrix. The snapshot then
        // waits for the screen update.
        wait(for: [settled], timeout: 30)
        controller.onLayout = nil
        // One pixel per point in 8-bit sRGB, the format of the design references.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        guard let data = image.pngData(), let source = image.cgImage, source.width == canvas.width, source.height == canvas.height else {
            throw ShellCaptureError("capture is not \(canvas.width)x\(canvas.height)")
        }
        return data
    }
}

private final class CaptureController: UIHostingController<AnyView> {
    var onLayout: (() -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }

    override var prefersStatusBarHidden: Bool { true }
}

private struct ShellCaptureError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
