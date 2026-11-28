// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

// The pure rules of the MLS admin and edge states (MLS-GUI M3, common 2.6, 2.7, 2.8, 3.7): the head-commit rule, the
// warning merge rule, the banner order, the quota and privacy-delay rules and the settings name check. No state here;
// the session and the screens call these so a rule has one definition.

/// Common 2.6: which commit row may be undone.
public enum MlsHeadCommit {
    /// The commit rows are the history rows of kind membership, settings and void. The entry shows on the one with the
    /// greatest `log_seq`, only while the newest page is loaded, only for the owner and admins, only in a group that is
    /// not read-only, and never on a void row or on a row a void already undid.
    public static func voidable(commits: [(seq: Int64, kind: MlsPostKind)], voided: Set<Int64>, detached: Bool, role: MlsRole, readOnly: Bool) -> Int64? {
        guard !detached, !readOnly, role == .owner || role == .admin else { return nil }
        guard let newest = commits.max(by: { $0.seq < $1.seq }), newest.kind != .void, !voided.contains(newest.seq) else { return nil }
        return newest.seq
    }
}

/// Common 2.7: the warnings of a group are a set keyed by code. An event sets or clears one code; a `group.info` result
/// replaces the set only when no event was applied after that read was issued, and otherwise merges only the codes the
/// events have not touched since.
public struct MlsWarningSet: Equatable, Sendable {
    public private(set) var codes: [String: MlsWarningCode] = [:]
    /// The generation at which an event last touched a code.
    private var touched: [String: Int] = [:]
    /// Counts the events applied to this set.
    public private(set) var generation = 0
    public init() {}

    /// One `warning` event: sets the code, or clears it.
    public mutating func apply(_ warning: MlsWarning) {
        generation += 1
        touched[warning.code.key] = generation
        if warning.cleared { codes[warning.code.key] = nil } else { codes[warning.code.key] = warning.code }
    }
    /// A code removed by another rule (approval on drops `admission_needs_online`, Q13) counts as an event.
    public mutating func drop(key: String) {
        generation += 1
        touched[key] = generation
        codes[key] = nil
    }
    /// A `group.info` result issued when the set was at `issued`.
    public mutating func applyInfo(_ rows: [MlsWarning], issued: Int) {
        var next: [String: MlsWarningCode] = [:]
        for row in rows where !row.cleared && (touched[row.code.key] ?? 0) <= issued { next[row.code.key] = row.code }
        for (key, code) in codes where (touched[key] ?? 0) > issued { next[key] = code }
        codes = next
    }
}

/// Common 3.7: the banners of a group chat and the info rows.
public struct MlsBanner: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case catchUp(MlsCatchUpView), warning(MlsWarningCode) }
    public enum Severity: Int, Equatable, Sendable { case critical, warning, info }
    public let kind: Kind
    public var id: String {
        switch kind { case .catchUp: "catchup"; case .warning(let code): code.name }
    }
    public var severity: Severity {
        switch kind {
        case .catchUp(let view): if case .rejoining = view { .critical } else { .warning }
        case .warning(let code):
            switch code {
            case .forkAlarm, .rejoinNeeded, .headCommitRejected: .critical
            case .undecryptable, .hostUnusual: .warning
            default: .info
            }
        }
    }
    /// `undecryptable`, `host_unusual` and `admission_needs_online` can be hidden for the session; the critical three cannot.
    public var canHide: Bool {
        if case .warning(let code) = kind {
            switch code { case .undecryptable, .hostUnusual, .admissionNeedsOnline: return true; default: return false }
        }
        return false
    }
    public init(kind: Kind) { self.kind = kind }
}

/// What a catch-up banner shows. `rejoining` follows the `rejoin_needed` reason when there is one.
public enum MlsCatchUpView: Equatable, Sendable {
    case running(done: Int, total: Int, skipping: Bool, error: MlsGroupError?)
    case rejoining(reason: MlsRejoinReason?)
}

public enum MlsBannerPlan {
    /// Banner order: `fork_alarm`, rejoining, `head_commit_rejected` (critical); running catch-up, `undecryptable`,
    /// `host_unusual` (warning); `admission_needs_online` (info). `rejoin_needed` shows as the rejoining catch-up banner,
    /// so it is never a second banner. `head_commit_rejected` is for the owner and admins only; hidden codes are left out.
    public static func banners(codes: [String: MlsWarningCode], catchUp: MlsCatchUpView?, role: MlsRole, hidden: Set<String>) -> [MlsBanner] {
        var out: [MlsBanner] = []
        func code(_ key: String) -> MlsWarningCode? { hidden.contains(key) ? nil : codes[key] }
        if let alarm = code("fork_alarm") { out.append(MlsBanner(kind: .warning(alarm))) }
        if case .rejoining? = catchUp, let catchUp { out.append(MlsBanner(kind: .catchUp(catchUp))) }
        if role == .owner || role == .admin, let rejected = code("head_commit_rejected") { out.append(MlsBanner(kind: .warning(rejected))) }
        if case .running? = catchUp, let catchUp { out.append(MlsBanner(kind: .catchUp(catchUp))) }
        for key in ["undecryptable", "host_unusual", "admission_needs_online"] { if let value = code(key) { out.append(MlsBanner(kind: .warning(value))) } }
        return out
    }
    /// The group info rows: every warning but `host_ip_visible` (the M2 row), hidden or not, in banner order, unknown codes last.
    public static func rows(codes: [String: MlsWarningCode], role: MlsRole) -> [MlsWarningCode] {
        var out: [MlsWarningCode] = []
        let order = ["fork_alarm", "rejoin_needed", "head_commit_rejected", "undecryptable", "host_unusual", "admission_needs_online"]
        for key in order {
            guard let value = codes[key] else { continue }
            if key == "head_commit_rejected", role != .owner, role != .admin { continue }
            out.append(value)
        }
        for key in codes.keys.sorted() where key.hasPrefix("unknown:") { if let value = codes[key] { out.append(value) } }
        return out
    }
    /// Banners shown at once: at most two, then "+N".
    public static let visibleLimit = 2
}

/// Common 2.8.
public enum MlsQuotaRule {
    /// The line shows on the first day, or when `remaining ≤ max(1, limit / 5)`.
    public static func shows(_ quota: MlsQuota) -> Bool { quota.firstDay || quota.remaining <= max(1, quota.limit / 5) }
}

public enum MlsPrivacyRule {
    /// The composer ETA: a `send_after` that is still in the future. A time in the past counts as `{send_after: null}`.
    public static func eta(_ delay: MlsPrivacyDelay, now: Int64) -> Int64? {
        if case .waiting(let after) = delay, after > now { return after }
        return nil
    }
    /// The info row shows for `{send_after: null}` and for any `send_after`.
    public static func showsInfo(_ delay: MlsPrivacyDelay) -> Bool { delay != .none }
}

public enum MlsAdminRules {
    /// Common 2.4: trimmed, 1 to 64 grapheme clusters.
    public enum NameCheck: Equatable, Sendable { case ok(String), empty, tooLong }
    public static func checkName(_ raw: String) -> NameCheck {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        return name.count > 64 ? .tooLong : .ok(name)
    }
}
