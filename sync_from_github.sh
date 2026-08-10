#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'error: this script must be run from inside a git clone.\n' >&2
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! git remote get-url origin >/dev/null 2>&1; then
    printf 'error: this clone does not have an origin remote.\n' >&2
    exit 1
fi

printf 'fetching latest repository state from origin...\n'
git fetch origin --prune

DEFAULT_BRANCH="$(git ls-remote --symref origin HEAD | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }')"

if [[ -z "$DEFAULT_BRANCH" ]]; then
    printf 'error: could not determine the default branch on origin.\n' >&2
    exit 1
fi

printf 'replacing local tracked content with origin/%s...\n' "$DEFAULT_BRANCH"
git checkout --force -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"
git reset --hard "origin/$DEFAULT_BRANCH"

printf 'removing untracked files and folders...\n'
git clean -fd

printf 'local clone now matches origin/%s.\n' "$DEFAULT_BRANCH"
