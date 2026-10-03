#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu
test "${RUNNER_DEBUG:-}" = 1 && set -x

. "$SCRIPTS_DIR"/liblog.sh


: "${1:?BINPKGS_REPO must not be empty}"
: "${2:?TMP_TAG must not be empty}"
: "${3:?RELEASED_TAG must not be empty}"

NEW_NOTES='Current release by the build bot'


# Main

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open

set +e
prevdate=$(gh release view --json publishedAt --repo "$1" "$3" \
	| jq -r '.publishedAt')
set -e
if [ -n "$prevdate" ] && [ "$prevdate" != null ] ; then
	oldtitle=$(TZ=UTC date -d "$prevdate" '+%Y%m%dT%H%M%S')
	oldtitle="${3}-${oldtitle}"
	oldnotes="Previous release $oldtitle"

	inf "Renaming old release %s@%s to %s" "$1" "$3" "$oldtitle"
	gh release edit --notes "$oldnotes" --tag "$oldtitle" --title "$oldtitle" \
		--repo "$1" "$3"
fi

inf "Releasing new release %s@%s" "$1" "$3"
gh release edit --draft=false --latest=true --prerelease=false \
	--notes "$NEW_NOTES" --tag "$3" --title "$3" --repo "$1" "$2"
