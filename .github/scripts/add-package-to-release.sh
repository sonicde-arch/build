#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu

. "$SCRIPTS_DIR"/libarchpkg.sh
. "$SCRIPTS_DIR"/libgithub.sh
. "$SCRIPTS_DIR"/liblog.sh


# Arguments

repo=${1-$REPOSITORY}
tag=${2-$STAGING_TAG}
dbname=${3-$REPO_DB_NAME}
package_dir=$4


# Environment

: "${DOCKER_IMAGE:?DOCKER_IMAGE must not be empty}"


# Constants

CEXT='tar.zst'


# Functions

cleanup() {
	rc=$?
	log_close || :
	return $rc
}


# Main

trap cleanup 0
trap 'exit 1' HUP INT TERM
log_open

cd "$package_dir"

assets=$(ls -1 -- *.pkg.*)
if [ "${REGISTER_NEEDED:-false}" != 'true' ] ; then
	inf 'Uploading packages:\n%s' "$assets"
	gh release upload --repo "$repo" "$tag" -- *.pkg.*
fi

attempt=1
maxtries=20
while : ; do
	olddb=$(gh_release_get_asset_maxrev "$repo" "$tag" "$dbname.db")

	inf 'Downloading package database %s' "$olddb"
	gh release download --clobber --repo "$repo" "$tag" --pattern "$olddb*"
	newdb=$(gh_release_inc_asset_revision "$olddb")
	mv "$olddb.$CEXT" "$newdb.$CEXT"

	inf 'Adding packages to database %s' "$newdb"
	repodb_add_packages "$DOCKER_IMAGE" "$newdb.$CEXT" ./*.pkg."$CEXT"
	rm -f "$newdb"*.old

	inf 'Uploading database %s*' "$newdb"
	if gh release upload --repo "$repo" "$tag" "$newdb"* ; then
		inf 'Uploaded database %s*' "$newdb"
		break
	fi
	if [ "$attempt" -ge "$maxtries" ] ; then
		err 'Tried %s times to upload database. Giving up' "$attempt"
		exit 1
	fi

	sleep "$attempt"
	attempt=$((attempt + 1))
done

inf 'Awaiting availability of assets'
gh_release_await_assets "$repo" "$tag" "$assets
$newdb
$newdb.$CEXT"
