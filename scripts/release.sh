#!/usr/bin/env bash
#
# Cut a ClockBar release: tag the version, build the DMG, publish a GitHub release.
#
# Usage:
#   scripts/release.sh vX.Y.Z [--dry-run]
#
# The git tag is the source of truth for the version: the Makefile derives
# MARKETING_VERSION from `git describe --tags`, so the tag is created *before*
# the DMG is built so the right version is compiled in.
#
# "Only I can release" is ultimately enforced by GitHub repo permissions
# (pushing the tag and creating the release both require write access). This
# script adds an explicit allowlist guard on top so it refuses to run for
# anyone other than the authorized maintainer, with a clear message instead of
# a confusing permission error halfway through the build.

set -euo pipefail

# GitHub login(s) allowed to cut a release. Override locally if maintainership
# changes, e.g. `RELEASE_OWNERS="alice bob" scripts/release.sh v1.2.3`.
RELEASE_OWNERS="${RELEASE_OWNERS:-Doge-is-Dope}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --- pretty output -----------------------------------------------------------
if [ -t 1 ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=''; RED=''; GREEN=''; YELLOW=''; RESET=''
fi
step() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$1"; }
ok()   { printf '%s  ✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '%s  !%s %s\n' "$YELLOW" "$RESET" "$1"; }
die()  { printf '%s  ✗ %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

# --- args --------------------------------------------------------------------
DRY_RUN=false
TAG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    v*) TAG="$arg" ;;
    *) die "unknown argument: $arg (expected vX.Y.Z and/or --dry-run)" ;;
  esac
done

[ -n "$TAG" ] || die "missing version argument, e.g. scripts/release.sh v0.1.3"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like vX.Y.Z (got: $TAG)"
VERSION="${TAG#v}"
DMG="ClockBar-${VERSION}.dmg"

$DRY_RUN && warn "dry run: will validate + build, but will NOT push the tag or create the release"

# --- preflight: tooling ------------------------------------------------------
step "Checking tooling"
command -v gh >/dev/null   || die "gh (GitHub CLI) not found — https://cli.github.com"
command -v make >/dev/null || die "make not found"
gh auth status >/dev/null 2>&1 || die "not logged in to GitHub — run: gh auth login"
ok "gh + make available and authenticated"

# --- preflight: authorization ------------------------------------------------
step "Checking release authorization"
GH_USER="$(gh api user --jq '.login')"
authorized=false
for owner in $RELEASE_OWNERS; do
  [ "$GH_USER" = "$owner" ] && authorized=true
done
$authorized || die "authenticated as '$GH_USER', who is not in RELEASE_OWNERS ('$RELEASE_OWNERS') — not authorized to release"

PERM="$(gh repo view --json viewerPermission --jq '.viewerPermission' 2>/dev/null || echo UNKNOWN)"
case "$PERM" in
  ADMIN|MAINTAIN|WRITE) ;;
  *) die "your GitHub permission on this repo is '$PERM' — need WRITE or higher to release" ;;
esac
ok "authorized as '$GH_USER' ($PERM)"

# --- preflight: repo state ---------------------------------------------------
step "Checking repository state"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || die "must release from 'main' (on '$BRANCH')"

[ -z "$(git status --porcelain)" ] || die "working tree is dirty — commit or stash first"

git fetch --tags --quiet origin
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists locally"
git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1 && die "tag $TAG already exists on origin"

# HEAD must be pushed, so the release reflects code that's actually on origin.
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo '')"
[ -n "$UPSTREAM" ] || die "no upstream for 'main' — push it first: git push -u origin main"
if [ "$(git rev-parse HEAD)" != "$(git rev-parse "$UPSTREAM")" ]; then
  die "local main differs from $UPSTREAM — push/pull so they match before releasing"
fi
ok "on main, clean, in sync with origin; tag $TAG is free"

# --- preflight: lint ---------------------------------------------------------
step "Linting (make lint)"
make lint >/dev/null || die "make lint failed — fix lint before releasing"
ok "lint passed"

# --- create tag (local), then build the DMG at that version ------------------
# Build after tagging so the Makefile compiles the correct MARKETING_VERSION.
# If the build fails, drop the local tag so a retry starts clean.
step "Tagging $TAG (local)"
git tag -a "$TAG" -m "$TAG"
cleanup_tag() { git tag -d "$TAG" >/dev/null 2>&1 || true; }
trap 'cleanup_tag' ERR
ok "created local tag $TAG"

step "Building $DMG (make dmg)"
make dmg
[ -f "$DMG" ] || die "expected $DMG was not produced"
ok "built $DMG"

if $DRY_RUN; then
  cleanup_tag
  trap - ERR
  warn "dry run complete — removed local tag $TAG; nothing was pushed or published"
  warn "artifact left in place for inspection: $DMG"
  exit 0
fi

# --- publish -----------------------------------------------------------------
step "Pushing tag $TAG"
git push origin "$TAG"
trap - ERR   # tag is on origin now; don't auto-delete it on later errors
ok "pushed $TAG"

step "Creating GitHub release"
gh release create "$TAG" \
  --title "$TAG" \
  --generate-notes \
  --verify-tag \
  "$DMG"

URL="$(gh release view "$TAG" --json url --jq '.url')"
ok "released $TAG"
printf '\n%sRelease published:%s %s\n' "$BOLD" "$RESET" "$URL"
