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
inf 'Uploading packages:\n%s' "$assets"
gh release upload --repo "$repo" "$tag" -- *.pkg.*

attempt=1
maxtries=20
while : ; do
	oldname=$(gh_release_get_asset_maxrev "$repo" "$tag" "$dbname.db")

	inf 'Downloading package database %s' "$oldname"
	gh release download --clobber --repo "$repo" "$tag" --pattern "$oldname*"
	revname=$(gh_release_inc_asset_revision "$oldname")
	mv "$oldname.$CEXT" "$revname.$CEXT"

	inf 'Adding packages to database %s' "$revname"
	repodb_add_packages "$DOCKER_IMAGE" "$revname.$CEXT" ./*.pkg."$CEXT"
	rm -f "$revname".*.old

	if gh release upload --repo "$repo" "$tag" "$revname"* ; then
		inf 'Uploaded database %s' "$revname"
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
$revname"
