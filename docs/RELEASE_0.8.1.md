Supervision fixes and tests for the universal macOS 14+ team build.

- Focus now starts screenshot supervision on drop, including changes inside the same browser window (45-second foreground checks).
- Chill nudges when keyboard activity resumes during its two-minute break.
- Reminders appear as a small dismissible toast even outside the attached app.
- Focus/Chill modes cancel the other mode's supervision; Stop cancels reminders.

15 tests passed, including a live OpenAI vision smoke test on three synthetic screenshots (work, entertainment, and coding during a break). Chrome is not installed on the test machine, so real Chrome end-to-end behavior remains a teammate test.

Universal Apple Silicon/Intel package, Developer ID signed, not notarized. Use your own API key in Companions & Setup. No key is bundled. Screen Recording permission is needed for AI window supervision. Relaxation is encouraged through reminders; the app does not block input or applications.
