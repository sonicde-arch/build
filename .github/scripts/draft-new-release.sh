#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE

set -eu
set -x

. "$SCRIPTS_DIR"/liblog.sh
. "$SCRIPTS_DIR"/libgithub.sh


# Arguments

# $1: repository for storing the binaries
# $2: name of the tag
# $3: BUILD_NEEDED


# Environment

: "${CURRENT_TAG:?CURRENT_TAG must not be empty}"
: "${NEXT_TAG:?NEXT_TAG must not be empty}"
: "${REPO_DB_NAME:?REPO_DB_NAME must not be empty}"


# Constants

CEXT='tar.zst'
NUL=/dev/null
NOTES='Staging area for the next release'


# Main

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open

gh_release_delete "$1" "$NEXT_TAG" 2>$dbg || :

if gh release view --repo "$1" "$2" >$NUL 2>&1 ; then
	test "$3" != 'true' && die 0 'Keeping existing release %s@%s' "$1" "$2"

	inf 'Deleting existing release %s@%s' "$1" "$2"
	gh_release_delete "$1" "$2"
fi

curname="$REPO_DB_NAME.db"
revname="$REPO_DB_NAME-r0000.db"

gh release download --repo "$1" "$CURRENT_TAG" --pattern "$curname" 2>$dbg || :
test -f "$curname" || tar --zstd -cf "$curname" -T /dev/null

mv "$curname" "$revname" && cp "$revname" "$revname.$CEXT"

gh release create --prerelease --title "$2" --notes "$NOTES" --repo "$1" "$2"
gh release upload --repo "$1" "$2" ./*.db*
