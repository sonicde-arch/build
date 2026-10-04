#!/bin/sh

set -eu
#set -x

export SCRIPTS_DIR=.

. ./libarch.sh

: "${1:?PACKAGE must not be empty}"

CARCH='x86_64'
PKGSPECS_DIR=~/tmp/sonicde-arch/sonicde-arch
PKGEXT=pkg.tar.zst

arch_list_bdepend_assets "$PKGSPECS_DIR" "$1" "$CARCH" "$PKGEXT"
