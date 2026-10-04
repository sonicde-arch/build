#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE

set -eu

. "$SCRIPTS_DIR"/libgithub.sh


_CONT_IDLE=-256

_cont_setup_tmpfs() {
	_mem="$(grep '^MemTotal:' /proc/meminfo | cut -d: -f2 | tr -d ' kB')"
	_size="$((_mem * 75 / 100))k"
	printf '%s /tmp:rw,nosuid,nodev,exec,size=%s\n' '--tmpfs' "$_size"
}

container_start() {
	: "${CONTAINER_NAME:?CONTAINER_NAME must not be empty}"
	: "${DOCKER_IMAGE:?DOCKER_IMAGE must not be empty}"
	: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must not be empty}"

	_dopts=
	test "${SETUP_TMPFS:-0}" = 1 && _dopts=$(_cont_setup_tmpfs)

	docker run --detach --name "$CONTAINER_NAME" --workdir "$GITHUB_WORKSPACE" \
		--volume "$GITHUB_WORKSPACE:$GITHUB_WORKSPACE" \
		--volume "$RUNNER_TEMP:$RUNNER_TEMP" $_dopts \
		"$DOCKER_IMAGE" sh -c 'while :; do sleep 3600; done' >/dev/null &
	_CONT_STATE=$!
	gh_env_set _CONT_STATE "$_CONT_STATE"
}

_container_setup() {
	: "${CONTAINER_NAME:?CONTAINER_NAME must not be empty}"
	: "${CONTAINER_USER:?CONTAINER_USER must not be empty}"

	docker exec "$CONTAINER_NAME" sh -c "
		set -eu
		useradd -m -u '$(id -u)' '$CONTAINER_USER'
		chown -R '$CONTAINER_USER': /home/'$CONTAINER_USER'
		chown -R '$CONTAINER_USER': '$RUNNER_TEMP'
		printf '%s ALL=(ALL) NOPASSWD: ALL\n' '$CONTAINER_USER' >> /etc/sudoers
	"
}

container_await() {
	_CONT_STATE=${_CONT_STATE:-$_CONT_IDLE}
	_rc=0

	test "$_CONT_STATE" -eq "$_CONT_IDLE" && container_start
	test "$_CONT_STATE" -le 0 && return "$((-_CONT_STATE))"
	wait "$_CONT_STATE" || _rc=$?
	gh_env_set _CONT_STATE "$((-_rc))"
	test "$_CONT_STATE" -lt 0 && return "$((-_CONT_STATE))"

	_container_setup
}

container_cp() {
	container_await
	docker cp "$@"
}

container_exec() {
	container_await
	docker exec --user "$CONTAINER_USER" --workdir "$(pwd)" "$CONTAINER_NAME" "$@"
}

container_sudo() {
	container_await
	docker exec --workdir "$(pwd)" "$CONTAINER_NAME" "$@"
}
