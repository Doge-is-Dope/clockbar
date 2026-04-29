# 104 Clock

Swift-native clock-in/out automation for [104](https://pro.104.com.tw) on macOS.

## Features

- Menu bar status for today’s clock-in / clock-out
- Manual punch with native macOS notifications
- Scheduled auto-punch via launchd
- Missed-punch macOS notifications after a configurable delay
- Built-in 104 web login with session cookies stored at `~/.104/session.json` (file-backed, `0600`)
- Wake-before-punch scheduling via `pmset` (admin approval required)
- Launch at login and periodic status refresh

## Install

Download the latest `.dmg` from [GitHub Releases](../../releases/latest), open it, and drag **ClockBar** to your Applications folder.

## Updates

ClockBar uses Sparkle for in-app update checks. The appcast is expected at:

```text
https://doge-is-dope.github.io/104-clock/appcast.xml
```

Before producing a release, generate Sparkle EdDSA keys with Sparkle's `generate_keys` tool and pass the public key into the build:

```sh
make build SPARKLE_PUBLIC_ED_KEY="..."
```

Publish signed release archives on GitHub Releases, then generate and upload the Sparkle appcast to GitHub Pages.

## Requirements

- macOS 15+

## Build from Source

```sh
make build
make install
```

For development:

```sh
make menubar
```

## Usage

Launch ClockBar from the menu bar, sign in through the built-in 104 web view, then:

- view today’s clock-in / clock-out status
- punch manually
- configure scheduled punch windows
- enable or disable auto-punch
- enable or disable missed-punch notifications

The bundled `clockbar-helper` manages launchd jobs and automation logic.

Useful helper commands:

```sh
./ClockBar.app/Contents/MacOS/clockbar-helper config
./ClockBar.app/Contents/MacOS/clockbar-helper status
./ClockBar.app/Contents/MacOS/clockbar-helper punch
./ClockBar.app/Contents/MacOS/clockbar-helper auto clockin|clockout [--dry-run]
./ClockBar.app/Contents/MacOS/clockbar-helper schedule install|status [--force]
./ClockBar.app/Contents/MacOS/clockbar-helper schedule remove [--force]
./ClockBar.app/Contents/MacOS/clockbar-helper schedule test install <clockin|clockout> <HH:MM> [--real] [--force]
./ClockBar.app/Contents/MacOS/clockbar-helper schedule test status
./ClockBar.app/Contents/MacOS/clockbar-helper schedule test remove [<clockin|clockout>] [--force]
```

`schedule install`/`remove` wait for any in-flight auto-punch to finish before tearing down launchd jobs. Pass `--force` to interrupt a stuck run instead of waiting.

## Makefile Targets

| Target      | Description |
|-------------|-------------|
| `build`     | Compile `ClockBar.app` and bundle the helper |
| `menubar`   | Build and launch ClockBar |
| `install`   | Copy to `/Applications` and install launchd schedules |
| `uninstall` | Remove launchd schedules and delete `/Applications/ClockBar.app` |
| `status`    | Show launchd job state and recent auto-punch logs |
| `dmg`       | Create a `.dmg` disk image for distribution |
| `clean`     | Delete the local build output |

## Configuration

Config lives at `~/.104/config.json`:

```json
{
  "schedule": {
    "clockin": "09:00",
    "clockin_end": "09:15",
    "clockout": "18:00",
    "clockout_end": "18:15"
  },
  "min_work_hours": 9,
  "missed_punch_notification_enabled": true,
  "missed_punch_notification_delay": 0,
  "autopunch_enabled": true,
  "wake_enabled": false,
  "wake_before": 300,
  "refresh_interval": 1800
}
```

Randomized punch timing is derived from each configured schedule window (`clockin` to `clockin_end`, `clockout` to `clockout_end`) rather than a standalone `random_delay_max` setting.

All time-based values (`missed_punch_notification_delay`, `wake_before`, `refresh_interval`) are in **seconds**.

Temporarily disable auto-punch with:

```sh
touch ~/.104/autopunch-disabled
```
