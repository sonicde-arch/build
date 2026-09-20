#!/bin/sh

set -eu

. "$SCRIPTS_DIR"/libarchpkg.sh
. "$SCRIPTS_DIR"/liblog.sh
. "$SCRIPTS_DIR"/libgithub.sh


# Arguments

package_dir=$1


# Environment

: "${CARCH:?CARCH must not be empty}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must not be empty}"
: "${PACKAGES_REPOSITORY:?PACKAGES_REPOSITORY must not be empty}"
: "${REPO_DB_PREFIX:?REPO_DB_PREFIX must not be empty}"


# Main

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open

# env variables needed for the package build action
repo_db=$(gh_release_get_asset_maxrev "$REPOSITORY" "$STAGING_TAG" \
	"$REPO_DB_NAME.db")
gh_env_set STAGING_REPO_NAME "${repo_db%.db}"
repourl="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY_OWNER/$RELEASE_BRANCH"
repourl="$repourl/releases/download/$STAGING_TAG"
gh_env_set STAGING_REPO_URL "$repourl"

gh repo clone "$PACKAGES_REPOSITORY" "$GITHUB_WORKSPACE"/pkgbuilds -- \
	--branch "$BRANCH" --depth 1 --single-branch
