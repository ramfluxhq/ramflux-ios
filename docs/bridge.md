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
executor. Ordinary worker concurrency is four, with a separate worker reserved for subscription opening, with admission limited to 64 requests and
4 MiB of retained request bodies; lifecycle work has its own serial executor.
Every request carries an absolute Unix deadline. Mutating Proxy calls require a
caller-owned operation ID. The bridge never retries, reconciles automatically,
or invents a replacement operation ID.

Swift Task cancellation explicitly invokes the ABI operation-cancel handle.
Before submission cancellation has no effects. After submission the bridge keeps
unknown-effect status unless the core provides its terminal no-effect result.
Completion polling never resubmits. Ordinary operation tokens are released once after completion; a subscription token is
retained through its stream lifetime and cancelled/released exactly once at shutdown. Unknown
numeric error codes remain representable. Errors from ordinary public completions
retain the response/reason; secret-output errors retain the original bytes in
CoreFailure.sealedResponse with numeric code and operation identity. Descriptions
redact both representations.

The package has one app-session event consumer per open client. Its subscription
acknowledgement/snapshot is exposed as `EventSubscription.initialSnapshot`;
apply it before live rows. The AsyncSequence uses a bounded AsyncThrowingStream
with count and byte credit. Overflow terminates with `resyncRequired`; completion
credit remains independent. Persist the last applied journal cursor yourself.
Consume rows in the feature MainActor context. Cancel and `await subscription.stop()` when releasing a stream. Client suspend/close
automatically joins established and concurrently opening pumps before native shutdown.
Reopen and read projections after resync, then subscribe from the applied cursor.
After stopping the old stream, re-read current projections and call
`client.resetEvents()` before subscribing from the applied cursor. Failed opens
and ended subscriptions release the stream slot. A copied stream or iterator
retains its subscription when the EventSubscription handle is dropped. Requested
stop terminates cleanly; an event gap remains a terminal resync error.

`PhoneLifecycle` serializes transitions across actor suspension. Background return
means the C supervisor shutdown completed and its writer was released. The app
must grant background execution time around this call and end that OS task only
after completion. A failed close/suspend retains its client handle and refuses start until a
subsequent close confirms completion. Transient open errors hold no handle and
leave foreground retryable.
Foreground reacquires the core. Extensions must never construct a NativeCore.

## Secrets and app storage

`SecretBytes` is single-use, non-Codable and redacted. Its private allocation is
explicitly erased on consume, erase and destruction. `SecretRequest` encodes
secret strings/three-word confirmation answers directly into an erased bounded
buffer. Use `SecretField.text` or `.words`; the generated Proxy APIs use the SDK-owned secret_input/secret_output/show_once
policy. Sealed outputs use a one-shot byte accessor, and secret input is encoded
into erased storage. A new method without explicit SDK policy fails generation. AccountCeremony sequences show-once, hide, challenge,
and a single confirmation attempt; errors do not permit another confirmation.
Creation and recovery must not interleave on one client connection.

The Keychain adapter uses AfterFirstUnlockThisDeviceOnly with synchronization
disabled and no extension access group or file fallback. A key without its
existing database returns orphanedVault; it never creates replacement identity
state. AppStorage sets directory backup exclusion and owner permissions. On iOS
it restricts the root to Application Support and applies
completeUntilFirstUserAuthentication recursively to account directories and database/WAL/shm files after foreground.
The database/spool never belong in an App Group. There is no NSE.

Show-once responses never pass through Data, String, JSONValue, or JSONDecoder
inside the bridge. A bounded C scan reads the numeric completion prefix, then the
SDK allocation is copied directly into zeroizing SecretBytes and erased/released.
Hiding the phrase erases that bridge-owned copy. Secret-output errors take the
same sealed path. Decode ordinary app data only explicitly inside the accessor;
do not log, cache or persist secret response frames. Caller-created and immutable
Security-owned CFData copies cannot all be erased by the bridge. Keychain writes
borrow the SecretBytes allocation without a Data copy; reads borrow the provider's
immutable NSData directly into SecretBytes, without a COW resetBytes claim.
Data-protection Keychain access and noninteractive LAContext are explicit.
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
