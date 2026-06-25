# Pull the encrypted ~/.claude subset from R2, then restore MCP servers + plugins.
# Non-destructive: uses `copy`, so it never deletes local files (only adds/updates).
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:RCLONE_CONFIG = Join-Path $dir 'rclone.conf'
$filter = Join-Path $dir 'claude-filter.txt'
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$env:CLAUDE_DIR = $claudeDir
New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null

if (-not (Test-Path $env:RCLONE_CONFIG)) { Write-Host 'No rclone.conf — run .\setup.ps1 first.'; exit 1 }

$sec = Read-Host 'Encryption passphrase' -AsSecureString
$pass = [System.Net.NetworkCredential]::new('', $sec).Password
$env:RCLONE_CONFIG_R2CRYPT_PASSWORD = (rclone obscure $pass)
$pass = $null

Write-Host "Pulling r2crypt:vault -> $claudeDir ..."
rclone copy r2crypt:vault $claudeDir -L --filter-from $filter --transfers 8 --progress

# Merge MCP servers into ~/.claude.json.
$mcp = Join-Path $claudeDir 'mcp-servers.json'
if ((Test-Path $mcp) -and (Get-Command node -ErrorAction SilentlyContinue)) {
  node -e 'const os=require(\"os\"),fs=require(\"fs\"),p=require(\"path\");const cj=p.join(os.homedir(),\".claude.json\");const base=fs.existsSync(cj)?JSON.parse(fs.readFileSync(cj,\"utf8\")):{};const add=(JSON.parse(fs.readFileSync(p.join(process.env.CLAUDE_DIR,\"mcp-servers.json\"),\"utf8\")).mcpServers)||{};base.mcpServers=Object.assign(base.mcpServers||{},add);fs.writeFileSync(cj,JSON.stringify(base,null,2));console.log(\"Merged MCP server(s): \"+Object.keys(add).join(\", \"));'
}

# Restore marketplaces + plugins from the path-free manifest.
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "NOTE: 'claude' not on PATH — skipping plugin restore. Re-run this script once Claude Code's CLI is available."
} elseif (Test-Path (Join-Path $claudeDir 'plugins-manifest.json')) {
  Write-Host 'Restoring marketplaces + plugins ...'
  $cmds = node -e 'const fs=require(\"fs\"),p=require(\"path\");const m=JSON.parse(fs.readFileSync(p.join(process.env.CLAUDE_DIR,\"plugins-manifest.json\"),\"utf8\"));const o=[];for(const mk of m.marketplaces)o.push(\"claude plugin marketplace add \"+mk.repo);for(const pl of m.plugins)o.push(\"claude plugin install \"+pl);process.stdout.write(o.join(\"\n\"));'
  foreach ($cmd in ($cmds -split \"`n\")) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
    Write-Host "+ $cmd"
    try { Invoke-Expression $cmd } catch { Write-Host '  (skipped - may already exist)' }
  }
}

Write-Host ''
Write-Host 'Almost done. Final manual steps:'
Write-Host '  1. Launch claude and run /login (auth is intentionally not synced).'
Write-Host '  2. Reconnect claude.ai connectors in the app if you use them.'
Write-Host '  3. Restart Claude Code so restored plugins load.'
