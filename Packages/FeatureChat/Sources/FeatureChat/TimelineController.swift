// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import AppData
import FeatureCards
import RFDesign

/// The chat timeline: a UIKit table keyed by stable row ids, anchored to the bottom.
///
/// - Short conversations sit at the bottom edge above the composer (top inset fills the gap).
/// - New rows keep the view pinned to the bottom when it was at the bottom; otherwise the first
///   visible row keeps its screen position, so prepending an older page never jumps.
/// - Measured row heights are cached per id, width and text size and used as estimates, which
///   keeps prepends and self-sizing stable.
/// - Reaching the top asks for the next older page; displaying an incoming row reports it so the
///   view model can mark the conversation read.
@MainActor public final class TimelineController: UITableViewController {
    public var onAction: (ChatAction) -> Void = { _ in }
    private var theme: RFTheme = .light
    private var locale: Locale = .current
    private var isGroup = false
    private var olderAvailable = false
    private var entries: [String: TimelineItem] = [:]
    private var previous: [TimelineItem] = []
    private var source: UITableViewDiffableDataSource<Int, String>?
    private var revision: UInt64 = 0
    private var heights: [String: CGFloat] = [:]
    private var heightContext: String = ""
    private var requestedOlderAt: Int?
    var presentationRevision: UInt64 { revision }
    public override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.keyboardDismissMode = .interactive
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        source = UITableViewDiffableDataSource(tableView: tableView) { [weak self] table, path, id in
            let cell = table.dequeueReusableCell(withIdentifier: "row", for: path)
            cell.backgroundColor = .clear; cell.selectionStyle = .none
            if let self, let item = self.entries[id] {
                let isGroup = self.isGroup, theme = self.theme, locale = self.locale
                cell.contentConfiguration = UIHostingConfiguration { [weak self] in
                    TimelineRow(item: item, isGroup: isGroup, onAction: { action in self?.onAction(action) }).environment(\.rfTheme, theme).environment(\.locale, locale)
                }.margins(.all, 0)
            }
            return cell
        }
    }
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        anchorToBottom()
    }
    /// Pads the top so that content shorter than the viewport rests on the bottom edge.
    private func anchorToBottom() {
        let visible = tableView.bounds.height - tableView.adjustedContentInset.bottom - (tableView.adjustedContentInset.top - tableView.contentInset.top)
        let gap = max(0, visible - tableView.contentSize.height)
        if abs(tableView.contentInset.top - gap) > 0.5 { tableView.contentInset.top = gap }
    }
    public func update(_ messages: [MessageRecord], outbox: [OutboxEntry] = [], theme: RFTheme = .light, locale: Locale = .current, isGroup: Bool = false, unreadAnchorID: String? = nil, olderAvailable: Bool = false, loadingOlder: Bool = false, media: [String: MediaTransferState] = [:], revealed: Set<String> = [], cards: [String: SurfaceCardState] = [:], agentAuthors: Set<String> = []) {
        let items = TimelineProjection.items(messages, outbox: outbox, calendar: .current, unreadAnchorID: unreadAnchorID, loadingOlder: loadingOlder, media: media, revealed: revealed, cards: cards, agentAuthors: agentAuthors)
        loadViewIfNeeded()
        self.olderAvailable = olderAvailable
        if !loadingOlder { requestedOlderAt = nil }
        guard previous != items || self.theme != theme || self.locale != locale || self.isGroup != isGroup, let source else { return }
        let presentationChanged = self.theme != theme || self.locale != locale || self.isGroup != isGroup
        self.theme = theme; self.locale = locale; self.isGroup = isGroup
        let nearBottom = previous.isEmpty || tableView.contentOffset.y + tableView.bounds.height >= tableView.contentSize.height + tableView.adjustedContentInset.bottom - 60
        let anchor = tableView.indexPathsForVisibleRows?.sorted().first { source.itemIdentifier(for: $0) != TimelineItem.history.id }
        let anchorID = anchor.flatMap { source.itemIdentifier(for: $0) }
        let anchorY = anchor.map { tableView.rectForRow(at: $0).minY - tableView.contentOffset.y }
        let old = entries
        entries = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        previous = items
        if presentationChanged { heights.removeAll() }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0]); snapshot.appendItems(items.map(\.id), toSection: 0)
        let changed = items.filter { old[$0.id] != nil && (presentationChanged || old[$0.id] != $0) }.map(\.id)
        for id in changed { heights[id] = nil }
        EventDiagnostics.note("timeline update items=\(items.count) reconfigured=\(changed.count)")
        snapshot.reconfigureItems(changed)
        revision &+= 1; let current = revision
        source.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self, self.revision == current else { return }
            self.tableView.layoutIfNeeded()
            self.anchorToBottom()
            if nearBottom, let last = items.last, let path = source.indexPath(for: last.id) {
                self.tableView.scrollToRow(at: path, at: .bottom, animated: false)
            } else if let anchorID, let path = source.indexPath(for: anchorID), let anchorY {
                self.tableView.contentOffset.y = self.tableView.rectForRow(at: path).minY - anchorY
            }
        }
    }
    private var context: String { "\(Int(tableView.bounds.width))|\(traitCollection.preferredContentSizeCategory.rawValue)" }
    public override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        if heightContext != context { heights.removeAll(); heightContext = context }
        guard let id = source?.itemIdentifier(for: indexPath) else { return 80 }
        return heights[id] ?? 80
    }
    public override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let id = source?.itemIdentifier(for: indexPath) else { return }
        if heightContext != context { heights.removeAll(); heightContext = context }
        heights[id] = cell.bounds.height
        if case .message(let record, _)? = entries[id], record.isOwn != true { onAction(.displayed(record.id)) }
        if olderAvailable, indexPath.row < 8, requestedOlderAt == nil, !previous.isEmpty {
            requestedOlderAt = indexPath.row
            onAction(.loadOlder)
        }
    }
}
#endif
