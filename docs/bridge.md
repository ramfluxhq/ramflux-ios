<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
<!-- Copyright (c) 2026 Span Brain -->
# RamfluxCore bridge

RamfluxCore is a Swift 6 package for macOS 15+ and iOS 18+. It has no UI, network
service, third-party Swift dependency, generated FFI language runtime, or second
account implementation. `NativeCore` forwards through the SDK's C ABI v2 and
existing supervisor. Application features consume the Proxy protocols.

`SDKOperation.swift` and `OperationProxies.swift` contain names-only adapters for
the SDK method inventory. Request bodies and complete response frames retain
the SDK's schema, including unsupported content and presence. `JSONValue` is
transport JSON, not an alternative message/domain model. Decimal strings stay
strings; unsigned numeric journal cursors retain UInt64 precision. Native domain
models must be generated from the SDK descriptor before UI consumes typed messages.
`NativeCore.methods` exposes negotiation capabilities. Missing methods fail before
submission. Pass the expected descriptor fingerprint to NativeCore when typed
message bindings are added; it refuses mismatches. The negotiated fingerprint is exposed; this package does not decode message payload schemas.

## Requests and ownership

Construct `NativeCore` with a private data-root URL, then inject it into
`RamfluxClient` and `SDKProxy`. Start the client before executing requests. The
client dispatches blocking C startup/shutdown and operation waits off the caller's
executor. Worker concurrency is four, with admission limited to 64 requests and
4 MiB of retained request bodies; lifecycle work has its own serial executor.
Every request carries an absolute Unix deadline. Mutating Proxy calls require a
caller-owned operation ID. The bridge never retries, reconciles automatically,
or invents a replacement operation ID.

Swift Task cancellation explicitly invokes the ABI operation-cancel handle.
Before submission cancellation has no effects. After submission the bridge keeps
unknown-effect status unless the core provides its terminal no-effect result.
Completion polling never resubmits. Every operation is released once. Unknown
numeric error codes remain representable; failures retain the SDK error frame,
reason and operation identity, while descriptions redact payloads.

The package has one app-session event consumer per open client. Its subscription
acknowledgement/snapshot is exposed as `EventSubscription.initialSnapshot`;
apply it before live rows. The AsyncSequence uses a bounded AsyncThrowingStream
with count and byte credit. Overflow terminates with `resyncRequired`; completion
credit remains independent. Persist the last applied journal cursor yourself.
Consume rows in the feature MainActor context. Cancel and `await subscription.stop()` when releasing a stream. Client suspend/close
automatically joins established and concurrently opening pumps before native shutdown.
Reopen and read projections after resync, then subscribe from the applied cursor.
A cancelled session stream is not reopened on the same native client.

`PhoneLifecycle` serializes transitions across actor suspension. Background return
means the C supervisor shutdown completed and its writer was released. The app
must grant background execution time around this call and end that OS task only
after completion. A failed close/suspend does not authorize another writer.
Foreground reacquires the core. Extensions must never construct a NativeCore.

## Secrets and app storage

`SecretBytes` is single-use, non-Codable and redacted. Its private allocation is
explicitly erased on consume, erase and destruction. `SecretRequest` encodes
secret strings/three-word confirmation answers directly into an erased bounded
buffer. Use `SecretField.text` or `.words`; ordinary Proxy methods refuse known
secret-bearing operations. AccountCeremony sequences show-once, hide, challenge,
and a single confirmation attempt; errors do not permit another confirmation.
Creation and recovery must not interleave on one client connection.

The Keychain adapter uses AfterFirstUnlockThisDeviceOnly with synchronization
disabled and no extension access group or file fallback. A key without its
existing database returns orphanedVault; it never creates replacement identity
state. AppStorage sets directory backup exclusion and owner permissions. On iOS
it restricts the root to Application Support and applies
completeUntilFirstUserAuthentication to database/WAL/shm files after foreground.
The database/spool never belong in an App Group. There is no NSE.

Managed-language/CFData/JSONDecoder copies of secrets cannot all be erased.
Account ceremony output is transiently decoded as a response frame before being
sealed for one-time consumption; do not log, cache or persist response frames.
Keychain provider round trips, locked-phone behavior, SQLCipher lock release and
real gateway execution require SDK/device integration; the headless fixture
suite does not establish them.

## Deferred capabilities

SearchProxy, AgentConfigurationProxy, StrangerReportingProxy and
MessageRevisionProxy define the application boundary. UnavailableFeatures returns
explicit typed capability errors and performs no SDK call. Search, Agent
configuration, stranger reporting/batch operations await their shared SDK modules.
Edit/reaction/reply adapters await the message-unification SDK contract. There
are no fake results, guessed wire methods, or preview fixtures in the product.
