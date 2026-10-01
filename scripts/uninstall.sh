#!/bin/bash
# Tar bort Notchi: hooks, app och inställningar.
set -euo pipefail
cd "$(dirname "$0")"
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.notchi-backup-$(date +%Y%m%d%H%M%S)"
  /usr/bin/osascript -l JavaScript merge-hooks.js uninstall "$SETTINGS" "" "$HOME/.notchi/prev-statusline.txt"
fi
pkill -x Notchi 2>/dev/null || true
rm -rf "$HOME/Applications/Notchi.app"
# Tar du bort även ~/.notchi försvinner dina inställningar och API-nycklar:
read -r -p "Ta bort ~/.notchi (inställningar)? [j/N] " svar
[[ "$svar" =~ ^[jJ]$ ]] && rm -rf "$HOME/.notchi"
echo "✓ Notchi är borttagen."
