#!/bin/bash

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for XLibre

set -eu

# Script Parameters
# $1: binaries repository to download the dependencies from
# $2: NEXT_RELEASE_TAG
# $3: pkgbase to download the dependencies for


# Constants

ROOTDIR=$(pwd)
DEPSWD="$(mktemp -d "${TMPDIR:-/tmp}/download-dependencies.XXXXXXXXXX")"


# Functions

list_normalize() {
	SPACE2NL='s/[[:space:]][[:space:]]*/\n/g'
	DEL_EMPTY_LINES='/^[[:space:]]*$/d'

	sed -i -e "$SPACE2NL" -e "$DEL_EMPTY_LINES" "$1"
}

# Resolve the dependencies of a given package. It parses the PKGBUILDs and
# recursively records the dependencies in the top level file "dependencies.csv".
#
# $1: PKGBASE
resolve_deps() {
	test -e "$DEPSWD/$1" && return 0
	test -e "$ROOTDIR/$1/PKGBUILD" || return 0 # skip split packages

	mkdir -p "$DEPSWD/$1" && cd "$DEPSWD/$1"

	source "$ROOTDIR/$1"/PKGBUILD
	printf "%s\n" "${pkgname[@]}" | grep -v "$1" >> ../dependencies.csv || true
	printf "%s\n" "${depends[@]}" > raw-deps.csv
	printf "%s\n" "${makedepends[@]}" >> raw-deps.csv

	list_normalize raw-deps.csv
	grep -xFf ../org-packages.csv raw-deps.csv >> dependencies.csv || true
	cat dependencies.csv >> ../dependencies.csv

	while IFS= read -r PACKAGE; do
		resolve_deps "$PACKAGE"
	done < dependencies.csv
}


# Main

find . -mindepth 1 -name PKGBUILD -exec bash -c \
	'source "{}" ; echo "${pkgname[@]}" >> org-packages.tmp' \;
list_normalize org-packages.tmp
mv org-packages.tmp "$DEPSWD"/org-packages.csv

source "$3"/PKGBUILD

printf '\nResolving dependencies\n'
resolve_deps "${pkgname[0]}"

cd "$DEPSWD"

list_normalize dependencies.csv
mv dependencies.csv dependencies.csv.tmp
cat dependencies.csv.tmp | sort | uniq > dependencies.csv


printf '\nDownloading dependencies\n'

cd "$ROOTDIR"
mkdir -p dependencies

while IFS= read -r PKGBASE; do
	printf "Downloading $PKGBASE\n"
	gh release download --skip-existing --repo "$1" \
		--pattern "$PKGBASE"-*.pkg.* \
		--dir dependencies "$2"
done < "$DEPSWD"/dependencies.csv

rm -rf "$DEPSWD"
ls -l dependencies
