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

# 1b. Snapshot installed plugins + marketplaces as a path-free manifest.
#     (The raw plugins/*.json carry absolute OS-specific paths — we never sync those.)
if command -v node >/dev/null; then
  node -e 'const fs=require("fs"),p=require("path"),d=process.env.CLAUDE_DIR;
    const mk=p.join(d,"plugins","known_marketplaces.json"),ip=p.join(d,"plugins","installed_plugins.json");
    const o={marketplaces:[],plugins:[]};
    if(fs.existsSync(mk)){for(const[n,i]of Object.entries(JSON.parse(fs.readFileSync(mk,"utf8")))){const r=i.source&&i.source.repo;if(r)o.marketplaces.push({name:n,repo:r});}}
    if(fs.existsSync(ip)){for(const k of Object.keys(JSON.parse(fs.readFileSync(ip,"utf8")).plugins||{})){if(!k.endsWith("@local"))o.plugins.push(k);}}
    fs.writeFileSync(p.join(d,"plugins-manifest.json"),JSON.stringify(o,null,2));
    console.log("plugins-manifest.json: "+o.marketplaces.length+" marketplaces, "+o.plugins.length+" plugins");'
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
