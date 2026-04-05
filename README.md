# 104 Clock

Swift-native clock-in/out automation for [104](https://pro.104.com.tw) on macOS.

## Components

- **ClockBar/** — SwiftUI menu bar app with in-app 104 login, status refresh, manual punch, and schedule editing
- **clockbar-helper** — Bundled Swift helper used by launchd for scheduled auto-punch runs

## Features

- **Menu bar status** — View today's clock-in/out times at a glance; icon shows an error badge when issues are detected
- **Manual punch** — One-click clock in or out with real-time status updates and native macOS notifications
- **Schedule editor** — Collapsible time pickers to configure auto-punch times, persisted to config and synced with launchd
- **Auto-punch** — launchd-scheduled jobs that automatically punch at configured times with smart guards:
  - Taiwan national holiday detection (cached annually)
  - Late threshold prompts (configurable, default 1200s / 20 min; toggle via `late_prompt_enabled`)
  - Mac wake detection to avoid misfires
  - Random delay (0–900s) for natural timing
  - Kill switch via `~/.104/autopunch-disabled`
- **Web-based login** — Embedded WebKit window for 104 authentication with session cookies stored in macOS Keychain
- **Launch at login** — Registers with `SMAppService` to start automatically on boot
- **Settings window** — Dedicated configuration window for schedule, auto-punch, reminders, wake, refresh interval, and sign out
- **Wake schedule** — Uses `pmset schedule wake` to wake the Mac before scheduled auto-punch times (requires admin approval)
- **Auto-refresh** — Polls punch status in the background (default every 30 minutes, configurable)

## Requirements

- macOS 15+
- A valid 104 account that can sign in through the app

## Setup

```sh
# Build the app bundle locally
make build

# Install to /Applications and install launchd jobs
make install
```

For development:

```sh
make menubar
```

## Usage

Launch ClockBar from the menu bar, sign in through the built-in 104 web view, and then use the app to:

- view today’s clock-in / clock-out status
- punch manually
- change scheduled auto-punch times
- enable or disable auto-punch

Scheduled jobs are managed by the bundled helper executable rather than Python.

Helper CLI commands:

```sh
./ClockBar.app/Contents/MacOS/clockbar-helper config
./ClockBar.app/Contents/MacOS/clockbar-helper status
./ClockBar.app/Contents/MacOS/clockbar-helper punch
./ClockBar.app/Contents/MacOS/clockbar-helper auto clockin|clockout [--dry-run]
./ClockBar.app/Contents/MacOS/clockbar-helper schedule install|remove|status
```

## Makefile Targets

| Target      | Description |
|-------------|-------------|
| `build`     | Compile `ClockBar.app` and bundle the helper |
| `menubar`   | Build and launch ClockBar |
| `install`   | Copy to `/Applications` and install launchd schedules |
| `uninstall` | Remove launchd schedules and delete `/Applications/ClockBar.app` |
| `status`    | Show launchd job state and recent auto-punch logs |
| `clean`     | Delete the local build output |

## Configuration

Config lives at `~/.104/config.json`:

```json
{
  "schedule": { "clockin": "09:00", "clockout": "18:00" },
  "late_prompt_enabled": true,
  "late_threshold": 1200,
  "random_delay_max": 900,
  "autopunch_enabled": true,
  "wake_enabled": false,
  "wake_before": 300,
  "refresh_interval": 1800
}
```

All time-based values (`late_threshold`, `wake_before`, `random_delay_max`, `refresh_interval`) are in **seconds**.

Disable auto-punch temporarily with:

```sh
touch ~/.104/autopunch-disabled
```
