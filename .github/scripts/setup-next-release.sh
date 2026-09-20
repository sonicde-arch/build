#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE

set -eu

. "$SCRIPTS_DIR"/libarchpkg.sh
. "$SCRIPTS_DIR"/libgithub.sh
. "$SCRIPTS_DIR"/liblog.sh


# Arguments

repo=$1     # repository for storing the binaries
reltag=$2   # released release tag
stagetag=$3 # staged release tag
nexttag=$4  # next release tag
force=$5    # force the build flag


# Environment

: "${DOCKER_IMAGE:?DOCKER_IMAGE must not be empty}"
: "${PACKAGES_REPOSITORY:?PACKAGES_REPOSITORY must not be empty}"
: "${REPO_DB_NAME:?REPO_DB_NAME must not be empty}"


# Constants

CEXT='tar.zst'
NUL=/dev/null
NOTES='Staging area for the next release'
OPTIONS="\
debug
strip"
PKGEXT='.pkg.tar.zst'


# Functions

list_assets() {
	gh release view --json assets --repo "$1" "$2" | jq -r '.assets[].name'
}

download_assets() {
	xargs -r -P 4 -I {} gh release download --repo "$1" "$2" --pattern '{}' < "$3"
}

upload_assets() {
	_repo=$1; _tag=$2; shift 2
	gh release upload --repo "$_repo" "$_tag" "$@"
}

start_container() {
	docker run --detach --name builder --workdir /workspace \
		--volume "$(pwd):/workspace" \
		"$DOCKER_IMAGE" sh -c 'while :; do sleep 3600; done' >$NUL &
	contpid=$!
}


# Main

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open

contpid=
dbname=$REPO_DB_NAME
tmp=$(mktemp -d)

start_container

gh repo clone "$PACKAGES_REPOSITORY" . -- \
	--branch "$BRANCH" --depth 1 --single-branch

gh_release_delete "$repo" "$nexttag" 2>$NUL || : # cleanup
test "$force" = true && gh_release_delete "$repo" "$stagetag" 2>$NUL || :

if ! gh release view --repo "$repo" "$stagetag" 2>$NUL ; then
	inf 'Creating new release %s@%s' "$repo" "$stagetag"
	revname="$REPO_DB_NAME-r0000.db"
	tar --zstd -cf "$revname" -T /dev/null
	cp "$revname" "$revname.$CEXT"
	gh release create --prerelease --title "$stagetag" --notes "$NOTES" \
		--repo "$repo" "$stagetag"
	gh release upload --repo "$repo" "$stagetag" ./*.db*
fi

# shellcheck disable=SC2012
ls -1 -- */PKGBUILD | cut -d '/' -f 1 > bases.csv || :
if [ "$force" = true ] ; then
	gh_output 'packages' "$(jq -Rs 'split("\n")[:-1]' < bases.csv)"
	exit 0
fi


inf 'Calculating sets of assets'

for pkgbuild in */PKGBUILD; do
	test -f "$pkgbuild" || continue
	pkgbase=${pkgbuild%/*}

	makepkg_packagelist "$pkgbase/.SRCINFO" "$CARCH" "$PKGEXT" "$OPTIONS" |
	while IFS= read -r asset; do
		printf '%s\n' "$asset" >> assets.csv
		printf '%s|%s\n' "$asset" "$pkgbase" >> assets2bases.csv
	done
done

list_assets "$repo" "$stagetag" > staged.csv
list_assets "$repo" "$reltag" > released.csv 2>$NUL || :

cat staged.csv released.csv | grep -Fxf assets.csv | sort -u > existing.csv || :
grep -vFxf staged.csv assets.csv > missing.csv || :
grep -vFxf released.csv missing.csv > build-assets.csv || :
grep -Fxf released.csv missing.csv > copy-assets.csv || :

dbasset=$(gh_release_get_asset_maxrev "$repo" "$stagetag" "$dbname.db")
gh release download --clobber --repo "$repo" "$stagetag" --pattern "$dbasset*"
tar -xf "$dbasset" -C "$tmp"
find "$tmp" -name 'desc' -exec sed -n '2p' {} \; | sort -u > db-assets.csv

grep -vFxf existing.csv db-assets.csv > db-obsolete.csv || :
grep -vFxf db-assets.csv existing.csv > db-missing.csv || :
grep -vFxf copy-assets.csv db-missing.csv > download-assets.csv || :

for file in *.csv; do
	printf '\n%s\n' "$file"
	cat "$file"
done

inf 'Downloading and copying assets'

sed 's/$/*/g' copy-assets.csv > copy-assets-star.csv # for *.sig etc.
download_assets "$repo" "$reltag" copy-assets-star.csv
download_assets "$repo" "$stagetag" download-assets.csv
# shellcheck disable=SC2046
test -s copy-assets.csv &&
	set -- $(cat copy-assets-star.csv) &&
	gh release upload --repo "$repo" "$stagetag" "$@"


inf 'Ensuring database consistency'

if [ -s db-missing.csv ] || [ -s db-obsolete.csv ] ; then
	inf 'Obsolete assets:\n%s\n' "$(cat db-obsolete.csv)"
	inf 'Missing assets:\n%s\n' "$(cat db-missing.csv)"

	revname=$(gh_release_inc_asset_revision "$dbasset")
	mv "$dbasset.$CEXT" "$revname.$CEXT"
	wait "$contpid"
	docker exec --user "$(id -u):$(id -g)" builder sh -c '
		sed "s/\.pkg\.tar\.zst$//; s/-[^-]*-[^-]*-[^-]*$//" db-obsolete.csv |
			xargs -r repo-remove "$1"
		xargs -r repo-add "$1" < db-missing.csv
	' _ "$revname.$CEXT"
	upload_assets "$repo" "$stagetag" "$revname"*
fi


inf 'Emitting packages to build'

sed 's/$/|/' build-assets.csv | grep -Ff - assets2bases.csv |
	cut -d '|' -f 2 | sort -u > build-bases.csv || :

echo "build-bases:"
cat build-bases.csv

gh_output 'packages' "$(jq -Rs 'split("\n")[:-1]' < build-bases.csv)"
