## Summary

<!-- What does this change and why. -->

## How I tested

<!--
There are no unit tests in this repo; verification is manual.
Mention which paths you exercised, e.g.:
- `make build` succeeds
- Manual punch via menu bar
- `clockbar-helper auto clockin --dry-run`
- `clockbar-helper schedule test install clockin HH:MM`
-->

## Checklist

- [ ] If I added or removed a Swift file, I updated **both** `ClockBar.xcodeproj/project.pbxproj` and `Makefile` (`APP_SOURCES`, plus `HELPER_SOURCES` if the helper needs it)
- [ ] `make build` passes locally
- [ ] No new logging / config keys without a corresponding update to `CLAUDE.md` if conventions changed
