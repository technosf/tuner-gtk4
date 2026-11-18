#!/usr/bin/env bash
# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# flatpak-run.sh - run the Tuner Flatpak installed for the current user (scripts/flatpak-build.sh).
#
# Usage: scripts/flatpak-run.sh [-v] [-b]
#   -v  verbose: G_MESSAGES_DEBUG=all
#   -b  run the build folder (build/flatpak) instead of the installed Flatpak; nothing has to be installed
#       (build with scripts/flatpak-build.sh -n)
#
# Note: the app id is the Flathub one, so it shares settings and data with an installed Tuner of the same id.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="io.github.tuner_labs.tuner"
verbose=0
from_build=0

while getopts "vb" opt; do
    case "$opt" in
        v) verbose=1 ;;
        b) from_build=1 ;;
        *) sed -n '9,13p' "$0"; exit 2 ;;
    esac
done

env_args=()
[ "$verbose" -eq 1 ] && env_args=(--env=G_MESSAGES_DEBUG=all)

if [ "$from_build" -eq 1 ]; then
    manifest="$repo/build/io.github.tuner_labs.tuner.local.yml"
    [ -d "$repo/build/flatpak/files" ] && [ -f "$manifest" ] || { echo "Nothing built: run scripts/flatpak-build.sh first." >&2; exit 1; }
    if command -v flatpak-builder >/dev/null 2>&1; then
        builder=(flatpak-builder)
    else
        builder=(flatpak run org.flatpak.Builder)
    fi
    # --run applies the manifest's finish-args (display, audio, network), which a plain "flatpak build" does not
    [ "$verbose" -eq 1 ] && export G_MESSAGES_DEBUG=all
    cd "$repo"
    exec "${builder[@]}" --run build/flatpak "$manifest" tuner-gtk4
fi

exec flatpak --user run "${env_args[@]}" "$app"
