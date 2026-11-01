# Supervision verification — 0.8.1

## Passed

15 tests passed, including one opt-in live OpenAI test making three requests with synthetic screenshots. No personal browser content was sent.

- Relevant database migration plan: model returned NO_NUDGE.
- Entertainment feed while the purpose was a migration plan: model returned a reminder referencing the migration.
- Coding during a break: model returned a break/relaxation reminder.
- Focus: switching away triggers a reminder, staying in the target app stays quiet, cooldown suppresses repeated nudges.
- Chill: typing activity triggers one reminder within the cooldown, break completes once.
- Stop cancels pending reminders. Starting Chill replaces the Focus local monitor.
- Tests use accelerated timers, not a real two-minute wait. The live model results are a smoke test, not a guarantee of future classification.

## Fixed while testing

Focus now enables screenshot supervision on drop so it can assess changes inside a browser, rather than only app switching. Requires screen permission and a usable API key.

Chill now checks keyboard activity during its break. It does not read typed characters and cannot determine whether typing is work. It nudges rather than blocks input or applications.

Reminders use a small dismissible toast visible even when the attached application is in the background. The toast disappears after ten seconds. Stop/dismiss ends the owning local monitor; switching Focus/Chill pauses the other mode's AI task and watch loop.

## Not yet verified

Chrome is not installed on this machine, so no real Chrome attachment/tab-switch test was performed. Dragging, ScreenCaptureKit permission/capture, UI movement, and toast presentation still need an end-to-end session on a teammate's Mac. Intel runtime is also untested.

## Reproduce

`swift test` runs deterministic tests and skips the network smoke test.

`PIKA_LIVE_TESTS=1 swift test` additionally calls OpenAI with the three synthetic window fixtures. Requires an API key with quota; incurs a small API charge.

For manual Chrome testing: open an innocuous work page, drop Focus, grant screen permission, and set a concrete purpose. Change to an unrelated entertainment page in the SAME Chrome window. Wait up to 45 seconds for an AI check. Then test a different app for the local switch reminder. Drop Chill, type for at least ten seconds, and check for a break nudge. Dismiss and confirm no further reminders. Never test on private account pages unless you intend to send their selected-window contents to OpenAI.
