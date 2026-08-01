#!/bin/bash

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for XLibre

set +e # we intentionally skip existing stuff, so don't care
set -u

# Script Parameters
# $1: binaries repository to download the dependencies from
# $2: NEXT_RELEASE_TAG
# $3: INPUT_FORCE_BUILD


# Constants

NOTES='Staging area for next release'


# Main

EXISTING="$(gh release view --json tagName --repo "$1" "$2" 2>/dev/null)"

if [ "$EXISTING" ] && [ "$3" = 'true' ] ; then
	gh release delete --cleanup-tag --yes --repo "$1" "$2" 2>/dev/null
	printf "Deleted previous draft '$2'.\n"
	EXISTING=
fi
test "$EXISTING" && exit 0

gh release create --draft --title "$2" --notes "$NOTES" \
	--repo "$1" "$2" 2>/dev/null

sleep 1 # give GitHub some time to think about itself
