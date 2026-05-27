# LuraMemorySync

Raid-Addon für **L'ura / Death's Dirge**: Symbol-Reihenfolge per **Addon-Message** synchronisieren — Runen-Icons sind **im Addon enthalten**.

## Setup

1. Ordner `LuraMemorySync` nach `World of Warcraft\_retail_\Interface\AddOns\`
2. Addon aktivieren, `/reload`
3. **RL oder Assist:** `/lms macro` — erstellt `LMS Rune 1` … `5` + Send/Undo/Reset
4. Raid: `/lms ver` — wer hat das Addon?

**Kein** extra `Interface\Icons`-Ordner und **kein** NSRT-Icon-Download nötig.

## Im Pull (RL/Assist)

1. Beim ersten **Dark Rune**-Debuff: neue Runde — Anzeige leert (BOSS + TANK bleiben)
2. Symbole nacheinander per Macro — **jedes Symbol sofort live** bei allen mit Addon
3. Layout: **BOSS** Mitte, **TANK** oben (ohne Symbol), fünf Runen im Uhrzeigersinn ab rechts oben
4. Nach vollständiger Eingabe bleibt die Anzeige stehen bis zur nächsten Runde

## Befehle

| Befehl | Wirkung |
|--------|---------|
| `/lms show` | Layout anzeigen |
| `/lms hide` | Layout verstecken |
| `/lms test` | alle 5 Positionen mit Test-Symbolen |
| `/lms macro` | Macros anlegen |
| `/lms send` | aktuelle Warteschlange senden |
| `/lms undo` | letztes Symbol entfernen |
| `/lms reset` | Reset für alle |
| `/lms force` | ohne RL/Assist senden |
| `/lms ver` | Addon-Versionen im Raid |
| `/lms last` | letzte Reihenfolge erneut senden |

## Sync

- Pro Klick: `LIVEADD:1` … `LIVEADD:5` (oder Legacy-ID falls alte Macros)
- Kein Raid-Chat nötig
