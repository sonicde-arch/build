#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu
test "${RUNNER_DEBUG:-}" = 1 && set -x

. "$SCRIPTS_DIR"/liblog.sh


: "${1:?REPOSITORY must not be empty}"
: "${2:?STAGING_TAG must not be empty}"
: "${3:?PACKAGE must not be empty}"

: "${BINPKGS_DIR:?BINPKGS_DIR must not be empty}"

ARCFMT='tar.zst'

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open


inf 'Uploading assets'

cd "$BINPKGS_DIR"
ghpy release upload -v --repo "$1" "$2" -- *.pkg.$ARCFMT*
ghpy release await-assets -v --repo "$1" "$2" -- *.pkg.$ARCFMT*
