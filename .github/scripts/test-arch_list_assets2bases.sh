#!/bin/sh

set -eu
#set -x

export SCRIPTS_DIR=.

. ./libarch.sh

CARCH='x86_64'
PKGSPECS_DIR=~/tmp/sonicde-arch/sonicde-arch
PKGEXT=pkg.tar.zst
OPTIONS=

arch_list_assets2bases "$PKGSPECS_DIR" "$CARCH" "$PKGEXT" "$OPTIONS"
