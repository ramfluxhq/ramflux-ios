// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
import FeatureChat
import RFLocalization
public enum FeatureMlsGroupsStrings {
    public static func text(_ key: String, locale: Locale = .current) -> String {
        CatalogLookup.text(key, bundle: .module, locale: locale)
    }
    public static func format(_ key: String, _ arguments: CVarArg..., locale: Locale = .current) -> String {
        CatalogLookup.format(key, arguments, bundle: .module, locale: locale)
    }
    public static func sentence(_ key: String, _ arguments: [RFTextArgument], locale: Locale = .current) -> String {
        CatalogLookup.sentence(key, arguments, bundle: .module, locale: locale)
    }
}

/// Text of the join sheet and the group screens that is not a plain catalog lookup. Typed refusals use the catalog; names
/// are bidi-isolated; nothing here shows or logs a link.
public enum MlsGroupsText {
    static func dateTime(_ millis: Int64, locale: Locale) -> String {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000).formatted(.dateTime.month().day().hour().minute().locale(locale))
    }
    /// Minutes under one hour, otherwise hours.
    static func duration(_ seconds: Int, locale: Locale) -> String {
        let minutes = seconds < 3600
        let value = minutes ? max(1, (seconds + 59) / 60) : max(1, (seconds + 3599) / 3600)
        return Duration.seconds(value * (minutes ? 60 : 3600)).formatted(Duration.UnitsFormatStyle(allowedUnits: minutes ? [.minutes] : [.hours], width: .wide).locale(locale))
    }
    public static func refusal(_ refusal: MlsJoinRefusal, locale: Locale) -> String {
        switch refusal {
        case .linkInvalid: FeatureMlsGroupsStrings.text("group.join.refused.linkInvalid", locale: locale)
        case .inviteInvalid: FeatureMlsGroupsStrings.text("group.join.refused.inviteInvalid", locale: locale)
        case .queueFull: FeatureMlsGroupsStrings.text("group.join.refused.queueFull", locale: locale)
        case .inviteExpired(let at): at.map { FeatureMlsGroupsStrings.format("group.join.refused.inviteExpired", dateTime($0, locale: locale), locale: locale) } ?? FeatureMlsGroupsStrings.text("group.join.refused.generic", locale: locale)
        case .groupFull: FeatureMlsGroupsStrings.text("group.join.refused.groupFull", locale: locale)
        case .requestExpired: FeatureMlsGroupsStrings.text("group.join.refused.requestExpired", locale: locale)
        case .alreadyMember: FeatureMlsGroupsStrings.text("group.join.refused.alreadyMember", locale: locale)
        case .rateLimited(let seconds): FeatureMlsGroupsStrings.format("group.join.refused.rateLimited", duration(seconds ?? 10, locale: locale), locale: locale)
        case .unknown: FeatureMlsGroupsStrings.text("group.join.refused.generic", locale: locale)
        }
    }
    /// The line of a join outcome; `groupName` is the name from `group.info` once known.
    public static func outcome(_ outcome: MlsJoinOutcome, groupName: String?, locale: Locale) -> String {
        switch outcome {
        case .joined:
            if let groupName, !groupName.isEmpty { FeatureMlsGroupsStrings.sentence("group.join.joined", [.untrusted(groupName)], locale: locale) }
            else { FeatureMlsGroupsStrings.text("group.join.joinedUnnamed", locale: locale) }
        case .pending(_, let reason, let expires):
            switch reason {
            case .awaitingMemberOnline: FeatureMlsGroupsStrings.format("group.join.pending.online", dateTime(expires, locale: locale), locale: locale)
            default: FeatureMlsGroupsStrings.format("group.join.pending.admin", dateTime(expires, locale: locale), locale: locale)
            }
        case .refused(let value, _): refusal(value, locale: locale)
        case .failed(let error): MlsChatText.error(error, locale: locale)
        }
    }
    public static func approvalHelp(_ on: Bool, locale: Locale) -> String {
        FeatureMlsGroupsStrings.text(on ? "group.create.approvalOnHelp" : "group.create.approvalOffHelp", locale: locale)
    }
    public static func push(_ value: MlsPush, locale: Locale) -> String {
        switch value {
        case .mentionsReplies: FeatureMlsGroupsStrings.text("group.push.mentionsReplies", locale: locale)
        case .all: FeatureMlsGroupsStrings.text("group.push.all", locale: locale)
        case .none: FeatureMlsGroupsStrings.text("group.push.none", locale: locale)
        case .unknown: FeatureMlsGroupsStrings.text("group.push.mentionsReplies", locale: locale)
        }
    }
    /// The create sheet's name check: trimmed, 1 to 64 grapheme clusters.
    public enum NameCheck: Equatable, Sendable { case ok(String), empty, tooLong }
    public static func checkName(_ raw: String) -> NameCheck {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        return name.count > 64 ? .tooLong : .ok(name)
    }
}
