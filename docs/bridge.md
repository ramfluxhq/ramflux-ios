<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
<!-- Copyright (c) 2026 Span Brain -->
# RamfluxCore bridge

RamfluxCore is a Swift 6 package for macOS 15+ and iOS 18+. It has no UI, network
service, third-party Swift dependency, generated FFI language runtime, or second
account implementation. `NativeCore` forwards through the SDK's C ABI v2 and
existing supervisor. Application features consume the Proxy protocols.
Native libraries use `CARGO_PROFILE_RELEASE_PANIC=unwind`; v2 refuses `panic=abort`.

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
`client.resetEvents()` before subscribing from the applied cursor. Teardown stops polling, cancels/releases the opening token, and awaits an explicit
`subscription.close` completion before releasing the stream slot. Its acknowledgement
has a five-second absolute deadline, with at most three admission attempts for
code 15/no-effect and 20 ms backoff. Token release (which includes cancellation)
also gets at most three retries with 20 ms backoff for code 15 before the ack request. Failure keeps the slot fenced until confirmed
whole-client shutdown. Failed opens use the same acknowledgement cleanup. The pump
performs no further polls after acknowledgement; `stop()` joins that pump. Direct
CoreTransport consumers must call `EventQueue.finish()` after their last poll.
The pinned SDK publishes an exact decimal-string `subscription_generation` on
successful open responses and every event frame. NativeCore adopts it only after
a successful open; NativeEventQueue drops frames with a different generation or
account, including stale lag notifications. Reset passes the last successful
generation to the C ABI, so it cannot clear a replacement stream. Invalid/missing
open generations fail closed. The fixture exercises close/reopen and stale frames. A copied stream or iterator
retains the subscription; requested stop ends cleanly and event gaps require resync.

`PhoneLifecycle` serializes transitions across actor suspension. Background return
means the C supervisor shutdown completed and its writer was released. The app
must grant background execution time around this call and end that OS task only
after completion. Pending shutdown retains its client handle and refuses start until confirmed
completion. After any close error, nonblocking `client_release` probes terminal
completion: Pending preserves the fence, while confirmed release permits rebuild
and reports the original numeric failure with `writerReleaseConfirmed`. Blocking
open/close and filesystem preparation run outside the state mutex; transitions are
reserved under the mutex, so cancellation and concurrent admission remain responsive. Transient open errors hold no handle and
leave foreground retryable.
Foreground reacquires the core. Extensions must never construct a NativeCore.

## Secrets and app storage

`SecretBytes` is single-use, non-Codable and redacted. Its private allocation is
explicitly erased on consume, erase and destruction. `SecretRequest` encodes
secret strings/three-word confirmation answers directly into an erased bounded
buffer. Use `SecretField.text` or `.words`; the generated Proxy APIs use the SDK-owned secret_input/secret_output/show_once
policy. Sealed outputs use a one-shot byte accessor, and secret input is encoded
into erased storage. A new method without explicit SDK policy fails generation. Negotiation requires policy version 2 and an exact match of the advertised method inventory, capability, secret input, secret output, show-once, key-export and bridge-allowed flags with the pinned table. A bridge-allowed row must be advertised; a denied row such as daemon.stop must not be. Absent or mismatched policy throws incompatibleABI. The client config sets allow_secret_exports so account creation and custody show-once are admitted. That same flag admits the other key-export methods; this app does not call them. allow_raw_messages stays off. AccountCeremony sequences show-once, hide, challenge,
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

SearchProxy, AgentConfigurationProxy and StrangerReportingProxy define the
application boundary for contracts that are still absent. UnavailableFeatures
returns explicit typed capability errors and performs no SDK call. Search, Agent
configuration and stranger reporting/batch operations await their shared SDK
modules. Conversation send, reply, edit, reaction and delete use the published
conversation methods. There are no fake results, guessed wire methods, or
preview fixtures in the product.
