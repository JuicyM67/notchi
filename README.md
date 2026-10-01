<p align="center">
  <img src="brand/notchi-lockup.png" alt="Notchi" width="420"><br>
  <b>Din lilla kollega i notchen.</b>
</p>

En liten maskot som bor i MacBookens notch, håller koll på Claude Code, låter dig godkänna
saker med ett klick eller med rösten, pratar med dig och kan öppna mappar, hitta filer och
starta program.

Varumärke, färger, typsnitt och tonalitet: se [BRAND.md](BRAND.md).

## Installera (inga utvecklarverktyg behövs)

1. Gå till **Releases** i repot och ladda ner `Notchi-macOS.zip` från *Senaste bygget*.
2. Dubbelklicka på zip-filen så att mappen `Notchi` packas upp.
3. Öppna Terminal, dra in `install.sh` från mappen och tryck Enter.

GitHub bygger appen automatiskt på en Mac i molnet varje gång koden ändras.

Skriptet lägger appen i `~/Applications`, installerar hooken i `~/.notchi/bin`
och kopplar in den i `~/.claude/settings.json` (en säkerhetskopia sparas bredvid).
Dina befintliga hooks lämnas orörda.

### Bygga själv

Har du Command Line Tools (`xcode-select --install`) kan du bygga från källkoden:

```bash
./scripts/install.sh --rebuild
```

Första gången frågar macOS om mikrofon och taligenkänning – svara ja.

## Så använder du den

| Vad | Hur |
|---|---|
| Se vad Claude Code gör | Titta på maskoten, eller hovra över notchen |
| Godkänna/neka | Klicka **Tillåt/Neka** i notchen, eller håll ⌃⌥ Mellanslag och säg "ja"/"nej" |
| Skicka tillbaka till terminalen | Klicka **Terminal** |
| Prata | Håll **⌃⌥ Mellanslag**, prata, släpp |
| Byta karaktär | ●-ikonen i menyraden → välj Pim, Oda, Bo eller Kix |
| Väcka med rösten | Slå på *Lyssna efter ”Hej Notchi”* i menyn (av som standard, mikrofonen är då alltid på). Säg sedan ”Hej Notchi, vad gör Claude?” |
| Styra datorn | ”Spela musik”, ”pausa”, ”nästa låt”, ”öppna Spotify och spela musik” (lokalt, direkt). Allt annat, t.ex. ”öppna VS Code och skapa en mapp här som heter kundportal”, utför Claude Code med ditt abonnemang – ingen API-nyckel |
| Välja hur händelser hörs | Menyn → *När något händer*: Systemljud (standard), Röst eller Tyst |
| Hoppa till en session | Klicka på sessionen i utfälld vy: rätt app öppnas, i VS Code rätt projektfönster |
| Höra läget | Klicka på maskoten eller notchen; klicka igen för att tysta |
| Låsa öppen / fälla ihop | Nålen respektive ⌃-knappen uppe till höger i utfälld vy |
| Se användning | Mätarna 5 tim och Vecka i utfälld vy, ringen runt statuspricken, eller fråga "hur mycket har jag kvar?" |

Exempel på vad du kan säga:

- "Öppna hämtade filer" · "Öppna mappen kundprojekt"
- "Starta Spotify" · "Öppna Safari"
- "Hitta filen offert" · "Var ligger budget 2026"
- "Kör genvägen Fokusläge"
- "Vad gör Claude?" / "Hur går det?"
- "Vad är skillnaden på SwiftUI och AppKit?" (går till Claude)
- "Vad säger SMHI om vädret i Borås i morgon?" (Claude + webbsökning)
- "Fråga Claude Code vad den senaste commiten gjorde" (körs i ditt senaste projekt)

## Gänget och humöret

Varje Claude Code-session får en egen karaktär: din valda först, sedan resten av gänget.
Notchen visar den som är viktigast just nu (den som väntar på dig, annars den som jobbar).

Humöret följer dagen:

| Humör | När | Syns som |
|---|---|---|
| Sömnig | före 08 och efter 23 | tunga ögonlock, gäspar, små zzz |
| Stolt | fyra klara uppgifter på 90 minuter | gnistor runt huvudet, stort leende |
| Stressad | 90 % av 5-timmarsgränsen eller 95 % av veckan | svettdroppe, rör sig fortare |

Notchi säger också till vid 80 % och 100 % av 5-timmarsgränsen (och 90/100 % av veckan),
en gång per period.

## Kostnad – så hålls den nere

Allt är inställt för att kosta så lite som möjligt:

| Del | Standardval | Kostnad |
|---|---|---|
| Röst | macOS talsyntes | **0 kr** |
| Taligenkänning | Apple, på enheten när det stöds | **0 kr** |
| Öppna/starta/hitta/godkänna/status | Tolkas lokalt, inget API-anrop | **0 kr** |
| Uppläsning av händelser | Färdiga fraser, ingen AI | **0 kr** |
| Frågor | Claude Haiku 4.5, max 350 tokens svar, kort historik | ören per fråga |
| Webbsökning | Max 1 sökning per fråga | liten extra avgift per sökning |
| "Fråga Claude Code" | `claude -p` med ditt vanliga Claude-abonnemang | inga API-krediter |

