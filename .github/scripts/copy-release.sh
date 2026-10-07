#!/bin/sh

# shellcheck disable=SC2086

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu
test "${RUNNER_DEBUG:-}" = 1 && set -x

. "$SCRIPTS_DIR"/libarch.sh
. "$SCRIPTS_DIR"/libdocker.sh
. "$SCRIPTS_DIR"/libgithub.sh
. "$SCRIPTS_DIR"/liblog.sh


srcrepo=${1-$SOURCE_REPOSITORY}
srctag=${2-$SOURCE_TAG}
destrepo=${3-$DESTINATION_REPOSITORY}
desttag=${4-$DESTINATION_TAG}
createdb=${5:-0}
delsrc=${6:-0}

: "${BINPKG_EXT:?BINPKG_EXT must not be empty}"
: "${PKGDB_PREFIX:?PKGDB_PREFIX must not be empty}"
: "${TMP_TAG:?TMP_TAG must not be empty}"

SOURCE_DB=$PKGDB_PREFIX-${srcrepo##*/}
DEST_DB=$PKGDB_PREFIX-${destrepo##*/}

tmptag=$TMP_TAG

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open


test "$createdb" = 1 && container_start

cd "$(mktemp -d)"

inf 'Downloading assets from %s@%s' "$srcrepo" "$srctag"
ghpy release download -v --repo "$srcrepo" "$srctag" --pattern '*'

inf 'Processing package database %s' "$DEST_DB"
test "$createdb" = 1 && arch_pkgdb_add "$DEST_DB" -- *.$BINPKG_EXT
test "$SOURCE_DB" != "$DEST_DB" && arch_pkgdb_rename "$SOURCE_DB" "$DEST_DB"
arch_pkgdb_exists "$DEST_DB" || die 1 'Package database %s missing' "$DEST_DB"

inf 'Creating new release %s@%s' "$destrepo" "$desttag"
gh_release_delete "$destrepo" "$tmptag" 2>/dev/null || :
gh release create --draft --repo "$destrepo" "$tmptag"

inf 'Uploading assets to %s@%s' "$destrepo" "$desttag"
ghpy release upload -v --repo "$destrepo" "$tmptag" -- *

release-new-release.sh "$destrepo" "$tmptag" "$desttag"

if [ "$delsrc" = 1 ] ; then
	inf 'Deleting release %s@%s' "$srcrepo" "$srctag"
	gh_release_delete "$srcrepo" "$srctag"
fi
