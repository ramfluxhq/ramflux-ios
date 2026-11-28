// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

// The timeline of one MLS group (common 3.3): a bounded, deduplicated window of posts keyed by `(group_id, log_seq)`,
// the own posts that are not yet posted, and the projection into rows and service lines. Pure value types: the session
// owns them, the views only read snapshots.

/// A name as a service line shows it: `display`, or "Member" when nil, or "You" for the own account.
public struct MlsActorName: Equatable, Sendable {
    public let display: String?
    public let isMe: Bool
    public let aiFlag: Bool
    public init(display: String?, isMe: Bool, aiFlag: Bool = false) { self.display = display; self.isMe = isMe; self.aiFlag = aiFlag }
}

/// A centred line of the group timeline. `device_added` and `device_removed` never become lines.
public struct MlsServiceLine: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case joined([MlsActorName]), left([MlsActorName])
        case removed(by: MlsActorName?, target: MlsActorName), banned(by: MlsActorName?, target: MlsActorName)
        case roleAdmin(by: MlsActorName?, target: MlsActorName), roleMember(by: MlsActorName?, target: MlsActorName)
        case name(by: MlsActorName?, MlsGroupName), approvalOn(by: MlsActorName?), approvalOff(by: MlsActorName?)
        case void, updated
    }
    public let id: String
    public let kind: Kind
    public init(id: String, kind: Kind) { self.id = id; self.kind = kind }
}

/// A group name inside a service line (untrusted text).
public struct MlsGroupName: Equatable, Sendable { public let text: String; public init(_ text: String) { self.text = text } }

public enum MlsNotSentReason: Equatable, Sendable {
    case error(MlsGroupError)
    case rateLimited(MlsQuota)
    case failed(String)
}

/// An own post that is not posted yet. `localID` is a client-made UUID; a post found in history (r4 item 8) uses `post:<post_id>`.
public struct MlsPendingPost: Equatable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum State: Equatable, Sendable {
        case submitting
        case queued(MlsQueueReason)
        case delayed(sendAfter: Int64)
        case notSent(MlsNotSentReason)
    }
    public var id: String { localID }
    public let localID: String
    public let groupID: String
    public let text: String
    public let replyTo: String?
    public let mentions: [String]
    public var postID: String?
    public var state: State
    public init(localID: String, groupID: String, text: String, replyTo: String?, mentions: [String], postID: String? = nil, state: State) { self.localID = localID; self.groupID = groupID; self.text = text; self.replyTo = replyTo; self.mentions = mentions; self.postID = postID; self.state = state }
    public var description: String { "MlsPendingPost" }
    public var debugDescription: String { description }
    public var canRetry: Bool { if case .notSent = state { true } else { false } }
}

/// A posted row of the timeline: a text, attachment or card post, or a tombstone.
public struct MlsPostRow: Equatable, Sendable, Identifiable {
    public var id: String { post.postID }
    public let post: MlsPost
    public let isMine: Bool
    public let isDeleted: Bool
    /// Own posted rows only (they have a `log_seq`).
    public let canDelete: Bool
    public let deleting: Bool
    public let authorIsAgent: Bool
}

public enum MlsTimelineEntry: Equatable, Sendable, Identifiable {
    case post(MlsPostRow)
    case service(MlsServiceLine)
    case pending(MlsPendingPost)
    /// "Earlier messages are not available on this device".
    case floor
    public var id: String {
        switch self {
        case .post(let row): "post:" + row.id
        case .service(let line): "service:" + line.id
        case .pending(let pending): "pending:" + pending.localID
        case .floor: "floor"
        }
    }
}

public struct MlsTimelineSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case loading, ready, failed(MlsGroupError) }
    public var groupID: String
    public var entries: [MlsTimelineEntry] = []
    public var phase: Phase = .loading
    public var olderAvailable = false
    public var loadingOlder = false
    public var detached = false
    public var readOnly: MlsReadOnly?
    /// Unix milliseconds until which the composer is off after a daily limit with nothing left; nil when it is on.
    public var composerOffUntil: Int64?
    /// The error of the last explicit action on the group (delete), until the view clears it.
    public var actionError: MlsGroupError?
    public var newestLogSeq: Int64 = 0
    public init(groupID: String) { self.groupID = groupID }
}

