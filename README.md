# Pika Dots

Tiny skill-backed companions for your Mac. Drag a dot from the menu bar onto a window, give it a task, and get a floating response.

## Run

Requires macOS 14+ and Xcode command-line tools with Swift 6.

```sh
./scripts/build-app.sh
open "dist/Pika Dots.app"
```

For development, use `swift run` or open `Package.swift` in Xcode and run PikaDots. The app appears in the menu bar, not the Dock.

## Try it

1. Open a document or browser window.
2. Open the Pika Dots menu-bar icon.
3. Drag a colored dot onto that window. Clicking its name also attaches to the topmost application window.
4. Enter a request and press Go.
5. Focus starts an app-switch reminder (10-second checks, 60-second cooldown). Chill starts a two-minute break. Explain demonstrates the response flow.
6. Close the bubble or choose Stop session to end monitoring.

**This is a local demo.** No model request is made, and no screenshot is captured or sent. Window selection reads public window metadata; macOS may omit window titles depending on permissions. Focus detects app switches, not whether content is actually procrastination. All skills are bundled Markdown files. The model and capture integration are participant workstreams below.

Current scope: one task bubble at a time, one monitoring session, pinned screen position. Windows do not follow their target when it moves. Attaching another dot closes the previous bubble and stops its monitor. The app is locally ad-hoc signed, not notarized for distribution.

## Team

See [participant tracks](docs/PARTICIPANT_TRACKS.md) for file ownership, shared contracts, integration order, and demo acceptance checks.

```sh
swift build
swift test
```
