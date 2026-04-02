# 104 Clock

Swift-native clock-in/out automation for [104](https://pro.104.com.tw) on macOS.

## Components

- **ClockBar/** — SwiftUI menu bar app with in-app 104 login, status refresh, manual punch, and schedule editing
- **clockbar-helper** — Bundled Swift helper used by launchd for scheduled auto-punch runs

## Requirements

- macOS 13+
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
  "server": { "port": 8104, "token": "" }
}
```

The `server` block is kept for config compatibility but is no longer used by the Swift runtime.

Disable auto-punch temporarily with:

```sh
touch ~/.104/autopunch-disabled
```
