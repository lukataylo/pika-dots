# Pika Dots 0.10.0 — teammate testing

## Install

Download PikaDots-0.10.0-universal.zip from this repository's v0.10.0 GitHub release. Unzip, move Pika Dots.app to Applications, and open it. macOS 14 or later is required. The same package includes Apple Silicon and Intel executables. Quit older versions first.

This is a Developer ID signed hackathon test build, not a notarized release. macOS may block its first launch. If you trust this team's build, use System Settings → Privacy & Security → Open Anyway after attempting to open it. Do not disable Gatekeeper. Building locally from source is another option.

## Setup

The first launch opens Companions & Setup. Enter your own OpenAI API key into the secure field and click Save key. It stays in this Mac's Keychain; no API key is distributed in the app. You need API access and quota for the selected model (default gpt-4.1-mini). The Keychain entry is shared across versions of this app, not across teammates' Macs.

Use the shelf gear → Settings & permissions to request or recheck access. Allow Pika Dots in System Settings → Privacy & Security → Screen & System Audio Recording when it asks. Restart after granting permission if requested. Accessibility and Input Monitoring permissions are not needed: keyboard activity uses idle time, never the characters you type.

## Create and edit

Click the menu-bar cat, then +, or right-click the shelf → Create or edit companions.

- Choose a companion to edit, or New companion to create one.
- Set its name, colour, description, and skill Markdown.
- Promptable: click its attached dot, type a purpose, then Go.
- Supervisor: supply a default purpose. Dropping a custom supervisor starts an immediate AI check and a check every 15 seconds while that target window is foreground. Background/minimized windows pause checks.
- Built-in Focus combines local app-switch reminders with AI window checks. Chill uses a two-minute break timer and keyboard-activity reminders. Their Markdown is used when you explicitly ask the AI with Go/Watch.
- Saving updates the skill file and dismisses that companion's active attachment. Reattach it to use the new settings.

Skills are ordinary .md files at `~/Library/Application Support/PikaDots/Companions/`, with mode/name/colour in roster.json. Direct file edits load on the next launch. The app editor is the easiest way to update them.

## Test checklist

1. Create a promptable companion. Edit its Markdown, save, quit, and reopen. Confirm the name and skill persist.
2. Drag it onto Notes, then Chrome (or another browser). Move and resize each window; the tiny dot should follow its edge.
3. Click the dot, ask a question about visible content, and verify a grounded answer.
4. Create a supervisor with a clear default purpose; drop it without typing. Confirm the green Watch indicator and an initial response.
5. Change to another app and confirm periodic checks pause; return and wait 15 seconds.
6. Right-click the dot → Dismiss. Confirm reminders stop and it disappears.
7. Deny screen access or use an invalid key and verify a visible, recoverable error. Never include keys or private window contents in a bug report.

Report Mac model/architecture, macOS version, app version, target app, reproduction steps, and a screenshot with private details removed.

## Known limits

Cross-application attachment follows window IDs by polling; it is not a child NSWindow of another process. Maximized windows keep tabs inside the title-bar edge where there is no room above. Protected windows may refuse capture. Tasks provide analysis and suggestions, not automatic typing or clicking. Focus detects YouTube from the attached browser window title every two seconds; other content uses AI checks. Window-colour sampling is approximate. Intel compilation is verified; runtime behavior still needs a teammate's Intel Mac.

Version 0.10.0 routes all replies through notifications rather than an attached response box. Use the gear → Notifications → Test to check delivery. Cats are 2× larger. If alerts are disabled, a compact corner banner appears for five seconds.

Version 0.10.0 keeps only the cat on the window by default. Click to set a purpose; right-click for supervision, settings, and dismissal. Click elsewhere or press Escape to hide the input.


## 0.10.0 supervision and attachment checks

- Move a target window, cover it with another window, then bring it forward. Its cat stays immediately above that window in the desktop stacking order, retaining its purpose and paused/running state. Minimized targets hide the cat until they return.
- Restart from Settings: attachments restore if the same target windows are still open and visible. Closing and reopening the target application creates new window IDs; reattach then.
- Edit Focus: “Treat YouTube as a distraction” is enabled by default. Attach it to your browser, then open YouTube in that same window. Detection runs every two seconds without requiring an AI response. Turn this off when using YouTube for research.
- “Pause screen on YouTube” is optional and off by default. When enabled, a Pika pause screen takes keyboard focus. Continue (or Escape) allows one minute; Stop supervision stops that companion. Tabs are never closed and typed text is never recorded.
- Right-click the cat for current status, Check now, pause, Settings, or Dismiss. Background windows retain attachment state while screenshot checks pause. Temporary API failures retry instead of stopping supervision.
- After changing Screen Recording access in macOS, use Settings → Check again. This performs a real capture-service check. If macOS still requires a restart, use Restart Pika Dots; it saves attachments and fully quits before reopening. The user must approve access in macOS.

Validation: 26 automated tests passed; two opt-in live API tests skipped. Universal signed package built successfully. Running app launch, cat rendering, and target-relative desktop window ordering checked. Permission deny/grant recovery and the optional pause screen still need end-to-end teammate checks.
