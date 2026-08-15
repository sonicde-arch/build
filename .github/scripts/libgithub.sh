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
	[ -n "$regex" ] || return 1
	gh release view --repo "$1" --json assets "$2" | jq -r '.assets[].name' |
		grep -E "$regex"
}

# Arguments
# $1: Git repository
# $2: release tag
# $3: filenames or wildcards, one per line
gh_release_download_assets() {
	repo=$1; tag=$2; wildcards=$3

	set --
	while IFS= read -r pattern || [ -n "$pattern" ] ; do
		set -- "$@" --pattern "$pattern"
	done <<EOF
$wildcards
EOF
	gh release download --repo "$repo" "$tag" "$@"
}

# Arguments
# $1: Git repository
# $2: source release tag
# $3: target release tag
# $4: filenames or wildcards, one per line
# $5: overwrite existing files if set to 1 (default: 0)
gh_release_copy_assets() {
	repo=$1; srctag=$2; dsttag=$3; wildcards=$4; upopts=; rc=0

	test "${5:-0}" = 1 && upopts='--clobber'
	oldpwd=$(pwd)
	tmpdir=$(mktemp -d)
	cd "$tmpdir" || return 1

	gh_release_download_assets "$repo" "$srctag" "$wildcards"
	gh release upload $upopts --repo "$repo" "$dsttag" ./* || rc=$?

	cd "$oldpwd"
	rm -rf "$tmpdir"
	return "$rc"
}

# Arguments
# $1: Git repository
# $2: release tag
gh_release_delete() {
	delopts=''
	isdraft=$(gh release view --repo "$1" "$2" --json isDraft --jq '.isDraft')
	test "$isdraft" = 'true' || delopts=--cleanup-tag
	gh release delete $delopts --yes --repo "$1" "$2"
}

# Arguments
# $1: Git repository
# $2: release tag
# $3: filenames or wildcards, one per line
# $4: ignore errors and try to delete all (default: 0)
gh_release_delete_assets() {
	assets=$(gh_release_filter_assets "$1" "$2" "$3") || return 1
	while IFS= read -r asset ; do
		if ! gh release delete-asset --yes --repo "$1" "$2" "$asset" ; then
			printf 'Failed to delete asset: %s\n' "$asset"
			test "${4:-0}" -eq 1 && continue
			return 1
		fi
	done <<EOF
$assets
EOF
}

# Arguments
# $1: file name with revision
gh_release_inc_asset_revision() {
	name=${1%.*}
	ext=${1#"$name"}

	test "$name" = "$1" && ext=
	rev=$(printf '%s\n' "$name" | sed 's/.*-r0*//; s/^$/0/')
	case $rev in ''|*[!0-9]*) die 1 'Invalid revision: %s in %s' "$rev" "$1";; esac
	rev=$((rev + 1))
	printf '%s-r%04d%s\n' "${name%-r*}" "$rev" "$ext"
}

# Arguments
# $1: repository name
# $2: release tag
# $3: asset base name
gh_release_get_asset_maxrev() {
	wildcard="${3%.*}-r*.${3##*.}"
	assets=$(gh_release_filter_assets "$1" "$2" "$wildcard")
	if [ -z "$assets" ] ; then
		err 'No matching assets found for %s in %s@%s' "$3" "$1" "$2"
		exit 1
	fi

	printf '%s\n' "$assets" | LC_ALL=C sort | tail -n 1
}

# Arguments
# $1: repository name
# $2: release tag
# $3: newline-separated asset names
# $4: number of retries (default: 8)
# $5: initial delay in seconds (default: 1)
# $6: backoff factor (default: 2)
gh_release_await_assets() {
	assets=$3
	retries=${4:-8}
	delay=${5:-1}
	backoff=${6:-2}
	copts='--fail --location --show-error --silent --range 0-0 --output /dev/null'
	url="$GITHUB_SERVER_URL/$1/releases/download/$2"

	while test -n "$assets"; do
		while IFS= read -r asset; do
			# shellcheck disable=SC2086
			if curl $copts "$url/$asset" 2>$dbg; then
				dbg 'Asset available: %s' "$asset"
				assets=$(printf '%s\n' "$assets" | grep -Fvx "$asset") || :
			else
				inf 'Asset not available: %s' "$asset"
			fi
		done <<EOF
$assets
EOF

		test -z "$assets" && return 0
		test "$retries" -eq 0 && break

		inf 'Awaiting assets failed; retrying in %ds...' "$delay"
		retries=$((retries - 1))
		sleep "$delay"
		delay=$((delay * backoff))
	done

	err 'timed out waiting for assets in %s@%s' "$1" "$2"
	return 1
}
