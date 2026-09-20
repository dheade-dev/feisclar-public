#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# FeisClár APK & Assets Release Publisher
# Automates replacing feisclar.apk & backup datasets on GitHub releases & git repo
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
echo "🚀 FeisClár Release Publisher"
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

UPLOAD_URL="$(python3 -c '
import json, sys
data = json.loads(sys.argv[1])
print(data.get("upload_url", "").split("{")[0])
' "$RELEASE_JSON")"

if [[ -z "$UPLOAD_URL" ]]; then
  echo "❌ Error: Could not determine release upload URL."
  exit 1
fi

# Function to upload or replace a release asset
upload_release_asset() {
  local file_path="$1"
  local content_type="$2"
  local filename="$(basename "$file_path")"

  if [[ ! -f "$file_path" ]]; then
    echo "⚠️  Notice: File '$file_path' not found. Skipping."
    return 0
  fi

  local file_size_bytes="$(stat -c%s "$file_path")"
  local file_size_display
  if [[ "$file_size_bytes" -ge 1048576 ]]; then
    file_size_display="$(awk "BEGIN {printf \"%.2f MB\", $file_size_bytes / 1048576}")"
  else
    file_size_display="$(awk "BEGIN {printf \"%.1f KB\", $file_size_bytes / 1024}")"
  fi

  # Check if asset already exists on this release
  local existing_id="$(python3 -c '
import json, sys
data = json.loads(sys.argv[1])
found = ""
for a in data.get("assets", []):
    if a.get("name") == sys.argv[2]:
        found = str(a.get("id", ""))
        break
print(found)
' "$RELEASE_JSON" "$filename")"

  if [[ -n "$existing_id" ]]; then
    echo "🗑️  Removing previous asset '$filename' (ID: $existing_id)..."
    curl -s -o /dev/null -X DELETE -H "$AUTH_HEADER" -H "$API_HEADER" \
      "https://api.github.com/repos/$REPO/releases/assets/$existing_id" || true
  fi

  echo "⬆️  Uploading '$filename' ($file_size_display) to release '$TAG'..."
  local upload_target="${UPLOAD_URL}?name=${filename}"
  local upload_resp="$(curl -# -w "\n__HTTP_STATUS__%{http_code}" -X POST \
    -H "$AUTH_HEADER" \
    -H "$API_HEADER" \
    -H "Content-Type: $content_type" \
    --data-binary "@$file_path" \
    "$upload_target")"

  local upload_status="$(echo "$upload_resp" | grep "^__HTTP_STATUS__" | sed 's/^__HTTP_STATUS__//')"
  local upload_json="$(echo "$upload_resp" | sed '/^__HTTP_STATUS__/d')"

  if [[ "$upload_status" -eq 201 || "$upload_status" -eq 200 ]]; then
    echo "✅ Published: https://github.com/$REPO/releases/download/$TAG/$filename"
  else
    echo "❌ Failed to upload '$filename' (HTTP $upload_status)."
    echo "$upload_json"
    return 1
  fi
}

# 5. Upload APK Release Asset
upload_release_asset "$APK_PATH" "application/vnd.android.package-archive"

# 6. Upload Sample Backup Datasets
SAMPLE_JSON="$MAIN_REPO_DIR/sample_open_dancer_backup.json"
SAMPLE_FEISCLAR="$MAIN_REPO_DIR/sample_open_dancer_backup.feisclar"

if [[ -f "$SAMPLE_JSON" ]]; then
  echo ""
  echo "📦 Uploading Sample Dancer Backup Dataset..."
  upload_release_asset "$SAMPLE_JSON" "application/json"
fi

if [[ -f "$SAMPLE_FEISCLAR" ]]; then
  upload_release_asset "$SAMPLE_FEISCLAR" "application/octet-stream"
fi

# 7. Sync Sample Backup Datasets directly to public git repository
if [[ -d "$PUBLIC_REPO_DIR/.git" ]]; then
  echo ""
  echo "📂 Syncing backup files to git repository: $PUBLIC_REPO_DIR..."
  cp "$SAMPLE_JSON" "$PUBLIC_REPO_DIR/" 2>/dev/null || true
  cp "$SAMPLE_FEISCLAR" "$PUBLIC_REPO_DIR/" 2>/dev/null || true
  (
    cd "$PUBLIC_REPO_DIR"
    git add sample_open_dancer_backup.json sample_open_dancer_backup.feisclar 2>/dev/null || true
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
      git commit -m "Update sample open dancer test backup data (Ciara Kelly - 24 feiseanna)" || true
      echo "🚀 Pushing commits to remote git repository ($REPO)..."
      git push origin main || echo "⚠️  Note: git push to origin main skipped or requires token/ssh auth."
    else
      echo "ℹ️  Git working tree clean; latest backup files are already committed."
    fi
  )
fi

echo ""
echo "=================================================="
echo "🎉 SUCCESS! All Release Assets & Git Data Updated!"
echo "=================================================="
echo "🌐 Release Page:  https://github.com/$REPO/releases/tag/$TAG"
echo "📥 APK Asset:      https://github.com/$REPO/releases/download/$TAG/$APK_NAME"
if [[ -f "$SAMPLE_JSON" ]]; then
  echo "📄 Sample JSON:    https://github.com/$REPO/releases/download/$TAG/sample_open_dancer_backup.json"
fi
echo "🕒 Completed At:   $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=================================================="
