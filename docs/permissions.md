# Device permissions

`FeaturePermissions` owns the local permission screens, explanation/dismissal state,
view model and coordinator. `NativeDevicePermissionsRepository` is the only caller
of OS authorization APIs. Status is not an SDK projection and is never sent to a node.

Launch and foreground refresh read status without requesting authorization. A newly
created account offers notifications once per installation/device preference store;
unlock and recovery do not offer them. The marker is saved before showing the
explanation. Cancel does not request permission. Continue dismisses the host sheet;
only its dismissal event invokes the system request. Native status is read again
after the decision. System-restricted sensors remain unavailable; they are distinct
from usable provisional notifications or limited photo authorization. APNs registration occurs only after authorized/provisional status.
This module does not prove APNs delivery or connect a new notification backend.

Camera and add-only Photos intents use the same explanation boundary. A denied or
restricted grant is not repeatedly requested; the UI offers the app's system settings.
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
