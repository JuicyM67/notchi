#!/bin/bash
# Installerar Notchi.
#  • Laddade du ner en färdig release (Notchi.app ligger bredvid det här skriptet)? Då behövs inga utvecklarverktyg.
#  • Kör du från källkoden bygger skriptet först (kräver Command Line Tools: xcode-select --install).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$HERE/Notchi.app" ]; then
  APP="$HERE/Notchi.app"                       # färdig release
elif [ -d "$HERE/../build/Notchi.app" ] && [ "${1:-}" != "--rebuild" ]; then
  APP="$HERE/../build/Notchi.app"
else
  "$HERE/package.sh"
  APP="$HERE/../build/Notchi.app"
fi

echo "▸ Lägger Notchi i ~/Applications…"
pkill -x Notchi 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Notchi.app"
cp -R "$APP" "$HOME/Applications/Notchi.app"
# Nedladdade appar märks av Gatekeeper; ta bort märket och signera lokalt
xattr -dr com.apple.quarantine "$HOME/Applications/Notchi.app" 2>/dev/null || true
codesign --force --deep --sign - "$HOME/Applications/Notchi.app" 2>/dev/null || true

echo "▸ Installerar hooken…"
mkdir -p "$HOME/.notchi/bin"
cp "$HOME/Applications/Notchi.app/Contents/MacOS/notchi-hook" "$HOME/.notchi/bin/notchi-hook"
chmod +x "$HOME/.notchi/bin/notchi-hook"

echo "▸ Kopplar in hooks i ~/.claude/settings.json (säkerhetskopia sparas)…"
mkdir -p "$HOME/.claude"
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.notchi-backup-$(date +%Y%m%d%H%M%S)"
/usr/bin/osascript -l JavaScript "$HERE/merge-hooks.js" install "$SETTINGS" "$HOME/.notchi/bin/notchi-hook"

echo "▸ Startar Notchi…"
open "$HOME/Applications/Notchi.app"

cat <<'DONE'

✓ Klart!
  • Maskoten sitter nu i notchen. Välj karaktär via ●-ikonen i menyraden.
  • Håll ⌃⌥ Mellanslag och prata.
  • Lägg in din Anthropic API-nyckel i ~/.notchi/config.json för att kunna ställa frågor
    (öppna/starta/hitta fungerar gratis utan nyckel). Starta om Notchi efteråt.
  • Nya Claude Code-sessioner plockar upp hooken automatiskt.
DONE
