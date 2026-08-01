#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for XLibre

set -eu

#. "${0%/*}"/gh-helpers.sh


# Script Parameters
# $1: binaries repository to check for existing artifacts
# $2: CURRENT_RELEASE_TAG
# $3: NEXT_RELEASE_TAG


# Constants

NEW_NOTES='Current release by the build bot'


# Main

set +e
PREV_RELEASE_DATE="$(gh release view --json publishedAt --repo "$1" "$2" \
	| jq -r '.publishedAt')"
set -e
if [ "$PREV_RELEASE_DATE" ] ; then
	OLD_TITLE="$(TZ=UTC date -d "$PREV_RELEASE_DATE" '+%Y%m%dT%H%M%S')"
	OLD_TITLE="${2}-${OLD_TITLE}"
	OLD_NOTES="Previous release $OLD_TITLE"

	printf "Renaming old release\n"
	gh release edit --notes "$OLD_NOTES" --tag "$OLD_TITLE" --title "$OLD_TITLE" \
		--repo "$1" "$2"
fi

printf "Releasing new release\n"
gh release edit --draft=false --latest --notes "$NEW_NOTES" \
	--tag "$2" --title "$2" --repo "$1" "$3"
