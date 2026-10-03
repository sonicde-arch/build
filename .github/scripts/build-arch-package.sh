#!/bin/sh

set -eu
test "${RUNNER_DEBUG:-}" = 1 && set -x

. "$SCRIPTS_DIR"/libdocker.sh
. "$SCRIPTS_DIR"/liblog.sh


: "${1:?PACKAGE must not be empty}"
: "${PKGSPECS_DIR:?PKGSPECS_DIR must not be empty}"

MAKEPKG_OPTS='--syncdeps --noconfirm'


inf 'Running makepkg'

cd "$PKGSPECS_DIR/$1"

cmd=$(cat <<-'CMD'
	set -eu

	for n in 1 2 3; do
		makepkg $1 --nobuild && break
		test $n -eq 3 && printf 'makepkg init timed out\n' && exit 124
		printf 'Dependencies download failed; retrying in %ds\n' $n
		sleep $n
	done

	makepkg $1
CMD
)

container_exec sh -c "$cmd" sh "$MAKEPKG_OPTS"
