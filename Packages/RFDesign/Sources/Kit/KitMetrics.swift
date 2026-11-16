// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import CoreGraphics

public enum KitMetrics {
    public static let hairline: CGFloat = 0.5
    public static let stroke: CGFloat = 1
    public static let controlStroke: CGFloat = 1.5
    public static let emphasis: CGFloat = 2
    public static let focusRing: CGFloat = 2
    public static let pressedAlpha: CGFloat = 0.88
    public static let disabledAlpha: CGFloat = 0.45
    public static let fieldDisabledAlpha: CGFloat = 0.55
    public static let bubbleWidthFraction: CGFloat = 0.78
    public static let agentRadiusRatio: CGFloat = 0.28
    public static let screen: CGFloat = 393
    public static let content: CGFloat = 361
    public static let gutter: CGFloat = 16
    public static let lineTight: CGFloat = 1.25
    public static let lineTitle: CGFloat = 1.3
    public static let lineBody: CGFloat = 1.45
    public static let lineBubble: CGFloat = 1.35
    public static let lineSecondary: CGFloat = 1.4
    public static let buttonHeight: CGFloat = 52
    public static let buttonCompact: CGFloat = 44
    public static let buttonPadH: CGFloat = 20
    public static let hit: CGFloat = 44
    public static let header: CGFloat = 60
    public static let headerPadV: CGFloat = 8
    public static let iconBack: CGFloat = 22
    public static let iconInfo: CGFloat = 20
    public static let iconAction: CGFloat = 22
    public static let search: CGFloat = 36
    public static let searchIcon: CGFloat = 17
    public static let searchPad: CGFloat = 8
    public static let row: CGFloat = 58
    public static let rowPadV: CGFloat = 8
    public static let conversation: CGFloat = 72
    public static let tabBar: CGFloat = 83
    public static let tab: CGFloat = 44
    public static let tabPadTop: CGFloat = 8
    public static let tabInset: CGFloat = 31
    public static let tabGap: CGFloat = 2
    public static let tabIcon: CGFloat = 24
    public static let tabBadge: CGFloat = 18
    public static let tabBadgeMin: CGFloat = 15
    public static let tabBadgePad: CGFloat = 4
    public static let badgeX: CGFloat = 14
    public static let badgeY: CGFloat = -4
    public static let statusBar: CGFloat = 59
    public static let statusPad: CGFloat = 24
    public static let statusIcon: CGFloat = 17
    public static let statusBattery: CGFloat = 23
    public static let statusGap: CGFloat = 8
    public static let homeWidth: CGFloat = 120
    public static let homeHeight: CGFloat = 4
    public static let homeRadius: CGFloat = 2
    public static let switchWidth: CGFloat = 51
    public static let switchHeight: CGFloat = 31
    public static let switchKnob: CGFloat = 27
    public static let switchInset: CGFloat = 2
    public static let checkbox: CGFloat = 24
    public static let check: CGFloat = 16
    public static let optionBox: CGFloat = 20
    public static let segmented: CGFloat = 36
    public static let segmentedPad: CGFloat = 2
    public static let composerPad: CGFloat = 8
    public static let composerRow: CGFloat = 44
    public static let capsuleRadius: CGFloat = 20
    public static let capsulePadStart: CGFloat = 16
    public static let capsulePad: CGFloat = 6
    public static let send: CGFloat = 32
    public static let sendIcon: CGFloat = 18
    public static let attachIcon: CGFloat = 24
    public static let modeChip: CGFloat = 30
    public static let modePad: CGFloat = 8
    public static let optionRow: CGFloat = 36
    public static let replyBar: CGFloat = 52
    public static let replyAccentWidth: CGFloat = 3
    public static let replyAccentHeight: CGFloat = 36
    public static let replyRadius: CGFloat = 2
    public static let attachment: CGFloat = 56
    public static let fileTile: CGFloat = 40
    public static let fileGlyph: CGFloat = 22
    public static let bubblePadV: CGFloat = 8
    public static let bubblePadH: CGFloat = 12
    public static let bubbleGap: CGFloat = 4
    public static let bubbleMaster: CGFloat = 260
    public static let metaIcon: CGFloat = 14
    public static let agentTag: CGFloat = 18
    public static let avatar18: CGFloat = 18
    public static let avatar28: CGFloat = 28
    public static let avatar36: CGFloat = 36
    public static let avatar44: CGFloat = 44
    public static let avatar52: CGFloat = 52
    public static let avatar72: CGFloat = 72
    public static let initial8: CGFloat = 8
    public static let initial12: CGFloat = 12
    public static let initial15: CGFloat = 15
    public static let initial17: CGFloat = 17
    public static let initial22: CGFloat = 22
    public static let initial28: CGFloat = 28
    public static let glyph10: CGFloat = 10
    public static let glyph14: CGFloat = 14
    public static let glyph16: CGFloat = 16
    public static let glyph21: CGFloat = 21
    public static let glyph24: CGFloat = 24
    public static let glyph28: CGFloat = 28
    public static let glyph40: CGFloat = 40
    public static let approvalAvatar: CGFloat = 24
    public static let approvalRadius: CGFloat = 6
    public static let tile: CGFloat = 30
    public static let tileGlyph: CGFloat = 18
    public static let chevron: CGFloat = 14
    public static let listBadge: CGFloat = 20
    public static let listBadgeRadius: CGFloat = 10
    public static let listBadgePad: CGFloat = 8
    public static let sheetPadTop: CGFloat = 8
    public static let sheetPadH: CGFloat = 16
    public static let sheetPadBottom: CGFloat = 40
    public static let sheetGap: CGFloat = 12
    public static let grabberWidth: CGFloat = 36
    public static let grabberHeight: CGFloat = 5
    public static let grabberRadius: CGFloat = 3
    public static let shadowBlur: CGFloat = 24
    public static let menu: CGFloat = 240
    public static let menuItem: CGFloat = 44
    public static let menuIcon: CGFloat = 20
    public static let menuPad: CGFloat = 16
    public static let reaction: CGFloat = 44
    public static let reactionCell: CGFloat = 40
    public static let reactionPad: CGFloat = 8
    public static let reactionGap: CGFloat = 4
    public static let moreIcon: CGFloat = 18
    public static let datePadV: CGFloat = 8
    public static let chipPadV: CGFloat = 4
    public static let chipPadH: CGFloat = 8
    public static let unread: CGFloat = 28
    public static let unreadGap: CGFloat = 12
    public static let unreadLine: CGFloat = 1
    public static let tipPadV: CGFloat = 10
    public static let tipPadH: CGFloat = 12
    public static let tipGap: CGFloat = 8
    public static let tipIcon: CGFloat = 18
    public static let securityPad: CGFloat = 12
    public static let securityGap: CGFloat = 10
    public static let securityIcon: CGFloat = 20
    public static let hero: CGFloat = 72
    public static let heroGlyph: CGFloat = 40
    public static let heroRadius: CGFloat = 36
    public static let approval: CGFloat = 329
    public static let approvalPad: CGFloat = 12
    public static let approvalGap: CGFloat = 10
    public static let scopePad: CGFloat = 10
    public static let monoPadTop: CGFloat = 12
    public static let monoPadBottom: CGFloat = 12
    public static let monoPadStart: CGFloat = 16
    public static let monoPadEnd: CGFloat = 4
    public static let pairing: CGFloat = 72
    public static let pairingSize: CGFloat = 24
    public static let pairingTrack: CGFloat = 2
    public static let qr: CGFloat = 200
    public static let qrGlyph: CGFloat = 150
    public static let fieldGap: CGFloat = 6
    public static let fieldBox: CGFloat = 48
    public static let fieldPad: CGFloat = 12
    public static let fieldIcon: CGFloat = 18
    public static let rowGap: CGFloat = 12
    public static let labelGap: CGFloat = 1
    public static let tagPadV: CGFloat = 2
    public static let tagPadH: CGFloat = 8
    public static let summaryGap: CGFloat = 2
    public static let avatarGap: CGFloat = 12
    public static let headerGap: CGFloat = 8
    public static let iconButton: CGFloat = 44
}

