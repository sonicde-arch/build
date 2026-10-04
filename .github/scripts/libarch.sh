#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu

. "$SCRIPTS_DIR"/libdocker.sh
. "$SCRIPTS_DIR"/libgithub.sh


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

# TODO add new entries as well
arch_pacman_conf() {
	container_sudo sed -i "s/^$1 = .*/$1 = $2/" /etc/pacman.conf
}

arch_repo_conf() {
	_repo=$(cat <<-REPO
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
	container_sudo sh -c "$_cmd" sh "$_repo"
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

# Arguments
# $1: effective makepkg options
# $2: pkgbase option overrides
_package_debuggable() {
	_debug=; _strip=
	for _opt in $1 $2; do
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
# $1: path to .SRCINFO
# $2: target architecture
# $3: package file extension
# $4: effective makepkg options
arch_list_assets() {
	epoch=; garchs=; opts=

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
		}' "$1")
	EOF
	version=${epoch:+$epoch:}$pkgver-$pkgrel

	sed -n -E '/^pkgname = /,$ {
			s/^[[:blank:]]*pkgname = (.*)$/\v\1/p
			s/^[[:blank:]]*arch = (.*)$/\1/p
		} ' "$1" | tr '\v\n' '\n|' |
	while IFS='|' read -r pkgname archs || [ -n "$pkgname$archs" ]; do
		test -n "$pkgname" || continue
		archs=${archs:-$garchs}
		case "|$archs" in
			*'|any|'*) arch=any ;;
			*"|$2|"*)  arch=$2 ;;
			*)         continue ;;
		esac
		printf '%s-%s-%s.%s\n' "$pkgname" "$version" "$arch" "$3"
	done

	_package_debuggable "${4:-}" "$opts" || return 0
	case "|$garchs" in
		*'|any|'*) arch=any ;;
		*"|$2|"*)  arch=$2 ;;
		*)         return ;;
	esac
	printf '%s-debug-%s-%s.%s\n' "$pkgbase" "$version" "$arch" "$3"
}

# Arguments
# $1: path to PKGSPECS
# $2: target architecture
# $3: package file extension
# $4: effective makepkg options
arch_list_assets2bases() {
	for info in "$1"/*/.SRCINFO; do
		test -f "$info" || continue
		pkgbase=${info%/*}
		pkgbase=${pkgbase##*/}

		arch_list_assets "$info" "$2" "$3" "$4" | sed "s/\$/\|$pkgbase/"
	done
}

# Arguments
# $1: base dir with PKGBUILDs in subdirs
# $2: temporary workdir
# $3: package base name to get the dependencies for
_list_bdepends() {
	_bol='^[[:blank:]]*'
	_bdeps_re="1,/^pkgname = /s/${_bol}(depends|makedepends) = (.*)$/^\2|/p"

	sed -E -n "$_bdeps_re" "$1/$3/.SRCINFO" | grep -f - "$2"/pkgs2bases.csv |
	while IFS='|' read -r _ pkgbase; do
		mkdir "$2/$pkgbase" 2>/dev/null || continue
		_list_bdepends "$1" "$2" "$pkgbase"
	done
}

# List all build time dependent asset names of the given package base
#
# Arguments
# $1: base dir with PKGBUILDs in subdirs
# $2: name of the pkgbase to start with
# $3: target architecture
# $4: package file extension
arch_list_bdepend_assets() {
	_oldpwd=$(pwd); _tmp=$(mktemp -d)

	sed -n '
		/^pkgbase = /{s/^pkgbase = //;h}
		/^pkgname = /{s/^pkgname = //;G;s/\n/|/p}
	' "$1"/*/.SRCINFO > "$_tmp"/pkgs2bases.csv

	_list_bdepends "$1" "$_tmp" "$2"

	for dir in "$_tmp"/*; do
		test -d "$dir" || continue
		pkgbase=${dir##*/}
		arch_list_assets "$1/$pkgbase/.SRCINFO" "$3" "$4"
	done

	cd "$_oldpwd" && rm -rf "$_tmp"
}

# Arguments
# $1: path to repository database
# $2-$n: package files to add
arch_repo_add() {
	_db=$1 ; shift
	container_exec repo-add "$_db" "$@"
}
