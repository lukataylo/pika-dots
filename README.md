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

1. Open the roster from the menu-bar icon.
2. Drag a character onto a window, or click its name to attach to the topmost external window.
3. Enter its purpose above the target window and press Go. The app remembers each companion's purpose per application.
4. On the first request, allow Pika Dots in System Settings → Privacy & Security → Screen & System Audio Recording. Restart if macOS requests it.
5. Go sends the task and a fresh image of only that window to OpenAI's Responses API. No background screenshots are uploaded. Window content is untrusted input, separate from the companion's instructions.
6. Drag the attached character onto another window to move it. The overlay follows window movement/resizing, hides when another app is foreground, and returns with its target.
7. Focus starts local app-switch reminders; Chill starts a two-minute timer. These modes replace one another. Stop all cancels requests and timers.

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
