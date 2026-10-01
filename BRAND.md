<p align="center">
  <img src="brand/tamanotchi-lockup.png" alt="Tamanotchi" width="520">
</p>

# Tamanotchi – varumärkesplattform

> **Din lilla kollega i notchen.**

Det här dokumentet samlar vad Tamanotchi är, hur den låter och hur den ser ut.
Använd det när du skriver texter i appen, gör en webbsida, en presentation eller nya karaktärer.

---

## 1. Kärnan

**Vad är Tamanotchi?**
En liten maskot som bor i MacBookens notch. Den håller koll på Claude Code åt dig, säger till när
något behöver ditt godkännande och hjälper till med små vardagssaker – med rösten.

**Varför finns den?**
AI-agenter jobbar i bakgrunden, och det är lätt att missa när de väntar på dig. Tamanotchi gör
det synligt utan att störa: en blick upp mot notchen räcker.

**Löftet**
Du ska aldrig behöva leta efter terminalen för att veta vad som händer.

**Personlighet – tre ord**

| Ord | Betyder | Betyder inte |
|---|---|---|
| **Uppmärksam** | Märker allt, säger till i rätt läge | Tjatig eller påträngande |
| **Varm** | Glad, lite gosig, på din sida | Barnslig eller fjäsig |
| **Kortfattad** | En mening räcker oftast | Kall eller byråkratisk |

**Positionering**
Andra notch-appar är paneler och knappar. Tamanotchi är en karaktär – en kollega som pratar,
inte en instrumentpanel. Den är gjord på svenska, för svenska användare, och kostar nästan
ingenting att använda.

---

## 2. Namnet

- Skrivs **Tamanotchi** i löptext, med stor bokstav. Ordmärket skrivs med gemener: `tamanotchi`.
- Uttalas *tama-nått-schi*. Smeknamn i tal: *Tama*.
- Hette tidigare *Notchi*; namnet byttes eftersom det redan användes.
- Karaktärerna heter **Pim, Oda, Bo och Kix**. Tillsammans kallas de *gänget*.
- Skriv inte "TAMANOTCHI", "Tamanotchi-appen" i rubriker eller "tamanotchi" i löptext.

---

## 3. Tonalitet (så pratar Tamanotchi)

Tamanotchi pratar som en trevlig kollega som sitter bredvid dig: rakt, vänligt och kort.

**Regler**
1. **Max tre korta meningar.** Det mesta ska gå att säga på en andning.
2. **Säg vad som händer, inte hur.** "Klart i kundportalen!" – inte "Processen har avslutats".
3. **Du-tilltal, alltid.**
4. **Fråga tydligt när du behöver något.** Avsluta med en fråga som går att svara ja eller nej på.
5. **Ingen jargong i talet.** Inga filsökvägar, inga flaggor, inga förkortningar som låter konstigt uppläsa.
6. **Glad, inte gullig.** Utropstecken när något blir klart – aldrig i felmeddelanden.
7. **Inga emojis i det som läses upp.**

**Exempel**

| Läge | ✅ Så här | ❌ Inte så här |
|---|---|---|
| Godkännande | "Kundportalen vill köra npm install. Godkänner du?" | "PermissionRequest: Bash(npm install) awaiting user decision." |
| Klart | "Klart i kundportalen!" | "Uppgiften har slutförts framgångsrikt 🎉🎉" |
| Väntar | "Kundportalen väntar på dig." | "Hallå?? Är du där? 👀" |
| Fel | "Jag når inte Claude just nu." | "Oj då! Något gick snett!!" |
| Känsligt kommando | "Det där behöver du godkänna med ett klick." | "Nej, det får du inte." |

---

## 4. Logotyp

| Fil | Användning |
|---|---|
| `brand/tamanotchi-lockup.svg` / `.png` | Standard: symbol + ordmärke på ljus bakgrund |
| `brand/tamanotchi-lockup-white.svg` / `.png` | På mörk bakgrund |
| `brand/tamanotchi-mark.svg` / `.png` | Bara symbolen – avatarer, favicon, små ytor |
| `brand/tamanotchi-wordmark.svg` / `-white.svg` | Bara ordmärket |
| `brand/tamanotchi-app-icon.svg` / `-1024.png` / `AppIcon.icns` | Appikon |

**Symbolen**: Pim som tittar fram under en notch. Den visar hela idén på en bild – någon bor där uppe.

**Ordmärket**: `tamanotchi` i Fredoka SemiBold, där pricken över i:et är en mintgrön punkt – samma
statuslampa som lyser i notchen.

**Gör så här**
- Ge logotypen luft: minst lika mycket fritt utrymme som notchens höjd runt om.
- Minsta bredd: 140 px för lockupen, 20 px för symbolen.
- Använd den vita varianten på mörka och färgstarka bakgrunder.

**Gör inte så här**
- Byt inte färg på i-pricken (den är alltid Pim-mint).
- Sträck, rotera eller lägg skugga på logotypen.
- Byt Pim i symbolen mot en annan karaktär – symbolen är alltid Pim. Karaktärerna får däremot synas fritt runt omkring.

