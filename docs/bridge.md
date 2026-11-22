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

## Shared event fan-out (AppData)

Features never open a native subscription. They call `observe(account:)` on their
repository, which forwards to the one `NativeUpdateSource` shared by every repository
built over the client (`AppDataFactory`). The hub keeps one native subscription per
active account and multicasts to any number of `RepositoryObservation`s:

- `observe(account:) async -> RepositoryObservation` registers an observer. The first
  observer resets the event slot and opens the subscription; later observers join it.
  Every observer receives `.invalidated` once it is live.
- `observation.stream` is an `AsyncStream<RepositoryUpdate>` buffering only the newest
  update: `.invalidated` means "reload your visible window"; `.failed(AppFailure)` is
  terminal and the stream finishes after it.
- `observation.stop()` is idempotent; cancelling the consuming task also removes the
  observer. When the last observer leaves, the hub stops and joins the native
  subscription. Subscribe on appear and stop on disappear.
- A lag notification, queue overflow or byte-credit exhaustion (`resyncRequired`)
  never reaches features as a failure: the hub stops the stream, resets, resubscribes
  and sends `.invalidated` to every observer so each reloads from read models. After
  four consecutive resubscriptions without a delivered event it reports `.failed`.
- Observing a different account finishes the previous account's observers and joins
  their native stop before resetting and subscribing for the new account.
- Transient frames: `observe(account:transientFrames: true)` also returns `observation.transient`, an
  `AsyncStream<TransientFrame>` (newest 32 buffered) carrying the live `message.transient` frames of
  the account (typing indicators) as the frame topic and its body in JSON bytes. Only observers that
  ask receive them; a transient frame never sends `.invalidated` and is never replayed after a resync.
  The stream finishes with the observation.
- The topic list is fixed in `NativeUpdateSource.topics`; there is no `*` subscription.
  Events carry no payload to observers: a feature that needs to filter (for example a
  chat that only cares about its own conversation) re-reads its window and compares.

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

Search methods are in the pinned inventory. SearchProxy stays a local refusal
because this app has no search screen and does not invent a query result.
Agent configuration and stranger reporting still have no published methods, so
those proxies stay local refusals and perform no SDK call. Conversation send,
reply, edit, reaction and delete use the published conversation methods. There
are no fake results, guessed wire methods, or preview fixtures in the product.

Linking this phone to an existing account is not available at SDK `3dafe1f8`. The
joining device must supply its new account code through the SDK's attended credential
channel during `device.pair.join` (`bus/credentials.rs`, credential action `setup`).
That channel exists only on local-bus socket connections (`bus/connection.rs`) and on
the narrow `ramflux_pairing_call` ABI, which needs a same-user local daemon socket
(`pairing_socket`). The in-process v2 operation ABI that this app uses opens no
credential channel, and the SDK's `docs/device_pairing.md` states that phone pairing
companions are outside the release. The onboarding "link" entry therefore shows the
typed unavailable state. Device list and revocation use `device.list` and
`device.revoke` and are available.
