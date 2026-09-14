#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# FeisClár APK Release Publisher
# Automates replacing feisclar.apk on GitHub releases
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLIC_REPO_DIR="/home/dhead/code/feisclar-public"
MAIN_REPO_DIR="/home/dhead/code/feisclar"

# 1. Load .env file if available
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
elif [[ -f "$PUBLIC_REPO_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$PUBLIC_REPO_DIR/.env"
elif [[ -f "$MAIN_REPO_DIR/.env.release" ]]; then
  # shellcheck disable=SC1091
  source "$MAIN_REPO_DIR/.env.release"
elif [[ -f "$PWD/.env" ]]; then
  # shellcheck disable=SC1091
  source "$PWD/.env"
fi

# 2. Configuration & Defaults
DEFAULT_REPO="dheade-dev/feisclar-public"
DEFAULT_TAG="0.3"
DEFAULT_APK_FEISCLAR="/home/dhead/code/feisclar/feisclar.apk"

REPO="${GITHUB_REPO:-$DEFAULT_REPO}"
TAG="${2:-${RELEASE_TAG:-$DEFAULT_TAG}}"

# Resolve APK path
if [[ -n "${1:-}" ]]; then
  APK_PATH="$1"
elif [[ -f "$DEFAULT_APK_FEISCLAR" ]]; then
  APK_PATH="$DEFAULT_APK_FEISCLAR"
elif [[ -f "$SCRIPT_DIR/feisclar.apk" ]]; then
  APK_PATH="$SCRIPT_DIR/feisclar.apk"
elif [[ -f "$PUBLIC_REPO_DIR/feisclar.apk" ]]; then
  APK_PATH="$PUBLIC_REPO_DIR/feisclar.apk"
elif [[ -f "$PWD/feisclar.apk" ]]; then
  APK_PATH="$PWD/feisclar.apk"
else
  echo "❌ Error: Could not find feisclar.apk"
  echo "Usage: $0 [path-to-apk] [release-tag]"
  echo "Example: $0 /home/dhead/code/feisclar/feisclar.apk 0.3"
  exit 1
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "❌ Error: APK file not found at: $APK_PATH"
  exit 1
fi

APK_NAME="$(basename "$APK_PATH")"
APK_SIZE_BYTES="$(stat -c%s "$APK_PATH")"
APK_SIZE_MB="$(awk "BEGIN {printf \"%.2f\", $APK_SIZE_BYTES / 1048576}")"

# 3. Resolve GitHub Token
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]] && command -v gh >/dev/null 2>&1; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi

if [[ -z "$TOKEN" ]]; then
  echo ""
  echo "⚠️  GitHub Token not detected!"
  echo "To publish releases, this script needs a GitHub Personal Access Token."
  echo "You can create one at: https://github.com/settings/tokens"
  echo "  -> Classic token: Select 'public_repo' (or 'repo')"
  echo "  -> Fine-grained token: Select 'feisclar-public', 'Contents: Read and write'"
  echo ""
  echo -n "Enter GitHub Token: "
  read -r -s TOKEN
  echo ""
  if [[ -z "$TOKEN" ]]; then
    echo "❌ Operation cancelled: No token provided."
    echo "Tip: Save your token in $PUBLIC_REPO_DIR/.env as:"
    echo "GITHUB_TOKEN=ghp_yourTokenHere"
    exit 1
  fi
fi

AUTH_HEADER="Authorization: Bearer $TOKEN"
API_HEADER="Accept: application/vnd.github+json"

echo "=================================================="
echo "🚀 FeisClár APK Release Publisher"
echo "=================================================="
echo "📦 Repository:  $REPO"
echo "🏷️  Release Tag: $TAG"
echo "📱 APK File:     $APK_PATH ($APK_SIZE_MB MB)"
echo "=================================================="

# 4. Fetch Release Information from GitHub
echo "🔍 Fetching release details for tag '$TAG'..."
RELEASE_RESP="$(curl -s -w "\n__HTTP_STATUS__%{http_code}" -H "$AUTH_HEADER" -H "$API_HEADER" "https://api.github.com/repos/$REPO/releases/tags/$TAG")"

HTTP_STATUS="$(echo "$RELEASE_RESP" | grep "^__HTTP_STATUS__" | sed 's/^__HTTP_STATUS__//')"
RELEASE_JSON="$(echo "$RELEASE_RESP" | sed '/^__HTTP_STATUS__/d')"

