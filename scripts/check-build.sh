#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# check-build.sh - configure and compile, and keep the output in build.log (in the repository root, ignored by git)
# so it can be read afterwards. The core's own tests are run from the tuner-core checkout (its scripts/check-build.sh).
#
# Usage: scripts/check-build.sh [BUILD_DIR [MESON_SETUP_ARGS...]]      (default: build)

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="${1:-build}"
shift || true
extra=("$@")
log="$root/build.log"

cd "$root"
{
    echo "== $(date -Is)  $(git rev-parse --short HEAD 2>/dev/null)  $dir"
    if [ -d "$dir" ]; then
        meson setup --reconfigure "$dir" --buildtype=debug ${extra[@]+"${extra[@]}"}
    else
        meson setup "$dir" --buildtype=debug ${extra[@]+"${extra[@]}"}
    fi
    status=$?
    if [ $status -eq 0 ]; then
        meson compile -C "$dir"
        status=$?
    fi
    echo "== exit status $status"
    exit "$status"
} 2>&1 | tee "$log"
exit "${PIPESTATUS[0]}"
