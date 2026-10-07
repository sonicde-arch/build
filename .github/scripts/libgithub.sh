#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE

set -eu

. "$SCRIPTS_DIR"/liblog.sh


# GitHub context functions

# Arguments
# $1: JSON object containing variable names and values
# $2: optional prefix for the variable names
gh_context_import() {
	code=$(
		printf '%s\n' "$1" | jq -r --arg prefix "${2-}" '
			to_entries[]
			| .key |= (ascii_upcase | gsub("[^A-Z0-9_]"; "_"))
			| @sh "gh_env_set \($prefix)\(.key) \(.value | tostring)"
		'
	)
	eval "$code"
}


# GitHub output functions

# Arguments
# $1: name of the env variable
# $2: value of the env variable
gh_env_set() {
	delim="GH_ENV_$$"
	printf '%s<<%s\n%s\n%s\n' "$1" "$delim" "$2" "$delim" >> "$GITHUB_ENV"
	export "$1=$2"
}

# Arguments
# $1: name of the env variable
# $2: value of the env variable
gh_output() {
	delim="GH_OUTPUT_$$"
	printf '%s<<%s\n%s\n%s\n' "$1" "$delim" "$2" "$delim" >> "$GITHUB_OUTPUT"
}


# GitHub release functions

# Arguments
# $1: target repo
# $2: release tag
# $3: filenames or wildcards, one per line
gh_release_filter_assets() {
	regex=$(printf '%s' "$3" | sed -e '/^[[:space:]]*$/d' -e 's/\./\\./g' \
		-e 's/\*/.*/g' -e 's/^/^/g' -e 's/$/$/g')
	test -n "$regex" || return 1
	gh release view --repo "$1" --json assets "$2" | jq -r '.assets[].name' |
		grep -E "$regex"
}

# Arguments
# $1: Git repository
# $2: release tag
# $3: filenames or wildcards, one per line
gh_release_download_ff() {
	_repo=$1; _tag=$2; _wildcards=$3
	set --
	while IFS= read -r pattern; do
		test -n "$pattern" && set -- "$@" --pattern "$pattern"
	done < "$_wildcards"
	ghpy release download -v --repo "$_repo" "$_tag" "$@"
}

# Arguments
# $1: Git repository
# $2: source release tag
# $3: target release tag
# $4: filenames or wildcards, one per line
# $5: overwrite existing files if set to 1 (default: 0)
gh_release_copy_assets_ff() {
	repo=$1; srctag=$2; dsttag=$3; wildcards=$(realpath -e "$4"); upopts=; rc=0

	test "${5:-0}" = 1 && upopts='--clobber'
	oldpwd=$(pwd); tmpdir=$(mktemp -d); cd "$tmpdir"

	gh_release_download_ff "$repo" "$srctag" "$wildcards"
	ghpy release upload $upopts -v --repo "$repo" "$dsttag" ./* || rc=$?

	cd "$oldpwd" && rm -rf "$tmpdir"
	return "$rc"
}

# Arguments
# $1: Git repository
# $2: release tag
gh_release_delete() {
	delopts=
	isdraft=$(gh release view --repo "$1" "$2" --json isDraft --jq '.isDraft')
	test "$isdraft" = true || delopts=--cleanup-tag
	gh release delete $delopts --yes --repo "$1" "$2"
}

# Arguments
# $1: Git repository
# $2: release tag
gh_release_exists() {
	gh release view --json databaseId --repo "$1" "$2" 1>/dev/null 2>&1
}

# Arguments
# $1: Git repository
# $2: release tag
# $3: filenames or wildcards, one per line
# $4: ignore errors and try to delete all (default: 0)
gh_release_delete_assets_ff() {
	while IFS= read -r asset ; do
		if ! gh release delete-asset --yes --repo "$1" "$2" "$asset" ; then
			printf 'Failed to delete asset: %s\n' "$asset"
			test "${4:-0}" -eq 1 && continue
			return 1
		fi
	done < "$3"
}
