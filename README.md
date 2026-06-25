# claude-sync

Sync your Claude Code "brain" — skills, agents, commands, plugins, MCP servers, memory,
settings — across machines through **your own Cloudflare R2**, encrypted before it leaves
your computer. No third-party server, no subscription.

It's two scripts on top of [`rclone`](https://rclone.org). rclone's `crypt` backend
encrypts every file client-side with a passphrase and uploads only what changed. R2 only
ever stores scrambled blobs (filenames included) that Cloudflare can't read. Type the same
passphrase on another machine and it decrypts.

## What you need

- [rclone](https://rclone.org/downloads/) — `winget install Rclone.Rclone` / `brew install rclone`
- A Cloudflare R2 bucket + an API token (Dashboard → R2 → Manage API Tokens)
- Node.js (already ships with Claude Code) — used for the MCP + plugin steps

## Setup (once per machine)

```bash
git clone https://github.com/markee2301/claude-code-sync.git
cd claude-code-sync
./setup.sh        # Windows PowerShell: .\setup.ps1
```

`setup` asks for your R2 Account ID, Access Key, Secret (hidden), and bucket, then writes a
**gitignored** `rclone.conf`. Your secret key and passphrase never touch git.

## Daily use

```bash
./claude-push.sh   # this machine  -> encrypt -> R2
./claude-pull.sh   # R2 -> decrypt -> this machine
```

Each prompts for your encryption passphrase (the one thing to remember — it's never
stored). Use the **same passphrase on every machine.**

## What syncs

Defined in `claude-filter.txt` — edit it to taste.

**On:** `settings.json`, `skills/`, `agents/`, `commands/`, `memory/` + `MEMORY.md`,
`plans/`, `tasks/`, the plugin manifests, and `mcp-servers.json` (your local MCP servers,
snapshotted from `~/.claude.json` on push).

**Off:** conversation history (`projects/`, `sessions/`, `history.jsonl` — large; opt in by
editing the filter), plugin *code* (`plugins/cache/` — reinstalled instead), and anything
machine-local or secret (`.credentials.json`, `settings.local.json`, caches).

Plugins are restored on `pull` by reinstalling from the synced manifest
(`claude plugin marketplace add` + `claude plugin install`), so their hardcoded install
paths don't have to be portable. Login/auth is not synced — run `/login` on the new machine.

## How push and pull differ (important)

- **push = mirror.** R2 is made to match this machine. Deleting a synced file locally and
  pushing removes it from R2 too. So **push from the machine that's up to date.** Replaced
  and deleted blobs are kept under `backups/<timestamp>/` in R2, so a bad push is
  recoverable.
- **pull = additive.** Brings R2 down without deleting anything local (uses `copy`).

Rule of thumb: **pull before you work, push when you're done.**

## Security

- Encryption happens locally (rclone `crypt`); R2 stores only encrypted blobs.
- The passphrase is never written to disk or uploaded. Lose it = no recovery, by design.
- `rclone.conf` (your R2 keys) is gitignored. Anyone with it can reach your bucket, but the
  contents stay encrypted by your passphrase. Treat it like a password.

## Other storage

Configured for Cloudflare R2. rclone also speaks AWS S3, Backblaze B2, etc. — edit the
`[r2]` remote in `rclone.conf` for another provider; the `crypt` layer stays the same.
