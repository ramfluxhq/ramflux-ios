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

F4 to F9 and F12 to F16 are recorded by the tasks that need them.