if [[ "$HTTP_STATUS" -ne 200 ]]; then
  echo "❌ Failed to fetch release '$TAG' (HTTP $HTTP_STATUS)."
  if [[ "$HTTP_STATUS" -eq 401 || "$HTTP_STATUS" -eq 403 ]]; then
    echo "⚠️  Authentication error. Please verify your GITHUB_TOKEN has proper repo write permissions."
  elif [[ "$HTTP_STATUS" -eq 404 ]]; then
    echo "⚠️  Release tag '$TAG' not found in repository '$REPO'."
  fi
  echo "$RELEASE_JSON"
  exit 1
fi

# Extract upload_url, release_id, and existing asset id using python
READ_RESULT="$(python3 -c '
import json, sys
data = json.loads(sys.argv[1])
release_id = data.get("id", "")
upload_url = data.get("upload_url", "").split("{")[0]
asset_id = ""
for asset in data.get("assets", []):
    if asset.get("name") == sys.argv[2]:
        asset_id = str(asset.get("id", ""))
        break
print(f"{release_id}|{upload_url}|{asset_id}")
' "$RELEASE_JSON" "$APK_NAME")"

RELEASE_ID="$(echo "$READ_RESULT" | cut -d'|' -f1)"
UPLOAD_URL="$(echo "$READ_RESULT" | cut -d'|' -f2)"
EXISTING_ASSET_ID="$(echo "$READ_RESULT" | cut -d'|' -f3)"

if [[ -z "$UPLOAD_URL" ]]; then
  echo "❌ Error: Could not determine release upload URL."
  exit 1
fi

# 5. Delete existing asset if present
if [[ -n "$EXISTING_ASSET_ID" ]]; then
  echo "🗑️  Removing existing '$APK_NAME' from release (Asset ID: $EXISTING_ASSET_ID)..."
  DELETE_RESP="$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "$AUTH_HEADER" \
    -H "$API_HEADER" \
    "https://api.github.com/repos/$REPO/releases/assets/$EXISTING_ASSET_ID")"

  if [[ "$DELETE_RESP" -eq 204 || "$DELETE_RESP" -eq 200 ]]; then
    echo "✅ Existing asset successfully deleted."
  else
    echo "⚠️  Notice: Delete returned HTTP $DELETE_RESP (proceeding with upload anyway)..."
  fi
else
  echo "ℹ️  No previous asset named '$APK_NAME' found in release."
fi

# 6. Upload new APK asset with real-time progress
echo "⬆️  Uploading new '$APK_NAME' ($APK_SIZE_MB MB) to release '$TAG'..."
echo "   (Progress bar below indicates upload transfer)"

UPLOAD_TARGET="${UPLOAD_URL}?name=${APK_NAME}"

UPLOAD_RESP="$(curl -# -w "\n__HTTP_STATUS__%{http_code}" -X POST \
  -H "$AUTH_HEADER" \
  -H "$API_HEADER" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary "@$APK_PATH" \
  "$UPLOAD_TARGET")"

UPLOAD_STATUS="$(echo "$UPLOAD_RESP" | grep "^__HTTP_STATUS__" | sed 's/^__HTTP_STATUS__//')"
UPLOAD_JSON="$(echo "$UPLOAD_RESP" | sed '/^__HTTP_STATUS__/d')"

if [[ "$UPLOAD_STATUS" -eq 201 || "$UPLOAD_STATUS" -eq 200 ]]; then
  DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$APK_NAME"
  echo ""
  echo "=================================================="
  echo "🎉 SUCCESS! FeisClár APK Published Successfully!"
  echo "=================================================="
  echo "🌐 Release Page:   https://github.com/$REPO/releases/tag/$TAG"
  echo "📥 Download URL:   $DOWNLOAD_URL"
  echo "📱 Asset Name:     $APK_NAME"
  echo "📊 File Size:      $APK_SIZE_MB MB"
  echo "🕒 Published At:   $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "=================================================="
else
  echo ""
  echo "❌ Upload failed (HTTP $UPLOAD_STATUS)."
  echo "GitHub Response:"
  echo "$UPLOAD_JSON"
  exit 1
fi
