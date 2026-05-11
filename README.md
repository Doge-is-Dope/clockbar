# ClockBar

Swift-native clock-in/out automation for [104](https://pro.104.com.tw) on macOS.

## Features

- Today's clock-in / clock-out status in the menu bar
- Manual punch with macOS notifications
- Scheduled auto-punch on weekdays via launchd
- Late and missed-punch reminders
- Built-in 104 sign-in — no separate browser session needed
- Optional wake-before-punch via `pmset` (one-time admin approval)
- Launches at login

## Requirements

- macOS 15+
- Xcode 16+

## Install

```sh
git clone https://github.com/Doge-is-Dope/clockbar.git
cd clockbar
make install
```

To update:

```sh
git pull
make install
```

## First run

1. Click the ClockBar icon in the menu bar.
2. Open **Settings → Account** and sign in to 104 in the built-in web view.
3. In **Settings → Automation**, set your **Clock In** and **Clock Out** windows. Auto-punch fires at a random time inside each window, weekdays only, when the Mac is awake.
4. Optionally enable **Sleep & Wake → Wake for auto-punch** so the Mac wakes itself shortly before clock-in. macOS will prompt for admin once to install the `pmset` rule.

If the Mac is asleep at the scheduled time, you get a Missed notification with a Punch Now button when it next wakes.

## Pause auto-punch

```sh
touch ~/.104/autopunch-disabled
```

Delete the file to resume.

## Diagnostics

State, logs, and a dry-run path live behind `clockbar-helper`:

```sh
./ClockBar.app/Contents/MacOS/clockbar-helper config
./ClockBar.app/Contents/MacOS/clockbar-helper status
./ClockBar.app/Contents/MacOS/clockbar-helper punch
./ClockBar.app/Contents/MacOS/clockbar-helper auto clockin|clockout [--dry-run]
./ClockBar.app/Contents/MacOS/clockbar-helper schedule install|remove|status [--force]
./ClockBar.app/Contents/MacOS/clockbar-helper schedule test install <clockin|clockout> <HH:MM> [--real] [--force]
./ClockBar.app/Contents/MacOS/clockbar-helper schedule test status
./ClockBar.app/Contents/MacOS/clockbar-helper schedule test remove [<clockin|clockout>] [--force]
```

`schedule install` / `remove` wait for any in-flight auto-punch to finish before tearing down launchd jobs. Pass `--force` to interrupt a stuck run.

Logs: `~/.104/clockbar.log`.

## Development

```sh
make menubar      # build and launch
make uninstall    # remove from /Applications, unload launchd jobs
make status       # launchd state + recent auto-punch log lines
make clean
```

## Configuration file

The Settings window writes `~/.104/config.json`. Edit it directly only if you need to:

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

`missed_punch_notification_delay`, `wake_before`, and `refresh_interval` are in seconds.
