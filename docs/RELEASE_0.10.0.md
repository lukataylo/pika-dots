# Pika Dots 0.10.0

Cats follow the target window’s desktop stacking order and retain their purpose and supervision state when covered. Settings restart saves and restores attachments to still-open visible target windows.

Focus checks YouTube window titles every two seconds. Optional “Pause screen on YouTube” interrupts typing with a dismissible pause screen; Continue/Escape snoozes for one minute, and Stop supervision ends it. Other content uses selected-window AI checks every 15 seconds while foreground. Temporary errors retry; right-click shows status and Check now.

Screen Recording Check again probes ScreenCaptureKit rather than relying only on cached permission status. Restart fully exits before relaunching. Native notifications fall back to short in-app banners when alerts are disabled.

Validation: 26 automated tests passed, two optional live tests skipped. App launch, artwork, and target-relative window order checked. Full permission-toggle recovery and pause-screen interaction require teammate end-to-end checks.

Universal Apple Silicon/Intel, macOS 14+. Developer ID signed; not notarized. Each teammate supplies their own API key. See TEAM_TESTING.md for setup and limits.
