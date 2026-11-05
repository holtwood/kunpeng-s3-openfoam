#!/usr/bin/env bash
# Create (if needed) and push this repository to Gitee.
#
# Authentication:
#   Create a Gitee personal access token with the "projects" scope and save it:
#     printf '%s' '<token>' > ~/.gitee-token
#     chmod 600 ~/.gitee-token
#
# The token is read from the file and is never echoed by this script.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TOKEN_FILE="${GITEE_TOKEN_FILE:-$HOME/.gitee-token}"
REPO="${GITEE_REPO:-kunpeng-s3-openfoam}"
DESC="${GITEE_DESC:-Kunpeng S3 OpenFOAM v2606 simpleFoam performance optimization workspace}"
API="https://gitee.com/api/v5"

if [ ! -f "$TOKEN_FILE" ]; then
    echo "missing token file: $TOKEN_FILE" >&2
    echo "create it with:" >&2
    echo "  printf '%s' '<your-token>' > ~/.gitee-token" >&2
    echo "  chmod 600 ~/.gitee-token" >&2
    exit 2
fi

TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
if [ -z "$TOKEN" ]; then
    echo "token file is empty: $TOKEN_FILE" >&2
    exit 2
fi

echo "authenticating against Gitee..."
if ! USER_JSON="$(curl -fsS --max-time 20 "$API/user?access_token=$TOKEN")"; then
    echo "Gitee authentication failed; check the token and its scopes." >&2
    exit 1
fi

LOGIN="$(printf '%s' "$USER_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["login"])')"
echo "authenticated as: $LOGIN"

STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    "$API/repos/$LOGIN/$REPO?access_token=$TOKEN")"

case "$STATUS" in
    200)
        echo "repository already exists: https://gitee.com/$LOGIN/$REPO"
        ;;
    404)
        echo "creating private repository: $REPO"
        curl -fsS -X POST "$API/user/repos" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$REPO\",\"private\":true,\"description\":\"$DESC\"}" \
            "$API/user/repos?access_token=$TOKEN" >/dev/null
        echo "created: https://gitee.com/$LOGIN/$REPO"
        ;;
    *)
        echo "unexpected Gitee API status for repository lookup: $STATUS" >&2
        exit 1
        ;;
esac

# Put the credential into the configured cache helper without printing it.
printf 'protocol=https\nhost=gitee.com\nusername=%s\npassword=%s\n\n' \
    "$LOGIN" "$TOKEN" | git credential approve

URL="https://gitee.com/$LOGIN/$REPO.git"
if git remote get-url gitee >/dev/null 2>&1; then
    git remote set-url gitee "$URL"
else
    git remote add gitee "$URL"
fi

echo "pushing main and tags to $URL"
git push -u gitee main
git push gitee --tags

echo
echo "done: https://gitee.com/$LOGIN/$REPO"
