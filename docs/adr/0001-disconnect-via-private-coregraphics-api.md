# Disconnect uses the private CoreGraphics display-enable API

"Disconnecting" a Display must stop macOS from rendering to it, not just make it look dark. Only the private `CGSConfigureDisplayEnabled` call achieves this; DDC power-off and brightness/black-overlay approaches leave WindowServer rendering to the Display. We accept the consequences: no Mac App Store, no App Sandbox, Developer ID distribution only, and the risk that a future macOS breaks it.

Disconnected state is deliberately never re-applied — a reboot or cable replug always brings every Display back, so a bad state is always recoverable. Quitting the app Reconnects every Disconnected Display first. Disconnected Display IDs are remembered only so that, after a crash, the next launch can offer to Reconnect them; they are never used to Disconnect again.

Verified with `prototypes/disconnect-probe` on both architectures, and the two differ: on macOS 27 (Apple Silicon, virtual Display) a Disconnected Display disappears from both the active and the online display lists; on macOS 15 (Intel, built-in panel) it stays online and only leaves the active list. The app therefore must not rely on the online list to find Disconnected Displays — it remembers their IDs on both architectures. A run made while the main Display was asleep failed with CGError 1014 and the same run succeeded once it was awake — the app should expect Disconnect to fail while Displays sleep.

## Considered Options

- DDC/CI power-off — monitor sleeps, but macOS still renders to it.
- Brightness zero / black overlay — purely cosmetic.
