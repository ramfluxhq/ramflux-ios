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
unavailable until voice media exists. Attachment transfer and pairing are currently
unavailable, so those features do not request camera, photo-library or file access;
the local intent APIs are ready for their future integration. No broad photo-library,
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
