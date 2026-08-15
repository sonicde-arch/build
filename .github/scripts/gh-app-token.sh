#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE
# SPDX-FileCopyrightInfo: 2026 Joseph Crowell joseph.w.crowell@gmail.com

set -eu


# Arguments

APP_ID="${1-$APP_ID}"
GITHUB_REPOSITORY_OWNER="${2-$GITHUB_REPOSITORY_OWNER}"


# Environment

: "${APP_PRIVATE_KEY:?APP_PRIVATE_KEY must not be empty}"


# Main

privkey=$(mktemp)

trap 'rm -f "$privkey"' EXIT HUP INT TERM
printf '%s\n' "$APP_PRIVATE_KEY" > "$privkey"

b64enc() {
	openssl base64 | tr -d '=\n' | tr '/+' '_-'
}

now=$(date +%s)

header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64enc)
payload=$(
	printf '{"iat":%s,"exp":%s,"iss":"%s"}' \
		"$((now - 60))" "$((now + 600))" "$APP_ID" | b64enc
)
signature=$(
	printf '%s.%s' "$header" "$payload" \
		| openssl dgst -binary -sha256 -sign "$privkey" | b64enc
)

jwt="$header.$payload.$signature"

install_id=$(
	gh api \
		--header "Authorization: Bearer $jwt" \
		"/orgs/$GITHUB_REPOSITORY_OWNER/installation" \
		--jq '.id'
)

gh api --method POST \
	--header "Authorization: Bearer $jwt" \
	"/app/installations/$install_id/access_tokens" \
	--jq '.token'
