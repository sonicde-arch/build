#!/bin/sh

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

: "${PKGDB_PREFIX:?PKGDB_PREFIX must not be empty}"
: "${TMP_TAG:?TMP_TAG must not be empty}"

SOURCE_DB=$PKGDB_PREFIX-${srcrepo##*/}
DEST_DB=$PKGDB_PREFIX-${destrepo##*/}

ARCFMT='tar.zst'
tmptag=$TMP_TAG

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open


test "$createdb" = 1 && container_start

cd "$(mktemp -d)"

inf 'Downloading assets from %s@%s' "$srcrepo" "$srctag"
ghpy release download -v --repo "$srcrepo" "$srctag" --pattern '*'

if [ "$createdb" = 1 ] ; then
	inf 'Creating package database'
	rm -f "$SOURCE_DB".db* "$SOURCE_DB".files*
	arch_repo_add -- "$DEST_DB".db.$ARCFMT *.pkg.$ARCFMT
fi

if "$SOURCE_DB" != "$DEST_DB" ; then
	mv "$SOURCE_DB".db "$DEST_DB".db
	mv "$SOURCE_DB".db.$ARCFMT "$DEST_DB".db.$ARCFMT
	mv "$SOURCE_DB".files "$DEST_DB".files
	mv "$SOURCE_DB".files.$ARCFMT "$DEST_DB".files.$ARCFMT
fi

ls "$DEST_DB".db "$DEST_DB".db.$ARCFMT 1>/dev/null # assert files exist

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
