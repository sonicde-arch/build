#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu


# Arguments
# $1: global architecture list
# $2: package architecture list
# $3: target architecture
_package_arch() {
	arch=$3
	printf '%s\n' "${2:-$1}" | grep -Fxq any && arch=any
	printf '%s\n' "${2:-$1}" | grep -Fxq "$arch" && printf '%s\n' "$arch"
}

# Arguments
# $1: package name
# $2: attribute name
# $3: path to .SRCINFO
_package_attr() {
	_name=$(printf '%s\n' "$1" | sed 's/\./\\./g')
	sed -n "/^pkgname = $_name\$/,/^pkgname = /s/^[[:blank:]]*$2 = //p" "$3"
}

# Arguments
# $1: effective makepkg options
# $2: pkgbase option overrides
_package_debuggable() {
	test "$(printf '%s\n' "$1" "$2" | sed -n '/^!*debug$/p' | tail -1)" = debug ||
		return
	test "$(printf '%s\n' "$1" "$2" | sed -n '/^!*strip$/p' | tail -1)" = strip
}

# Arguments
# $1: path to .SRCINFO
# $2: target architecture
# $3: package file extension
# $4: effective makepkg options
makepkg_packagelist() {
	info=$1

	bol='^[[:blank:]]*' # beginning of line + indentation
	pkgbase=$(sed -n "s/${bol}pkgbase = //p" "$info")
	pkgver=$(sed -n "s/${bol}pkgver = //p" "$info")
	pkgrel=$(sed -n "s/${bol}pkgrel = //p" "$info")
	epoch=$(sed -n "s/${bol}epoch = \([1-9][0-9]*\)\$/\1/p" "$info")
	garch=$(sed -n "1,/^pkgname = /s/${bol}arch = //p" "$info")
	opts=$(sed -n "1,/^pkgname = /s/${bol}options = //p" "$info")

	version=${epoch:+$epoch:}$pkgver-$pkgrel

	sed -n 's/^pkgname = //p' "$info" |
	while IFS= read -r pkgname; do
		larch=$(_package_attr "$pkgname" arch "$info")
		arch=$(_package_arch "$garch" "$larch" "$2") || continue
		printf '%s-%s-%s%s\n' "$pkgname" "$version" "$arch" "$3"
	done

	arch=$(_package_arch "$garch" '' "$2") || return
	_package_debuggable "$4" "$opts" &&
		printf '%s-debug-%s-%s%s\n' "$pkgbase" "$version" "$arch" "$3"
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
