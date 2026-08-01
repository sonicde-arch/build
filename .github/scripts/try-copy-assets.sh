#!/bin/bash

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for XLibre

set -eu

. "${0%/*}"/gh-helpers.sh


# Script Parameters
# $1: binaries repository to check for existing artifacts
# $2: source release tag
# $3: target release tag
# $4: package name


# Functions

assets_filter() {
	set +e
	gh release view --json assets --repo "$1" "$2" 2>/dev/null \
		| jq -r '.assets.[].name' | grep "$ASSETS_RE"
	set -e
}


# Main

epoch=0
source "$4"/PKGBUILD

PKGBASE="${pkgname[0]}"
test $epoch -gt 0 && epoch="${epoch}." || epoch=
ASSETS_WC="$PKGBASE-${epoch}$pkgver-$pkgrel-*.pkg.*"
ASSETS_RE="$(printf "$ASSETS_WC" | sed -e 's/\./\\./g' -e 's/\*/.*/g')"

printf "Looking for an asset matching '$ASSETS_WC'.\n"

ASSETS="$(assets_filter "$1" "$3")"
if [ "$ASSETS" ] ; then
	printf "Found assets in '$3':\n$ASSETS\nSkipping build.\n"
	exit 0
fi

ASSETS="$(assets_filter "$1" "$2")"
if [ ! "$ASSETS" ] ; then
	printf "No assets '$ASSETS_WC' found in '$2'.\nSetting BUILD_NEEDED.\n"
	gh_env_set BUILD_NEEDED 'true'
	exit 0
fi

printf "Copying assets of '$PKGBASE' from release '$2' to '$3'\n"
for PKGNAME in "${pkgname[@]}" ; do
	ASSETS_WC="$PKGNAME-${epoch}$pkgver-$pkgrel-*.pkg.*"
	gh release download --skip-existing --pattern "$ASSETS_WC" --repo "$1" "$2"
	gh release upload --repo "$1" "$3" "$ASSETS_WC"
done