Tips för ännu lägre kostnad:
- Sätt `"webSearch": false` i config om du inte behöver aktuell info.
- Sänk `"historyTurns"` till 2.
- Ladda ner en bättre gratisröst: *Systeminställningar → Hjälpmedel → Talat innehåll →
  Systemröst → Hantera röster → Svenska* (t.ex. Alva, Premium/Förbättrad). Notchi väljer
  automatiskt den bästa svenska rösten som finns.

## Inställningar (`~/.notchi/config.json`)

```json
{
  "anthropicApiKey": "sk-ant-…",
  "model": "claude-haiku-4-5-20251001",
  "maxTokens": 350,
  "webSearch": true,
  "webSearchMaxUses": 1,
  "historyTurns": 6,
  "voice": "system",
  "speechRate": 0.52,
  "elevenLabsApiKey": null,
  "elevenLabsVoiceId": null,
  "elevenLabsModel": "eleven_flash_v2_5",
  "skin": "pim",
  "speakEvents": true,
  "voiceApprovals": true,
  "language": "sv-SE"
}
```

Du kan också låta bli att skriva nyckeln i filen och sätta `ANTHROPIC_API_KEY` i miljön.
Filen skyddas så att bara ditt användarkonto kan läsa den. Starta om Notchi efter ändringar.

Vill du ha en riktigt snygg röst senare: sätt `"voice": "elevenlabs"` plus nyckel och röst-id.
Om ElevenLabs inte svarar faller Notchi tillbaka på gratisrösten.

## Säkerhet

- Socketen `~/.notchi/notchi.sock` kan bara användas av ditt konto.
- Röstgodkännande fungerar bara för ofarliga saker. Kommandon med t.ex. `rm`, `sudo`,
  `git push`, `curl … | sh` kräver alltid ett klick.
- Om Notchi inte är igång gör hooken ingenting och Claude Code frågar som vanligt i terminalen.
- Svarar du inte inom ~10 minuter går frågan tillbaka till terminalen.

## Hur det hänger ihop

```
Claude Code ──hook (stdin JSON)──▶ notchi-hook ──Unix-socket──▶ Notchi.app
                                        ▲                          │
                 Tillåt/Neka (stdout) ◀─┘◀────── svar (bara vid ────┘
                                                 PermissionRequest)

Du (⌃⌥ Mellanslag) ─▶ Taligenkänning ─▶ Lokal tolk ─┬─▶ öppna/starta/hitta/godkänn (gratis)
                                                     └─▶ Claude API (Haiku + verktyg + webbsök)
                                                             │
                                          Talsyntes ◀────────┘  ─▶ maskotens mun rör sig
```

| Fil | Innehåll |
|---|---|
| `Sources/Notchi/NotchiApp.swift` | Start, meny, snabbtangent, kopplar ihop allt |
| `Sources/Notchi/NotchWindow.swift` | Fönstret runt notchen, utfälld vy, knappar |
| `Sources/Notchi/Mascot.swift` | De fyra karaktärerna + animation per tillstånd |
| `Sources/Notchi/SessionStore.swift` | Tillstånd, sessioner, godkännanden, färdiga fraser |
| `Sources/Notchi/HookServer.swift` | Socket-servern och hook-händelser |
| `Sources/Notchi/IntentRouter.swift` | Lokal tolkning av svenska kommandon |
| `Sources/Notchi/LocalTools.swift` | Öppna mapp, hitta fil (Spotlight), starta app, Genvägar, Claude Code |
| `Sources/Notchi/Brain.swift` | Claude API med verktyg och webbsökning |
| `Sources/Notchi/Speaker.swift` | Röster: macOS (gratis) och ElevenLabs |
| `Sources/Notchi/Listener.swift` | Tryck-och-håll-taligenkänning |
| `Sources/NotchiHook/main.swift` | Hooken som Claude Code kör |
| `scripts/package.sh` | Bygger `build/Notchi.app` |
| `scripts/install.sh` | Installerar (färdig release eller egen build) |
| `.github/workflows/build.yml` | Molnbygget som skapar releasen |
| `brand/` | Logotyp, symbol, appikon |

## Nästa steg (förslag)

- Läs om `config.json` automatiskt när den ändras.
- Spara API-nycklar i Nyckelhanden (Keychain) i stället för i filen.
- "Hej Notchi"-väckningsord (kräver alltid-på-lyssning; kan göras lokalt med Apples taligenkänning).
- Klicka på en session för att hoppa till rätt terminalflik.
- Bygga egna genvägar i Genvägar-appen för allt du vill att Notchi ska kunna göra.

## Uppdatera

```bash
cd /tmp && curl -fsSL --retry 3 https://github.com/JuicyM67/notchi/releases/download/latest/Notchi-macOS.zip -o n.zip && rm -rf Notchi && unzip -q n.zip && bash Notchi/install.sh
```

## Avinstallera

```bash
./scripts/uninstall.sh
```
