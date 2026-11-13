// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
// Generated forwarding methods; no business logic or payload schema.
public protocol A2IProxy: SDKProxyProtocol {}
public extension A2IProxy {
    func a2iAcknowledge(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.a2iAcknowledge, context: context, body: body)
    }
    func a2iAppend(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.a2iAppend, context: context, body: body)
    }
    func a2iList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.a2iList, context: context, body: body)
    }
    func a2iListPending(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.a2iListPending, context: context, body: body)
    }
}
public protocol A2UIProxy: SDKProxyProtocol {}
public extension A2UIProxy {
    func a2uiAction(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.a2uiAction, context: context, body: body)
    }
    func a2uiRender(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.a2uiRender, context: context, body: body)
    }
}
public protocol AccountProxy: SDKProxyProtocol {}
public extension AccountProxy {
    func accountBackupExport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField]) async throws -> JSONValue {
        try await performSecret(.accountBackupExport, context: context, body: body, secrets: secrets)
    }
    func accountBackupImport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField]) async throws -> JSONValue {
        try await performSecret(.accountBackupImport, context: context, body: body, secrets: secrets)
    }
    func accountConfigGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountConfigGet, context: context, body: body)
    }
    func accountConfigSet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountConfigSet, context: context, body: body)
    }
    func accountCreate(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountCreate, context: context, body: body)
    }
    func accountCreateBegin(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountCreateBegin, context: context, body: body)
    }
    func accountCreateCancel(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountCreateCancel, context: context, body: body)
    }
    func accountCreateConfirm(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField]) async throws -> JSONValue {
        try await performSecret(.accountCreateConfirm, context: context, body: body, secrets: secrets)
    }
    func accountCreateHiddenChallenge(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountCreateHiddenChallenge, context: context, body: body)
    }
    func accountCreateShowOnce(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountCreateShowOnce, context: context, body: body)
    }
    func accountExportAgentCredentials(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField]) async throws -> JSONValue {
        try await performSecret(.accountExportAgentCredentials, context: context, body: body, secrets: secrets)
    }
    func accountList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountList, context: context, body: body)
    }
    func accountLock(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountLock, context: context, body: body)
    }
    func accountPassphraseRotate(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField]) async throws -> JSONValue {
        try await performSecret(.accountPassphraseRotate, context: context, body: body, secrets: secrets)
    }
    func accountRecoverBegin(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountRecoverBegin, context: context, body: body)
    }
    func accountRecoverCancel(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountRecoverCancel, context: context, body: body)
    }
    func accountRecoverConfirm(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField]) async throws -> JSONValue {
        try await performSecret(.accountRecoverConfirm, context: context, body: body, secrets: secrets)
    }
    func accountStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountStatus, context: context, body: body)
    }
    func accountSwitch(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountSwitch, context: context, body: body)
    }
    func accountUnlock(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField]) async throws -> JSONValue {
        try await performSecret(.accountUnlock, context: context, body: body, secrets: secrets)
    }
}
public protocol BotProxy: SDKProxyProtocol {}
public extension BotProxy {
    func botInstall(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.botInstall, context: context, body: body)
    }
    func botList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.botList, context: context, body: body)
    }
    func botRevoke(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.botRevoke, context: context, body: body)
    }
    func botTrustAdd(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.botTrustAdd, context: context, body: body)
    }
}
public protocol BusProxy: SDKProxyProtocol {}
public extension BusProxy {
    func busSubscribe(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.busSubscribe, context: context, body: body)
    }
}
public protocol CallProxy: SDKProxyProtocol {}
public extension CallProxy {
    func callAnswer(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.callAnswer, context: context, body: body)
    }
    func callHangup(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.callHangup, context: context, body: body)
    }
    func callInvite(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.callInvite, context: context, body: body)
    }
    func callList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.callList, context: context, body: body)
    }
    func callMediaSession(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.callMediaSession, context: context, body: body)
    }
    func callReject(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.callReject, context: context, body: body)
    }
}
public protocol ContactProxy: SDKProxyProtocol {}
public extension ContactProxy {
    func contactAccept(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactAccept, context: context, body: body)
    }
    func contactAdd(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactAdd, context: context, body: body)
    }
    func contactBlock(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactBlock, context: context, body: body)
    }
    func contactCardExport(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactCardExport, context: context, body: body)
    }
    func contactCardImport(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactCardImport, context: context, body: body)
    }
    func contactDecline(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactDecline, context: context, body: body)
    }
    func contactList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactList, context: context, body: body)
    }
    func contactReject(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactReject, context: context, body: body)
    }
    func contactRejected(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactRejected, context: context, body: body)
    }
    func contactRemove(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactRemove, context: context, body: body)
    }
    func contactRequest(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactRequest, context: context, body: body)
    }
    func contactRequestAccept(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactRequestAccept, context: context, body: body)
    }
    func contactRequestBlock(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactRequestBlock, context: context, body: body)
    }
    func contactRequestDecline(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactRequestDecline, context: context, body: body)
    }
    func contactRequestsList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactRequestsList, context: context, body: body)
    }
    func contactRequestsPolicyGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactRequestsPolicyGet, context: context, body: body)
    }
    func contactRequestsPolicySet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactRequestsPolicySet, context: context, body: body)
    }
    func contactSafetyNumber(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactSafetyNumber, context: context, body: body)
    }
    func contactUnblock(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactUnblock, context: context, body: body)
    }
    func contactVerificationStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactVerificationStatus, context: context, body: body)
    }
    func contactVerify(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.contactVerify, context: context, body: body)
    }
}
public protocol ConversationProxy: SDKProxyProtocol {}
public extension ConversationProxy {
    func conversationDirectory(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.conversationDirectory, context: context, body: body)
    }
    func conversationDisappearingExpire(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.conversationDisappearingExpire, context: context, body: body)
    }
    func conversationDisappearingSet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.conversationDisappearingSet, context: context, body: body)
    }
    func conversationList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.conversationList, context: context, body: body)
    }
    func conversationMute(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.conversationMute, context: context, body: body)
    }
}
public protocol DaemonProxy: SDKProxyProtocol {}
public extension DaemonProxy {
    func daemonStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.daemonStatus, context: context, body: body)
    }
}
public protocol DeviceProxy: SDKProxyProtocol {}
public extension DeviceProxy {
    func deviceActivate(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.deviceActivate, context: context, body: body)
    }
    func deviceAuthorize(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.deviceAuthorize, context: context, body: body)
    }
    func deviceList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.deviceList, context: context, body: body)
    }
    func deviceMigrate(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.deviceMigrate, context: context, body: body)
    }
    func devicePairApprove(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.devicePairApprove, context: context, body: body)
    }
    func devicePairBegin(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.devicePairBegin, context: context, body: body)
    }
    func devicePairCancel(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.devicePairCancel, context: context, body: body)
    }
    func devicePairConfirm(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.devicePairConfirm, context: context, body: body)
    }
    func devicePairJoin(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.devicePairJoin, context: context, body: body)
    }
    func devicePairStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.devicePairStatus, context: context, body: body)
    }
    func devicePushRouteSet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.devicePushRouteSet, context: context, body: body)
    }
    func deviceRefresh(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.deviceRefresh, context: context, body: body)
    }
    func deviceRevoke(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.deviceRevoke, context: context, body: body)
    }
    func deviceSyncExport(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.deviceSyncExport, context: context, body: body)
    }
    func deviceSyncImport(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.deviceSyncImport, context: context, body: body)
    }
}
public protocol GrantProxy: SDKProxyProtocol {}
public extension GrantProxy {
    func grantApprove(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.grantApprove, context: context, body: body)
    }
    func grantCreateStandingApproval(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.grantCreateStandingApproval, context: context, body: body)
    }
    func grantDeny(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.grantDeny, context: context, body: body)
    }
    func grantList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.grantList, context: context, body: body)
    }
    func grantListStandingApprovals(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.grantListStandingApprovals, context: context, body: body)
    }
    func grantRequest(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.grantRequest, context: context, body: body)
    }
    func grantRevoke(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.grantRevoke, context: context, body: body)
    }
    func grantRevokeStandingApproval(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.grantRevokeStandingApproval, context: context, body: body)
    }
}
public protocol GroupProxy: SDKProxyProtocol {}
public extension GroupProxy {
    func groupCreate(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupCreate, context: context, body: body)
    }
    func groupHistory(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupHistory, context: context, body: body)
    }
    func groupInvitationAccept(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupInvitationAccept, context: context, body: body)
    }
    func groupInvitationDecline(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupInvitationDecline, context: context, body: body)
    }
    func groupInvitationsList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupInvitationsList, context: context, body: body)
    }
    func groupInviteAccept(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupInviteAccept, context: context, body: body)
    }
    func groupInviteCreate(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupInviteCreate, context: context, body: body)
    }
    func groupList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupList, context: context, body: body)
    }
    func groupMemberAdd(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupMemberAdd, context: context, body: body)
    }
    func groupMemberBan(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupMemberBan, context: context, body: body)
    }
    func groupMemberKick(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupMemberKick, context: context, body: body)
    }
    func groupMemberRemove(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupMemberRemove, context: context, body: body)
    }
    func groupMembers(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupMembers, context: context, body: body)
    }
    func groupMessageDelete(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupMessageDelete, context: context, body: body)
    }
    func groupNameSet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupNameSet, context: context, body: body)
    }
    func groupOwnerTransfer(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupOwnerTransfer, context: context, body: body)
    }
    func groupRead(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupRead, context: context, body: body)
    }
    func groupReceive(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupReceive, context: context, body: body)
    }
    func groupRequestsList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupRequestsList, context: context, body: body)
    }
    func groupRoleSet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupRoleSet, context: context, body: body)
    }
    func groupSend(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupSend, context: context, body: body)
    }
    func groupSenderKeyExport(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupSenderKeyExport, context: context, body: body)
    }
    func groupSenderKeyImport(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.groupSenderKeyImport, context: context, body: body)
    }
}
public protocol IdentityProxy: SDKProxyProtocol {}
public extension IdentityProxy {
    func identityDirectory(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.identityDirectory, context: context, body: body)
    }
}
public protocol MCPProxy: SDKProxyProtocol {}
public extension MCPProxy {
    func mcpApprovalDenied(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.mcpApprovalDenied, context: context, body: body)
    }
    func mcpApprovalGranted(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.mcpApprovalGranted, context: context, body: body)
    }
    func mcpApprovalList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.mcpApprovalList, context: context, body: body)
    }
    func mcpAuditList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.mcpAuditList, context: context, body: body)
    }
    func mcpServerAdd(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.mcpServerAdd, context: context, body: body)
    }
    func mcpServerList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.mcpServerList, context: context, body: body)
    }
    func mcpServerRefresh(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.mcpServerRefresh, context: context, body: body)
    }
    func mcpToolList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.mcpToolList, context: context, body: body)
    }
    func mcpToolStarted(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.mcpToolStarted, context: context, body: body)
    }
}
public protocol MessageProxy: SDKProxyProtocol {}
public extension MessageProxy {
    func messageAck(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.messageAck, context: context, body: body)
    }
    func messageDelete(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.messageDelete, context: context, body: body)
    }
    func messageFrankingEvidence(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.messageFrankingEvidence, context: context, body: body)
    }
    func messageList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.messageList, context: context, body: body)
    }
    func messageRead(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.messageRead, context: context, body: body)
    }
    func messageReceiptDelivered(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.messageReceiptDelivered, context: context, body: body)
    }
    func messageReceiptRead(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.messageReceiptRead, context: context, body: body)
    }
    func messageReceive(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.messageReceive, context: context, body: body)
    }
    func messageSubmit(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.messageSubmit, context: context, body: body)
    }
}
public protocol NodeProxy: SDKProxyProtocol {}
public extension NodeProxy {
    func nodeAdd(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.nodeAdd, context: context, body: body)
    }
    func nodeConfirm(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.nodeConfirm, context: context, body: body)
    }
    func nodeList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.nodeList, context: context, body: body)
    }
    func nodeProbe(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.nodeProbe, context: context, body: body)
    }
    func nodeRemove(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.nodeRemove, context: context, body: body)
    }
    func nodeSetDefault(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.nodeSetDefault, context: context, body: body)
    }
    func nodeSetEnabled(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.nodeSetEnabled, context: context, body: body)
    }
}
public protocol ObjectProxy: SDKProxyProtocol {}
public extension ObjectProxy {
    func objectDelete(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectDelete, context: context, body: body)
    }
    func objectDirectory(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectDirectory, context: context, body: body)
    }
    func objectFetch(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectFetch, context: context, body: body)
    }
    func objectGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectGet, context: context, body: body)
    }
    func objectGetBegin(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectGetBegin, context: context, body: body)
    }
    func objectGetFinish(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectGetFinish, context: context, body: body)
    }
    func objectGetRead(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectGetRead, context: context, body: body)
    }
    func objectGetStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectGetStatus, context: context, body: body)
    }
    func objectImport(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectImport, context: context, body: body)
    }
    func objectList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectList, context: context, body: body)
    }
    func objectPut(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectPut, context: context, body: body)
    }
    func objectPutBegin(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectPutBegin, context: context, body: body)
    }
    func objectPutChunk(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectPutChunk, context: context, body: body)
    }
    func objectPutFinish(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectPutFinish, context: context, body: body)
    }
    func objectPutStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectPutStatus, context: context, body: body)
    }
    func objectShare(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectShare, context: context, body: body)
    }
    func objectTransferResume(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectTransferResume, context: context, body: body)
    }
    func objectTransferStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.objectTransferStatus, context: context, body: body)
    }
}
public protocol StreamProxy: SDKProxyProtocol {}
public extension StreamProxy {
    func streamRead(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.streamRead, context: context, body: body)
    }
}
public protocol SubscriptionProxy: SDKProxyProtocol {}
public extension SubscriptionProxy {
    func subscriptionOpen(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.subscriptionOpen, context: context, body: body)
    }
}
public protocol SurfaceProxy: SDKProxyProtocol {}
public extension SurfaceProxy {
    func surfaceAction(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.surfaceAction, context: context, body: body)
    }
    func surfaceGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.surfaceGet, context: context, body: body)
    }
    func surfaceList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.surfaceList, context: context, body: body)
    }
    func surfaceRequestResync(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.surfaceRequestResync, context: context, body: body)
    }
    func surfaceResync(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.surfaceResync, context: context, body: body)
    }
    func surfaceSend(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.surfaceSend, context: context, body: body)
    }
}
public protocol SyncProxy: SDKProxyProtocol {}
public extension SyncProxy {
    func syncStatusGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.syncStatusGet, context: context, body: body)
    }
}
public protocol TaskProxy: SDKProxyProtocol {}
public extension TaskProxy {
    func taskAccept(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskAccept, context: context, body: body)
    }
    func taskCancel(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskCancel, context: context, body: body)
    }
    func taskDecisionProve(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskDecisionProve, context: context, body: body)
    }
    func taskDecline(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskDecline, context: context, body: body)
    }
    func taskGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskGet, context: context, body: body)
    }
    func taskList(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskList, context: context, body: body)
    }
    func taskPropose(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskPropose, context: context, body: body)
    }
    func taskResolve(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskResolve, context: context, body: body)
    }
    func taskStart(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskStart, context: context, body: body)
    }
    func taskUpdate(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.taskUpdate, context: context, body: body)
    }
}
