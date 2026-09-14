# Owl

A tiny SwiftUI menu bar app that keeps your Mac awake, including with the lid closed.

Click the owl. Use the slider to pick **1**, **3**, **6**, **9 hours**, or **∞**, then click **Start**. The default is 9 hours; your last selection is remembered. The owl turns amber.
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
**Keep Awake on Battery**, **Sleep at 10% Battery**, **Launch at Login**, and **Quit Owl** are always visible below the session actions.
Keep Awake on Battery is off by default and remembers your choice:
- **Off:** keeps working with the lid closed while plugged in. On battery, keeps
  working with the lid open; closing the lid (or unplugging while closed) ends the
  session and puts the Mac to sleep.
- **On:** keeps working even on battery with the lid closed.

**Sleep at 10% Battery** is on by default. During an active session it puts the Mac to sleep at 10% or below when unplugged, even with the lid open or unlimited time selected. Plugged-in Macs are unaffected. Toggle rows highlight on hover and switch when clicked anywhere without dismissing the panel.

Settings are captured once when Start is clicked. All toggles are disabled while a session is active or starting; stop the session to change them.
Launch at Login uses macOS's login-item setting and is off by default. It opens Owl
when you sign in; you still choose a duration to start keeping the Mac awake.
Quit Owl exits the app and the helper restores normal sleep.

## How it works

Owl uses `caffeinate -ims`, plus `pmset -a disablesleep 1` when plugged in or
Keep Awake on Battery is enabled. The Mac stays awake
while the display can turn off normally. macOS notifications report power-source,
battery, lid and display changes. Owl requests display sleep once when a session
starts with the lid closed, the lid closes, or an external display is unplugged.
It never sends display-sleep requests with an external display connected or when
display detection is unavailable. There are no periodic display-sleep retries.

The helper watches the request directory for start/stop events, watches the app's
process for exit/crash, and schedules one expiry timer for timed sessions. Requests
are immutable during a session. There is no heartbeat, recurring session timer,
or periodic file/battery/lid polling. The app watches status-file changes; its
countdown display refreshes once a minute without contacting the helper. A failed
sleep-restoration command is the sole exception: cleanup retries until it succeeds.

The helper is installed for one Mac user and accepts only 1-, 3-, 6-, 9-hour or
indefinite requests. It never grants passwordless sudo or executes commands from
requests. Quit or a detected app crash ends the session; a root-owned marker lets
launchd restore sleep after helper crashes or reboots. Stale start requests are
not replayed after recovery. The helper refuses to take over another tool's global
sleep setting. Selecting Start installs an updated helper when needed.

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
