# Owl

A tiny SwiftUI menu bar app that keeps your Mac awake, including with the lid closed.

Click the owl. Pick **3 hours**, **Indefinitely**, or **9 hours**. The owl turns amber.
Click **Turn Off** to restore normal sleep early. Timed sessions turn off automatically; Indefinitely runs until stopped, quit, or interrupted by the battery policy.
While active, the menu shows the remaining time as **HH:MM left** above Turn Off.
No Dock icon, settings window, accounts, dependencies, or network calls.

## Build and run

Requires macOS 13+ and Apple's Command Line Tools (`xcode-select --install`).

```sh
./build.sh
open Owl.app
```

You can move Owl.app to Applications. The first time you select a duration, macOS
asks for an administrator password to install Owl's helper. Later sessions are one click.
**Keep Awake on Battery**, **Launch at Login**, and **Quit Owl** are always visible below the session actions.
Keep Awake on Battery is off by default and remembers your choice:
- **Off:** keeps working with the lid closed while plugged in. On battery, keeps
  working with the lid open; closing the lid (or unplugging while closed) ends the
  session and puts the Mac to sleep.
- **On:** keeps working even on battery with the lid closed.

Changing the toggle applies to the current session without extending its timer.
Launch at Login uses macOS's login-item setting and is off by default. It opens Owl
when you sign in; you still choose a duration to start keeping the Mac awake.
Quit Owl exits the app and the helper restores normal sleep.

## How it works

Owl uses `caffeinate -ims`, plus `pmset -a disablesleep 1` when plugged in or
Keep Awake on Battery is enabled. The Mac stays awake
while the display can turn off normally. While a session is active, Owl reads the
lid sensor and calls `pmset displaysleepnow` when the lid closes (within about two
seconds), retrying every six seconds while closed if necessary. This sleeps all
attached displays, not only the built-in screen. Opening the lid stops those requests.
A small root-owned launch daemon accepts only 3-hour, 9-hour, or indefinite requests from the user who
installed it; it does not grant passwordless sudo or execute commands from requests.
The helper confirms success before the owl turns amber. Turn Off is confirmed within
about two seconds. If the app crashes, the helper restores sleep within approximately
12 seconds. A root-owned marker enables restoration after helper crashes and reboots.
The helper refuses to start if another tool already disabled sleep. Avoid running
multiple sleep-control tools during an Owl session because pmset is a global setting.
When a new app version needs an updated helper, selecting a duration prompts for
administrator access again to install it.

The helper is installed for one Mac user at a time and polls every two seconds.
It remains available while Owl is closed. Enable Launch at Login to open Owl automatically.
When `apple_secrets/owl-developer-id.cer` and `apple_secrets/owl-developer-id.key`
are present, the build uses the new **Developer ID Application** certificate with
hardened runtime and Apple's secure timestamp. The signing script requires a valid
Developer ID identity and a positive OCSP revocation check. It does not use the old,
revoked Mac Developer export. Signing uses
a temporary keychain that is deleted afterward; secrets are excluded from Git and
the app bundle. Apple's public certificate chain is downloaded from apple.com and
added to the login keychain; the private key remains temporary. Without those files,
builds use `SIGNING_IDENTITY` or ad-hoc signing.
Run `./scripts/release.sh` to build, notarize, staple Apple's tickets, and create a
DMG. It uses the `Owl-notarization` credential profile in the macOS Keychain;
the app-specific password is not stored in the project. Set `NOTARY_PROFILE` to
use a different profile. Releases target the build Mac's architecture (`arm64`
for Apple silicon, `x86_64` for Intel). Share the DMG from `dist/` only after the
release script completes successfully.
Lid behavior depends on macOS/hardware; verify on your Mac.
Keep the Mac ventilated while awake with its lid closed.

## Verify / remove

```sh
./scripts/test.sh
# Read-only live status:
pmset -g
cat /var/run/com.yonigo.Owl/status.json
# Remove the helper and restore sleep (quit Owl first):
sudo /bin/bash scripts/uninstall.sh
```

Tests cover the session, power-mode, and lid-display policies without changing power settings. For a manual end-to-end
check: select 3 hours, approve setup, verify `disablesleep 1` and the amber owl, close
and reopen the lid, then Turn Off and verify `disablesleep 0`. Also verify force-quitting
Owl restores sleep. Check both battery modes by closing the lid and unplugging power:
with the toggle off the session should end and the Mac should sleep; with it on the
session should continue with the display off. Real lid-closed behavior requires a physical hardware test.

Inspired by [Quill](https://github.com/yonigottesman/quill/): a small native menu bar
utility with a direct action and very little UI. Owl uses SwiftUI's MenuBarExtra and
a custom vector owl that adapts to light/dark menu bars and turns amber while active.

## GitHub releases

Push to main after bumping `CFBundleShortVersionString` and `CFBundleVersion` in
`Resources/Info.plist`. The release workflow tests, signs, notarizes and publishes
`Owl.dmg` for Apple silicon. README-only pushes skip the build once that version
is released. The Actions tab also allows a manual run to retry an unreleased version.
The README uses the same download badge as Quill and always links to the latest DMG.

The repository Actions secret `OWL_SIGNING` is a JSON object with:
- `certificate`: base64 of the Developer ID Application DER certificate.
- `private_key`: base64 of its matching PEM private key.
- `apple_id`: Apple account email.
- `team_id`: Apple Developer team ID.
- `app_password`: Apple app-specific password for notarization.

Credentials are prepared only on the release runner and deleted afterward. Never
commit the secret, private key or password. Local releases still use the macOS
Keychain profile described above.
