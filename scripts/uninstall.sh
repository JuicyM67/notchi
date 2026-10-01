#!/bin/bash
# Tar bort Tamanotchi: hooks, app och inställningar.
set -euo pipefail
cd "$(dirname "$0")"
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.tamanotchi-backup-$(date +%Y%m%d%H%M%S)"
  /usr/bin/osascript -l JavaScript merge-hooks.js uninstall "$SETTINGS" "" "$HOME/.tamanotchi/prev-statusline.txt"
fi
pkill -x Tamanotchi 2>/dev/null || true
rm -rf "$HOME/Applications/Tamanotchi.app"
# Tar du bort även ~/.tamanotchi försvinner dina inställningar och API-nycklar:
read -r -p "Ta bort ~/.tamanotchi (inställningar)? [j/N] " svar
[[ "$svar" =~ ^[jJ]$ ]] && rm -rf "$HOME/.tamanotchi"
echo "✓ Tamanotchi är borttagen."
