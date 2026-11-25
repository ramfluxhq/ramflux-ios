# Device permissions

`FeaturePermissions` owns the local permission screens, explanation/dismissal state,
view model and coordinator. `NativeDevicePermissionsRepository` is the only caller
of OS authorization APIs. Status is not an SDK projection and is never sent to a node.

Launch and foreground refresh read status without requesting authorization. A newly
created account offers notifications once per account in the local preference store;
unlock and recovery do not offer them. The marker is saved only when the explanation
sheet resolves, including cancellation. An interrupted sheet remains unconsumed.
The legacy device-wide marker is ignored because it cannot identify an account. Cancel does not request permission. Continue dismisses the host sheet;
only its dismissal event invokes the system request. Native status is read again
after the decision. System-restricted sensors remain unavailable; they are distinct
from usable provisional notifications or limited photo authorization. Status reads have no registration side effects. Foreground and completed notification
requests explicitly register for APNs only after a fresh authorized/provisional status check.
This module does not prove APNs delivery or connect a new notification backend.

Camera and add-only Photos intents use the same explanation boundary. A denied or
restricted grant is not repeatedly requested; the UI offers the app's system settings.
Settings navigation keeps the originating active window scene. A user request made
while inactive is held until foreground activation; cancellation clears that intent.
The notification-needed sheet uses the public notification-settings URL; the status
page uses the public app-settings URL. A successful system completion confirms URL
acceptance, not which Settings page was displayed.
Foreground refresh reads changes made there. The settings list includes unavailable
incoming-call support, current microphone status, picker/file access that needs no
permission, and system background refresh restrictions. Microphone requests remain
unavailable until voice media exists (request R28). The chat requests the camera through
this flow only when the user takes a photo for a message, and add-only Photos access only
when the user saves an image; the system photo and file pickers need no permission. Linking
a device from this phone shows a code and never scans one (joining is request R32), so
pairing requests nothing. Incoming calls use CallKit, which needs no permission; the
integration stays inert while the call media engine refuses. No broad photo-library,
storage, contacts, location, Bluetooth, calendar, tracking or local-network grant exists.

The app declares only camera, microphone and add-only Photos usage descriptions,
localized in English and Simplified Chinese. Its sole background mode is
`remote-notification`. Signing profiles need the Push Notifications capability;
Debug uses development APNs and Release uses production APNs. Run `xcodegen generate`
and `python3 scripts/check-permissions.py` to check declarations.

Scoped checks are `swift test --package-path Packages/FeaturePermissions`, AppData
and onboarding tests, native `DevicePermissionPlatformTests`, confirmation-control
tests, and permission screen captures in light/dark with en/zh-CN/expanded copy.
The optional native `LivePermissionProbeTests` uses the real OS repository and
host explanation/presenter. It skips in ordinary CI. On a fresh simulator authorization
state, set the app's `RFPermissionProbe` defaults key to `notifications`, `camera` or
`photoAdd`, run the explanation/prompt test and interact with its real explanation/system prompt.
The probe has a bounded deadline and records actual system status; it does not
manufacture grants. Remove the defaults key afterward. The separate `provisional` opt-in test uses the real OS provisional API on a fresh
simulator and verifies the local Limited status. Production requests remain
alert/sound/badge only. System-restricted enum mapping is tested without
manufacturing device-management restrictions.

Push integration owns token forwarding and generic sender content. Media and pairing
integration own the currently dormant camera/add-only Photos intent callers.

The optional `LivePermissionProbeTests.testOptInRealSettingsDestination` accepts
`RFSettingsProbe=app` or `notifications` and invokes the real native route from an
active scene. It skips normal CI. Inspect the actual Settings destination when
using it; URL acceptance alone is insufficient. Remove the probe preference afterward.

On fresh simulators the public Settings routes can open the Settings root instead
of the app page. The denied screen provides the manual Settings > Apps > Ramflux
path in English and Simplified Chinese and scrolls for larger text. Cold navigation
to the app and notification pages still requires physical-device verification.

## Message notifications (beta flow 11)

`MessageNotifier` (AppData) posts local notifications for messages that arrive while the app is not
active and the process and core are alive. It is one more observer on the shared event source: on every
invalidation it reads the first `conversation.directory` page (100 rows) and compares unread counts with
its previous read. The first read after following an account is only a baseline; muted conversations
neither notify nor count. The app follows the active unlocked account (a locked session stops it; the
privacy shield of an inactive scene does not) and tells it whether the scene is active.

- Content is the catalog's generic "New message" (`notification.message.title`), with no message text, no
  sender, no conversation title and no conversation id. There is one notification per account: its request
  id is the fixed slot `ramflux.message.local.<n>` (`AccountSlots` numbers the accounts on this phone), so a
  later message replaces the earlier notification, and its category is `RF_MESSAGE`. The slot id in
  `userInfo` is mapped back to the account in memory; after the process ends a tap opens the app only. A
  pushed message notification (see `docs/push.md`) removes the local slot before it is shown.
- A tap sends `AppShellAction.openWhenReady(nil, account:)`: the shell shows that account's chat list
  once that account is active and unlocked and the privacy shield is down, so a locked or concealed
  session shows unlock first, and another account becoming active drops the route.
- Notifications are not presented while the app is active; becoming active removes delivered ones.
- The badge is the unread total of the loaded rows (the first directory page, without muted rows).
  Limitation: the directory is ordered by conversation id, not activity, and the SDK has no account-wide
  unread total, so detection and the badge cover only those rows.
- Authorisation stays with the existing permission flow. `NativeMessageNotificationCenter` never
  requests it; it posts only when alerts are allowed and sets the badge only when badges are allowed.
- Limitation: entering the background shuts the core down to release the database writer
  (`PhoneLifecycle`), so nothing is observed there. In practice local notifications cover the inactive
  scene (Notification Centre or Control Centre over the app, the app switcher, an incoming system
  alert); delivery to a backgrounded or terminated app needs the push work below.

### Background delivery

The node sends an APNs alert push with `mutable-content` and a generic localization key when a delivery is
queued for an offline device (payload contract: `docs/push.md`). A notification service extension
(`RamfluxNotificationService`) shows the fixed generic text of the wake's class; it shares the SDK data root (App
Group container) and the Keychain access group with the app, as `docs/bridge.md` describes. The core's wake-fetch
entry point can fetch the named deliveries from the extension without decrypting them; showing, suppressing and
clearing by decrypted state, the call wake path (PushKit and CallKit) and the token and route registration are
later tasks of the push work and are not part of the app yet. Until then `registerForRemoteNotifications` runs
after authorisation and nothing registers the token with the node.
