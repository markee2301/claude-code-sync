#!/usr/bin/env bash
# Pull the encrypted ~/.claude subset from R2, then restore MCP servers + plugins.
# Non-destructive: uses `copy`, so it never deletes local files (only adds/updates).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RCLONE_CONFIG="$DIR/rclone.conf"
FILTER="$DIR/claude-filter.txt"
export CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mkdir -p "$CLAUDE_DIR"

[ -f "$RCLONE_CONFIG" ] || { echo "No rclone.conf — run ./setup.sh first."; exit 1; }

# 1. Passphrase (same one used on push).
read -rsp "Encryption passphrase: " PASS; echo
RCLONE_CONFIG_R2CRYPT_PASSWORD="$(rclone obscure "$PASS")"; export RCLONE_CONFIG_R2CRYPT_PASSWORD
unset PASS

echo "Pulling r2crypt:vault -> $CLAUDE_DIR ..."
rclone copy r2crypt:vault "$CLAUDE_DIR" -L --filter-from "$FILTER" --transfers 8 --progress

# 2. Merge synced MCP servers into ~/.claude.json (preserves existing entries).
if [ -f "$CLAUDE_DIR/mcp-servers.json" ] && command -v node >/dev/null; then
  node -e 'const os=require("os"),fs=require("fs"),p=require("path");
    const cj=p.join(os.homedir(),".claude.json");
    const base=fs.existsSync(cj)?JSON.parse(fs.readFileSync(cj,"utf8")):{};
    const add=(JSON.parse(fs.readFileSync(p.join(process.env.CLAUDE_DIR,"mcp-servers.json"),"utf8")).mcpServers)||{};
    base.mcpServers=Object.assign(base.mcpServers||{},add);
    fs.writeFileSync(cj,JSON.stringify(base,null,2));
    const n=Object.keys(add);console.log("Merged MCP server(s): "+(n.length?n.join(", "):"none"));'
fi

# 3. Restore marketplaces + plugins from the synced manifest (best-effort, skips @local).
if command -v claude >/dev/null && [ -f "$CLAUDE_DIR/plugins/known_marketplaces.json" ]; then
  echo "Restoring marketplaces + plugins ..."
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    echo "+ $cmd"
    eval "$cmd" || echo "  (skipped — may already exist)"
  done < <(node -e 'const fs=require("fs"),p=require("path");const b=process.env.CLAUDE_DIR;
    const mk=JSON.parse(fs.readFileSync(p.join(b,"plugins","known_marketplaces.json"),"utf8"));
    const ip=JSON.parse(fs.readFileSync(p.join(b,"plugins","installed_plugins.json"),"utf8"));
    const o=[];for(const m of Object.values(mk)){const r=m.source&&m.source.repo;if(r)o.push("claude plugin marketplace add "+r);}
    for(const k of Object.keys(ip.plugins||{})){if(k.endsWith("@local"))continue;o.push("claude plugin install "+k);}
    process.stdout.write(o.join("\n"));')
fi

echo
echo "Almost done. Final manual steps:"
echo "  1. Launch 'claude' and run /login (auth is intentionally not synced)."
echo "  2. Reconnect claude.ai connectors (Figma, Gmail, Drive, ...) in the app if you use them."
echo "  3. Restart Claude Code so restored plugins load."
