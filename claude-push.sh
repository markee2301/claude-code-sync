#!/usr/bin/env bash
# Push the curated ~/.claude subset -> encrypted -> R2.
# Usage: ./claude-push.sh [extra rclone args]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RCLONE_CONFIG="$DIR/rclone.conf"
FILTER="$DIR/claude-filter.txt"
export CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

[ -f "$RCLONE_CONFIG" ] || { echo "No rclone.conf — run ./setup.sh first."; exit 1; }

# 1. Snapshot local MCP servers from ~/.claude.json into the synced tree.
if [ -f "$HOME/.claude.json" ] && command -v node >/dev/null; then
  node -e 'const os=require("os"),fs=require("fs"),p=require("path");
    const j=JSON.parse(fs.readFileSync(p.join(os.homedir(),".claude.json"),"utf8"));
    const out=p.join(process.env.CLAUDE_DIR,"mcp-servers.json");
    fs.writeFileSync(out,JSON.stringify({mcpServers:j.mcpServers||{}},null,2));
    console.log("mcp-servers.json: "+Object.keys(j.mcpServers||{}).length+" server(s)");'
fi

# 2. Encryption passphrase — never stored, prompted each run.
read -rsp "Encryption passphrase: " PASS; echo
RCLONE_CONFIG_R2CRYPT_PASSWORD="$(rclone obscure "$PASS")"; export RCLONE_CONFIG_R2CRYPT_PASSWORD
unset PASS

# 3. Mirror to R2. Replaced/deleted blobs are kept under backups/<timestamp>, not destroyed.
TS="$(date +%Y%m%d-%H%M%S)"
echo "Pushing $CLAUDE_DIR -> r2crypt:vault ..."
rclone sync "$CLAUDE_DIR" r2crypt:vault \
  -L --filter-from "$FILTER" \
  --backup-dir "r2crypt:backups/$TS" \
  --transfers 8 --progress "$@"
echo "Done. Any replaced/removed files are recoverable at r2crypt:backups/$TS"
