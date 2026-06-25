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

# 2. Encryption passphrase — never stored.
$sec = Read-Host 'Encryption passphrase' -AsSecureString
$pass = [System.Net.NetworkCredential]::new('', $sec).Password
$env:RCLONE_CONFIG_R2CRYPT_PASSWORD = (rclone obscure $pass)
$pass = $null

# 3. Mirror to R2 with a timestamped backup of replaced/deleted blobs.
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
Write-Host "Pushing $claudeDir -> r2crypt:vault ..."
rclone sync $claudeDir r2crypt:vault -L --filter-from $filter --backup-dir "r2crypt:backups/$ts" --transfers 8 --progress @args
Write-Host "Done. Replaced/removed files recoverable at r2crypt:backups/$ts"
