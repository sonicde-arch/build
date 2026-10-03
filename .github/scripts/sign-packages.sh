#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE

set -eu
test "${RUNNER_DEBUG:-}" = 1 && set -x

. "$SCRIPTS_DIR"/liblog.sh

: "${1:?BINPKGS_DIR must not be empty}"
: "${2:?SIGNING_KEY must not be empty}"
: "${3:?SIGNING_KEY_PASSWORD must not be empty}"

ARCFMT='tar.zst'
export GNUPGHOME="${GNUPGHOME:-$(mktemp -d)}"
export TZ=UTC


inf 'Signing packages'

keyid=$(printf '%s\n' "$2" |
	gpg --import-options show-only --with-colon --import |
	grep '^fpr:' | cut -d ':' -f 10 | head -n 1)

printf '%s\n' "$2" | gpg --batch --import

for file in "$1"/*.pkg.$ARCFMT ; do
	test -f "$file" || continue
	printf '%s\n' "$3" | gpg --verbose --batch --passphrase --passphrase-fd 0 \
		--pinentry-mode loopback --default-key "$keyid" --detach-sign \
		--output "$file".sig --sign "$file"
done
