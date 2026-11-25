# Push wake handling (iOS client)

Contract and verification notes for the APNs wake path. The design is `IOS-PUSH-WAKE-01` in the workspace
documents; this file holds what the repository itself needs: identifiers, payloads, the injector and the
platform facts measured on the simulator.

## Identifiers

| Build setting | Debug | Release |
|---|---|---|
| `RAMFLUX_APP_BUNDLE_ID` | `org.ramflux.ios.dev` | `org.ramflux.ios` |
| `RAMFLUX_APP_GROUP` | `group.$(RAMFLUX_APP_BUNDLE_ID)` | same |
| `RAMFLUX_KEYCHAIN_GROUP` | `$(AppIdentifierPrefix)$(RAMFLUX_APP_BUNDLE_ID).shared` | same |
| `RAMFLUX_APNS_ENVIRONMENT` | `development` | `production` |

The notification service extension (`RamfluxNotificationService`) is `$(RAMFLUX_APP_BUNDLE_ID).NotificationService`.
Both targets declare the App Group and the shared Keychain access group in their entitlements and in Info.plist
(`RamfluxAppGroup`, `RamfluxKeychainGroup`); `Push.SharedContainer` reads them from the host bundle. A company team or
registration changes build settings only. The filtering entitlement is not declared until Apple grants it.

## Payloads

An alert wake carries only `aps.alert.loc-key`, `mutable-content` and an `rf` object `{v: 1, c, t, w}`
(`c` is `m`, `call`, `x` or `t`; `t` the route tag; `w` the wake id). The client reads `aps` and `rf` only. The
files in `scripts/push/payloads/` are the `simctl push` forms (no headers: push type, priority, expiration and
collapse id cannot be expressed in them).

## Injector

```sh
scripts/push/inject.sh message|test|clear|call-alert|unknown-route|unknown-class|debug-call [--simulator rf-realrun] [--account ID]
```

It fills `ROUTE_TAG` from `push/routes.json` in the app's App Group container when that map exists (it prints
no tag, no account and no text), and otherwise sends a tag no account owns. It runs `xcrun simctl push`.
The app must be authorised for notifications on that simulator, or `simctl push` refuses with "Source is not
authorized" (UNErrorDomain 2003).

## Token and routes

The app delegate reports the APNs token to `Push.ApnsTokenSource` (memory only; logs carry its length only).
`RouteRegistrar` (AppData) registers an unlocked account: Debug builds send `{provider: apns, token, route_tag,
environment: sandbox, capability: alert}` with `device.push_route.set` to the developer's own node (design D4);
Release builds record `waitingForCentre` and send nothing until the central service seals tokens. One route tag
(16 random bytes, unpadded base64url) exists per account in `push/routes.json` of the App Group container, which
`inject.sh` reads. `DeliveryStatus` per account lives in the group's defaults suite under a salted hash of the
account id. Sign-out and local removal call `device.push_route.set` with a null registration first (five seconds at
most) and then drop the tag and the status.

Answer mapping: registered gives `ready`. A refused registration reaches the app as the generic `invalid_argument`
(SDK status ValidationFailed) with no finer reason, because the C ABI does not carry the node's typed code; that is
treated as `serverNoPush` ("your server does not send push notifications") and is open question CR4 for the core.
A real node with an APNs credential would answer `registered`; this was not exercised, the test node has none.

## Message delivery page

Settings, next to System permissions, opens `FeatureDelivery`'s page (route `AppRoute.delivery`). It shows the
`DeliveryStatus` of the active account, the last wake per class (App Group defaults), this iPhone's notification
settings, Background App Refresh and Low Power Mode (`NativeDeliverySignalsRepository` is the only reader), guidance
for what Ramflux cannot check, how calls reach the phone until calling exists, a local self-test (a test
notification after five seconds; lock the phone to see it) and the late-delivery wording. It re-reads every signal
when the app becomes active, so a change made in iOS Settings shows on return. Debug builds can open it with the
launch argument `-RFDebugRoute delivery`.

## Platform facts measured on the simulator

Measured with Xcode 27.2 (27B52), simulator runtime iOS 27.2 (device `rf-realrun`), macOS 26.6.2, Apple silicon,
ad hoc simulator signing, no team.

| # | Question | Measured answer |
|---|---|---|
| F1 | `simctl push` alert shows a notification | Yes, with the app terminated; the app must be authorised for notifications first. |
| F2 | Loc-keys resolve against the app bundle | See the IP02 entry below. |
| F3 | `simctl push` with `mutable-content: 1` starts the notification service extension | No. The extension is installed (`PlugIns/RamfluxNotificationService.appex`) but is never started: no `push.nse.received`, no extension process. SpringBoard receives the request through CoreSimulatorBridge `addRequest` with `mutableContent: YES` and presents it directly. |
| F10 | Device token on the simulator without a team | Yes: `didRegisterForRemoteNotificationsWithDeviceToken` fires after authorisation (`push.token.ok len=80`). |
| F11 | App Group container and shared Keychain group with ad hoc signing | App side: yes. `containerURL(forSecurityApplicationGroupIdentifier:)` returns a container for `group.org.ramflux.ios.dev`, and a generic-password item with `kSecAttrAccessGroup` = `FAKETEAMID.org.ramflux.ios.dev.shared` was added (status 0). `$(AppIdentifierPrefix)` resolves to `FAKETEAMID.` in simulator builds, not to an empty string. Extension side: not provable, because F3 means the extension cannot be started on the simulator. Device only. |

The generic floor (IP02): with the app terminated or at Home, `inject.sh message` shows one "New message" banner; with the app in the foreground nothing is presented (`willPresent` returns no options). The extension-side behaviour (catalog body, removal of the local slot) cannot be exercised on the simulator, see F3. The local-notification path needs the scene inactive (Notification Center pulled over the app), which no script can set up, so it is covered by the existing unit tests only.

Uninstalling the app removes its App Group container on the simulator (verified: the container and its contents are gone, and a fresh install starts empty), so the real-run reset still starts from an empty SDK root.

| F6 (setup) | `simctl push` of a silent push (`content-available`, no visible content) | Refused: UNErrorDomain 1401 "Notification has no user visible content" (badge only: 2002). `clear.apns` and a silent `debug-*` payload cannot be sent on this runtime. |
| F9 | CallKit incoming-call UI on the simulator via `reportNewIncomingCall` | No. The call fails with `com.apple.CallKit.error` code 0 (unknown); no UI appears. The dispatcher, the placeholder report, the 45 s timer and the "Missed call" notification still run (log `push.call.refused`, `push.call.missed`). A call the system refuses ends as missed after the same timeout. |

## Debug wake injector

Compiled only with `RAMFLUX_DEBUG_WAKE` (Debug). It runs a wake through the same `WakeProcessor`, `WakeDispatcher`
and `CallWakeHandler` as the extension and PushKit, with source `debugInjector`. Entry points: the launch argument
`-RFDebugWake call` or `-RFDebugWake message` (cold start, before the shell loads), and an alert push carrying
`rf_debug` sent to the app in the foreground (`debug-call.apns` rings, `debug-message.apns` runs the message path;
silent pushes cannot be sent, see F6). `scripts/check-release-symbols.sh` fails when a Release binary contains the
injector.

| F15 | Time Sensitive and Scheduled Summary settings | Both exist on the simulator and are read through `UNNotificationSettings`. Time Sensitive reads "not supported" until the app declares `com.apple.developer.usernotifications.time-sensitive`; with it declared the build still signs ad hoc and the setting reads on. Scheduled Summary reads off by default. |

F4 to F9 and F12 to F16 are recorded by the tasks that need them.
