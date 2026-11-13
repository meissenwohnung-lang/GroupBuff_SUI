# GroupBuff SUI

**GroupBuff SUI by Solomon · Designed for Selo^^**

GroupBuffs-Addon mit **SpartanUI-Dock**: zeigt die Buffs der Gruppe, welchen fehlenden Buff *du* geben kannst (Klick = zaubern), Restzeiten, Verbrauchsgüter-Check, Chat-Meldung beim Bereitschaftscheck, Rollenfilter, Pet-Buffs, Optionsfenster und Ansicht-Optionen – und hängt sich auf Wunsch an das **Classic-Artwork von SpartanUI**.

Läuft auch ohne SpartanUI. Eigenständig neben dem Addon *GroupBuffs* nutzbar (eigene Einstellungen, Befehl `/gbs`).

## Installation

Inhalt dieses Repos nach `Interface\AddOns\GroupBuff_SUI\` kopieren (Ordnername `GroupBuff_SUI`).

## SpartanUI-Dock

- Wirkt nur, wenn SpartanUI läuft und das Theme **Classic** aktiv ist.
- Das Fenster wird relativ zur Classic-Aktionsleisten-Platte positioniert: links neben den Leisten (Standard), rechts oder mittig darüber. Fein justierbar mit `/gbs dock x|y <Zahl>`.
- Optional nutzt es den Classic-Leistenhintergrund aus dem installierten SpartanUI (nur Verweis, es werden keine SpartanUI-Dateien kopiert).
- Angedockt ist das Fenster nicht frei ziehbar. `/gbs dock off` gibt es wieder frei.
- Befehle: `/gbs dock on|off|skin|left|right|center|x N|y N|reset`, Optionsseite „SpartanUI-Dock“.

Hinweis: Die Positionen beruhen auf dem Quellcode von SpartanUI und sind im Spiel noch nicht geprüft. Bei Überlappung (z. B. mit Einheitenfenstern) die Verschiebung nutzen.

## Befehle

`/gbs` (Fenster), `/gbs config`, `/gbs view`, `/gbs dock`, `/gbs help` – wie bei GroupBuffs, nur mit `/gbs` statt `/gb`.

## Lizenz

MIT, siehe `LICENSE`. SpartanUI gehört seinen Autoren; GroupBuff SUI nutzt nur dessen laufende Frames und Texturverweise.
