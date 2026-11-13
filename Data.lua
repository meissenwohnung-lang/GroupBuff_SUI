local _, ns = ...

-- Buff-Familien. Jede Familie ist EIN Effekt, egal welcher Zauber ihn liefert.
--   cast : Zauber-IDs, die DU wirken kannst (der erste bekannte gewinnt, beste zuerst)
--   alt  : weitere IDs, die den gleichen Effekt geben (z.B. Gruppenversion) -> zählt als "gebufft"
--   mana : true = nur für Mana-Nutzer relevant
--   pets : true = gilt auch für Pets/Begleiter (nur aktiv mit /gbs pets)
--   roles: Gruppenrollen, für die der Buff relevant ist, z.B. { TANK = true, DAMAGER = true }.
--          Ohne Angabe = alle. Spieler ohne zugewiesene Rolle werden immer geprüft.
--          Änderbar im Spiel mit /gbs role <Schlüssel> tank heal dps | all | default
--
-- WICHTIG: Forever ist klassenlos und die Spell-IDs können sich vom Retail-Client
-- unterscheiden. Unbekannte IDs werden still übersprungen. Mit "/gbs scan" siehst du
-- die echten IDs auf dir/deinem Ziel, mit "/gbs add <ID>" nimmst du sie auf.
ns.FAMILIES = {
    { key = "stamina",   cast = { 21562 },  alt = { 21564, 1243, 1244, 1245, 2791, 10937, 10938, 25389 }, pets = true },
    { key = "motw",      cast = { 1126 },   alt = { 21849, 21850, 5232, 6756, 5234, 8907, 9884, 9885, 26990 }, pets = true },
    { key = "intellect", cast = { 1459 },   alt = { 23028, 1460, 1461, 10156, 10157, 27126 }, mana = true },
    { key = "battleshout", cast = { 6673 }, alt = { 5242, 6192, 11549, 11550, 11551, 25289 }, roles = { TANK = true, DAMAGER = true }, pets = true },
    { key = "might",     cast = { 19740 },  alt = { 25782, 19834, 19835, 19836, 19837, 19838, 25291 }, roles = { TANK = true, DAMAGER = true }, pets = true },
    { key = "kings",     cast = { 20217 },  alt = { 25898 } },
    { key = "wisdom",    cast = { 19742 },  alt = { 25894, 19850, 19852, 19853, 19854, 25290 }, mana = true },
}
