# Pika Dots

A native macOS menu-bar roster of tiny, skill-backed companions. Drag a dot onto a Chrome, Notes, or other standard application window, give it an app-specific purpose above the window, and ask OpenAI about that window.

## Run

Requires macOS 14+, Swift 6 command-line tools.

```sh
./scripts/build-app.sh
open "dist/Pika Dots.app"
```

Or open Package.swift in Xcode. The app lives in the menu bar, not the Dock. Quit any previous build before launching a new one.

## Configure

Keep `OPENAI_API_KEY` in the ignored `.env.local` at the repository root. The packaged app finds it when launched from `dist/`. For an app moved elsewhere, use `~/Library/Application Support/PikaDots/.env.local`, or launch with the environment variable set. Keys are read at request time, never included in the app bundle. Optional `OPENAI_MODEL` overrides `gpt-4.1-mini`.

## Use

1. Open the roster from the menu-bar icon. The menu opens a transparent row of small named companions. Right-click it for Stop all or Quit.
2. Drag a character onto a window, or click its name to attach to the topmost external window.
3. Enter its purpose in the tab above the window and press Go. Purposes are remembered per companion and application.
4. Click the perched dot to expand or collapse the purpose tab. Drag the dot to move it to another window.
5. On the first request, allow Pika Dots in System Settings → Privacy & Security → Screen & System Audio Recording. Restart if macOS requests it.
6. Go sends a single selected-window image and your task to OpenAI. Watch sends an immediate request and checks every 15 seconds while that target window is foreground; background or minimized targets pause checks.
7. Watching shows a green indicator. Click Watch again, detach the dot, or choose Stop all to stop pending checks. Keyboard monitoring uses a local idle-time signal; it never records typed text, key codes, or clipboard contents.
8. Focus starts local app-switch reminders; Chill starts a two-minute timer. These modes replace one another. Errors stop periodic watching and appear in the expanded tab.

Three dots may attach to three different windows. Each window gets one dot and a purpose field. Dots stretch along the direction of dragging, spring into place, blink, and breathe; reduced-motion settings disable stretching and idle motion.

## Scope and limitations

Chrome, Notes, and standard macOS apps use the same window-ID based path; there is no app-specific browser extension or Accessibility permission requirement. Protected content may not be capturable. A minimized window or a window on another Space hides its dot; restoring the same window restores it. Closing a window leaves its attachment dormant until you reattach that dot. Full-screen/maximized windows place the field just inside the top edge when there is no space above. Window following uses a 250 ms poll, not a native child-window relationship across processes.

The AI can analyze and suggest text/code. It does not click, type, or modify the target app. Focus detects switching apps rather than classifying actual procrastination. A screenshot/API failure is displayed in the bubble; it does not fall back to a fabricated answer. Tasks are one-shot, without conversation history.

## Team and checks

See [participant tracks](docs/PARTICIPANT_TRACKS.md). The baseline now includes real capture/runtime and window following; participants should extend these existing components rather than add parallel implementations.

```sh
swift test
```

The packaged app is ad-hoc signed for local use, not notarized for distribution.

Build 0.3 adds the perched dot and expanding window tab. If you see “Local demo provider,” quit that old process and launch the current packaged app. The drawer displays 0.3 so you can verify the running version.

Version 0.6: a custom transparent status-bar panel replaces the system popover. Focus and Chill start local behavior on drop with default purposes and no typing. Explain opens its prompt. Screenshots and model requests still occur only through Go or Watch. Colour sampling excludes window shadows and stays local.

## Create your own dots (0.8)

Use the + on the shelf to open Companions & Setup. Create or select a companion, edit its skill Markdown, choose Promptable or Supervisor, and save. Custom supervisors require a default purpose and start periodic window checks on drop. Skills and configuration persist in Application Support; editing dismisses the active attachment so it can be reattached with the new settings. The secure setup field stores each teammate’s own key in their Mac’s Keychain.

Download the universal team test package from the v0.8.0 release. See [team testing instructions](docs/TEAM_TESTING.md). Use `scripts/package-release.sh` to rebuild the package; set PIKA_SIGN_IDENTITY to a local signing certificate to sign with Developer ID. No secrets are bundled.

## Permissions and artwork (0.9)

The shelf has a soft rounded background and a gear button. Settings can request screen access, refresh its status, open the macOS permission pane, and restart the app. Permission failures have a small Settings/Retry card. macOS permission approval remains a user action. The three generated character PNGs are bundled in Resources/Characters; see docs/CHARACTER_ARTWORK.md for prompts.

## Compact notifications (0.9.1)

Attached windows no longer show response/error boxes. Updates use native notifications capped at 14 words / 100 characters, with a five-second corner banner fallback when disabled. The gear includes notification status, Enable, and Test. Cat views are 40 points across shelf, dragging, and attachment.
