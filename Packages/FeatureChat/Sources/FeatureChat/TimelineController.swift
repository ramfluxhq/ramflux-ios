// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import AppData

@MainActor public final class TimelineController: UITableViewController {
    public var onAction: (ChatAction) -> Void = { _ in }
    private var entries: [String: MessageRecord] = [:]
    private var previous: [MessageRecord] = []
    private var source: UITableViewDiffableDataSource<Int, String>?
    private var revision: UInt64 = 0
    public override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.keyboardDismissMode = .interactive
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "message")
        source = UITableViewDiffableDataSource(tableView: tableView) { [weak self] table, path, id in
            let cell = table.dequeueReusableCell(withIdentifier: "message", for: path)
            cell.backgroundColor = .clear; cell.selectionStyle = .none
            if let record = self?.entries[id] { cell.contentConfiguration = UIHostingConfiguration { MessageBubble(message: record, onAction: { [weak self] action in self?.onAction(action) }) }.margins(.all, 0) }
            return cell
        }
    }
    public func update(_ messages: [MessageRecord]) {
        loadViewIfNeeded()
        guard previous != messages, let source else { return }
        let nearBottom = previous.isEmpty || tableView.contentOffset.y + tableView.bounds.height >= tableView.contentSize.height - 60
        let anchor = tableView.indexPathsForVisibleRows?.sorted().first
        let anchorID = anchor.flatMap { source.itemIdentifier(for: $0) }
        let anchorY = anchor.map { tableView.rectForRow(at: $0).minY - tableView.contentOffset.y }
        let old = entries
        entries = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        previous = messages
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0]); snapshot.appendItems(messages.map(\.id), toSection: 0)
        snapshot.reconfigureItems(messages.filter { old[$0.id] != nil && old[$0.id] != $0 }.map(\.id))
        revision &+= 1; let current = revision
        source.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self, self.revision == current else { return }
            self.tableView.layoutIfNeeded()
            if nearBottom, let last = messages.last, let path = source.indexPath(for: last.id) {
                self.tableView.scrollToRow(at: path, at: .bottom, animated: false)
            } else if let anchorID, let path = source.indexPath(for: anchorID), let anchorY {
                self.tableView.contentOffset.y = self.tableView.rectForRow(at: path).minY - anchorY
            }
        }
    }
}
#endif
