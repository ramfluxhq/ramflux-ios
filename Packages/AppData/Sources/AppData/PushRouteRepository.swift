// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
import Push

/// What the node or the SDK answered to a push route registration.
public enum PushRouteAnswer: Equatable, Sendable {
    case registered, deregistered
    /// A typed refusal by code (for example `provider_unavailable`).
    case refused(String)
    case failed
}

/// Registers or clears this device's push route for an account (`device.push_route.set`).
public protocol PushRouteRepository: Sendable {
    func register(account: String, token: String, routeTag: String, sandbox: Bool) async -> PushRouteAnswer
    func deregister(account: String) async -> PushRouteAnswer
}

public struct UnavailablePushRouteRepository: PushRouteRepository {
    public init() {}
    public func register(account: String, token: String, routeTag: String, sandbox: Bool) async -> PushRouteAnswer { .failed }
    public func deregister(account: String) async -> PushRouteAnswer { .failed }
}

struct NativePushRouteRepository: PushRouteRepository {
    private let gateway: ProxyGateway
    init(client: RamfluxClient) { gateway = ProxyGateway(proxy: SDKProxy(client: client)) }
    func register(account: String, token: String, routeTag: String, sandbox: Bool) async -> PushRouteAnswer {
        let registration: JSONValue = .object(["provider": .string("apns"), "token": .string(token), "route_tag": .string(routeTag),
                                               "environment": .string(sandbox ? "sandbox" : "production"), "capability": .string("alert")])
        return await send(account: account, body: .object(["registration": registration]))
    }
    func deregister(account: String) async -> PushRouteAnswer { await send(account: account, body: .object(["registration": .null])) }
    private func send(account: String, body: JSONValue) async -> PushRouteAnswer {
        do {
            let answer = try await gateway.call(.devicePushRouteSet, account: account, body: body)
            if answer["deregistered"]?.bool == true { return .deregistered }
            if answer["registered"]?.bool == true { return .registered }
            PushLog.route.notice("push.route.answer registered=false")
            return .failed
        } catch {
            guard let failure = error as? CoreFailure else { return .failed }
            // The C ABI does not carry the node's typed refusal code (open question CR4): a refused registration
            // arrives as the generic `invalid_argument` (ValidationFailed) with no finer reason, so the typed code
            // is used when present and `invalid_argument` otherwise.
            if let code = failure.reasonCode ?? failure.specificReason ?? failure.response?["error"]?["code"]?.string { return .refused(code) }
            if failure.code == .invalidArgument { return .refused("invalid_argument") }
            return .failed
        }
    }
}
