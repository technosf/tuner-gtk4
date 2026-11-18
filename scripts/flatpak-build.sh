#!/usr/bin/env bash
# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# flatpak-build.sh - build the Flatpak from the LOCAL checkout (uncommitted work included) and install it for the
# current user. It uses the CI manifest (flatpak/io.github.tuner_labs.tuner.ci.yml: same id and options as the
# Flathub release manifest) with its source folders made absolute: this checkout, and the tuner-core checkout.
#
# Usage: scripts/flatpak-build.sh [-n] [-c CORE_DIR] [-o OUT_DIR]
#   -n  build only; do not install
#   -c  the tuner-core checkout (default: subprojects/tuner-core, normally a link to ../../tuner-core)
#   -o  build folder (default: build/flatpak)
#
# The manifest actually built is a copy in build/; the one in the repository is not changed. Run it with
# scripts/flatpak-run.sh. The Flathub release manifest (flatpak/io.github.tuner_labs.tuner.yml) pins git sources
# and is not used here.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core="$repo/subprojects/tuner-core"
out="build/flatpak"
install_flag="--install"

while getopts "nc:o:" opt; do
    case "$opt" in
        n) install_flag="" ;;
        c) core="$OPTARG" ;;
        o) out="$OPTARG" ;;
        *) sed -n '12,16p' "$0"; exit 2 ;;
    esac
done

[ -f "$core/meson.build" ] || { echo "No tuner-core at: $core (use -c CORE_DIR)" >&2; exit 1; }
core="$(cd "$core" && pwd -P)"

manifest_in="$repo/flatpak/io.github.tuner_labs.tuner.ci.yml"
mkdir -p "$repo/build"
manifest="$repo/build/io.github.tuner_labs.tuner.local.yml"

# Make the two "type: dir" source paths absolute (the copy lives in build/). First is this repo, second the core
python3 - "$manifest_in" "$manifest" "$repo" "$core" <<'PY'
import re, sys
src, dst, repo, core = sys.argv[1:5]
text = open(src).read()
paths = iter([repo, core])
text, n = re.subn(r"(type:\s*dir\s*\n(?:\s*#[^\n]*\n)*\s*path:\s*)\S+", lambda m: m.group(1) + next(paths), text)
if n != 2:
    sys.exit("Expected two dir sources in " + src + ", found %d" % n)
open(dst, "w").write(text)
PY
echo "Manifest: $manifest" >&2

if command -v flatpak-builder >/dev/null 2>&1; then
    builder=(flatpak-builder)
else
    builder=(flatpak run org.flatpak.Builder)
fi

# No --sandbox: it refuses sources outside the manifest's folder, and these are local folders
cd "$repo"
"${builder[@]}" --user --force-clean --install-deps-from=flathub \
    --state-dir=build/flatpak-state $install_flag "$out" "$manifest"
