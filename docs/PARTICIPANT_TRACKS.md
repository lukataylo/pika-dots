# Parallel participant tracks

Four people: three implementation tracks plus one integrator/demo owner. This document is the handoff; tracks can start simultaneously against the existing contracts. Do not all edit the app entry point.

## Shared baseline

- Native SwiftUI/AppKit executable, macOS 14+, no external dependencies.
- Core/Models.swift owns AgentDefinition, WindowContext, TaskRequest, AgentResponding.
- Runtime input: skill text, prompt, window metadata. Future capture must be explicit context, not instructions.
- AppController owns the selected bubble and invokes the responder. UI state remains on the main actor.
- Current response contract is one async String, with thrown errors and task cancellation. Keep it stable for the first integration.
- Runtime dot concurrency is distinct from participant concurrency: the MVP has one bubble and one monitor. Multiple concurrent bubbles are a later feature.

## Participant 1 — Desktop and character interaction

Branch: feature/desktop-interaction

Own: Sources/PikaDots/Desktop/ only.

- Improve drop feedback and persistent dot appearance using native shapes.
- Attach the floating bubble to the selected window edge; follow movement only if time allows.
- Make target selection work across displays and handle a closed target.
- Keep clicking a roster name as a fallback.
- Coordinate bubble lifecycle changes with the integrator.

Acceptance: drag onto two different apps; verify the correct target; test a secondary display if available; empty desktop drops remain usable; panel input accepts typing.

## Participant 2 — Model and window context

Branch: feature/model-runtime

Own: Sources/PikaDots/Runtime/ and a new Sources/PikaDots/Capture/ directory.

- Implement AgentResponding with a real provider; pass agent.skillText as instructions.
- Implement selected-window capture with ScreenCaptureKit and a clear user-triggered permission flow.
- Give the integrator a capture service and provider factory; propose shared type changes before editing Core.
- Never store credentials in source control or log window images/prompts.
- Keep DemoResponder as a fallback when credentials or capture permission are missing.
- Explain should produce an answer grounded in the selected window, explicitly reporting unavailable context.

Acceptance: one genuine window-grounded response, denied-permission fallback, recoverable request error, cancellation when the bubble closes. Credential setup is a separate integration step; none is configured in this baseline.

## Participant 3 — Skills and companion behavior

Branch: feature/companion-behaviors

Own: Sources/PikaDots/Behaviors/, Sources/PikaDots/Resources/Skills/ and behavior tests.

- Refine Focus/Chill/Explain skill files with distinct personalities.
- Replace fixed timers with a configurable duration and an explicitly labeled demo interval.
- Improve Focus's app-switch heuristic without claiming it understands distraction.
- Ensure Focus and Chill replace each other, reminders have cooldowns, and Stop cancels all timers.
- Expose monitor status via a small callback for the integrator; do not edit Views.swift independently.

Acceptance: one nudge after leaving the chosen app, no repeated nudge during cooldown, Chill completion once, no reminders after Stop.

## Participant 4 — Integrator, release, demo

Own: Sources/PikaDots/PikaDotsApp.swift, Core/, Package.swift, scripts/, README, shared UI wiring.

- Protect the contracts and integrate small commits as they become available.
- Wire real capture/provider and behavior controls into the bubble.
- Test the packaged .app, not just swift run; keep bundle identifier stable for permissions.
- Maintain a working demo branch and record a backup walkthrough.

## Working agreement

Start from the same baseline commit. Each participant creates their branch with `git switch -c feature/<track>` in their own clone. Land small, compiling changes. Do not reformat other tracks. Agree on any new model fields with the integrator before implementation. No force pushes to main.

## Integration order and timebox

1. First 45 minutes: all participants run the packaged baseline; confirm drag and permissions on the demo Mac.
2. Next 90 minutes: desktop polish, real provider/capture, behavior improvements proceed independently.
3. Midpoint: integrate a single real Explain response before adding further features.
4. Next hour: integrate Focus/Chill controls and polish.
5. Final hour: freeze functionality; rehearse and record the backup.

Cut first: window following, elaborate animation, multi-window concurrent agents. Keep: drag/select, prompt, one real answer, one understandable nudge.

## Final demo acceptance

- Fresh launch shows the roster in the menu bar.
- Each dot loads a nonempty bundled skill.
- Drop identifies the intended external window.
- Explain answers a question about actual captured content, or clearly reports demo/unavailable mode.
- Focus and Chill never run conflicting monitoring timers.
- Closing a bubble cancels pending work; Stop ends monitoring.
- Permission denial and network failure leave the app responsive.
