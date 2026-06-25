#!/usr/bin/env bash
# Browse push backups in R2 and restore a file or folder from a snapshot.
# Backups are created automatically by claude-push (--backup-dir): each push that
# overwrites or deletes files keeps the previous versions under backups/<timestamp>/.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RCLONE_CONFIG="$DIR/rclone.conf"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CANARY="claude-code-sync:passphrase-ok:v1"

[ -f "$RCLONE_CONFIG" ] || { echo "No rclone.conf — run ./setup.sh first."; exit 1; }

# Passphrase, verified against the canary.
while :; do
  read -rsp "Encryption passphrase: " PASS; echo
  RCLONE_CONFIG_R2CRYPT_PASSWORD="$(rclone obscure "$PASS")"; export RCLONE_CONFIG_R2CRYPT_PASSWORD; unset PASS
  GOT="$(rclone cat r2crypt:passcheck 2>/dev/null || true)"
  [ "$GOT" = "$CANARY" ] && break
  echo "Wrong passphrase (or nothing pushed yet)."
  read -rp "Try again? [Y/n] " a; case "$a" in [Nn]*) exit 1;; esac
done

# List snapshots.
mapfile -t SNAPS < <(rclone lsf r2crypt:backups/ 2>/dev/null | sed 's:/$::' | sort)
if [ "${#SNAPS[@]}" -eq 0 ]; then
  echo "No backups yet — no push has overwritten or deleted anything."; exit 0
fi
echo; echo "Backup snapshots (newest last):"
i=1; for s in "${SNAPS[@]}"; do echo "  [$i] $s"; i=$((i+1)); done
read -rp "Snapshot number: " N
if [[ "$N" =~ ^[0-9]+$ ]]; then SNAP="${SNAPS[$((N-1))]:-}"; else SNAP=""; fi
[ -n "$SNAP" ] || { echo "Invalid selection."; exit 1; }

echo; echo "Contents of $SNAP:"; rclone tree "r2crypt:backups/$SNAP"

echo
read -rp "Path to restore (e.g. skills/foo or commands/x.md), or 'all': " REL
[ -n "$REL" ] || { echo "Nothing selected."; exit 1; }

echo "Restore where?"
echo "  [1] ./restored/$SNAP   (safe — inspect, then move it yourself)   [default]"
echo "  [2] $CLAUDE_DIR        (overwrites your current files!)"
read -rp "Choice [1/2]: " D
if [ "$D" = "2" ]; then DEST="$CLAUDE_DIR"; else DEST="$DIR/restored/$SNAP"; mkdir -p "$DEST"; fi

if [ "$REL" = "all" ]; then
  rclone copy "r2crypt:backups/$SNAP" "$DEST" --progress
else
  rclone copy "r2crypt:backups/$SNAP" "$DEST" --include "/$REL" --include "/$REL/**" --progress
fi
echo "Done -> $DEST"
[ "$D" = "2" ] || echo "Inspect it, then copy what you want into $CLAUDE_DIR."
