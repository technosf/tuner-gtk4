#!/usr/bin/env bash

# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Flags source files that contain translatable strings (_() N_() NC_() C_() ngettext) but are not listed in
# a po/*/POTFILES, and POTFILES entries that do not exist. Run from anywhere: ./scripts/check-potfiles.sh
# Exit status 1 if anything is flagged, so it can run in CI.

set -u
cd "$(dirname "$0")/.." || exit 2

PATTERN='(^|[^A-Za-z0-9_])(_|N_|NC_|C_|ngettext)[[:space:]]*\('
status=0

listed=$(grep -hv '^[[:space:]]*#' po/*/POTFILES | sed '/^[[:space:]]*$/d' | sort -u)

# Search the app and the core (subprojects/tuner-core may be a symbolic link: -L follows it)
while IFS= read -r f; do
    if ! grep -qxF "$f" <<<"$listed"; then
        echo "NOT IN POTFILES: $f ($(grep -cE "$PATTERN" "$f") strings)"
        status=1
    fi
done < <(grep -rlEd recurse --include='*.vala' --include='*.in' "$PATTERN" src data subprojects/tuner-core/src 2>/dev/null | sort -u)

while IFS= read -r f; do
    if [[ ! -e "$f" ]]; then
        echo "LISTED BUT MISSING: $f"
        status=1
    fi
done <<<"$listed"

[[ $status -eq 0 ]] && echo "POTFILES are complete."
exit $status
