#!/bin/sh

# shellcheck disable=SC2034,SC2329

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE

LOG_IMPL="${LOG_IMPL:-libghlog.sh}"


dbg=/dev/null
inf=/dev/stdout
wrn=/dev/stdout
err=/dev/stderr

log_open() { :; }
log_close() { :; }

log() {
	{
		_prefix=$1
		_format=$2
		shift 2
		# shellcheck disable=SC2059
		printf '%s'"$_format"'\n' "$_prefix" "$@"
		unset _format _prefix
	} >&2
}

dbg() {
	log 'DEBUG: ' "$@"
}

inf() {
	log 'INFO: ' "$@"
}

wrn() {
	log 'WARNING: ' "$@"
}

err() {
	log 'ERROR: ' "$@"
}

die() {
	_code="$1"
	shift
	case $_code in
		0) inf "$@" ;;
		*) err "$@" ;;
	esac
	exit "$_code"
}


LOG_IMPL_LOADED=${LOG_IMPL_LOADED:-0}

# shellcheck source=libghlog.sh
if test "$LOG_IMPL_LOADED" = 0 ; then
	. "$SCRIPTS_DIR/$LOG_IMPL" || return
	LOG_IMPL_LOADED=1
fi
