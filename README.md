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
  - Late threshold prompts (configurable, default 20 min)
  - Mac wake detection to avoid misfires
  - Random delay (0–900s) for natural timing
  - Kill switch via `~/.104/autopunch-disabled`
- **Web-based login** — Embedded WebKit window for 104 authentication with session cookies stored in macOS Keychain
- **Launch at login** — Registers with `SMAppService` to start automatically on boot
- **Auto-refresh** — Polls punch status every 60 seconds in the background

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
  "late_threshold_min": 20,
  "random_delay_max": 900,
  "autopunch_enabled": true,
  "wake_enabled": false,
  "wake_before_min": 5
}
```

Disable auto-punch temporarily with:

```sh
touch ~/.104/autopunch-disabled
```
