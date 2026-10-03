#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE

set -eu
test "${RUNNER_DEBUG:-}" = 1 && set -x

. "$SCRIPTS_DIR"/libarch.sh
. "$SCRIPTS_DIR"/libgithub.sh
. "$SCRIPTS_DIR"/liblog.sh


# Arguments

repo=${1-$BINPKGS_REPO}    # repository for storing the binaries
stagetag=${2-$STAGING_TAG} # staged release tag
force=${3-$FORCE_BUILD}    # force the build flag


# Environment

: "${PKGSPECS_REPO:?PKGSPECS_REPO must not be empty}"
: "${RELEASED_TAG:?RELEASED_TAG must not be empty}"
: "${TMP_TAG:?TMP_TAG must not be empty}"


# Constants

NUL=/dev/null
NOTES='Staging area for the next release'
OPTIONS="\
debug
strip"
reltag=$RELEASED_TAG

ARCFMT='tar.zst'


# Functions

gh_release_list_assets() {
	gh release view --json assets --repo "$1" "$2" | jq -r '.assets[].name'
}


# Main

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open

gh repo clone "$PKGSPECS_REPO" . -- --branch "$BRANCH" --depth 1 --single-branch

gh_release_delete "$repo" "$TMP_TAG" 2>$NUL || : # cleanup
test "$force" = true && gh_release_delete "$repo" "$stagetag" 2>$NUL || :

if ! gh_release_exists "$repo" "$stagetag" ; then
	inf 'Creating new release %s@%s' "$repo" "$stagetag"
	gh release create --prerelease --title "$stagetag" --notes "$NOTES" \
		--repo "$repo" "$stagetag"
fi

# shellcheck disable=SC2012
ls -1 -- */PKGBUILD | cut -d '/' -f 1 > bases.csv || :
if [ "$force" = true ] ; then
	gh_output packages "$(jq -Rs 'split("\n")[:-1]' < bases.csv)"
	exit 0
fi


inf 'Calculating sets of assets'

arch_list_assets2bases . "$CARCH" "pkg.$ARCFMT" "$OPTIONS" >> assets2bases.csv
cut -d '|' -f 1 assets2bases.csv >> assets.csv

gh_release_list_assets "$repo" "$stagetag" > staged.csv
gh_release_list_assets "$repo" "$reltag" > released.csv 2>$NUL || :

grep -vFxf assets.csv staged.csv > stale.csv || :
grep -vFxf staged.csv assets.csv > missing.csv || :
grep -vFxf released.csv missing.csv > build-assets.csv || :
grep -Fxf released.csv missing.csv | sed 's/$/*/' > copy-assets.csv || :


if [ -s copy-assets.csv ] ; then
	inf 'Copying missing assets from %s to %s' "$reltag" "$stagetag"
	gh_release_copy_assets_ff "$repo" "$reltag" "$stagetag" copy-assets.csv
fi
if [ -s stale.csv ] ; then
	inf 'Deleting stale assets from %s' "$stagetag"
	gh_release_delete_assets_ff "$repo" "$stagetag" stale.csv
fi

inf 'Emitting packages to build'

sed 's/$/|/' build-assets.csv | grep -Ff - assets2bases.csv |
	cut -d '|' -f 2 | sort -u > build-bases.csv || :
gh_output packages "$(jq -Rs 'split("\n")[:-1]' < build-bases.csv)"
