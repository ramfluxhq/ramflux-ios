// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// Onboarding and unlock, drawn to boards MOB-S01 (splash), S02 (get started, 2026-11-16 revision), S18
/// (welcome), N01 (create account), A01 (continue with an existing identity), A02 (unlock an existing
/// account) and A07 (device unlock information). Steps without a board (node address and identity, the
/// recovery phrase, the six-digit code, recovery, completion) use the same page frame from the Kit.
public struct OnboardingScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    public let securePresentation: AnyView?
    public let state: OnboardingState
    public let onAction: (OnboardingAction) -> Void
    public init(state: OnboardingState, onAction: @escaping (OnboardingAction) -> Void, securePresentation: AnyView? = nil) { self.state = state; self.onAction = onAction; self.securePresentation = securePresentation }
    public var body: some View {
        Group {
            if state.showingUnlockInfo { unlockInfo }
            else {
                switch state.stage {
                case .launch: splash
                case .connection: getStarted
                case .welcome: welcome
                case .start: existingIdentity
                case .create: createAccount
                case .localUnlock where state.unlockingSavedAccount: unlockExisting
                default: page(title: state.stage.title(locale: locale)) { content } footer: { footer }
                }
            }
        }
        .rfFont(.body)
        .foregroundStyle(theme.text)
        .tint(theme.primary)
        .privacySensitive()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(state.stage.board)
        #if os(iOS)
        // Steps with a Kit header carry their own back control; the system one would be a second.
        .navigationBarBackButtonHidden(Self.drawsOwnBack(state))
        #endif
    }

    /// Whether the current step draws a Kit page header with a back control (every step but the
    /// splash, get started and welcome boards, which keep the system back control).
    static func drawsOwnBack(_ state: OnboardingState) -> Bool {
        state.showingUnlockInfo || ![.launch, .connection, .welcome].contains(state.stage)
    }

    // MARK: Board pages

    /// MOB-S01: the app mark, the wordmark, the signature and the starting status, above the centre.
    private var splash: some View {
        VStack(spacing: OnboardingMetrics.splashGap) {
            BrandMark(letter: copy("onboarding.brand.letter"))
            BrandWordmark(text: copy("common.appName"), size: OnboardingMetrics.splashWordmark)
            BrandSignature().frame(width: OnboardingMetrics.signatureWidth * 0.75, alignment: .leading)
            HStack(spacing: KitMetrics.headerGap) {
                KitIcon(name: "loader-circle", size: KitMetrics.iconInfo, tint: theme.secondary)
                Text(copy("onboarding.s01.starting")).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.bottom, OnboardingMetrics.splashLift)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
    }

    /// MOB-S02: the brand, the purpose, the selected node and "change node", then Continue.
    private var getStarted: some View {
        start(top: OnboardingMetrics.startTop, signature: 30, purpose: copy("onboarding.s02.purpose")) {
            selectedNodeCard
            KitRow(copy("onboarding.s02.changeNode"), action: { onAction(.customNode) }, icon: "network", value: copy("onboarding.s02.changeNode.detail"), enabled: !state.busy, tag: "s02-change-node")
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_card))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius_card))
        } footer: {
            KitButton(copy("onboarding.complete.continue"), action: { onAction(.getStarted) }, enabled: !state.busy, tag: "s02-continue")
        }
    }

    /// MOB-S18: the brand and the three account choices; restoring a backup stays one tap away.
    private var welcome: some View {
        start(top: OnboardingMetrics.welcomeTop, signature: 40, purpose: copy("onboarding.welcome.primaryDevice"), footerBottom: OnboardingMetrics.welcomeFooterBottom) {
            // Not on the board, which has no backup entry; kept in the board's empty middle so the choices stay in place.
            KitButton(copy("onboarding.welcome.restoreBackup"), action: { onAction(.restoreBackup) }, kind: .text, size: .compact, enabled: !state.busy, tag: "s18-restore-backup")
        } footer: {
            VStack(spacing: KitMetrics.headerGap) {
                KitButton(copy("onboarding.create.title"), action: { onAction(.create) }, enabled: !state.busy, tag: "s18-create")
                KitButton(copy("onboarding.s18.existing"), action: { onAction(.existingAccount) }, kind: .secondary, enabled: !state.busy, tag: "s18-existing")
                KitButton(copy("onboarding.s18.recover"), action: { onAction(.recover) }, kind: .text, enabled: !state.busy, tag: "s18-recover")
            }
        }
    }

    /// MOB-A01: node and account are confirmed separately; unlock an account stored on this phone.
    private var existingIdentity: some View {
        page(title: copy("onboarding.a01.header"), heading: copy("onboarding.a01.heading")) {
            card {
                VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                    Text(copy("onboarding.n01.node.selected")).rfFont(.size(theme.size_mobile_body))
                    if let node = selectedNode { Text(untrusted: node.origin).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary).lineLimit(2) }
                    else { Text(copy("onboarding.node.noneConfirmed")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary) }
                }
                .padding(.horizontal, KitMetrics.gutter).padding(.vertical, KitMetrics.headerGap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kitHairlineDivider(theme.line)
                KitRow(copy("onboarding.s02.changeNode"), action: { onAction(.customNode) }, icon: "network", value: copy("onboarding.a01.changeNode.detail"), enabled: !state.busy, tag: "a01-change-node")
            }
            infoLine(copy("onboarding.a01.local"), info: { onAction(.unlockInfo(true)) }, tag: "a01-info")
            card {
                KitRow(copy("onboarding.a01.unauthorized"), action: { onAction(.link) }, icon: "shield-check", value: copy("onboarding.a01.unauthorized.detail"), enabled: !state.busy, tag: "a01-link")
            }
            Text(copy("onboarding.a01.noAccount")).rfFont(.size(theme.size_meta)).foregroundStyle(theme.secondary)
        } footer: {
            KitButton(copy("onboarding.welcome.unlockSaved"), action: { onAction(.unlockExisting) }, enabled: !state.busy, tag: "a01-unlock")
        }
    }

    /// MOB-A02: unlock an account stored on this phone with its six-digit code, on this phone only.
    private var unlockExisting: some View {
        page(title: copy("onboarding.welcome.unlockSaved"), heading: nil) {
            if let name = state.knownAccountName {
                VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                    Text(copy("onboarding.a02.knownAccount")).rfFont(.size(theme.size_meta)).foregroundStyle(theme.secondary)
                    Text(untrusted: name).rfFont(.size(theme.size_mobile_body), weight: .semibold).foregroundStyle(theme.text).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("a02-known-account")
            } else {
                KitTextField(value: Binding(get: { state.recoveryAccount }, set: { onAction(.recoveryAccountChanged($0)) }), label: copy("onboarding.localUnlock.accountID"), enabled: !state.busy, tag: "a02-account")
            }
            infoLine(copy("onboarding.a02.localOnly"), info: { onAction(.unlockInfo(true)) }, tag: "a02-info")
            VStack(alignment: .leading, spacing: KitMetrics.headerGap) {
                #if os(iOS)
                SecureOnboardingForm(fields: unlockFields, accountCode: .existing, enabled: !state.busy && !state.confirmationConsumed) { onAction(.submit($0)) }
                    .frame(minHeight: theme.composer_min * 3)
                #else
                Text(copy("common.secureInput.hostRequired"))
                #endif
                Text(copy("onboarding.accountCode.local")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
            }
            .padding(KitMetrics.gutter).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_card))
            if state.failure == .accountCode(.attemptsExhausted) || state.failure == .accountCode(.deviceUnlockUnavailable) {
                KitButton(copy("onboarding.stage.recover"), action: { onAction(.recover) }, kind: .secondary, enabled: !state.busy, tag: "a02-recover")
            }
            // The SDK refused this account for a reason other than the code: offer to remove it from this phone.
            if state.confirmingForget {
                Text(copy("onboarding.a02.forget.fact")).rfFont(.size(theme.size_body)).foregroundStyle(theme.text)
                KitButton(copy("onboarding.a02.forget.confirm"), action: { onAction(.confirmForget(true)) }, kind: .destructive, enabled: !state.busy, tag: "a02-forget-confirm")
                KitButton(copy("onboarding.a02.forget.keep"), action: { onAction(.confirmForget(false)) }, kind: .text, enabled: !state.busy, tag: "a02-forget-keep")
            } else if state.knownAccountName != nil, let failure = state.failure, !failure.isAccountCodeEntry {
                KitButton(copy("onboarding.a02.forget"), action: { onAction(.forgetKnownAccount) }, kind: .secondary, enabled: !state.busy, tag: "a02-forget")
            }
        } footer: {
            KitButton(copy("onboarding.a02.info"), action: { onAction(.unlockInfo(true)) }, kind: .secondary, enabled: !state.busy, tag: "a02-unlock-info")
        }
    }

    /// MOB-A07: how unlocking works on this phone (the six-digit account code).
    private var unlockInfo: some View {
        page(title: copy("onboarding.a07.header"), heading: nil, back: { onAction(.unlockInfo(false)) }) {
            Text(copy("onboarding.a07.intro")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
            card {
                infoRow("lock-keyhole", "onboarding.a07.code", "onboarding.a07.code.detail")
                infoRow("smartphone", "onboarding.a07.local", "onboarding.a07.local.detail")
                infoRow("history", "onboarding.a07.forgot", "onboarding.a07.forgot.detail")
            }
        } footer: {
            KitButton(copy("onboarding.a07.unlock"), action: { onAction(.unlockExisting) }, enabled: !state.busy, tag: "a07-unlock")
        }
    }

    /// MOB-N01: the display name, the selected node and the one-time phrase notice.
    private var createAccount: some View {
        let ready = !state.busy && !state.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedNode?.canCreateAccount == true
        return page(title: copy("onboarding.n01.header"), heading: nil, contentTop: OnboardingMetrics.sectionGap, spacing: theme.gap, footerBottom: OnboardingMetrics.createFooterBottom) {
            KitTextField(
                value: Binding(get: { state.name }, set: { onAction(.nameChanged($0)) }),
                label: copy("onboarding.n01.name"),
                note: copy("onboarding.n01.name.note"),
                enabled: !state.busy,
                tag: "n01-name"
            )
            Text(copy("onboarding.n01.node")).rfFont(.size(theme.size_secondary), weight: .semibold).foregroundStyle(theme.secondary)
            nodeCard
            KitTipBar(copy("onboarding.n01.phrase"), icon: "pencil-line", tag: "n01-phrase")
        } footer: {
            KitButton(copy("onboarding.n01.create"), action: { onAction(.beginCreation) }, enabled: ready, tag: "n01-create")
        }
    }

    // MARK: Frames

    /// The start boards (S02, S18): wordmark, signature, headline and purpose on the light page. At
    /// accessibility text sizes the actions scroll with the content instead of covering it.
    private func start(top: CGFloat, signature: CGFloat, purpose: String, footerBottom: CGFloat = OnboardingMetrics.footerBottom,
                       @ViewBuilder content: () -> some View, @ViewBuilder footer: () -> some View) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: OnboardingMetrics.sectionGap) {
                    BrandWordmark(text: copy("common.appName"), size: OnboardingMetrics.wordmark)
                    BrandSignature(height: signature)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(copy("onboarding.welcome.headline.first"))
                        Text(copy("onboarding.welcome.headline.second"))
                    }
                    .rfFont(.size(theme.size_title), weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                    Text(purpose).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
                    content()
                    status
                    if typeSize.isAccessibilitySize { footer() }
                }
                .padding(.horizontal, KitMetrics.gutter).padding(.top, top).padding(.bottom, KitMetrics.gutter)
                .frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity)
            }
            if !typeSize.isAccessibilitySize { footer().padding(.horizontal, KitMetrics.gutter).padding(.bottom, footerBottom).frame(maxWidth: theme.column_max) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
    }

    /// A page with the Kit header (back cancels setup unless `back` is given), an optional heading, the
    /// content, and actions pinned above the home indicator (A01, A02, A07, N01 and the steps without a board);
    /// at accessibility text sizes the actions scroll with the content.
    private func page(title: String, heading: String? = nil, contentTop: CGFloat = OnboardingMetrics.contentTop, spacing: CGFloat = KitMetrics.headerGap,
                      footerBottom: CGFloat = OnboardingMetrics.footerBottom, back: (() -> Void)? = nil,
                      @ViewBuilder _ content: () -> some View, @ViewBuilder footer: () -> some View) -> some View {
        VStack(spacing: 0) {
            KitPageHeader(title, onBack: back ?? { onAction(.cancel) }, tag: "onboarding-header")
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    if let heading { Text(heading).rfFont(.page, weight: .semibold).accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true) }
                    content()
                    status
                    if typeSize.isAccessibilitySize { footer() }
                }
                .padding(.horizontal, KitMetrics.gutter).padding(.top, contentTop).padding(.bottom, KitMetrics.gutter)
                .frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !typeSize.isAccessibilitySize { footer().padding(.horizontal, KitMetrics.gutter).padding(.bottom, footerBottom).frame(maxWidth: theme.column_max) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.nav.ignoresSafeArea())
    }
    @ViewBuilder private var status: some View {
        if state.busy { ProgressView(copy("onboarding.busy")) }
        if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
    }
    private func card(@ViewBuilder _ rows: () -> some View) -> some View {
        VStack(spacing: 0) { rows() }
            .frame(maxWidth: .infinity)
            .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius_card))
    }
    /// A section line with an information button (A01, A02).
    private func infoLine(_ title: String, info: @escaping () -> Void, tag: String) -> some View {
        HStack(spacing: 0) {
            Text(title).rfFont(.size(theme.size_body), weight: .semibold).frame(maxWidth: .infinity, alignment: .leading)
            KitInfoButton(label: copy("onboarding.a02.info"), tag: tag, action: info)
        }
        .frame(minHeight: OnboardingMetrics.infoLine)
    }
    /// An information row of A07: icon tile, title and detail, 76 pt high, not a control.
    private func infoRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: KitMetrics.rowGap) {
            KitIconTile(icon: icon)
            VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                Text(copy(title)).rfFont(.size(theme.size_mobile_body))
                Text(copy(detail)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, KitMetrics.gutter).padding(.vertical, OnboardingMetrics.infoRowPad)
        .frame(maxWidth: .infinity, minHeight: OnboardingMetrics.infoRow)
        .kitHairlineDivider(theme.line)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("a07-" + icon)
    }
    /// The selected node on S02: the official node or the confirmed origin, with its check mark.
    @ViewBuilder private var selectedNodeCard: some View {
        HStack(spacing: KitMetrics.rowGap) {
            VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                if let node = selectedNode {
                    if node.isDefault { Text(copy("onboarding.s02.official")).rfFont(.size(theme.size_mobile_body), weight: .semibold) }
                    else { Text(untrusted: node.origin).rfFont(.size(theme.size_mobile_body), weight: .semibold).lineLimit(2) }
                    Text(copy(node.isDefault ? "onboarding.s02.official.detail" : "onboarding.n01.node.selected")).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
                } else {
                    Text(copy("onboarding.node.noneConfirmed")).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if selectedNode != nil { KitIcon(name: "circle-check", size: KitMetrics.iconAction, tint: theme.text) }
        }
        .padding(.horizontal, KitMetrics.gutter)
        .frame(maxWidth: .infinity, minHeight: OnboardingMetrics.selectedCard)
        .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
        .overlay { RoundedRectangle(cornerRadius: theme.radius_card).strokeBorder(theme.text, lineWidth: KitMetrics.stroke) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("s02-node")
    }
    private var selectedNode: NodeRecord? { state.nodes.first { $0.id == state.selectedNodeID } }
    @ViewBuilder private var nodeCard: some View {
        if let node = selectedNode, node.canCreateAccount {
            HStack(spacing: KitMetrics.rowGap) {
                KitIconTile(icon: "server")
                VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                    Text(node.isDefault ? copy("onboarding.n01.node.official") : node.origin)
                        .rfFont(.size(theme.size_mobile_body))
                        .foregroundStyle(theme.text)
                    Text(copy("onboarding.n01.node.selected"))
                        .rfFont(.size(theme.size_secondary))
                        .foregroundStyle(theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KitIcon(name: "chevron-right", size: KitMetrics.chevron, tint: theme.control)
                    .opacity(KitMetrics.disabledAlpha)
            }
            .padding(.horizontal, KitMetrics.gutter)
            .frame(maxWidth: .infinity)
            .frame(height: KitMetrics.row)
            .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
            .accessibilityIdentifier("n01-node")
        } else {
            nodeChoices
        }
    }
    private func copy(_ key: String) -> String { FeatureOnboardingStrings.text(key, locale: locale) }

    // MARK: Steps without a board

    @ViewBuilder private var content: some View {
        switch state.stage {
        case .welcome, .launch, .start, .connection, .create:
            EmptyView()
        case .address, .defaultNode:
            Text(copy("onboarding.address.instructions")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
            KitTextField(value: Binding(get: { state.address }, set: { onAction(.addressChanged($0)) }), label: copy("onboarding.address.field"), placeholder: copy("onboarding.address.placeholder"), enabled: !state.busy, tag: "onboarding-address")
                .rfAddressInput()
        case .normalizedAddress, .checkingAddress:
            if let normalized = state.normalized {
                card {
                    LabeledContent(copy("onboarding.address.entered"), value: normalized.entered).padding(KitMetrics.gutter).kitHairlineDivider(theme.line)
                    LabeledContent(copy("onboarding.address.normalized"), value: normalized.origin).textSelection(.enabled).padding(KitMetrics.gutter)
                }
                if normalized.changed { KitTipBar(copy("onboarding.address.originOnly"), icon: "info", tag: "onboarding-origin-only") }
            }
        case .identity:
            if let candidate = state.candidate {
                card { Text(untrusted: candidate.origin).textSelection(.enabled).padding(KitMetrics.gutter).frame(maxWidth: .infinity, alignment: .leading) }
                if let fingerprint = state.visibleNodeFingerprint {
                    Text(copy("node.fingerprintInstructions")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
                    KitIdentifierText(fingerprint, tag: "onboarding-node-fingerprint").textSelection(.enabled)
                    RFHostConfirmationActions(summary: FeatureOnboardingStrings.sentence("node.confirmFingerprint.summary", [.untrusted(candidate.origin), .identifier(fingerprint)], locale: locale), enabled: !state.busy, cancelEnabled: !state.busy, confirm: { onAction(.saveNode) }, cancel: { onAction(.expectedNodeKeyChanged("")) }).id(fingerprint)
                } else {
                    Text(copy("node.operatorInstructions")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
                    KitTextField(value: Binding(get: { state.expectedNodeKey }, set: { onAction(.expectedNodeKeyChanged($0)) }), label: copy("node.operatorKey"), enabled: !state.busy, tag: "onboarding-operator-key")
                        .rfAddressInput()
                }
            }
        case .saved:
            KitTipBar(copy("onboarding.node.saved.message"), icon: "circle-check", tag: "onboarding-node-saved")
        case .savePhrase:
            KitSecurityWarning(copy("onboarding.stage.savePhrase"), body: copy("onboarding.phrase.keepPrivate"), tone: .warning, icon: "shield-alert", tag: "onboarding-phrase-warning")
            if state.displayID != nil {
                #if os(iOS)
                securePresentation
                    .padding(KitMetrics.gutter).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
                #else
                Text(copy("onboarding.phrase.hostRequired"))
                #endif
            }
        case .confirmPhrase:
            Text(copy("onboarding.confirmPhrase.instructions")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
            card {
                ForEach(state.positions, id: \.self) { position in
                    KitRow(FeatureOnboardingStrings.format("recovery.word.position", position.formatted(.number.locale(locale)), locale: locale), icon: "list-checks", trailing: .none, enabled: false, tag: "onboarding-word-\(position)")
                }
            }
            KitTipBar(copy("onboarding.phrase.erased"), icon: "eye", tag: "onboarding-phrase-erased")
        case .localUnlock:
            Text(copy("onboarding.localUnlock.instructions")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
            #if os(iOS)
            SecureOnboardingForm(fields: unlockFields, accountCode: .new, enabled: !state.busy && !state.confirmationConsumed) { onAction(.submit($0)) }
                .frame(minHeight: theme.composer_min * 7)
            Text(copy("onboarding.accountCode.local")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
            if state.failure == .accountCode(.attemptsExhausted) || state.failure == .accountCode(.deviceUnlockUnavailable) {
                KitButton(copy("onboarding.stage.recover"), action: { onAction(.recover) }, kind: .secondary, enabled: !state.busy, tag: "onboarding-recover")
            }
            #else
            Text(copy("common.secureInput.hostRequired"))
            #endif
        case .recover:
            if let metadata = state.metadata, let anchor = metadata.anchor {
                card { KitIdentifierText(anchor, tag: "onboarding-recover-fingerprint").textSelection(.enabled).padding(KitMetrics.gutter).frame(maxWidth: .infinity, alignment: .leading) }
                KitSecurityWarning(copy("onboarding.recover.fingerprint"), body: copy("onboarding.recover.warning"), tone: .danger, tag: "onboarding-recover-warning")
                Toggle(copy("onboarding.recover.fingerprintChecked"), isOn: Binding(get: { state.anchorChecked }, set: { onAction(.checkAnchor($0)) }))
                #if os(iOS)
                SecureOnboardingForm(fields: [RFSecureEntryField(id: "phrase", label: copy("onboarding.recover.phrase")), RFSecureEntryField(id: "passphrase", label: copy("onboarding.accountCode.existing"), kind: .accountCode)], accountCode: .existing, enabled: state.anchorChecked && !state.busy && !state.confirmationConsumed) { onAction(.submit($0)) }.frame(minHeight: theme.composer_min * 4)
                #endif
            } else {
                Text(copy("onboarding.recover.scope")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
                if state.recoversLockedAccount {
                    // Inside the lock cover the account is the locked one: shown, not editable, and no other entry.
                    VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                        Text(copy("onboarding.recover.accountID")).rfFont(.size(theme.size_meta)).foregroundStyle(theme.secondary)
                        KitIdentifierText(state.recoveryAccount, color: theme.secondary, tag: "onboarding-recover-locked-account")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                } else {
                    KitTextField(value: Binding(get: { state.recoveryAccount }, set: { onAction(.recoveryAccountChanged($0)) }), label: copy("onboarding.recover.accountID"), enabled: !state.busy, tag: "onboarding-recover-account")
                    card {
                        KitRow(copy("onboarding.welcome.restoreBackup"), action: { onAction(.restoreBackup) }, icon: "database-backup", value: copy("onboarding.recover.newInstall"), enabled: !state.busy, tag: "onboarding-restore-backup")
                    }
                }
            }
        case .complete:
            if let account = state.completedAccount {
                card {
                    VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                        Text(untrusted: account.displayName).rfFont(.page, weight: .semibold)
                        KitIdentifierText(account.id, color: theme.secondary)
                        Text(copy(account.networking == .live ? "onboarding.complete.connected" : state.watchingNetwork ? "onboarding.complete.connecting" : "onboarding.complete.notConnected"))
                            .rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
                            .accessibilityIdentifier("onboarding-complete-network")
                    }
                    .padding(KitMetrics.gutter).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .link:
            KitStatusHero(icon: "link", tag: "onboarding-link")
            Text(copy("onboarding.link.unavailable")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary)
        case .verifying, .restoring, .saving: ProgressView(state.stage.title(locale: locale))
        case .connectionFailed, .verificationFailed, .saveFailed, .configuration, .offline:
            KitTipBar(copy("onboarding.connection.preserved"), icon: "info", tag: "onboarding-connection-preserved")
        }
    }
    /// The pinned action of each step without a board; the same action the step offered before.
    @ViewBuilder private var footer: some View {
        switch state.stage {
        case .address, .defaultNode: primary(copy("onboarding.address.check"), .checkAddress)
        case .normalizedAddress, .checkingAddress: if state.normalized != nil { primary(copy("onboarding.address.connect"), .inspectOrigin) }
        case .identity:
            if state.visibleNodeFingerprint != nil { secondary(copy("node.editOperatorKey"), .expectedNodeKeyChanged("")) }
            else if state.candidate != nil { primary(copy("node.reviewFingerprint"), .reviewNodeKey) }
        case .saved:
            VStack(spacing: KitMetrics.headerGap) { primary(copy("onboarding.create.title"), .create); secondary(copy("onboarding.node.useAsDefault"), .setDefault) }
        case .savePhrase:
            if state.displayID != nil { primary(copy("onboarding.phrase.hideAndContinue"), .hidePhrase) } else { primary(copy("onboarding.phrase.showOnce"), .showPhrase) }
        case .confirmPhrase: primary(copy("onboarding.stage.localUnlock"), .continueUnlock)
        case .recover: if state.metadata?.anchor == nil { primary(copy("onboarding.recover.readFingerprint"), .beginRecovery) }
        case .complete: primary(copy("onboarding.complete.continue"), .done)
        case .connectionFailed, .verificationFailed, .saveFailed, .configuration, .offline: primary(copy("onboarding.connection.editAddress"), .customNode)
        default: EmptyView()
        }
    }
    #if os(iOS)
    private var unlockFields: [RFSecureEntryField] {
        if state.unlockingSavedAccount { return [RFSecureEntryField(id: "passphrase", label: copy("onboarding.accountCode.existing"), kind: .accountCode)] }
        let words = state.positions.enumerated().map { RFSecureEntryField(id: "word\($0.offset + 1)", label: FeatureOnboardingStrings.format("recovery.word.position", $0.element.formatted(.number.locale(locale)), locale: locale)) }
        return words + [RFSecureEntryField(id: "passphrase", label: copy("onboarding.accountCode.new"), kind: .accountCode),
                        RFSecureEntryField(id: "passphraseRepeat", label: copy("onboarding.accountCode.repeat"), kind: .accountCode)]
    }
    #endif
    @ViewBuilder private var nodeChoices: some View {
        if state.nodes.isEmpty { Text(copy("onboarding.node.noneConfirmed")).rfFont(.size(theme.size_body)).foregroundStyle(theme.secondary) }
        card {
            ForEach(state.nodes) { node in
                KitRow(RFUntrustedText.clean(node.origin), action: { onAction(.nodeSelected(node.id)) }, icon: "server", trailing: state.selectedNodeID == node.id ? .check : .none,
                       enabled: node.canCreateAccount && !state.busy, tag: "onboarding-node-" + node.id)
            }
            KitRow(copy("onboarding.node.other"), action: { onAction(.customNode) }, icon: "network", enabled: !state.busy, tag: "onboarding-node-other")
        }
    }
    private func primary(_ title: String, _ action: OnboardingAction) -> some View {
        KitButton(title, action: { onAction(action) }, enabled: !state.busy, tag: title)
    }
    private func secondary(_ title: String, _ action: OnboardingAction) -> some View {
        KitButton(title, action: { onAction(action) }, kind: .secondary, enabled: !state.busy, tag: title)
    }
}

private extension View {
    /// The divider between two parts of one card.
    func kitHairlineDivider(_ color: Color) -> some View { overlay(alignment: .bottom) { Rectangle().fill(color).frame(height: KitMetrics.hairline) } }
}
