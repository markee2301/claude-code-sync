# Push the curated ~/.claude subset -> encrypted -> R2.
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:RCLONE_CONFIG = Join-Path $dir 'rclone.conf'
$filter = Join-Path $dir 'claude-filter.txt'
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }

if (-not (Test-Path $env:RCLONE_CONFIG)) { Write-Host 'No rclone.conf — run .\setup.ps1 first.'; exit 1 }

# 1. Snapshot local MCP servers from ~/.claude.json into the synced tree.
$claudeJson = Join-Path $HOME '.claude.json'
if ((Test-Path $claudeJson) -and (Get-Command node -ErrorAction SilentlyContinue)) {
  $env:CLAUDE_DIR = $claudeDir
  node -e 'const os=require(\"os\"),fs=require(\"fs\"),p=require(\"path\");const j=JSON.parse(fs.readFileSync(p.join(os.homedir(),\".claude.json\"),\"utf8\"));fs.writeFileSync(p.join(process.env.CLAUDE_DIR,\"mcp-servers.json\"),JSON.stringify({mcpServers:j.mcpServers||{}},null,2));console.log(\"mcp-servers.json: \"+Object.keys(j.mcpServers||{}).length+\" server(s)\");'
}

# 1b. Snapshot installed plugins + marketplaces as a path-free manifest.
$env:CLAUDE_DIR = $claudeDir
if (Get-Command node -ErrorAction SilentlyContinue) {
  node -e 'const fs=require(\"fs\"),p=require(\"path\"),d=process.env.CLAUDE_DIR;const mk=p.join(d,\"plugins\",\"known_marketplaces.json\"),ip=p.join(d,\"plugins\",\"installed_plugins.json\");const o={marketplaces:[],plugins:[]};if(fs.existsSync(mk)){for(const[n,i]of Object.entries(JSON.parse(fs.readFileSync(mk,\"utf8\")))){const r=i.source&&i.source.repo;if(r)o.marketplaces.push({name:n,repo:r});}}if(fs.existsSync(ip)){for(const k of Object.keys(JSON.parse(fs.readFileSync(ip,\"utf8\")).plugins||{})){if(!k.endsWith(\"@local\"))o.plugins.push(k);}}fs.writeFileSync(p.join(d,\"plugins-manifest.json\"),JSON.stringify(o,null,2));console.log(\"plugins-manifest.json: \"+o.marketplaces.length+\" marketplaces, \"+o.plugins.length+\" plugins\");'
}

# 2. Encryption passphrase — never stored. Entered twice to catch typos.
$sec1 = Read-Host 'Encryption passphrase' -AsSecureString
$sec2 = Read-Host 'Confirm passphrase' -AsSecureString
$p1 = [System.Net.NetworkCredential]::new('', $sec1).Password
$p2 = [System.Net.NetworkCredential]::new('', $sec2).Password
if ($p1 -ne $p2) { Write-Host "Passphrases don't match. Aborting."; exit 1 }
$env:RCLONE_CONFIG_R2CRYPT_PASSWORD = (rclone obscure $p1)
$p1 = $null; $p2 = $null

# 2b. Refresh the passphrase canary so future pulls can verify the passphrase.
'claude-code-sync:passphrase-ok:v1' | rclone rcat r2crypt:passcheck

# 3. Mirror to R2 with a timestamped backup of replaced/deleted blobs.
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
Write-Host "Pushing $claudeDir -> r2crypt:vault ..."
rclone sync $claudeDir r2crypt:vault -L --filter-from $filter --backup-dir "r2crypt:backups/$ts" --transfers 8 --progress @args
Write-Host "Done. Replaced/removed files recoverable at r2crypt:backups/$ts"
