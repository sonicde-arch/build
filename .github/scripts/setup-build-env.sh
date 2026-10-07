#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu
test "${RUNNER_DEBUG:-}" = 1 && set -x

. "$SCRIPTS_DIR"/libgithub.sh


# Environment

: "${APP_ID:?APP_ID must not be empty}"
: "${APP_PRIVATE_KEY:?APP_PRIVATE_KEY must not be empty}"
: "${BINPKG_EXT:?BINPKG_EXT must not be empty}"
: "${BRANCH:?BRANCH must not be empty}"
: "${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER must not be empty}"
: "${PACKAGE_FEATURES?PACKAGE_FEATURES must be defined}"
: "${PACKAGING_OPTIONS?PACKAGING_OPTIONS must be defined}"
: "${PKGDB_PREFIX:?PKGDB_PREFIX must not be empty}"
: "${PKGSPECS_REPO:?PKGSPECS_REPO must not be empty}"
: "${RUNNER_TOOL_CACHE:?RUNNER_TOOL_CACHE must not be empty}"
: "${TARGET_ARCH:?TARGET_ARCH must not be empty}"


# Main

pypath=$(printf '%s\n' "$RUNNER_TOOL_CACHE"/Python/3.13.*/x64/bin)
export PATH="$pypath:$PATH"
python -m pip install "ghpy>=0.3,<0.4"

auth=$(gh-app-token.sh "$APP_ID")
gh_env_set GITHUB_TOKEN "$(printf '%s\n' "$auth" | cut -f1)"
gh_env_set GH_TOKEN "$GITHUB_TOKEN"

case "$BRANCH" in
	master) CHANNEL='stable-testing' ;;
	oldstable) CHANNEL='oldstable-testing' ;;
	*) CHANNEL="$BRANCH" ;;
esac
gh_env_set CHANNEL "$CHANNEL"

gh_env_set PKGSPECS_REPO "$PKGSPECS_REPO"
gh_env_set PKGSPECS_DIR pkgspecs

gh_env_set BINPKGS_REPO "$GITHUB_REPOSITORY_OWNER/$CHANNEL"
gh_env_set BINPKGS_STABLE_REPO "${BINPKGS_REPO%-testing}"
gh_env_set BINPKGS_DIR binpkgs

gh_env_set RELEASED_TAG "$TARGET_ARCH"
gh_env_set STAGING_TAG "$TARGET_ARCH-staging"
gh_env_set TMP_TAG "$TARGET_ARCH-tmp" # for swapping staging and released

gh_env_set CONTAINER_NAME build
gh_env_set CONTAINER_HOME /home/runner
gh_env_set CONTAINER_USER runner
