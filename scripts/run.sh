#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# run.sh - run the GTK4 app from the build folder, with the core's settings schema from the build tree.
#
# Usage: scripts/run.sh [BUILD_DIR]      (default: build)

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="${1:-build}"
GSETTINGS_SCHEMA_DIR="$root/$dir/subprojects/tuner-core/data" exec "$root/$dir/tuner-gtk4"
