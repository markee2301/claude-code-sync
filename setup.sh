#!/usr/bin/env bash
# Configure rclone for claude-code-sync. Writes a gitignored rclone.conf with your R2 creds.
# Run once per machine. The Secret Access Key uses a hidden prompt and never hits git.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$DIR/rclone.conf"

command -v rclone >/dev/null || { echo "rclone not found. Install it first:"; echo "  Windows: winget install Rclone.Rclone"; echo "  macOS:   brew install rclone"; exit 1; }

echo "Cloudflare R2 details (Dashboard > R2 > Manage API Tokens)."
read -rp "Account ID: " ACCOUNT_ID
read -rp "Access Key ID: " ACCESS_KEY
read -rsp "Secret Access Key (hidden): " SECRET_KEY; echo
read -rp "Bucket name [claude-sync]: " BUCKET
BUCKET="${BUCKET:-claude-sync}"

cat > "$CONF" <<EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = $ACCESS_KEY
secret_access_key = $SECRET_KEY
endpoint = https://$ACCOUNT_ID.r2.cloudflarestorage.com
region = auto
acl = private
no_check_bucket = true

[r2crypt]
type = crypt
remote = r2:$BUCKET/claude
filename_encryption = standard
directory_name_encryption = true
EOF

echo
echo "Wrote $CONF (gitignored)."
echo "Test the bucket connection:"
echo "  RCLONE_CONFIG=\"$CONF\" rclone lsd r2:$BUCKET"