func kitAgentRadius(_ size: CGFloat) -> CGFloat { (size * KitMetrics.agentRadiusRatio).rounded() }

func kitPersonInitial(_ size: CGFloat) -> CGFloat {
    switch size {
    case KitMetrics.avatar18: KitMetrics.initial8
    case KitMetrics.avatar28: KitMetrics.initial12
    case KitMetrics.avatar36: KitMetrics.initial15
    case KitMetrics.avatar44: KitMetrics.initial17
    case KitMetrics.avatar52: KitMetrics.initial22
    case KitMetrics.avatar72: KitMetrics.initial28
    default: max(1, (size * KitMetrics.agentRadiusRatio).rounded())
    }
}

func kitAgentGlyph(_ size: CGFloat) -> CGFloat {
    switch size {
    case KitMetrics.avatar18: KitMetrics.glyph10
    case KitMetrics.avatar28: KitMetrics.glyph16
    case KitMetrics.avatar36: KitMetrics.glyph21
    case KitMetrics.avatar44: KitMetrics.glyph24
    case KitMetrics.avatar52: KitMetrics.glyph28
    case KitMetrics.avatar72: KitMetrics.glyph40
    case KitMetrics.approvalAvatar: KitMetrics.glyph14
    default: (size * KitMetrics.lineTight).rounded()
    }
}
