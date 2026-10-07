#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu

. "$SCRIPTS_DIR"/libdocker.sh
. "$SCRIPTS_DIR"/libgithub.sh


# Keep this config local to not pollute the rest of the build system

FILESDB_EXT=files
FILESDB_ARCEXT=$FILESDB_EXT.tar.zst
PKGDB_EXT=db
PKGDB_ARCEXT=$PKGDB_EXT.tar.zst


# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

arch_install() {
	container_sudo pacman -S --needed --noconfirm "$@"
}

# TODO replace existing entries as well
arch_makepkg_conf() {
	container_sudo sh -c "printf '%s=\"%s\"\n' '$1' '$2' >> /etc/makepkg.conf"
}

# Arguments
# $1: PACKAGING_OPTIONS
arch_makepkg_conf_options() {
	result=
	for value in $1; do
		case $value in
			debug|!debug|strip|!strip) result="${result:+$result }$value" ;;
		esac
	done
	container_sudo sh -c "printf 'OPTIONS+=(%s)\n' '$result' >> /etc/makepkg.conf"
}

# TODO add new entries as well
arch_pacman_conf() {
	container_sudo sed -i "s/^$1 = .*/$1 = $2/" /etc/pacman.conf
}

arch_pkgdb_conf() {
	_pkgdb=$(cat <<-REPO
		[$1]
		Server = $2
		SigLevel = $3
	REPO
	)
	_cmd=$(cat <<-'CMD'
		tmp=$(mktemp)
		printf '%s\n' "$1" > "$tmp"
		cat /etc/pacman.conf >> "$tmp"
		cat "$tmp" > /etc/pacman.conf
	CMD
	)
	container_sudo sh -c "$_cmd" sh "$_pkgdb"
}

arch_trust_key() {
	container_sudo sh -c "
		printf '%s\n' '$1' | pacman-key --add /dev/stdin
		printf '%s\n' '$1' | gpg --import-options show-only --with-colon --import |
			grep '^fpr:' | cut -d ':' -f 10 | xargs -n1 pacman-key --lsign-key
	"
}


# ------------------------------------------------------------------------------
# Packaging
# ------------------------------------------------------------------------------

_packing_options_sign() {
	_sign=
	for _opt in ${PACKAGING_OPTIONS:-}; do
		case $_opt in
			sign)  _sign=1 ;;
			!sign) _sign= ;;
		esac
	done
	test "$_sign"
}

# Arguments
# $1: pkgbase option overrides
_pkg_creates_debug_artifact() {
	_debug=; _strip=
	for _opt in ${PACKAGING_OPTIONS:-} $1; do
		case $_opt in
			debug)  _debug=1 ;;
			!debug) _debug= ;;
			strip)  _strip=1 ;;
			!strip) _strip= ;;
		esac
	done
	test "$_debug" && test "$_strip"
}

# Arguments
# $1: path to pkgbase
arch_pkg_list_assets() {
	epoch=; garchs=; opts=
	_packing_options_sign && sign=1 || sign=

	while IFS= read -r line; do
		case $line in
			'pkgbase = '*) pkgbase=${line#pkgbase = } ;;
			'pkgver = '*)  pkgver=${line#pkgver = } ;;
			'pkgrel = '*)  pkgrel=${line#pkgrel = } ;;
			'epoch = '*)   epoch=${line#epoch = } ;;
			'arch = '*)    garchs="${garchs}${line#arch = }|" ;;
			'options = '*) opts="${opts:+$opts }${line#options = }" ;;
		esac
	done <<-EOF
		$(sed -n -E '1,/^pkgname = /{
			s/^[[:blank:]]*(pkgbase|pkgver|pkgrel|epoch|arch|options) = /\1 = /p
		}' "$1"/.SRCINFO)
	EOF
	version=${epoch:+$epoch:}$pkgver-$pkgrel

	sed -n -E '/^pkgname = /,$ {
			s/^[[:blank:]]*pkgname = (.*)$/\v\1/p
			s/^[[:blank:]]*arch = (.*)$/\1/p
		} ' "$1"/.SRCINFO | tr '\v\n' '\n|' |
	while IFS='|' read -r pkgname archs || [ -n "$pkgname$archs" ]; do
		test -n "$pkgname" || continue
		archs=${archs:-$garchs}
		case "|$archs" in
			*'|any|'*)           arch=any ;;
			*"|$TARGET_ARCH|"*)  arch=$TARGET_ARCH ;;
			*)                   continue ;;
		esac
		printf '%s-%s-%s.%s\n' "$pkgname" "$version" "$arch" "$BINPKG_EXT"
		test "$sign" != 1 && continue
		printf '%s-%s-%s.%s\n' "$pkgname" "$version" "$arch" "$BINPKG_EXT.sig"
	done

	_pkg_creates_debug_artifact "$opts" || return 0
	case "|$garchs" in
		*'|any|'*)           arch=any ;;
		*"|$TARGET_ARCH|"*)  arch=$TARGET_ARCH ;;
		*)                   return ;;
	esac
	printf '%s-debug-%s-%s.%s\n' "$pkgbase" "$version" "$arch" "$BINPKG_EXT"
	test "$sign" != 1 && return
	printf '%s-debug-%s-%s.%s\n' "$pkgbase" "$version" "$arch" "$BINPKG_EXT.sig"
}

