#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 callmetango for XLibre

set -eu

. "${SCRIPTS_DIR}"/gh-helpers.sh


# Constants

APP_TOKEN="${APP_TOKEN:-}"


# Main

if [ "$APP_TOKEN" ]; then
	gh_env_set GITHUB_TOKEN "$APP_TOKEN"
	gh_env_set GH_TOKEN "$APP_TOKEN"
else
	gh_env_set GH_TOKEN "$GITHUB_TOKEN"
fi

gh_env_set SCRIPTS_DIR "$SCRIPTS_DIR"

gh_env_set CURRENT_RELEASE_TAG "$CARCH"
gh_env_set NEXT_RELEASE_TAG "$CARCH-next"
gh_env_set STAGING_TAG "$CARCH-staging"

case "$INPUT_BRANCH" in
	master) RELEASE_BRANCH='stable-testing' ;;
	oldstable) RELEASE_BRANCH='oldstable-testing' ;;
	*) RELEASE_BRANCH="$INPUT_BRANCH" ;;
esac
gh_env_set RELEASE_BRANCH "$RELEASE_BRANCH"
gh_env_set TARGET_REPOSITORY "$GITHUB_REPOSITORY_OWNER/$RELEASE_BRANCH"
