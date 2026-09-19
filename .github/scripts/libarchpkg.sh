#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu

# Arguments
# $1: path to PKGBUILD
pkgbuild_pkgnames() {
	bash -s -- "$1" <<'EOF'
		set -eu
		source "$1"/PKGBUILD
		printf '%s\n' "${pkgname[@]}"
EOF
}


# Arguments
# $1: path to PKGBUILD
pkgbuild_pkgnames_to_wildcards() {
	bash -s -- "$1" <<'EOF'
		set -eu
		epoch=0
		source "$1"/PKGBUILD
		test $epoch -gt 0 && epoch="${epoch}_" || epoch=
		suffix="-${epoch}$pkgver-$pkgrel-*.pkg.*"
		printf '%s\n' "${pkgname[@]}" | sed "s/$/$suffix/g"
		printf '%s-debug\n' "${pkgname[@]}" | sed "s/$/$suffix/g"
EOF
}


# Arguments
# $1: path to repository database archive
# $2: newline-separated package names
repodb_has_pkgnames() {
	repo_db=$1
	pkgnames=$2

	registered=$(
		tar --zstd -xOf "$repo_db" --wildcards '*/desc' |
			awk '$0 == "%NAME%" { getline; print }'
	)

	while IFS= read -r pkgname || [ -n "$pkgname" ] ; do
		[ -n "$pkgname" ] || continue
		printf '%s\n' "$registered" | grep -Fqx "$pkgname" || return 1
	done <<EOF
$pkgnames
EOF
}

# Arguments
# $1: docker image
# $2: path to repository database
# $3-$n: package files to add
repodb_add_packages() {
	docker_image=$1
	repo_db=$2
	shift 2

	docker run --rm --user "$(id -u):$(id -g)" --volume "$(pwd)":/work \
		--workdir /work "$docker_image" repo-add "$repo_db" "$@"
}
