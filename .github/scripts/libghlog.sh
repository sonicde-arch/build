#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com


# Setup:
#	trap log_close 0
#	trap 'exit 1' HUP INT TERM
#	log_open || exit 1
#
# Usage:
#	command -o1 -o2 >$inf 2>$err
#	err "Failed %s" "$1"
#
# FIFO input is line-oriented; each input line is emitted as one log message.
# The implementation is not thread-safe.


LOG_DIR=


dbg() {
	log '::debug::' "$@"
}

inf() {
	log '::notice::' "$@"
}

wrn() {
	log '::warning::' "$@"
}

err() {
	log '::error::' "$@"
}

_dbgfd() {
	while IFS= read -r line; do
		dbg '%s' "$line"
	done
}

_inffd() {
	while IFS= read -r line; do
		inf '%s' "$line"
	done
}

_wrnfd() {
	while IFS= read -r line; do
		wrn '%s' "$line"
	done
}

_errfd() {
	while IFS= read -r line; do
		err '%s' "$line"
	done
}

log_open() {
	test -z "$LOG_DIR" || return 0

	LOG_DIR=$(mktemp -d) || return 1

	dbg="$LOG_DIR/dbg"
	inf="$LOG_DIR/inf"
	wrn="$LOG_DIR/wrn"
	err="$LOG_DIR/err"

	if ! mkfifo "$dbg" "$inf" "$wrn" "$err"; then
		rm -rf "$LOG_DIR"
		LOG_DIR=
		return 1
	fi

	_dbgfd <"$dbg" &
	LOG_DBG_PID=$!
	_inffd <"$inf" &
	LOG_INF_PID=$!
	_wrnfd <"$wrn" &
	LOG_WRN_PID=$!
	_errfd <"$err" &
	LOG_ERR_PID=$!
}

log_close() {
	test -n "$LOG_DIR" || return 0

	status=0
	: >"$dbg" || status=1
	: >"$inf" || status=1
	: >"$wrn" || status=1
	: >"$err" || status=1

	wait "$LOG_DBG_PID" || status=1
	wait "$LOG_INF_PID" || status=1
	wait "$LOG_WRN_PID" || status=1
	wait "$LOG_ERR_PID" || status=1

	rm -rf "$LOG_DIR" || status=1
	test "$status" = 0 && LOG_DIR=

	return "$status"
}
