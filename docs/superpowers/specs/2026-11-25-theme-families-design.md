# Theme families in the grid: design

## Intent
The grid shows every cursor theme as its own tile. Bibata alone is 12 tiles
(Modern/Original x Amber/Classic/Ice, each also as `-Right`, the mirrored
left-handed variant), mixed in with Adwaita, Yaru and the rest. The owner finds it
scattered and wants themes grouped by folder/family.

## Goals
- Themes that share a name prefix form one **family tile** ("Bibata", with a count).
- Clicking a family tile opens its variants in the same grid, with **Back**.
- Inside a family, `-Right` (left-handed) variants are hidden behind a **Left-handed**
  toggle, so Bibata shows 6 variants, not 12.
- A family tile is marked when the active theme belongs to it.

## Non-goals
- No grouping by the folder a theme lives in on disk, no user-defined groups, no
  nested families, no changes to how a theme is applied or saved.

## Decisions
- Family key: the id up to the first `-`, compared case-insensitively
  (`Bibata-Modern-Ice` -> `bibata`; `Adwaita` -> `adwaita`). A key shared by two or
  more themes is a family; otherwise the theme stays a plain tile (so `Future-dark-cursors`
  and `claude-cursors` stay alone). The family's name is that prefix as written.
- A theme is left-handed when its id ends in `-Right` (any case) and the id without
  that suffix exists in the same family. The toggle appears only if the family has some.
- The family tile previews the active variant if it belongs to the family, else its
  first right-handed variant. Opening a family starts with the toggle on when the active
  theme is left-handed.
- Searching still searches every theme and shows matches as plain tiles.
- Esc inside a family goes back; Esc elsewhere closes the panel as before.
- The "N cursor themes" counter still counts themes, not tiles.
- Approach A (family cards) was chosen over B (always-open sections) by the owner.
