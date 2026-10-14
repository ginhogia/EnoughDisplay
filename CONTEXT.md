# EnoughDisplay

A macOS menu-level utility for controlling the displays attached to this Mac: their resolution, whether they participate in the desktop at all, and their brightness.

## Language

**Display**:
A screen currently known to macOS, either built-in (laptop panel) or external (attached monitor).
_Avoid_: Monitor, screen (in code and UI copy)

**Disconnect**:
Removing a Display from the desktop configuration so macOS stops rendering to it entirely, as if its cable were unplugged. Windows move to the remaining Displays.
_Avoid_: Turn off, close, sleep, power off, blackout

**Reconnect**:
Returning a Disconnected Display to the desktop configuration.
_Avoid_: Turn on, enable

**Display Mode**:
One configuration macOS offers for a Display: a logical resolution, a pixel resolution, and a refresh rate. Only modes macOS itself offers exist; custom modes are out of scope.
_Avoid_: Resolution (when the refresh rate or pixel size matters), preset

**Mode Confirmation**:
The countdown after a Display Mode change during which the user must confirm the new mode; without confirmation the Display reverts to its previous mode.
_Avoid_: Preview, trial

**HiDPI**:
A Display Mode whose pixel resolution is twice its logical resolution in each dimension.
_Avoid_: Retina, scaled

**Mirror Set**:
A group of Displays showing the same image, configured outside this app. Only its primary Display offers Display Mode choices; this app never creates or breaks a Mirror Set.
_Avoid_: Clone, duplicate

**Brightness**:
The backlight level of a Display, controlled in the Display's own hardware. A Display whose backlight cannot be controlled has no Brightness; software dimming is not Brightness.
_Avoid_: Dimming, gamma

**Last Active Display**:
The only Display not Disconnected; it can never be Disconnected.
