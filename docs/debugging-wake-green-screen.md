# Debugging: green screen after a long sleep (Intel)

Symptom: after a long sleep (a weekend) on an Intel Mac, wake shows an all-green screen, an odd cursor colour, the cursor moves but clicks and keys do nothing.

## Hypotheses

1. A Display left Disconnected reaches standby/hibernate because the pre-sleep Reconnect failed or never ran. Idle sleep turns Displays off about 30 s before the system sleeps, and Reconnect fails (CGError 1014) while a Display is asleep.
2. The hibernate image-restore wake path (standby starts about 24 h into sleep, `standbydelayhigh=86400`) interacts badly with the Intel framebuffer or Thunderbolt drivers, independent of this app.

Neither is verified yet. A Display Disconnected across sleep is already known to crash WindowServer (see ADR 0001).

## Evidence so far (pmset log, Intel Mac, Fri 2026-10-16, app 0.3)

- `EnoughDisplay is slow(9238 ms)`: the sleep acknowledgement was held 9.2 s by the synchronous Reconnect on the main thread, so Reconnect did real work at least once.
- At 17:20 and 19:06 the Display went off ("Display is turned off") about 30 s before "Idle Sleep", and EnoughDisplay is absent from the ack list: consistent with Reconnect failing or having nothing to do.
- Maintenance Sleep / DarkWake cycles every 15-18 min.
- The log ends 23:46 on 10-16, before standby; the weekend wake is missing.

## Commands to collect

Run on the Intel Mac.

Weekend power log (standby, hibernate, wake reasons):

```sh
pmset -g log | awk '$1>="2026-10-16 23" && $1<="2026-10-20"' \
  | grep -vE "Assertions|Kernel Client Acks|Wake Requests|PM Client Acks|HibernateStats|WakeTime|sleepservices" \
  > ~/Desktop/pmset-weekend.txt
```

Look for `Standby`, `Hibernate`, `Wake from`, `Display is turned on`, and the last wake reason and time.

App log (0.4.2 and later logs every pre-sleep Reconnect, success and failure):

```sh
log show --last 2d --predicate 'subsystem == "EnoughDisplay"' --info
```

A `Reconnect of display N failed` line before a long sleep confirms hypothesis 1.

Power settings:

```sh
pmset -g | grep -E "hibernatemode|standby|standbydelay|autopoweroff"
```

Crash reports from WindowServer:

```sh
ls -t /Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports | grep -i -E "WindowServer|panic" | head
```

## Reading the result

- Reconnect failed before sleep and wake is green: hypothesis 1. Next step is waking the Display before Reconnect.
- Reconnect succeeded (or nothing was Disconnected) and wake is still green after standby: hypothesis 2, not caused by this app. Test with `sudo pmset -a hibernatemode 0` or a longer `standbydelayhigh`.
