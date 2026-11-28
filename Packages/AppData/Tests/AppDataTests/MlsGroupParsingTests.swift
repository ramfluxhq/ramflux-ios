// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import RamfluxCore
@testable import AppData

private func json(_ text: String) -> JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .null }

struct MlsGroupParsingTests {
    @Test func listAndInfoShapesParse() {
        let page = MlsGroupParsing.list(json(#"{"groups":[{"group_id":"g1","name":"Design","tier":1000,"members":12,"leaves":12,"agents":1,"approval":true,"my_role":"owner","host_node":"node.example","push":"mentions_replies","catch_up":{"state":"running","done":40,"total":120},"privacy_delay":{"send_after":null},"quota":{"post":{"limit":20,"remaining":3,"first_day":true,"resets_at":99},"commit":{"limit":5,"remaining":5,"first_day":false}},"last_log_seq":260,"warnings":[{"code":"host_ip_visible","params":{"host_node":"node.example"}}],"last_activity_at":1700,"unread":3,"unread_mentions":1,"read_log_seq":257,"last_post":{"log_seq":260,"kind":"text","author":{"anchor":"a1","display":"Ana","ai_flag":false,"is_me":false},"snippet":"hi","appended_at":1700}}],"cursor":"l2"}"#))
        #expect(page.cursor == "l2")
        let row = page.groups[0]
        #expect(row.name == "Design" && row.myRole == .owner && row.agents == 1 && row.catchUp == MlsCatchUp(state: .running, done: 40, total: 120))
        #expect(row.privacyDelay == .armed && row.postQuota?.remaining == 3 && row.visibleHost == "node.example")
        #expect(row.unread == 3 && row.unreadMentions == 1 && row.readLogSeq == 257 && row.lastPost?.snippet == "hi")
        #expect(MlsGroupParsing.info(json(#"{"group_id":"g2","name":"x","privacy_delay":null,"my_role":"banana","push":"all"}"#))?.privacyDelay == MlsPrivacyDelay.none)
        #expect(MlsGroupParsing.info(json(#"{"group_id":"g2","name":"x","my_role":"banana"}"#))?.myRole == .unknown("banana"))
        #expect(MlsGroupParsing.info(json(#"{"group_id":"g2","privacy_delay":{"send_after":1234}}"#))?.privacyDelay == .waiting(sendAfter: 1234))
        #expect(MlsGroupParsing.info(json(#"{"name":"no id"}"#)) == nil)
    }
    @Test func aGroupNameOver64CharactersIsTruncated() {
        let long = String(repeating: "x", count: 80)
        #expect(MlsGroupParsing.info(json(#"{"group_id":"g","name":"\#(long)"}"#))?.name.count == 64)
    }
    @Test func createAndInviteShapesParse() throws {
        let created = try #require(MlsGroupParsing.created(json(#"{"group_id":"g","invite":{"invite_id":"i1","link":"rfinv-x","max_uses":100,"uses_left":100,"expires_at":5}}"#)))
        #expect(created.invite.usesLeft == 100 && created.invite.link == "rfinv-x")
        let listed = MlsGroupParsing.invites(json(#"{"invites":[{"invite_id":"i1","link":"rfinv-x","max_uses":10,"uses_left":null,"expires_at":5,"revoked":true}]}"#))
        #expect(listed.count == 1 && listed[0].usesLeft == nil && listed[0].revoked)
    }
    @Test func aLinkIsNeverPrinted() throws {
        let created = try #require(MlsGroupParsing.created(json(#"{"group_id":"g","invite":{"invite_id":"i1","link":"rfinv-secret-token","max_uses":1,"expires_at":5}}"#)))
        for text in [String(describing: created), String(reflecting: created), "\(created.invite)", String(reflecting: created.invite)] { #expect(!text.contains("rfinv-secret-token")); #expect(text.contains("link=<redacted>")) }
    }
    @Test func joinResultsAndEveryRefusalParse() {
        #expect(MlsGroupParsing.join(json(#"{"state":"joined","group_id":"g"}"#)) == .joined(groupID: "g"))
        #expect(MlsGroupParsing.join(json(#"{"state":"pending","request_id":"r","reason":"awaiting_admin","expires_at":9}"#)) == .pending(requestID: "r", reason: .awaitingAdmin, expiresAt: 9))
        #expect(MlsGroupParsing.join(json(#"{"state":"pending","request_id":"r","reason":"awaiting_member_online","expires_at":9}"#)) == .pending(requestID: "r", reason: .awaitingMemberOnline, expiresAt: 9))
        let cases: [(String, String, MlsJoinRefusal)] = [
            ("link_invalid", "{}", .linkInvalid), ("invite_invalid", "{}", .inviteInvalid), ("queue_full", "{}", .queueFull),
            ("invite_expired", #"{"expired_at":7}"#, .inviteExpired(expiredAt: 7)), ("group_full", #"{"leaf_cap":3000}"#, .groupFull),
            ("request_expired", #"{"expired_at":8}"#, .requestExpired(expiredAt: 8)), ("already_member", #"{"group_id":"g"}"#, .alreadyMember(groupID: "g")),
            ("rate_limited", #"{"retry_after_s":10}"#, .rateLimited(retryAfterSeconds: 10)), ("banana", "{}", .unknown("banana")),
            // The reasons r4 removed are unknown now.
            ("invite_unknown", "{}", .unknown("invite_unknown")), ("invite_used_up", "{}", .unknown("invite_used_up")), ("invite_revoked", "{}", .unknown("invite_revoked")),
        ]
        for (reason, params, expected) in cases {
            #expect(MlsGroupParsing.join(json(#"{"state":"refused","reason":"\#(reason)","params":\#(params)}"#)) == .refused(expected))
        }
        #expect(MlsGroupParsing.join(json(#"{"state":"weird"}"#)) == nil)
    }
    @Test func membersParseWithTheNullNameRule() {
        let page = MlsGroupParsing.members(json(#"{"rows":[{"anchor":"a1","display":null,"role":"admin","ai_flag":true,"devices":2,"is_me":false},{"anchor":"a2","display":"Ben","role":"member","ai_flag":false,"devices":1,"is_me":true}],"cursor":"p2"}"#))
        #expect(page.cursor == "p2" && page.rows.count == 2)
        #expect(page.rows[0].display == nil && page.rows[0].aiFlag && page.rows[0].role == .admin && page.rows[0].devices == 2)
        #expect(page.rows[1].isMe)
    }
    @Test func historyRowsOfEveryKindParse() {
        let page = MlsGroupParsing.history(json(#"""
        {"posts":[
          {"log_seq":1,"post_id":"p1","author":{"anchor":"a1","display":"Ana","ai_flag":false,"is_me":false},"appended_at":10,"kind":"text","body":"hello","mentions":["a2"],"state":"sent"},
          {"log_seq":2,"post_id":"p2","author":{"anchor":"a1","display":null,"ai_flag":true,"is_me":false},"kind":"text","body":"gone","state":"deleted"},
          {"log_seq":3,"post_id":"p3","kind":"membership","body":{"changes":[{"change":"joined","anchor":"a3","display":"Chen","ai_flag":false,"is_me":false},{"change":"removed","anchor":"a4","display":null,"ai_flag":false,"is_me":true}],"by":{"anchor":"a1","display":"Ana","ai_flag":false,"is_me":false}},"state":"sent"},
          {"log_seq":4,"post_id":"p4","kind":"settings","body":{"name":"New","approval":false,"by":{"anchor":"a1","display":"Ana","ai_flag":false,"is_me":false}},"state":"sent"},
          {"log_seq":5,"post_id":"p5","kind":"void","body":{"voided_log_seq":4,"epoch":3,"by":{"anchor":"a1","display":"Ana","ai_flag":false,"is_me":false}},"state":"sent"},
          {"log_seq":6,"post_id":"p6","author":{"anchor":"a1","display":"Ana","ai_flag":false,"is_me":false},"kind":"poll","body":{},"state":"sent"},
          {"log_seq":null,"post_id":"p7","author":{"anchor":"a9","display":"Me","ai_flag":false,"is_me":true},"appended_at":null,"kind":"text","body":"unsent","state":"pending","send":{"state":"delayed_privacy","params":{"send_after":99,"delay_s":5}}}
        ],"floor_log_seq":1,"last_log_seq":6,"more":true}
        """#))
        #expect(page.posts.count == 7 && page.floorLogSeq == 1 && page.lastLogSeq == 6 && page.more)
        #expect(page.posts[0].body == .text("hello") && page.posts[0].mentions == ["a2"])
        #expect(page.posts[1].state == .deleted)
        if case .membership(let changes, let by) = page.posts[2].body { #expect(changes.count == 2 && changes[1].isMe && by?.display == "Ana") } else { Issue.record("membership") }
        #expect(page.posts[2].author == nil)
        #expect(page.posts[3].body == .settings(name: "New", approval: false, by: MlsAuthor(anchor: "a1", display: "Ana")))
        if case .void(let voided, _) = page.posts[4].body { #expect(voided == 4) } else { Issue.record("void") }
        #expect(page.posts[5].kind == .unknown("poll"))
        #expect(page.posts[6].logSeq == nil && page.posts[6].state == .pending(.delayed(sendAfter: 99, delaySeconds: 5)))
    }
    @Test func sendStatesParse() {
        #expect(MlsGroupParsing.send(json(#"{"post_id":"p","state":"sent","params":{"log_seq":4}}"#))?.state == .sent(logSeq: 4))
        #expect(MlsGroupParsing.send(json(#"{"post_id":"p","state":"queued","params":{"reason":"catching_up"}}"#))?.state == .queued(.catchingUp))
        #expect(MlsGroupParsing.send(json(#"{"post_id":"p","state":"queued","params":{"reason":"host_unreachable"}}"#))?.state == .queued(.hostUnreachable))
        #expect(MlsGroupParsing.send(json(#"{"post_id":"p","state":"queued","params":{"reason":"fetching_tokens"}}"#))?.state == .queued(.fetchingTokens))
        #expect(MlsGroupParsing.send(json(#"{"post_id":"p","state":"delayed_privacy","params":{"send_after":5000,"delay_s":90}}"#))?.state == .delayed(sendAfter: 5000, delaySeconds: 90))
        #expect(MlsGroupParsing.send(json(#"{"post_id":"p","state":"rate_limited","params":{"bucket":"post","limit":20,"remaining":0,"first_day":true,"resets_at":8}}"#))?.state == .rateLimited(MlsQuota(limit: 20, remaining: 0, firstDay: true, resetsAt: 8)))
        #expect(MlsGroupParsing.send(json(#"{"post_id":"p","state":"parked"}"#))?.state == .unknown("parked"))
        #expect(MlsGroupParsing.send(json(#"{"state":"sent"}"#)) == nil)
    }
    @Test func deleteLeaveRefreshReadAndPendingShapesParse() {
        #expect(MlsGroupParsing.deleteOutcome(json(#"{"post_id":"p","state":"deleted","log_seq":9}"#)) == .deleted(logSeq: 9))
        #expect(MlsGroupParsing.deleteOutcome(json(#"{"post_id":"p","state":"queued","params":{"reason":"catching_up"}}"#)) == .queued(.catchingUp))
        #expect(MlsGroupParsing.deleteOutcome(json(#"{"post_id":"p","state":"delayed_privacy","params":{"send_after":7,"delay_s":1}}"#)) == .delayed(sendAfter: 7))
        #expect(MlsGroupParsing.commit(json(#"{"state":"committed","log_seq":3}"#)) == MlsCommit(logSeq: 3))
        #expect(MlsGroupParsing.commit(json(#"{"state":"other"}"#)) == nil)
        #expect(MlsGroupParsing.refresh(json(#"{"groups":[{"group_id":"g","last_log_seq":5,"new_posts":2}]}"#)) == [MlsRefreshRow(groupID: "g", lastLogSeq: 5, newPosts: 2)])
        #expect(MlsGroupParsing.readState(json(#"{"read_log_seq":5,"unread":0,"unread_mentions":0}"#)) == MlsReadState(readLogSeq: 5, unread: 0, unreadMentions: 0))
        let pending = MlsGroupParsing.pendingJoins(json(#"{"requests":[{"request_id":"r","group_id":"g","host_node":"node.example","reason":"awaiting_admin","requested_at":1,"expires_at":2}]}"#))
        #expect(pending.count == 1 && pending[0].reason == .awaitingAdmin && pending[0].groupID == "g")
    }
    @Test func everyEventKindParses() {
        let author = #"{"anchor":"a1","display":"Ana","ai_flag":false,"is_me":false}"#
        if case .post(let group, let seq, _, let post) = MlsGroupParsing.event(json(#"{"seq":7,"at":1,"group_id":"g","kind":"post","log_seq":3,"post":{"log_seq":3,"post_id":"p","author":\#(author),"kind":"text","body":"x","state":"sent"}}"#)) { #expect(group == "g" && seq == 7 && post.logSeq == 3) } else { Issue.record("post") }
        if case .postState(_, let id, let state, let seq) = MlsGroupParsing.event(json(#"{"seq":8,"group_id":"g","kind":"post_state","post_id":"p","state":"sent","params":{"log_seq":4},"log_seq":4}"#)) { #expect(id == "p" && state == .sent && seq == 4) } else { Issue.record("post_state") }
        if case .postDeleted(_, let id, let postSeq, let seq) = MlsGroupParsing.event(json(#"{"seq":9,"group_id":"g","kind":"post_deleted","post_id":"p","post_log_seq":3,"log_seq":5}"#)) { #expect(id == "p" && postSeq == 3 && seq == 5) } else { Issue.record("post_deleted") }
        if case .membership(_, _, _, let post) = MlsGroupParsing.event(json(#"{"seq":10,"group_id":"g","kind":"membership","log_seq":6,"changes":[{"change":"left","anchor":"a2","display":null,"ai_flag":false,"is_me":true}]}"#)) {
            if case .membership(let changes, _) = post.body { #expect(changes.first?.isMe == true && changes.first?.change == .left) } else { Issue.record("body") }
        } else { Issue.record("membership") }
        if case .settings = MlsGroupParsing.event(json(#"{"seq":11,"group_id":"g","kind":"settings","log_seq":7,"approval":true,"by":\#(author)}"#)) {} else { Issue.record("settings") }
        #expect(MlsGroupParsing.event(json(#"{"seq":12,"group_id":"g","kind":"join_result","request_id":"r","state":"refused","reason":"request_expired","params":{"expired_at":3}}"#)) == .joinResult(MlsJoinEvent(requestID: "r", groupID: "g", outcome: .refused(.requestExpired(expiredAt: 3)))))
        #expect(MlsGroupParsing.event(json(#"{"seq":13,"group_id":"g","kind":"join_result","request_id":"r","state":"joined"}"#)) == .joinResult(MlsJoinEvent(requestID: "r", groupID: "g", outcome: .joined)))
        #expect(MlsGroupParsing.event(json(#"{"seq":14,"group_id":"g","kind":"read","read_log_seq":4,"unread":2,"unread_mentions":1}"#)) == .read(groupID: "g", readLogSeq: 4, unread: 2, unreadMentions: 1))
        for skipped in ["pending_join", "catch_up", "warning", "void", "banana"] { #expect(MlsGroupParsing.event(json(#"{"seq":1,"group_id":"g","kind":"\#(skipped)"}"#)) == .ignored) }
    }
    @Test func everyErrorCodeMaps() {
        let codes: [(String, MlsGroupError)] = [("not_member", .notMember), ("not_admin", .notAdmin), ("owner_protected", .ownerProtected), ("tier_unavailable", .tierUnavailable), ("group_full", .groupFull), ("paced", .paced(retryAt: nil)), ("rate_limited", .rateLimited), ("rejoin_needed", .rejoinNeeded), ("too_large", .tooLarge(maxBytes: nil)), ("host_unreachable", .hostUnreachable), ("unknown_invite", .unknownInvite), ("request_not_found", .requestNotFound), ("message_not_found", .messageNotFound), ("not_author", .notAuthor), ("void_not_head", .voidNotHead(headLogSeq: nil))]
        for (code, expected) in codes { #expect(MlsGroupParsing.error(code: code) == expected) }
        #expect(MlsGroupParsing.error(code: "paced", details: json(#"{"retry_at":5}"#)) == .paced(retryAt: 5))
        #expect(MlsGroupParsing.error(code: "too_large", details: json(#"{"max_bytes":65536}"#)) == .tooLarge(maxBytes: 65_536))
        #expect(MlsGroupParsing.error(code: "banana") == nil)
        let frame = CoreFailure(code: 3, typedName: nil, response: json(#"{"error":{"code":"too_large","details":{"max_bytes":10}}}"#))
        #expect(MlsGroupParsing.error(frame) == .tooLarge(maxBytes: 10))
        #expect(MlsGroupParsing.error(CoreFailure(code: 3, response: json(#"{"error":{"code":"banana"}}"#))) == .generic("banana"))
    }
    @Test func theLinkCheckTrimsOnlyAndRejectsTheRest() {
        #expect(MlsLinkCheck.trimmed("  rfinv-x\n") == "rfinv-x")
        #expect(MlsLinkCheck.trimmed("") == nil)
        #expect(MlsLinkCheck.trimmed("with space") == nil)
        #expect(MlsLinkCheck.trimmed(String(repeating: "a", count: 512)) != nil)
        #expect(MlsLinkCheck.trimmed(String(repeating: "a", count: 513)) == nil)
        #expect(MlsLinkCheck.trimmed("caf\u{E9}") == nil)
    }

    // MARK: M3 shapes (common 2.2 to 2.7, assumptions Q1 to Q9)
    @Test func requestsPageParsesRowsAndTheCursor() {
        let page = MlsGroupParsing.requests(json(#"{"requests":[{"request_id":"rq-1","anchor":"a1","display":"Ana","ai_flag":false,"requested_at":10,"expires_at":20},{"request_id":"rq-2","anchor":"a2","display":null,"ai_flag":true,"requested_at":11,"expires_at":21},{"anchor":"no-id"}],"cursor":"r2"}"#))
        #expect(page.rows.count == 2 && page.cursor == "r2")
        #expect(page.rows[0].display == "Ana" && page.rows[1].display == nil && page.rows[1].aiFlag && page.rows[0].expiresAt == 20)
        #expect(MlsGroupParsing.requests(json(#"{}"#)).rows.isEmpty)
    }
    @Test func requestTypesNeverPrintTheirIdentifiers() {
        let row = MlsJoinRequest(requestID: "rq-secret", anchor: "anchor-secret", display: "Name")
        for text in [String(describing: row), String(reflecting: row), { var out = ""; dump(row, to: &out); return out }(), String(describing: MlsAdminTarget.request("rq-secret")), { var out = ""; dump(MlsAdminTarget.member("anchor-secret"), to: &out); return out }()] {
            #expect(!text.contains("rq-secret") && !text.contains("anchor-secret") && !text.contains("Name"))
        }
    }
    @Test func adminOutcomesAndPushAndCatchUpResultsParse() {
        #expect(MlsGroupParsing.adminOutcome(json(#"{"state":"committed","log_seq":301}"#)) == .committed(logSeq: 301))
        #expect(MlsGroupParsing.adminOutcome(json(#"{"state":"declined"}"#)) == .declined)
        #expect(MlsGroupParsing.adminOutcome(json(#"{"state":"banana"}"#)) == nil)
        #expect(MlsGroupParsing.pushResult(json(#"{"push":"all"}"#)) == .all)
        #expect(MlsGroupParsing.pushResult(json(#"{}"#)) == nil)
        #expect(MlsGroupParsing.catchUpResult(json(#"{"state":"rejoining"}"#)) == .rejoining)
        #expect(MlsGroupParsing.catchUpResult(json(#"{"state":"running","done":4,"total":9}"#)) == .running(done: 4, total: 9))
        #expect(MlsGroupParsing.catchUpResult(json(#"{"state":"idle"}"#)) == .idle)
        #expect(MlsGroupParsing.catchUpResult(json(#"{"state":"x"}"#)) == nil)
    }
    @Test func m3ErrorsCarryTheirDetails() {
        #expect(MlsGroupParsing.error(code: "not_admin", details: json(#"{"required":"owner"}"#)) == .notOwner)
        #expect(MlsGroupParsing.error(code: "not_admin", details: json(#"{"required":"admin"}"#)) == .notAdmin)
        #expect(MlsGroupParsing.error(code: "not_admin") == .notAdmin)
        #expect(MlsGroupParsing.error(code: "paced", details: json(#"{"retry_at":99}"#)) == .paced(retryAt: 99))
        #expect(MlsGroupParsing.error(code: "void_not_head", details: json(#"{"head_log_seq":252}"#)) == .voidNotHead(headLogSeq: 252))
        let frame = CoreFailure(code: 3, response: json(#"{"error":{"code":"not_admin","details":{"required":"owner"}}}"#))
        #expect(MlsGroupParsing.error(frame) == .notOwner)
    }
    @Test func everyWarningCodeParsesWithItsParams() {
        func code(_ text: String) -> MlsWarningCode? { MlsGroupParsing.warning(json(text))?.code }
        #expect(code(#"{"code":"fork_alarm","params":{"head_n":2}}"#) == .forkAlarm(headN: 2))
        for (raw, reason) in [("pruned", MlsRejoinReason.pruned), ("gate_rejected", .gateRejected), ("apply_failed", .applyFailed), ("welcome_expired", .welcomeExpired), ("state_lost", .stateLost), ("banana", .unknown("banana"))] {
            #expect(code(#"{"code":"rejoin_needed","params":{"reason":"\#(raw)"}}"#) == .rejoinNeeded(reason))
        }
        #expect(code(#"{"code":"undecryptable","params":{"count":12,"from_log_seq":140}}"#) == .undecryptable(count: 12, fromLogSeq: 140))
        #expect(code(#"{"code":"admission_needs_online"}"#) == .admissionNeedsOnline)
        #expect(code(#"{"code":"host_unusual","params":{"kind":"late_roll"}}"#) == .hostUnusual(.lateRoll))
        #expect(code(#"{"code":"host_unusual","params":{"kind":"late_reply"}}"#) == .hostUnusual(.lateReply))
        #expect(code(#"{"code":"head_commit_rejected","params":{"log_seq":250}}"#) == .headCommitRejected(logSeq: 250))
        #expect(code(#"{"code":"host_ip_visible","params":{"host_node":"node.example"}}"#) == .hostIpVisible(hostNode: "node.example"))
        #expect(code(#"{"code":"weird"}"#) == .unknown("weird"))
        #expect(MlsGroupParsing.warning(json(#"{"code":"fork_alarm","params":{"head_n":1},"cleared":true}"#))?.cleared == true)
        #expect(MlsGroupParsing.warning(json(#"{"params":{}}"#)) == nil)
    }
    @Test func m3EventsParseWithTheBodyNesting() {
        if case .pendingJoin(let group, let seq, let request) = MlsGroupParsing.event(json(#"{"seq":20,"group_id":"g","kind":"pending_join","body":{"request_id":"rq-9","anchor":"a9","display":"Fay","ai_flag":false,"requested_at":1,"expires_at":2}}"#)) { #expect(group == "g" && seq == 20 && request.requestID == "rq-9" && request.display == "Fay") } else { Issue.record("pending_join") }
        if case .pendingJoin(_, _, let request) = MlsGroupParsing.event(json(#"{"seq":21,"group_id":"g","kind":"pending_join","request_id":"rq-flat","anchor":"a8"}"#)) { #expect(request.requestID == "rq-flat") } else { Issue.record("flat pending_join") }
        #expect(MlsGroupParsing.event(json(#"{"seq":22,"group_id":"g","kind":"catch_up","body":{"state":"running","done":10,"total":120}}"#)) == .catchUp(groupID: "g", seq: 22, state: MlsCatchUp(state: .running, done: 10, total: 120)))
        #expect(MlsGroupParsing.event(json(#"{"seq":23,"group_id":"g","kind":"catch_up","body":{"state":"idle"}}"#)) == .catchUp(groupID: "g", seq: 23, state: MlsCatchUp(state: .idle)))
        #expect(MlsGroupParsing.event(json(#"{"seq":24,"group_id":"g","kind":"warning","body":{"code":"fork_alarm","params":{"head_n":2},"cleared":false}}"#)) == .warning(groupID: "g", seq: 24, warning: MlsWarning(code: .forkAlarm(headN: 2))))
        #expect(MlsGroupParsing.event(json(#"{"seq":25,"group_id":"g","kind":"warning","body":{"code":"fork_alarm","cleared":true}}"#)) == .warning(groupID: "g", seq: 25, warning: MlsWarning(code: .forkAlarm(headN: nil), cleared: true)))
    }
    @Test func aVoidParsesToTheSameRowAsAKindVoidEventAndAsAPostVoid() {
        let author = #"{"anchor":"a1","display":"Ana","ai_flag":false,"is_me":false}"#
        let asKind = MlsGroupParsing.event(json(#"{"seq":30,"group_id":"g","kind":"void","log_seq":251,"body":{"voided_log_seq":250,"epoch":4,"by":\#(author)}}"#))
        let asPost = MlsGroupParsing.event(json(#"{"seq":31,"group_id":"g","kind":"post","post":{"log_seq":251,"kind":"void","body":{"voided_log_seq":250,"epoch":4,"by":\#(author)}}}"#))
        guard case .post(_, _, _, let first) = asKind, case .post(_, _, _, let second) = asPost else { Issue.record("void events"); return }
        #expect(first == second)
        #expect(first.kind == .void && first.logSeq == 251 && first.postID == "log:251")
        if case .void(let voided, let by) = first.body { #expect(voided == 250 && by?.display == "Ana") } else { Issue.record("body") }
    }
    @Test func infoWarningsKeepTheirParams() {
        let info = MlsGroupParsing.info(json(#"{"group_id":"g","name":"G","warnings":[{"code":"host_ip_visible","params":{"host_node":"node.example"}},{"code":"undecryptable","params":{"count":3,"from_log_seq":7}}]}"#))
        #expect(info?.visibleHost == "node.example")
        #expect(info?.warnings.map(\.code) == [.hostIpVisible(hostNode: "node.example"), .undecryptable(count: 3, fromLogSeq: 7)])
    }
}
