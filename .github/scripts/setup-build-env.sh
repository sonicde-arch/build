#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu

. "$SCRIPTS_DIR"/libgithub.sh


# Environment

: "${APP_ID:?APP_ID must not be empty}"
: "${APP_PRIVATE_KEY:?APP_PRIVATE_KEY must not be empty}"
: "${BRANCH:?BRANCH must not be empty}"
: "${CARCH:?CARCH must not be empty}"
: "${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER must not be empty}"
: "${REPO_DB_PREFIX:?REPO_DB_PREFIX must not be empty}"


# Main

APP_TOKEN=$(gh-app-token.sh "$APP_ID" "$GITHUB_REPOSITORY_OWNER")
gh_env_set GITHUB_TOKEN "$APP_TOKEN"
gh_env_set GH_TOKEN "$APP_TOKEN"

gh_env_set CURRENT_TAG "$CARCH"
gh_env_set NEXT_TAG "$CARCH-next"
gh_env_set STAGING_TAG "$CARCH-staging"

case "$BRANCH" in
	master) RELEASE_BRANCH='stable-testing' ;;
	oldstable) RELEASE_BRANCH='oldstable-testing' ;;
	*) RELEASE_BRANCH="$BRANCH" ;;
esac

gh_env_set RELEASE_BRANCH "$RELEASE_BRANCH"
gh_env_set REPO_DB_NAME "$REPO_DB_PREFIX-$RELEASE_BRANCH"
gh_env_set REPOSITORY "$GITHUB_REPOSITORY_OWNER/$RELEASE_BRANCH"
gh_env_set STABLE_REPOSITORY "${REPOSITORY%-testing}"
