# Configure rclone for claude-code-sync. Writes a gitignored rclone.conf with your R2 creds.
# Run once per machine. The Secret Access Key is read as a SecureString and never hits git.
$ErrorActionPreference = 'Stop'
$dir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$conf = Join-Path $dir 'rclone.conf'

if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
  Write-Host 'rclone not found. Install it: winget install Rclone.Rclone'
  exit 1
}

Write-Host 'Cloudflare R2 details (Dashboard > R2 > Manage API Tokens).'
$accountId = Read-Host 'Account ID'
$accessKey = Read-Host 'Access Key ID'
$sec       = Read-Host 'Secret Access Key' -AsSecureString
$secretKey = [System.Net.NetworkCredential]::new('', $sec).Password
$bucket    = Read-Host 'Bucket name [claude-sync]'
if ([string]::IsNullOrWhiteSpace($bucket)) { $bucket = 'claude-sync' }

@"
[r2]
type = s3
provider = Cloudflare
access_key_id = $accessKey
secret_access_key = $secretKey
endpoint = https://$accountId.r2.cloudflarestorage.com
region = auto
acl = private
no_check_bucket = true

[r2crypt]
type = crypt
remote = r2:$bucket/claude
filename_encryption = standard
directory_name_encryption = true
"@ | Out-File -FilePath $conf -Encoding utf8

Write-Host ''
Write-Host "Wrote $conf (gitignored)."
Write-Host "Test: `$env:RCLONE_CONFIG='$conf'; rclone lsd r2:$bucket"
