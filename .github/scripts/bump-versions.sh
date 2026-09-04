#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE

set -eu

. "$SCRIPTS_DIR"/liblog.sh


# Arguments

base=$1


# Environment

: "${APP_ID:?APP_ID must not be empty}"
: "${DOCKER_IMAGE:?DOCKER_IMAGE must not be empty}"
: "${GH_APP_SLUG:?GH_APP_SLUG must not be empty}"


# Functions

start_container() {
	uid=$(id -u)
	inf 'Starting Docker container'
	docker run --detach --name builder --env SRCDEST=/tmp \
		--volume "$GITHUB_WORKSPACE:/workspace" \
		"$DOCKER_IMAGE" sh -c 'while :; do sleep 3600; done'
	docker exec builder sh -c "
		set -eu
		pacman -Sy --needed --noconfirm pacman-contrib
		useradd -u $uid -m runner
	"
	started=1
}

cleanup() {
	docker rm --force builder >/dev/null 2>&1 || :
	log_close || :
	rm -rf "$tmpdir"
}


# Main

started=0
tmpdir=$(mktemp -d)

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM
log_open

cat > "$tmpdir"/base.toml <<-EOF
	[__config__]
	oldver = "$tmpdir/oldver"
	newver = "$tmpdir/newver"
EOF

for config in */.nvchecker.toml; do
	test -f "$config" || continue
	test $started -eq 0 && start_container

	dir=${config%/*}

	pkgbase=$(sed -n 's/^pkgbase = \(.*\)$/\1/p' "$dir"/.SRCINFO)
	pkgver=$(sed -n 's/^[ \t]*pkgver = \(.*\)$/\1/p' "$dir"/.SRCINFO)

	inf 'Checking for updates of %s v%s' "$pkgbase" "$pkgver"

	printf '{"%s": "%s"}\n' "$pkgbase" "$pkgver" > "$tmpdir"/oldver
	cat "$tmpdir"/base.toml "$config" > "$tmpdir"/nvchecker.toml

	nvchecker -c "$tmpdir"/nvchecker.toml

	version=$(sed -n 's/.*": "\(.*\)"/\1/p' "$tmpdir"/newver)

	test -n "$version" || die 1 'New version is empty for %s' "$pkgbase"
	test "$version" = "$pkgver" && { inf 'No new version found.' ; continue; }

	pr="update/$base/$pkgbase-$version"
	test -z "$(gh pr list --base "$base" --head "$pr")" || continue

	sed -i "s/^pkgver=.*/pkgver=$version/" "$dir"/PKGBUILD
	sed -i "s/^pkgrel=.*/pkgrel=1/" "$dir"/PKGBUILD

	docker exec --user runner --workdir "/workspace/$dir" builder sh -c '
		updpkgsums
		makepkg --printsrcinfo > .SRCINFO
	'

	msg=$(printf '%s: v%s\n\nBumping %s from %s to %s on %s branch.' "$pkgbase" \
		"$version" "$pkgbase" "$pkgver" "$version" "$base")
	git switch --create "$pr"
	git add "$dir"
	git commit --message "$msg"
	inf 'Pushing branch to %s ...' "$pr"
	git push --set-upstream origin "$pr" >$dbg
	gh pr create --base "$base" --head "$pr" --fill
	git switch --discard-changes "$base"
done
