# claude-code-sync

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

## Create your R2 bucket

You store everything in your own Cloudflare R2 (free tier is plenty — the synced config is
only a few MB).

1. Go to **Cloudflare Dashboard → R2 Object Storage** (enable R2 the first time).
2. Click **Create bucket** → name it `claude-sync`.
3. Go to **Manage R2 API Tokens → Create API Token**.
4. Select **Object Read & Write** permission → **Create**.
5. Copy the values you'll paste into `setup`: **Account ID**, **Access Key ID**, and
   **Secret Access Key** (the secret is shown only once).

## Setup & daily use

Clone it once on each machine:

```bash
git clone https://github.com/markee2301/claude-code-sync.git
cd claude-code-sync
```

> **Run the scripts with `bash` (macOS/Linux/Git Bash) or the `.ps1` via `-File`
> (Windows PowerShell).** Don't double-click them or type `./script.sh` in PowerShell —
> Windows tries to *open* the file (app picker / text editor) instead of running it.

### macOS / Linux  (Terminal — bash or zsh)

```bash
bash setup.sh         # one-time: enter R2 Account ID, Access Key, Secret (hidden), bucket
bash claude-push.sh   # this machine  -> encrypt -> R2
bash claude-pull.sh   # R2 -> decrypt -> this machine
```

### Windows  (PowerShell)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-push.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-pull.ps1
```

### Windows  (Git Bash — simplest, same as macOS)

```bash
bash setup.sh
bash claude-push.sh
bash claude-pull.sh
```

`setup` writes a **gitignored** `rclone.conf` — your secret key and passphrase never touch
git. `push` and `pull` each prompt for your encryption passphrase (the one thing to
remember — never stored). **Use the same passphrase on every machine.**

`push` asks for the passphrase **twice** (typo guard) and writes a small encrypted
**canary** file. `pull` decrypts that canary *before* downloading anything, so a wrong
passphrase is caught immediately and re-prompted instead of pulling undecryptable data.

> ### 👉 Rule of thumb: **pull before you start working, push when you're done.**
> `push` mirrors your machine to R2 (so push from whichever machine is up to date); `pull`
> brings changes down. Following this order keeps every machine current and avoids
> overwriting newer work. See [How push and pull differ](#how-push-and-pull-differ-important)
> for the details and the built-in backup safety net.

## What syncs (and what doesn't)

Everything is decided by `claude-filter.txt` — edit it to change these defaults.

### Synced ✅

| Path (under `~/.claude`) | What it is |
|---|---|
| `settings.json` | Shared settings: enabled plugins, statusline, marketplaces |
| `CLAUDE.md` | Global instructions (if you keep one) |
| `MEMORY.md` + `memory/` | Saved memory and its index |
| `skills/` | Your custom skills (symlinked skills are dereferenced into real files) |
| `agents/` | Your custom subagents |
| `commands/` | Your custom slash commands |
| `rules/` | Custom rules (if present) |
| `workflows/` | Custom workflows (if present) |
| `plans/` | Plan-mode plans |
| `tasks/` | Task-tracking state |
| `plugins-manifest.json` | Path-free list of your plugins + marketplaces, generated on push |
| `mcp-servers.json` | Your local MCP servers, snapshotted from `~/.claude.json` on push |

### Not synced ❌

| Path | Why not |
|---|---|
| `plugins/` (whole dir) | `installed_plugins.json` / `known_marketplaces.json` store **absolute OS-specific install paths**, and `cache/` holds thousands of arch-specific files (node_modules, venvs). Plugins are **reinstalled** from `plugins-manifest.json` instead. |
| `projects/` | Conversation history. Large, and folders are keyed to absolute project paths that differ per machine (so they wouldn't resume cleanly anyway). **Off by default.** |
| `sessions/` | Live session/runtime state — machine-local. |
| `history.jsonl` | Prompt-input history. **Off by default** (flip on if you want it). |
| `.credentials.json` | Your auth token — a secret. Run `/login` on each machine instead. |
| `settings.local.json` | Per-machine settings/permissions (that's the file's whole purpose). |
| `shell-snapshots/`, `ide/`, `file-history/` | Machine/OS-specific runtime state (e.g. Windows shell snapshots). |
| `cache/`, `image-cache/`, `paste-cache/`, `downloads/`, `backups/`, `*.log` | Regenerated caches and local noise. |

> **Want conversation history too?** In `claude-filter.txt`, change `- /projects/**` and
> `- /history.jsonl` to `+`. Note: those transcripts are keyed to absolute paths, so they
> won't auto-resume on a machine with a different home dir or OS (see *Limitations* below).

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

## Backups & recovery

Every `push` runs with `--backup-dir`, so the mirror can't lose data silently:

```bash
rclone sync ~/.claude r2crypt:vault --backup-dir r2crypt:backups/<timestamp>
```

Before overwriting a changed file or deleting one that's gone locally, rclone **moves the
old version into `backups/<timestamp>/`** instead of destroying it. Each push that changes
something creates one timestamped folder containing *only the files it replaced or removed*
(a delta, not a full snapshot). Pushes that add only new files create no backup. Backups are
encrypted like everything else.

**Do I need to do anything? Almost never.** Backups are insurance you can ignore until you
actually notice something *lost or reverted* — a skill, command, agent, or memory file that
you know you had is suddenly missing or back to an older version. That has one cause: a
`push` from a machine that **wasn't up to date** overwrote the newer state in R2 (exactly
what the *pull-before-work* rule prevents). Two ways you'd catch it:

- The push output reports it **deleted** files you didn't expect (e.g. `Deleted: 12`).
- After a pull, something you rely on is gone or stale.

The `"…recoverable at backups/…"` line printed on every push is informational, not an alert
— ignore it unless you've actually lost something.

### Restoring a file

From your `claude-code-sync` folder:

```bash
export RCLONE_CONFIG="$PWD/rclone.conf"
read -rsp "passphrase: " P; export RCLONE_CONFIG_R2CRYPT_PASSWORD=$(rclone obscure "$P"); unset P; echo

rclone lsf  r2crypt:backups/                       # list snapshots (one per changed push)
rclone tree r2crypt:backups/<timestamp>            # see what's inside one
rclone copy "r2crypt:backups/<timestamp>/skills/foo/SKILL.md" ./restored/   # pull a file back
```

Copy the recovered file into `~/.claude/` to roll it back. There's no "restore everything to
date X" command — backups are deltas, so recovery is a deliberate cherry-pick.

Backups accumulate (one folder per changed push). To prune old ones:

```bash
rclone purge r2crypt:backups/<old-timestamp>
```

## Limitations

- **Conversation history doesn't auto-resume across machines.** Claude indexes sessions by
  absolute project path (`~/.claude/projects/-Users-alice-my-app/`). A different username,
  home dir, or OS produces a different key, so `claude --resume` on machine B won't find
  machine A's threads even if you sync `projects/`. Settings, skills, agents, commands,
  memory, and plugins are all path-independent and sync fine — this caveat is *only* about
  resuming old conversations. (A future version could rewrite paths to a portable token on
  sync; not implemented yet.)

## Security

- Encryption happens locally (rclone `crypt`); R2 stores only encrypted blobs.
- The passphrase is never written to disk or uploaded. Lose it = no recovery, by design.
- `rclone.conf` (your R2 keys) is gitignored. Anyone with it can reach your bucket, but the
  contents stay encrypted by your passphrase. Treat it like a password.

## Other storage

Configured for Cloudflare R2. rclone also speaks AWS S3, Backblaze B2, etc. — edit the
`[r2]` remote in `rclone.conf` for another provider; the `crypt` layer stays the same.
