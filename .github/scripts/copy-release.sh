#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu
set -x

. "$SCRIPTS_DIR"/libarchpkg.sh
. "$SCRIPTS_DIR"/libgithub.sh
. "$SCRIPTS_DIR"/liblog.sh


# Arguments

src_repo=${1-$SOURCE_REPOSITORY}
src_tag=${2-$SOURCE_TAG}
tgt_repo=${3-$TARGET_REPOSITORY}
tgt_tag=${4-$TARGET_TAG}
recreate_db=${5:-0}
del_src=${6:-0}


# Environment

: "${DOCKER_IMAGE:?DOCKER_IMAGE must not be empty}"
: "${REPO_DB_PREFIX:?REPO_DB_PREFIX must not be empty}"
: "${REPO_DB_NAME:?REPO_DB_NAME must not be empty}"


# Constants

CEXT='tar.zst'
SRC_DB_NAME=$REPO_DB_PREFIX-${src_repo##*/}
TGT_DB_NAME=$REPO_DB_PREFIX-${tgt_repo##*/}


# Functions

# Arguments
# $1: old prefix
# $2: new prefix
# $3-$n: files to rename
chprefix() {
	old=$1 ; new=$2 ; shift 2

	for file in "$@"; do
		dir=${file%/*}
		name=${file##*/}
		case "$name" in
			"$old"*)
				test "$dir" = "$file" && dir=.
				mv "$file" "$dir/$new${name#"$old"}"
				;;
		esac
	done
}


# Main

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open

tmp_tag="$tgt_tag-next"

tmpdir=$(mktemp -d)
cd "$tmpdir"

inf 'Downloading assets from %s@%s' "$src_repo" "$src_tag"
gh release download --repo "$src_repo" "$src_tag" --pattern '*'

if [ "$recreate_db" -eq 1 ] ; then
	inf 'Recreating package database'
	rm -f "$SRC_DB_NAME"*.db* "$SRC_DB_NAME"*.files*
	repodb_add_packages "$DOCKER_IMAGE" "$TGT_DB_NAME.db.$CEXT" ./*pkg.$CEXT
	rm -f "$TGT_DB_NAME".*.old
fi

test "$SRC_DB_NAME" != "$TGT_DB_NAME" &&
	chprefix "$SRC_DB_NAME" "$TGT_DB_NAME" ./*.db* ./*.files*

ls "$TGT_DB_NAME.db" "$TGT_DB_NAME.db.$CEXT" 1>/dev/null # assert files exist

inf 'Creating new release %s@%s' "$tgt_repo" "$tgt_tag"
gh_release_delete "$tgt_repo" "$tmp_tag" 2>/dev/null || :
gh release create --draft --repo "$tgt_repo" "$tmp_tag"

inf 'Uploading assets to %s@%s' "$tgt_repo" "$tgt_tag"
gh release upload --repo "$tgt_repo" "$tmp_tag" -- *

release-new-release.sh "$tgt_repo" "$tmp_tag" "$tgt_tag"

if [ "$del_src" -eq 1 ] ; then
	inf 'Deleting release %s@%s' "$src_repo" "$src_tag"
	gh_release_delete "$src_repo" "$src_tag"
fi
