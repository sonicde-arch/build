#!/bin/sh

set -eu
test "${RUNNER_DEBUG:-}" = 1 && set -x

. "$SCRIPTS_DIR"/libarch.sh
. "$SCRIPTS_DIR"/libdocker.sh
. "$SCRIPTS_DIR"/liblog.sh


# Arguments/Environment

: "${1:?BINPKGS_REPO must not be empty}"
: "${2:?STAGING_TAG must not be empty}"
: "${3:?PACKAGE must not be empty}"

: "${BRANCH:?BRANCH must not be empty}"
: "${CARCH:?CARCH must not be empty}"
: "${CONTAINER_HOME:?CONTAINER_HOME must not be empty}"
: "${CONTAINER_NAME:?CONTAINER_NAME must not be empty}"
: "${CONTAINER_USER:?CONTAINER_USER must not be empty}"
: "${PKGSPECS_DIR:?PKGSPECS_DIR must not be empty}"
: "${PKGSPECS_REPO:?PKGSPECS_REPO must not be empty}"


# Constants

ARCFMT='tar.zst'
PKGEXT=pkg.$ARCFMT
CTR_HOME=$CONTAINER_NAME:$CONTAINER_HOME
CTR_WS=$GITHUB_WORKSPACE


# Main

container_start

gh repo clone "$PKGSPECS_REPO" "$PKGSPECS_DIR" -- --branch "$BRANCH" \
	--depth 1 --single-branch


inf 'Resolving dependencies'

mkdir -p dependencies
cd dependencies

arch_list_bdepend_assets ../"$PKGSPECS_DIR" "$3" "$CARCH" "$PKGEXT" >> assets.csv
if [ -s assets.csv ] ; then
	gh_release_download_ff "$1" "$2" assets.csv
	arch_repo_add -- dependencies.db.$ARCFMT *.pkg.$ARCFMT
	arch_repo_conf dependencies "file://$CTR_WS/dependencies" 'Optional TrustAll'
fi


inf 'Setting up the container'

cd "$GITHUB_WORKSPACE"

container_cp -a "$CONFIG_DIR"/makepkg.conf "$CTR_HOME"/.makepkg.conf
arch_makepkg_conf PKGDEST "$GITHUB_WORKSPACE/$BINPKGS_DIR"
arch_makepkg_conf PKGEXT ".$PKGEXT"
arch_pacman_conf DownloadUser "$CONTAINER_USER"

container_sudo pacman-key --init
container_sudo pacman --sync --refresh --sysupgrade

if [ "${SETUP_NINJA:-}" = 1 ] ; then
	arch_install ninja
	arch_makepkg_conf CMAKE_GENERATOR Ninja
fi

test -n "${PACKAGER:-}" && arch_makepkg_conf PACKAGER "$PACKAGER"
test -n "${PGP_KEY:-}" && arch_trust_key "$PGP_KEY"
