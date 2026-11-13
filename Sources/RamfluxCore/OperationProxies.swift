// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
// Generated forwarding APIs; SDK payload schemas remain authoritative.
public protocol A2IProxy: SDKProxyProtocol {}
public extension A2IProxy {
    func a2iAcknowledge(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.a2iAcknowledge, context: context, body: body, secrets: secrets)
    }
    func a2iAppend(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.a2iAppend, context: context, body: body, secrets: secrets)
    }
    func a2iList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.a2iList, context: context, body: body)
    }
    func a2iListPending(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.a2iListPending, context: context, body: body)
    }
}
public protocol A2UIProxy: SDKProxyProtocol {}
public extension A2UIProxy {
    func a2uiAction(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.a2uiAction, context: context, body: body, secrets: secrets)
    }
    func a2uiRender(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.a2uiRender, context: context, body: body, secrets: secrets)
    }
}
public protocol AccountProxy: SDKProxyProtocol {}
public extension AccountProxy {
    func accountBackupCancel(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> JSONValue {
        try await performSecret(.accountBackupCancel, context: context, body: body, secrets: secrets)
    }
    func accountBackupCreate(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> JSONValue {
        try await performSecret(.accountBackupCreate, context: context, body: body, secrets: secrets)
    }
    func accountBackupExport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountBackupExport, context: context, body: body, secrets: secrets)
    }
    func accountBackupImport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountBackupImport, context: context, body: body, secrets: secrets)
    }
    func accountBackupJobs(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> JSONValue {
        try await performSecret(.accountBackupJobs, context: context, body: body, secrets: secrets)
    }
    func accountConfigGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.accountConfigGet, context: context, body: body)
    }
    func accountConfigSet(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountConfigSet, context: context, body: body, secrets: secrets)
    }
    func accountCreate(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountCreate, context: context, body: body, secrets: secrets)
    }
    func accountCreateBegin(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountCreateBegin, context: context, body: body, secrets: secrets)
    }
    func accountCreateCancel(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountCreateCancel, context: context, body: body)
    }
    func accountCreateConfirm(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountCreateConfirm, context: context, body: body, secrets: secrets)
    }
    func accountCreateHiddenChallenge(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.accountCreateHiddenChallenge, context: context, body: body)
    }
    func accountCreateShowOnce(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.accountCreateShowOnce, context: context, body: body)
    }
    func accountCustodyBegin(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountCustodyBegin, context: context, body: body, secrets: secrets)
    }
    func accountCustodyCancel(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountCustodyCancel, context: context, body: body)
    }
    func accountCustodyConfirm(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountCustodyConfirm, context: context, body: body, secrets: secrets)
    }
    func accountCustodyHiddenChallenge(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.accountCustodyHiddenChallenge, context: context, body: body)
    }
    func accountCustodyShowOnce(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.accountCustodyShowOnce, context: context, body: body)
    }
    func accountExportAgentCredentials(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountExportAgentCredentials, context: context, body: body, secrets: secrets)
    }
    func accountList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.accountList, context: context, body: body)
    }
    func accountLock(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountLock, context: context, body: body, secrets: secrets)
    }
    func accountPassphraseRotate(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountPassphraseRotate, context: context, body: body, secrets: secrets)
    }
    func accountRecoverBegin(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountRecoverBegin, context: context, body: body, secrets: secrets)
    }
    func accountRecoverCancel(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.accountRecoverCancel, context: context, body: body)
    }
    func accountRecoverConfirm(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountRecoverConfirm, context: context, body: body, secrets: secrets)
    }
    func accountRestoreInstall(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> JSONValue {
        try await performSecret(.accountRestoreInstall, context: context, body: body, secrets: secrets)
    }
    func accountRestoreVerify(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> JSONValue {
        try await performSecret(.accountRestoreVerify, context: context, body: body, secrets: secrets)
    }
    func accountStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.accountStatus, context: context, body: body)
    }
    func accountSwitch(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountSwitch, context: context, body: body, secrets: secrets)
    }
    func accountUnlock(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.accountUnlock, context: context, body: body, secrets: secrets)
    }
}
public protocol BotProxy: SDKProxyProtocol {}
public extension BotProxy {
    func botInstall(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.botInstall, context: context, body: body, secrets: secrets)
    }
    func botList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.botList, context: context, body: body)
    }
    func botRevoke(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.botRevoke, context: context, body: body, secrets: secrets)
    }
    func botTrustAdd(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.botTrustAdd, context: context, body: body, secrets: secrets)
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
    func callAnswer(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.callAnswer, context: context, body: body, secrets: secrets)
    }
    func callHangup(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.callHangup, context: context, body: body, secrets: secrets)
    }
    func callInvite(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.callInvite, context: context, body: body, secrets: secrets)
    }
    func callList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.callList, context: context, body: body)
    }
    func callMediaSession(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.callMediaSession, context: context, body: body, secrets: secrets)
    }
    func callReject(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.callReject, context: context, body: body, secrets: secrets)
    }
}
public protocol ContactProxy: SDKProxyProtocol {}
public extension ContactProxy {
    func contactAccept(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactAccept, context: context, body: body, secrets: secrets)
    }
    func contactAdd(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactAdd, context: context, body: body, secrets: secrets)
    }
    func contactBlock(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactBlock, context: context, body: body, secrets: secrets)
    }
    func contactCardExport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactCardExport, context: context, body: body, secrets: secrets)
    }
    func contactCardImport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactCardImport, context: context, body: body, secrets: secrets)
    }
    func contactDecline(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactDecline, context: context, body: body, secrets: secrets)
    }
    func contactList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.contactList, context: context, body: body)
    }
    func contactReject(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactReject, context: context, body: body, secrets: secrets)
    }
    func contactRejected(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.contactRejected, context: context, body: body)
    }
    func contactRemove(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactRemove, context: context, body: body, secrets: secrets)
    }
    func contactRequest(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactRequest, context: context, body: body, secrets: secrets)
    }
    func contactRequestAccept(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactRequestAccept, context: context, body: body, secrets: secrets)
    }
    func contactRequestBlock(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactRequestBlock, context: context, body: body, secrets: secrets)
    }
    func contactRequestDecline(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactRequestDecline, context: context, body: body, secrets: secrets)
    }
    func contactRequestsList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.contactRequestsList, context: context, body: body)
    }
    func contactRequestsPolicyGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.contactRequestsPolicyGet, context: context, body: body)
    }
    func contactRequestsPolicySet(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactRequestsPolicySet, context: context, body: body, secrets: secrets)
    }
    func contactSafetyNumber(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactSafetyNumber, context: context, body: body, secrets: secrets)
    }
    func contactUnblock(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactUnblock, context: context, body: body, secrets: secrets)
    }
    func contactVerificationStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.contactVerificationStatus, context: context, body: body)
    }
    func contactVerify(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.contactVerify, context: context, body: body, secrets: secrets)
    }
}
public protocol ConversationProxy: SDKProxyProtocol {}
public extension ConversationProxy {
    func conversationDirectory(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.conversationDirectory, context: context, body: body)
    }
    func conversationDisappearingExpire(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.conversationDisappearingExpire, context: context, body: body, secrets: secrets)
    }
    func conversationDisappearingSet(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.conversationDisappearingSet, context: context, body: body, secrets: secrets)
    }
    func conversationList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.conversationList, context: context, body: body)
    }
    func conversationMute(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.conversationMute, context: context, body: body, secrets: secrets)
    }
    func conversationSend(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.conversationSend, context: context, body: body, secrets: secrets)
    }
}
public protocol DaemonProxy: SDKProxyProtocol {}
public extension DaemonProxy {
    func daemonStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.daemonStatus, context: context, body: body)
    }
    func daemonStop(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> JSONValue {
        try await performSecret(.daemonStop, context: context, body: body, secrets: secrets)
    }
}
public protocol DeviceProxy: SDKProxyProtocol {}
public extension DeviceProxy {
    func deviceActivate(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.deviceActivate, context: context, body: body, secrets: secrets)
    }
    func deviceAuthorize(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.deviceAuthorize, context: context, body: body, secrets: secrets)
    }
    func deviceList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.deviceList, context: context, body: body)
    }
    func deviceMigrate(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.deviceMigrate, context: context, body: body, secrets: secrets)
    }
    func devicePairApprove(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.devicePairApprove, context: context, body: body, secrets: secrets)
    }
    func devicePairBegin(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.devicePairBegin, context: context, body: body, secrets: secrets)
    }
    func devicePairCancel(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.devicePairCancel, context: context, body: body, secrets: secrets)
    }
    func devicePairConfirm(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.devicePairConfirm, context: context, body: body, secrets: secrets)
    }
    func devicePairJoin(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.devicePairJoin, context: context, body: body, secrets: secrets)
    }
    func devicePairStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.devicePairStatus, context: context, body: body)
    }
    func devicePushRouteSet(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.devicePushRouteSet, context: context, body: body, secrets: secrets)
    }
    func deviceRefresh(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.deviceRefresh, context: context, body: body, secrets: secrets)
    }
    func deviceRevoke(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.deviceRevoke, context: context, body: body, secrets: secrets)
    }
    func deviceSyncExport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.deviceSyncExport, context: context, body: body, secrets: secrets)
    }
    func deviceSyncImport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.deviceSyncImport, context: context, body: body, secrets: secrets)
    }
}
public protocol GrantProxy: SDKProxyProtocol {}
public extension GrantProxy {
    func grantApprove(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.grantApprove, context: context, body: body, secrets: secrets)
    }
    func grantCreateStandingApproval(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.grantCreateStandingApproval, context: context, body: body, secrets: secrets)
    }
    func grantDeny(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.grantDeny, context: context, body: body, secrets: secrets)
    }
    func grantList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.grantList, context: context, body: body)
    }
    func grantListStandingApprovals(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.grantListStandingApprovals, context: context, body: body)
    }
    func grantRequest(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.grantRequest, context: context, body: body, secrets: secrets)
    }
    func grantRevoke(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.grantRevoke, context: context, body: body, secrets: secrets)
    }
    func grantRevokeStandingApproval(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.grantRevokeStandingApproval, context: context, body: body, secrets: secrets)
    }
}
public protocol GroupProxy: SDKProxyProtocol {}
public extension GroupProxy {
    func groupCreate(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupCreate, context: context, body: body, secrets: secrets)
    }
    func groupHistory(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.groupHistory, context: context, body: body)
    }
    func groupInvitationAccept(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupInvitationAccept, context: context, body: body, secrets: secrets)
    }
    func groupInvitationDecline(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupInvitationDecline, context: context, body: body, secrets: secrets)
    }
    func groupInvitationsList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.groupInvitationsList, context: context, body: body)
    }
    func groupInviteAccept(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupInviteAccept, context: context, body: body, secrets: secrets)
    }
    func groupInviteCreate(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupInviteCreate, context: context, body: body, secrets: secrets)
    }
    func groupList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.groupList, context: context, body: body)
    }
    func groupMemberAdd(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupMemberAdd, context: context, body: body, secrets: secrets)
    }
    func groupMemberBan(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupMemberBan, context: context, body: body, secrets: secrets)
    }
    func groupMemberKick(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupMemberKick, context: context, body: body, secrets: secrets)
    }
    func groupMemberRemove(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupMemberRemove, context: context, body: body, secrets: secrets)
    }
    func groupMembers(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.groupMembers, context: context, body: body)
    }
    func groupMessageDelete(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupMessageDelete, context: context, body: body, secrets: secrets)
    }
    func groupNameSet(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupNameSet, context: context, body: body, secrets: secrets)
    }
    func groupOwnerTransfer(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupOwnerTransfer, context: context, body: body, secrets: secrets)
    }
    func groupRead(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupRead, context: context, body: body, secrets: secrets)
    }
    func groupReceive(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupReceive, context: context, body: body, secrets: secrets)
    }
    func groupRequestsList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.groupRequestsList, context: context, body: body)
    }
    func groupRoleSet(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupRoleSet, context: context, body: body, secrets: secrets)
    }
    func groupSend(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupSend, context: context, body: body, secrets: secrets)
    }
    func groupSenderKeyExport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupSenderKeyExport, context: context, body: body, secrets: secrets)
    }
    func groupSenderKeyImport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.groupSenderKeyImport, context: context, body: body, secrets: secrets)
    }
}
public protocol IdentityProxy: SDKProxyProtocol {}
public extension IdentityProxy {
    func identityDirectory(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.identityDirectory, context: context, body: body)
    }
}
public protocol MCPProxy: SDKProxyProtocol {}
public extension MCPProxy {
    func mcpApprovalDenied(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.mcpApprovalDenied, context: context, body: body, secrets: secrets)
    }
    func mcpApprovalGranted(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.mcpApprovalGranted, context: context, body: body, secrets: secrets)
    }
    func mcpApprovalList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.mcpApprovalList, context: context, body: body)
    }
    func mcpAuditList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.mcpAuditList, context: context, body: body)
    }
    func mcpServerAdd(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.mcpServerAdd, context: context, body: body, secrets: secrets)
    }
    func mcpServerList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.mcpServerList, context: context, body: body)
    }
    func mcpServerRefresh(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.mcpServerRefresh, context: context, body: body)
    }
    func mcpToolList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.mcpToolList, context: context, body: body)
    }
    func mcpToolStarted(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.mcpToolStarted, context: context, body: body, secrets: secrets)
    }
}
public protocol MessageProxy: SDKProxyProtocol {}
public extension MessageProxy {
    func messageAck(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.messageAck, context: context, body: body, secrets: secrets)
    }
    func messageDelete(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.messageDelete, context: context, body: body, secrets: secrets)
    }
    func messageFrankingEvidence(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.messageFrankingEvidence, context: context, body: body)
    }
    func messageList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.messageList, context: context, body: body)
    }
    func messageRead(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.messageRead, context: context, body: body)
    }
    func messageReceiptDelivered(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.messageReceiptDelivered, context: context, body: body, secrets: secrets)
    }
    func messageReceiptRead(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.messageReceiptRead, context: context, body: body, secrets: secrets)
    }
    func messageReceive(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.messageReceive, context: context, body: body, secrets: secrets)
    }
    func messageSubmit(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.messageSubmit, context: context, body: body, secrets: secrets)
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
    func objectDelete(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectDelete, context: context, body: body, secrets: secrets)
    }
    func objectDirectory(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.objectDirectory, context: context, body: body)
    }
    func objectFetch(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectFetch, context: context, body: body, secrets: secrets)
    }
    func objectGet(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectGet, context: context, body: body, secrets: secrets)
    }
    func objectGetBegin(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectGetBegin, context: context, body: body, secrets: secrets)
    }
    func objectGetFinish(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectGetFinish, context: context, body: body, secrets: secrets)
    }
    func objectGetRead(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectGetRead, context: context, body: body, secrets: secrets)
    }
    func objectGetStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.objectGetStatus, context: context, body: body)
    }
    func objectImport(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectImport, context: context, body: body, secrets: secrets)
    }
    func objectList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.objectList, context: context, body: body)
    }
    func objectPut(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectPut, context: context, body: body, secrets: secrets)
    }
    func objectPutBegin(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectPutBegin, context: context, body: body, secrets: secrets)
    }
    func objectPutChunk(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectPutChunk, context: context, body: body, secrets: secrets)
    }
    func objectPutFinish(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectPutFinish, context: context, body: body, secrets: secrets)
    }
    func objectPutStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.objectPutStatus, context: context, body: body)
    }
    func objectShare(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectShare, context: context, body: body, secrets: secrets)
    }
    func objectTransferResume(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.objectTransferResume, context: context, body: body, secrets: secrets)
    }
    func objectTransferStatus(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.objectTransferStatus, context: context, body: body)
    }
}
public protocol StreamProxy: SDKProxyProtocol {}
public extension StreamProxy {
    func streamRead(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.streamRead, context: context, body: body)
    }
}
public protocol SubscriptionProxy: SDKProxyProtocol {}
public extension SubscriptionProxy {
    func subscriptionClose(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.subscriptionClose, context: context, body: body)
    }
    func subscriptionOpen(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await perform(.subscriptionOpen, context: context, body: body)
    }
}
public protocol SurfaceProxy: SDKProxyProtocol {}
public extension SurfaceProxy {
    func surfaceAction(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.surfaceAction, context: context, body: body, secrets: secrets)
    }
    func surfaceGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.surfaceGet, context: context, body: body)
    }
    func surfaceList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.surfaceList, context: context, body: body)
    }
    func surfaceRequestResync(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.surfaceRequestResync, context: context, body: body, secrets: secrets)
    }
    func surfaceResync(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.surfaceResync, context: context, body: body, secrets: secrets)
    }
    func surfaceSend(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.surfaceSend, context: context, body: body, secrets: secrets)
    }
}
public protocol SyncProxy: SDKProxyProtocol {}
public extension SyncProxy {
    func syncStatusGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.syncStatusGet, context: context, body: body)
    }
}
public protocol TaskProxy: SDKProxyProtocol {}
public extension TaskProxy {
    func taskAccept(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.taskAccept, context: context, body: body, secrets: secrets)
    }
    func taskCancel(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.taskCancel, context: context, body: body, secrets: secrets)
    }
    func taskDecisionProve(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.taskDecisionProve, context: context, body: body, secrets: secrets)
    }
    func taskDecline(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.taskDecline, context: context, body: body, secrets: secrets)
    }
    func taskGet(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.taskGet, context: context, body: body)
    }
    func taskList(context: RequestContext, body: JSONValue = .object([:])) async throws -> SecretBytes {
        try await performSecretResponse(.taskList, context: context, body: body)
    }
    func taskPropose(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.taskPropose, context: context, body: body, secrets: secrets)
    }
    func taskResolve(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.taskResolve, context: context, body: body, secrets: secrets)
    }
    func taskStart(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.taskStart, context: context, body: body, secrets: secrets)
    }
    func taskUpdate(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField] = [:]) async throws -> SecretBytes {
        try await performSecretRequestResponse(.taskUpdate, context: context, body: body, secrets: secrets)
    }
}