# Arguments
# $1: path to PKGSPECS
arch_pkgspecs_list_assets2bases() {
	for info in "$1"/*/.SRCINFO; do
		test -f "$info" || continue
		basedir=${info%/*}
		pkgbase=${basedir##*/}

		arch_pkg_list_assets "$basedir" | sed "s/\$/\|$pkgbase/"
	done
}

# Arguments
# $1: base dir with PKGBUILDs in subdirs
# $2: temporary workdir
# $3: package base name to get the dependencies for
_pkg_list_bdepends() {
	_bol='^[[:blank:]]*'
	_bdeps_re="1,/^pkgname = /s/${_bol}(depends|makedepends) = (.*)$/^\2|/p"

	sed -E -n "$_bdeps_re" "$1/$3/.SRCINFO" | grep -f - "$2"/pkgs2bases.csv |
	while IFS='|' read -r _ pkgbase; do
		mkdir "$2/$pkgbase" 2>/dev/null || continue
		_pkg_list_bdepends "$1" "$2" "$pkgbase"
	done
}

# List all build time dependent asset names of the given package base
#
# Arguments
# $1: base dir with PKGBUILDs in subdirs
# $2: name of the pkgbase to start with
arch_pkgspecs_list_bdepend_assets() {
	_oldpwd=$(pwd); _tmp=$(mktemp -d)

	sed -n '
		/^pkgbase = /{s/^pkgbase = //;h}
		/^pkgname = /{s/^pkgname = //;G;s/\n/|/p}
	' "$1"/*/.SRCINFO > "$_tmp"/pkgs2bases.csv

	_pkg_list_bdepends "$1" "$_tmp" "$2"

	for dir in "$_tmp"/*; do
		test -d "$dir" || continue
		pkgbase=${dir##*/}
		arch_pkg_list_assets "$1/$pkgbase"
	done

	cd "$_oldpwd" && rm -rf "$_tmp"
}

# Arguments
# $1: package database name
# $2-$n: package files to add
arch_pkgdb_add() {
	_db=$1 ; shift
	container_exec repo-add "$_db.$PKGDB_ARCEXT" "$@"
}

# Arguments
# $1: package database name
# shellcheck disable=SC2086
arch_pkgdb_exists() {
	test -f "$1".$FILESDB_EXT
	test -f "$1".$FILESDB_ARCEXT
	test -f "$1".$PKGDB_EXT
	test -f "$1".$PKGDB_ARCEXT
}

# Arguments
# $1: source package database name
# $2: destination package database name
# shellcheck disable=SC2086
arch_pkgdb_rename() {
	mv "$1".$FILESDB_EXT "$2".$FILESDB_EXT
	mv "$1".$FILESDB_ARCEXT "$2".$FILESDB_ARCEXT
	mv "$1".$PKGDB_EXT "$2".$PKGDB_EXT
	mv "$1".$PKGDB_ARCEXT "$2".$PKGDB_ARCEXT
}
