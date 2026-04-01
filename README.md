# 104 Clock

Automated clock-in/out for [104](https://pro.104.com.tw) on macOS.

## Components

- **clock104.py** — CLI and launchd automation for punching, scheduling, and an HTTP API server
- **ClockBar/** — SwiftUI menu bar app for quick status checks and manual punches

## Requirements

- macOS with Homebrew Python 3 (`/opt/homebrew/bin/python3`)
- [agent-browser](https://www.npmjs.com/package/agent-browser) for cookie extraction from Chrome
- Active 104 session in Chrome

## Setup

```sh
# Build the Swift apps
make build

# Install launchd auto-punch schedules (default: 09:00 / 18:00)
make install
```

## Usage

### CLI

```sh
python3 clock104.py status              # Today's punch records
python3 clock104.py punch               # Clock in or out
python3 clock104.py auto clockin        # Smart auto-punch (for launchd)
python3 clock104.py schedule status     # Show launchd job state + logs
python3 clock104.py serve               # Start HTTP API on :8104
```

### Menu Bar App

```sh
make menubar
```

Opens ClockBar in the menu bar with live status, schedule controls, and a punch button.

### Makefile Targets

| Target      | Description                          |
|-------------|--------------------------------------|
| `build`     | Compile ClockBar.app                 |
| `menubar`   | Build and launch ClockBar            |
| `install`   | Build + install launchd schedules    |
| `uninstall` | Remove launchd schedules             |
| `status`    | Show launchd job state               |
| `clean`     | Delete compiled .app bundles         |

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

Disable auto-punch temporarily: `touch ~/.104/autopunch-disabled`