/// The mutable store behind a snapshot.
struct MlsTimelineStore {
    static let window = 600
    var groupID = ""
    var posts: [Int64: MlsPost] = [:]
    var byPostID: [String: Int64] = [:]
    var pending: [MlsPendingPost] = []
    var floor: Int64 = 0
    var last: Int64 = 0
    var olderMore = false
    var loadingOlder = false
    var loaded = false
    var phase: MlsTimelineSnapshot.Phase = .loading
    var detached = false
    var filling = false
    var fillQueued = false
    var deleting: Set<String> = []
    var tombstoned: Set<String> = []
    var readOnly: MlsReadOnly?
    var composerOffUntil: Int64?
    var actionError: MlsGroupError?
    var seenSeq: [Int64] = []

    var oldest: Int64? { posts.keys.min() }

    /// Inserts or merges one posted row. Returns true when it is new to the window.
    @discardableResult mutating func insert(_ post: MlsPost) -> Bool {
        if post.state == .deleted { tombstoned.insert(post.postID) }
        guard let seq = post.logSeq else {
            // An own unsent post from history (r4 item 8): keyed by `post_id`.
            if byPostID[post.postID] == nil, !pending.contains(where: { $0.postID == post.postID }) {
                var text = ""
                if case .text(let value) = post.body { text = value }
                pending.append(MlsPendingPost(localID: "post:" + post.postID, groupID: groupID, text: text, replyTo: post.replyTo, mentions: post.mentions, postID: post.postID, state: Self.pendingState(post.state)))
            }
            return false
        }
        pending.removeAll { $0.postID == post.postID }
        if let existing = posts[seq] {
            // The same slot: keep the first row, but a deletion always wins.
            if post.state == .deleted && existing.state != .deleted { posts[seq] = post }
            byPostID[post.postID] = seq
            return false
        }
        posts[seq] = post; byPostID[post.postID] = seq
        last = max(last, seq)
        return true
    }
    static func pendingState(_ state: MlsPostState) -> MlsPendingPost.State {
        switch state {
        case .pending(.some(.queued(let reason))): .queued(reason)
        case .pending(.some(.delayed(let after, _))): .delayed(sendAfter: after)
        case .queued(let reason): .queued(reason)
        case .delayed(let after): .delayed(sendAfter: after)
        case .failed(let reason): .notSent(.failed(reason))
        default: .queued(.unknown(""))
        }
    }
    /// Keeps at most `window` posts by dropping from the far end.
    mutating func trim(dropping end: End) {
        let excess = posts.count - Self.window
        guard excess > 0 else { return }
        let keys = posts.keys.sorted()
        let dropped = end == .oldest ? keys.prefix(excess) : keys.suffix(excess)
        for key in dropped { if let post = posts.removeValue(forKey: key) { byPostID[post.postID] = nil } }
        if end == .oldest { olderMore = true } else { detached = true; last = posts.keys.max() ?? last }
    }
    enum End { case oldest, newest }
    mutating func noteSeq(_ seq: Int64) -> Bool {
        if seenSeq.contains(seq) { return false }
        seenSeq.append(seq); if seenSeq.count > 256 { seenSeq.removeFirst(64) }
        return true
    }
}

enum MlsTimelineProjection {
    static let maxCollapsed = 500

    struct Context { let isMe: (MlsAuthor) -> Bool; let isAI: (MlsAuthor) -> Bool }

    static func name(_ author: MlsAuthor, _ context: Context) -> MlsActorName {
        MlsActorName(display: author.display, isMe: context.isMe(author), aiFlag: context.isAI(author))
    }

