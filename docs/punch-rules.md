# Punch System Rules

The rules that govern when ClockBar punches automatically, when it notifies, and when it stays silent. These are the steady-state behaviors after the AppleScript dialog was removed in favor of notifications.

> All reminders are macOS user notifications. Successful punches (auto or manual) post a confirmation notification with the time recorded.

## Roles

- **Helper** (`clockbar-helper`, launchd-driven) — fires at scheduled time, performs the silent auto-punch when the device is awake.
- **App** (`ClockBar.app`, menu-bar resident) — observes wake / lid-open / user-active events via `NSWorkspace`, runs the cross-day check, and decides whether a Late or Missed notification is due.
- **Notification ledger** (`~/.104/notification-ledger.json`) — caps per-shift notifications at one of each kind per `(action, date)`.

## Scheduled time

| Condition | Outcome |
|---|---|
| Device awake, not yet punched | **Auto-punch silently**, then post a confirmation notification (`Clocked in at HH:MM` / `Clocked out at HH:MM (in: HH:MM)`). |
| Device awake, already punched (any device) | No-op. No notification. |
| Device asleep | Helper does not fire. The Same-day rules below take over once the device wakes. |

## Same-day

Triggered by the app on `NSWorkspace.didWakeNotification` and `screensDidWakeNotification` (see `WakeObserver`). Each wake also fires `viewModel.refresh()` so the menu bar reflects current state without waiting for the next refresh-timer tick.

| Condition | Outcome |
|---|---|
| After scheduled time, not punched, within grace period | **Late notification** with a Punch Now action. Tapping calls `StatusViewModel.punchNow()`. |
| After grace period, not punched | **Missed notification** with a Punch Now action. Same handler. |
| Already punched (any device) | No notification. |
| Inside grace period AND a Late notification has already fired today | Suppressed by ledger. |
| Past grace AND a Missed notification has already fired today | Suppressed by ledger. |

The "Late" and "scheduled-time-but-still-pending" cases are the same notification — there is no separate "your shift just started" reminder when auto-punch already covered it.

## Missed / Late escalation

The grace period is `missedPunchNotificationDelay` from `~/.104/config.json` (seconds; existing field). The classification is purely time-based:

- `now − scheduledTime ≤ grace` → Late
- `now − scheduledTime > grace` → Missed

A Late and a Missed for the same `(action, date)` may both fire across a single day if the user is intermittently active — once each, in order. The ledger blocks duplicates.

## Cross-day

Triggered on app launch and on every wake (same `WakeObserver` path as Same-day; the ledger dedupes so each `(action, date)` notifies at most once). The app walks back through `HolidayStore` to find the most recent expected work day before today, then checks `Clock104API.getStatus` for that date.

| Condition | Outcome |
|---|---|
| Previous expected day complete (clock-in and clock-out both present) | No-op. |
| Previous expected day missing a punch and beyond grace | **Cross-day notification — informational only, no Punch Now button.** Body: "Yesterday's clock-out is missing — file a correction in 104." Default tap opens the menu bar; the user submits the correction in the 104 web UI. |
| Cross-day notification already fired for that `(date, action)` | Suppressed by ledger. |

Punching today does not fix yesterday, so no CTA is offered. 104 corrections require the web form.

## Cross-cutting rules

- **Already punched on another device.** The coordinator queries the server before notifying. If the server reports the punch, no notification fires (and the helper exits at the same `existingPunch` guard during auto-punch).
- **Offline.** `getStatus` failures cause the coordinator to skip the check and retry on the next wake / active tick. No speculative notifications.
- **Holidays and weekends.** Both helper (via `HolidayStore` and the launchd weekday gate) and the app coordinator skip these days entirely.
- **Notification cap.** At most one Late, one Missed, and one Cross-day notification per `(action, date)`. Confirmation notifications from successful punches are not capped.
- **Manual punch.** Always available from the menu-bar UI regardless of the rules above. A successful manual punch posts the same confirmation notification as a successful auto-punch.

## Quick reference

| Event | Helper auto-punches? | Notification fires? |
|---|---|---|
| Device awake at schedule, unpunched | Yes | Confirmation only |
| Device asleep at schedule | No | Late or Missed when device wakes (see Same-day) |
| Already punched (this device or another) | No | None |
| Schedule passed, lid opens within grace | No | Late |
| Schedule passed, lid opens after grace | No | Missed |
| Lid opens next day, prior day's punch missing | No | Cross-day (informational) |
| Holiday or weekend | No | None |
| Offline | No | None (deferred) |

## State files

| Path | Purpose |
|---|---|
| `~/.104/config.json` | Schedule, grace period, holiday cache opt-in. |
| `~/.104/session.json` | 104 session cookies (0600). |
| `~/.104/clockbar.log` | Append-only event log; every decision above writes a structured line via `Log.info/warn/error`. |
| `~/.104/notification-ledger.json` | Per-`(kind, action, date)` notification record. Entries older than 14 days trimmed on load. |
| `~/.104/autopunch-disabled` | Touch this file to disable the helper without editing config. |
