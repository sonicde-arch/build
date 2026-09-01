#!/bin/sh

set -eu

. "$SCRIPTS_DIR"/liblog.sh
. "$SCRIPTS_DIR"/libgithub.sh


# Environment

: "${APP_PRIVATE_KEY:?APP_PRIVATE_KEY must not be empty}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must not be empty}"
: "${PACKAGES_REPOSITORY:?PACKAGES_REPOSITORY must not be empty}"


# Debug

PACKAGES_REPOSITORY=sonicde-arch/nvcheck-dev


# Main

trap log_close 0
trap 'exit 1' HUP INT TERM
log_open

auth=$(gh-app-token.sh "$APP_ID")
gh_env_set GH_APP_SLUG "$(printf '%s\n' "$auth" | cut -f2)"
gh_env_set GITHUB_TOKEN "$(printf '%s\n' "$auth" | cut -f1)"
gh_env_set GH_TOKEN "$GITHUB_TOKEN"

sudo apt install --yes nvchecker

bot="${GH_APP_SLUG}[bot]"
bot_id=$(gh api "/users/$bot" --jq '.id')

gh auth setup-git
gh repo clone "$PACKAGES_REPOSITORY" "$GITHUB_WORKSPACE" -- \
	--branch "$BRANCH" --depth 1 --single-branch
git config user.name "$bot"
git config user.email "${bot_id}+$bot@users.noreply.github.com"