    /// The posted rows in `log_seq` order, with the membership lines collapsed (common 3.3 rule 6).
    static func entries(_ store: MlsTimelineStore, mine: (MlsPost) -> Bool, context: Context) -> [MlsTimelineEntry] {
        var out: [MlsTimelineEntry] = []
        if store.loaded, !store.olderMore, !store.posts.isEmpty { out.append(.floor) }
        for seq in store.posts.keys.sorted() {
            guard let post = store.posts[seq] else { continue }
            switch post.kind {
            case .text, .attachment, .card:
                let deleted = post.state == .deleted || store.tombstoned.contains(post.postID)
                let own = mine(post)
                out.append(.post(MlsPostRow(post: post, isMine: own, isDeleted: deleted, canDelete: own && !deleted && post.logSeq != nil, deleting: store.deleting.contains(post.postID) && !deleted, authorIsAgent: post.author.map(context.isAI) ?? false)))
            case .membership:
                guard case .membership(let changes, let by) = post.body else { continue }
                for line in membershipLines(changes, by: by, id: seq, context: context) { append(line, to: &out) }
            case .settings:
                guard case .settings(let name, let approval, let by) = post.body else { out.append(.service(MlsServiceLine(id: String(seq), kind: .updated))); continue }
                let actor = by.map { self.name($0, context) }
                var lines: [MlsServiceLine.Kind] = []
                if let name { lines.append(.name(by: actor, MlsGroupName(name))) }
                if let approval { lines.append(approval ? .approvalOn(by: actor) : .approvalOff(by: actor)) }
                if lines.isEmpty { lines = [.updated] }
                for (index, kind) in lines.enumerated() { out.append(.service(MlsServiceLine(id: "\(seq).\(index)", kind: kind))) }
            case .void: out.append(.service(MlsServiceLine(id: String(seq), kind: .void)))
            case .unknown: out.append(.service(MlsServiceLine(id: String(seq), kind: .updated)))
            }
        }
        for pending in store.pending { out.append(.pending(pending)) }
        return out
    }

    private static func membershipLines(_ changes: [MlsMembershipChange], by: MlsAuthor?, id: Int64, context: Context) -> [MlsServiceLine] {
        var joined: [MlsActorName] = [], left: [MlsActorName] = []
        var lines: [MlsServiceLine] = []
        for (index, change) in changes.enumerated() {
            let target = name(change.actor, context)
            let actor = by.map { name($0, context) }
            switch change.change {
            case .joined: if joined.count < maxCollapsed { joined.append(target) }
            case .left: if left.count < maxCollapsed { left.append(target) }
            case .removed: lines.append(MlsServiceLine(id: "\(id).r\(index)", kind: .removed(by: actor, target: target)))
            case .banned: lines.append(MlsServiceLine(id: "\(id).b\(index)", kind: .banned(by: actor, target: target)))
            case .roleChanged:
                switch change.role {
                case .some(.admin): lines.append(MlsServiceLine(id: "\(id).a\(index)", kind: .roleAdmin(by: actor, target: target)))
                case .some(.member): lines.append(MlsServiceLine(id: "\(id).m\(index)", kind: .roleMember(by: actor, target: target)))
                default: lines.append(MlsServiceLine(id: "\(id).u\(index)", kind: .updated))
                }
            case .deviceAdded, .deviceRemoved: break
            case .unknown: lines.append(MlsServiceLine(id: "\(id).x\(index)", kind: .updated))
            }
        }
        var result: [MlsServiceLine] = []
        if !joined.isEmpty { result.append(MlsServiceLine(id: "\(id).j", kind: .joined(joined))) }
        if !left.isEmpty { result.append(MlsServiceLine(id: "\(id).l", kind: .left(left))) }
        return result + lines
    }

    /// Appends a service line; a joined (or left) line directly after another one of the same kind merges into it.
    private static func append(_ line: MlsServiceLine, to out: inout [MlsTimelineEntry]) {
        if case .service(let previous)? = out.last {
            switch (previous.kind, line.kind) {
            case (.joined(let a), .joined(let b)): out[out.count - 1] = .service(MlsServiceLine(id: previous.id, kind: .joined(Array((a + b).prefix(maxCollapsed))))); return
            case (.left(let a), .left(let b)): out[out.count - 1] = .service(MlsServiceLine(id: previous.id, kind: .left(Array((a + b).prefix(maxCollapsed))))); return
            default: break
            }
        }
        out.append(.service(line))
    }
}
