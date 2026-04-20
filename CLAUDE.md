# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS menu-bar app (`ClockBar.app`) + CLI helper (`clockbar-helper`) that automates clock-in/out for [104](https://pro.104.com.tw). SwiftUI on macOS 15+, Swift 5 mode, uses Sparkle for updates.

## Build / run

Use `make`, not Xcode or `xcodebuild` directly:

```sh
make build        # compile ClockBar.app + bundle helper; the only supported build entry point
make menubar      # kill running instance, build, then open the app
make install      # copy to /Applications and install launchd schedules
make uninstall    # remove launchd schedules, then delete /Applications/ClockBar.app
make status       # print launchd job state + recent auto-punch logs
make dmg          # produce ClockBar-<version>.dmg
make clean
```

There are **no unit tests** in this repo. Verification is manual via the built app + helper CLI. For release builds, pass `SPARKLE_PUBLIC_ED_KEY="..."` to `make build`.

## When adding or removing a Swift file

The build is doubly-tracked — update **both** places, or the helper build will break:

1. `ClockBar.xcodeproj/project.pbxproj` — add a `PBXBuildFile`, a `PBXFileReference`, an entry in the correct `PBXGroup` (App / API / Auth / Models / Scheduling / Support / UI), and an entry in the `Sources` build phase. IDs follow the `A1000xxx` (file ref) / `A2000xxx` (build file) / `A3000xxx` (group) / `A4000xxx` (build phase) pattern.
2. `Makefile` — append to `APP_SOURCES`. If the file is also needed by the CLI helper, append to `HELPER_SOURCES` too.

The helper is compiled with a bare `swiftc` invocation from `HELPER_SOURCES`, not via Xcode. Anything not listed there is invisible to the helper target.

## Architecture

Two executables from one source tree:

- **App (`ClockBarApp`)** — SwiftUI `MenuBarExtra` UI, driven by `StatusViewModel` (@MainActor `ObservableObject`). `AppContainer` (in `ClockBar/App/AppContainer.swift`) owns the three long-lived singletons (`StatusViewModel`, `AppUpdater`, `SettingsWindowController`) and is held by a single `@StateObject` in `ClockBarApp`. **Never add a new app-wide reference as a plain `let` on `ClockBarApp`** — SwiftUI re-initializes the App struct multiple times per process and plain `let`s get rebuilt each time, which has caused use-after-free crashes in Settings. Put new singletons inside `AppContainer`.
- **Helper (`clockbar-helper`)** — entry point `ClockBarHelper.swift` at repo root. Subcommands: `config`, `status`, `punch`, `auto clockin|clockout [--dry-run]`, `schedule install|remove|status|test [--force]`. Invoked by launchd for auto-punch and by the user for diagnostics.

Data flow for a punch:

```
launchd → clockbar-helper auto clockin
        → AutoPunchEngine.run(action:)
        → ClockService → Clock104API (web scraping) → AuthStore (Keychain session)
        → AutoPunchLog (~/.104/logs/)
```

Layer responsibilities:

- `API/` — raw 104 HTTP surface (`Clock104API`), domain-level wrapper (`ClockService`), error types.
- `Auth/` — `AuthStore` (Keychain session), `AuthWindowController` (WKWebView login), `SilentAuthRefresher`.
- `Scheduling/` — `LaunchAgentManager` writes/loads launchd `.plist`s; `AutoPunchEngine` executes one scheduled punch (`Support/AutoPunchLock` serializes it against installer edits via `flock`); `HolidayStore`, `PowerStateMonitor`.
- `Support/` — `ConfigManager` (JSON at `~/.104/config.json`), `NotificationManager` (user notifications; app-only — not in helper sources), shell helpers, formatters.
- `App/` — SwiftUI App, view model, `AppUpdater` (Sparkle wrapper), `AppContainer`.
- `UI/` — views; `SettingsWindowController` opens Settings as a programmatic `NSWindow` (the SwiftUI `Window` scene caused a ghost menu-bar icon — commit `7d17fbb`). `showSettings()` defers via `DispatchQueue.main.async` for the same teardown-ordering reason; don't remove that dispatch.

## Scheduling specifics

- Auto-punch runs via a `launchd` user agent per action (clockin/clockout). Plists live under `~/Library/LaunchAgents/com.clockbar.104-*.plist`.
- `schedule install` and `schedule remove` acquire `AutoPunchLock` (flock) so they can't tear down launchd jobs mid-run. `--force` breaks the lock instead of waiting.
- `schedule test install <action> <HH:MM> [--real]` rehearses the full launchd → helper → AutoPunchEngine path without hitting the 104 API; only `--real` makes an actual punch.
- Wake-before-punch scheduling installs a single `pmset repeat wakeorpoweron MTWRF HH:MM:SS` rule via `osascript … with administrator privileges` (see `StatusViewModel.pmsetCommand(for:)` / `runWithAdmin`). One admin prompt per change to clock-in time, `wakeBefore`, or `wakeEnabled`. `pmset repeat` only has one wake slot, so only clock-in wakes the Mac — clock-out fires only if the Mac is already awake. Legacy per-date `ClockBarClockInWake` / `ClockBarClockOutWake` entries from pre-repeat installs are left to decay naturally (within 366 days); users who want to clear them immediately can run e.g. `pmset -g sched | grep ClockBar` and cancel them individually.
- Config rename convention: **no migration shims** — if you rename a key in `ClockConfig`, users need to re-save the config; do not add backward-compat code paths.

## Paths and state

- Config: `~/.104/config.json`
- Logs: `~/.104/logs/`
- Session: macOS Keychain (item managed by `AuthStore`)
- Disable autopunch without editing config: `touch ~/.104/autopunch-disabled`
- Launchd plists: `~/Library/LaunchAgents/com.clockbar.104-*.plist`

## CI

`.github/workflows/ci.yml` runs `make build` on `macos-15` for push/PR to `main`. `release.yml` handles tag releases + Sparkle appcast. Anything that breaks `make build` breaks CI.
