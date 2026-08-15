#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu

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
