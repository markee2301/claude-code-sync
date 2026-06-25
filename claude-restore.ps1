# Browse push backups in R2 and restore a file or folder from a snapshot.
# Backups are created automatically by claude-push (--backup-dir).
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:RCLONE_CONFIG = Join-Path $dir 'rclone.conf'
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$CANARY = 'claude-code-sync:passphrase-ok:v1'

if (-not (Test-Path $env:RCLONE_CONFIG)) { Write-Host 'No rclone.conf — run .\setup.ps1 first.'; exit 1 }

while ($true) {
  $sec = Read-Host 'Encryption passphrase' -AsSecureString
  $pass = [System.Net.NetworkCredential]::new('', $sec).Password
  $env:RCLONE_CONFIG_R2CRYPT_PASSWORD = (rclone obscure $pass); $pass = $null
  $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
  $got = (rclone cat r2crypt:passcheck 2>$null | Out-String).Trim()
  $ErrorActionPreference = $prevEAP
  if ($got -eq $CANARY) { break }
  $a = Read-Host 'Wrong passphrase (or nothing pushed yet). Try again? [Y/n]'
  if ($a -match '^[Nn]') { exit 1 }
}

$snaps = @(rclone lsf r2crypt:backups/ 2>$null | ForEach-Object { $_.TrimEnd('/') } | Sort-Object)
if ($snaps.Count -eq 0) { Write-Host 'No backups yet — no push has overwritten or deleted anything.'; exit 0 }

Write-Host "`nBackup snapshots (newest last):"
for ($i = 0; $i -lt $snaps.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $snaps[$i]) }
$n = Read-Host 'Snapshot number'
$idx = 0
if (-not [int]::TryParse($n, [ref]$idx) -or $idx -lt 1 -or $idx -gt $snaps.Count) { Write-Host 'Invalid selection.'; exit 1 }
$snap = $snaps[$idx - 1]

Write-Host "`nContents of ${snap}:"; rclone tree "r2crypt:backups/$snap"

$rel = Read-Host "`nPath to restore (e.g. skills/foo or commands/x.md), or 'all'"
if ([string]::IsNullOrWhiteSpace($rel)) { Write-Host 'Nothing selected.'; exit 1 }

Write-Host 'Restore where?'
Write-Host "  [1] .\restored\$snap   (safe - inspect, then move it yourself)   [default]"
Write-Host "  [2] $claudeDir        (overwrites your current files!)"
$d = Read-Host 'Choice [1/2]'
if ($d -eq '2') { $dest = $claudeDir } else { $dest = Join-Path (Join-Path $dir 'restored') $snap; New-Item -ItemType Directory -Force -Path $dest | Out-Null }

if ($rel -eq 'all') {
  rclone copy "r2crypt:backups/$snap" $dest --progress
} else {
  rclone copy "r2crypt:backups/$snap" $dest --include "/$rel" --include "/$rel/**" --progress
}
Write-Host "Done -> $dest"
if ($d -ne '2') { Write-Host "Inspect it, then copy what you want into $claudeDir." }
