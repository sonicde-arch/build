#!/bin/bash

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE.org

set -u

# Script Parameters
# $1: path to the directory containing the PKGBUILD

# Constants
ROOTDIR=$(pwd)
DEPSWD="$ROOTDIR/dep-repos"

# Functions

# Resolve the dependencies of a given package = repository name of this GitHub
# organization. It parses the PKGBUILDs and recursively records the
# dependencies in the top level file "dependencies.csv".
#
# $1: package name
resolve_deps() {
	test -e "$DEPSWD/$1" && return 0

	gh repo clone "$GITHUB_REPOSITORY_OWNER/$1" "$DEPSWD/$1" -- --depth 1
	cd "$DEPSWD/$1" || exit 1

	source PKGBUILD
	printf "%s\n" "${depends[@]}" > raw-deps.csv
	printf "%s\n" "${makedepends[@]}" >> raw-deps.csv

	grep -xFf "$ROOTDIR"/org-packages.csv raw-deps.csv >> dependencies.csv
	cat dependencies.csv >> "$ROOTDIR"/dependencies.csv

	while IFS= read -r repo; do
		resolve_deps "$repo"
	done < dependencies.csv
}

# Main
if [ ! -e org-packages.csv ] ; then
	printf 'Listing packages of this organization\n'
	gh repo list --limit 999 --no-archived --source --topic package \
		--json name "$GITHUB_REPOSITORY_OWNER" | \
		jq -r '.[] | .name' | sort | tee org-packages.csv
fi

source "$1"/PKGBUILD
PKGNAME="$pkgname"
test $PKGNAME || PKGNAME="$pkgbase"

printf '\nResolving dependencies\n'
resolve_deps "$PKGNAME"

rm -rf "$DEPSWD"
cd "$ROOTDIR"

# add repo owner to dependencies where missing
sed "/\//!s:^:${GITHUB_REPOSITORY_OWNER}/:g" dependencies.csv > dependencies.csv.tmp
cat dependencies.csv.tmp | sort | uniq > dependencies.csv

printf '\nDownloading dependencies\n'
mkdir dependencies
while IFS= read -r repo; do
	gh release download --repo "$repo" --pattern *.pkg.* --dir dependencies
done < dependencies.csv

ls -l dependencies