---

## 5. Färger

### Grund

| Namn | Hex | Används till |
|---|---|---|
| **Notch** | `#000000` | Notchen, appens panel |
| **Natt** | `#0E0D12` | Mörka bakgrunder |
| **Papper** | `#F4F2EE` | Ljusa bakgrunder |
| **Bläck** | `#1B1A20` | Text, ögon och munnar |
| **Grafit** | `#4A4753` | Sekundär text på ljust |
| **Dimma** | `#C9C6D3` | Sekundär text på mörkt |

### Gänget (accentfärger)

| Karaktär | Kropp | Skugga | Roll |
|---|---|---|---|
| **Pim** | `#5ED6A8` | `#2EA37A` | Huvudfärg för varumärket |
| **Oda** | `#FF7A6B` | `#DB4D45` | Accent – energi, uppmärksamhet |
| **Bo** | `#A88CFF` | `#7559DB` | Accent – lugn, tänkande |
| **Kix** | `#FFC73D` | `#ED941A` | Accent – glädje, klart |

### Signal (bara i gränssnittet)

| Namn | Hex | Betyder |
|---|---|---|
| **Tillåt** | `#1B7D45` | Godkänn-knappen |
| **Neka** | `#C4343A` | Neka-knappen |
| **Behöver dig** | `#E5484D` | Utropsmärket vid godkännande |
| **Jobbar** | `#3B82F6` | Statuslampan när Claude arbetar |

**Regler**
- Använd en karaktärsfärg i taget som accent. Alla fyra tillsammans bara när gänget visas.
- Vit text på karaktärsfärgerna klarar inte kontrastkraven. Använd **Bläck** på dem.
- Signalfärgerna är för knappar och status, inte för dekor.

---

## 6. Typografi

| Roll | Typsnitt | Vikt | Används till |
|---|---|---|---|
| Rubrik | **Fredoka** | SemiBold 600 | Ordmärke, stora rubriker, karaktärsnamn |
| Brödtext | **Figtree** | Regular 400 / Medium 500 / SemiBold 600 | Allt annat |
| Kod | System (SF Mono / Menlo) | Regular | Kommandon i notchen |

Båda typsnitten är gratis (Google Fonts, OFL-licens).

- Rubriker: tät radhöjd (0,95–1,05), aldrig versaler.
- Etiketter: Figtree SemiBold, versaler, 13–14 px, spärrning 0,08 em.
- Brödtext: 15–19 px, radhöjd 1,5.

---

## 7. Karaktärerna

Alla fyra ritas med kod (`Sources/Tamanotchi/Mascot.swift`) och delar samma byggstenar:
rundad kropp med färgövergång, glansfläck uppe till vänster, mörka ögon med vit
ljusprick, rosa kinder och en liten mun.

| | Form | Kännetecken | Temperament |
|---|---|---|---|
| **Pim** | Rundad pebble | Litet skott som vajar | Lugn, pålitlig – förvald |
| **Oda** | Droppe | Lock i toppen, höga ögon | Pigg, lite dramatisk |
| **Bo** | Böna | Antenn som lyser när den tänker | Sömnig i vila |
| **Kix** | Blomma | Fräknar | Glad, studsig |

**Uttryck** (samma för alla)

| Läge | Ögon | Mun | Rörelse |
|---|---|---|---|
| Vilar | Normala, blinkar | Litet leende | Andas långsamt |
| Tänker | Tittar upp åt sidan | Litet leende | Gungar mjukt |
| Jobbar | Tittar fram och tillbaka | Litet leende | Snabba små studs |
| Behöver dig | Stora | Litet "o" | Hoppar, rött utropsmärke |
| Lyssnar | Stora, huvudet på sned | Rör sig med ljudet | Ring som pulserar |
| Pratar | Normala | Öppnas med rösten | Stilla |
| Klar | Glada ^ ^ | Stort leende | Skutt |

**Nya karaktärer** ska ha: en enkel, rund siluett som går att känna igen på 22 px,
en egen färg från samma mjuka palett, ett enda kännetecken (inte fler) och samma ansikte.
Undvik djur, kläder och tillbehör som hattar – gänget är former, inte figurer ur en tecknad serie.

---

## 8. Rörelse

- Allt rör sig mjukt, med fjäder – aldrig linjärt.
- Notchen fälls ut på ca 0,35 s.
- Karaktärerna "andas" hela tiden, så att de känns levande även när inget händer.
- Stora rörelser (hopp, skutt) bara när något händer som du behöver veta.

---

## 9. Ljud och röst

- Svensk röst, ljus och vänlig (tonhöjd något över normal).
- Standard: bästa installerade svenska systemröst (rekommenderad: Alva, Premium).
- Talet ska vara kort nog att inte avbryta – Tamanotchi tystnar direkt när du börjar prata.

---

## 10. Taglines

- **Din lilla kollega i notchen.** (huvudtagline)
- Håller koll, så att du slipper.
- Claude jobbar. Tamanotchi säger till.
- En blick upp räcker.
