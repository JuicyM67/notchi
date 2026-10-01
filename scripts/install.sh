#!/bin/bash
# Installerar Tamanotchi.
#  • Laddade du ner en färdig release (Tamanotchi.app ligger bredvid det här skriptet)? Då behövs inga utvecklarverktyg.
#  • Kör du från källkoden bygger skriptet först (kräver Command Line Tools: xcode-select --install).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$HERE/Tamanotchi.app" ]; then
  APP="$HERE/Tamanotchi.app"                       # färdig release
elif [ -d "$HERE/../build/Tamanotchi.app" ] && [ "${1:-}" != "--rebuild" ]; then
  APP="$HERE/../build/Tamanotchi.app"
else
  "$HERE/package.sh"
  APP="$HERE/../build/Tamanotchi.app"
fi

# Flytta över från det gamla namnet (Notchi): inställningar, användning, tidigare statusrad
if [ -d "$HOME/.notchi" ] && [ ! -d "$HOME/.tamanotchi" ]; then
  echo "▸ Flyttar dina inställningar från Notchi…"
  mv "$HOME/.notchi" "$HOME/.tamanotchi"
  rm -f "$HOME/.tamanotchi/notchi.sock"
fi
pkill -x Notchi 2>/dev/null || true
rm -rf "$HOME/Applications/Notchi.app"

echo "▸ Lägger Tamanotchi i ~/Applications…"
pkill -x Tamanotchi 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Tamanotchi.app"
cp -R "$APP" "$HOME/Applications/Tamanotchi.app"
# Nedladdade appar märks av Gatekeeper; ta bort märket och signera lokalt
xattr -dr com.apple.quarantine "$HOME/Applications/Tamanotchi.app" 2>/dev/null || true
codesign --force --deep --sign - "$HOME/Applications/Tamanotchi.app" 2>/dev/null || true

echo "▸ Installerar hooken…"
mkdir -p "$HOME/.tamanotchi/bin"
cp "$HOME/Applications/Tamanotchi.app/Contents/MacOS/tamanotchi-hook" "$HOME/.tamanotchi/bin/tamanotchi-hook"
chmod +x "$HOME/.tamanotchi/bin/tamanotchi-hook"

echo "▸ Kopplar in hooks i ~/.claude/settings.json (säkerhetskopia sparas)…"
mkdir -p "$HOME/.claude"
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.tamanotchi-backup-$(date +%Y%m%d%H%M%S)"
/usr/bin/osascript -l JavaScript "$HERE/merge-hooks.js" install "$SETTINGS" "$HOME/.tamanotchi/bin/tamanotchi-hook" "$HOME/.tamanotchi/prev-statusline.txt"

echo "▸ Startar Tamanotchi…"
open "$HOME/Applications/Tamanotchi.app"

cat <<'DONE'

✓ Klart!
  • Maskoten sitter nu i notchen. Välj karaktär via ●-ikonen i menyraden.
  • Håll ⌃⌥ Mellanslag och prata.
  • Lägg in din Anthropic API-nyckel i ~/.tamanotchi/config.json för att kunna ställa frågor
    (öppna/starta/hitta fungerar gratis utan nyckel). Starta om Tamanotchi efteråt.
  • Nya Claude Code-sessioner plockar upp hooken automatiskt.
DONE
