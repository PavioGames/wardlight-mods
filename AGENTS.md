# For AI assistants (Claude, or any other)

This repository holds mods and texture packs for the game Wardlight. The
guide is `README.md` (Portuguese) and `README.en.md` (English); read it
before making anything. Answer the person in their own language.

## Rules

- **Original only.** No names, characters, textures, sounds or levels from
  other games or works, and nothing that imitates their look closely.
- **A texture pack is pictures only:** `pack.txt` (with `resolution` = 16,
  32, 64 or 128) and square PNGs of that size beside it, named as in
  `nomes.txt` (a mod's block by its own name). Never put scripts, blocks or
  other files in one.
- **A mod reaches nothing outside the game.** Do not try to read files,
  reach the network or run programs from a script; the game blocks it and
  the mod will not be accepted.
- **No shaders**, in mods or packs.
- Every pack and mod has a `pack.txt` with `name`, `version`, `author` and
  `license` (CC-BY-4.0 for art, GPL-3.0 for scripts, unless the author
  chooses another free license).
- Run `python3 tools/check.py <folder>` and fix every error before saying
  it is done.

## Making textures

The pack's resolution (16 by default; 32, 64 or 128 for more detail), opaque unless the block is see-through (glass, leaves,
water). Keep the game's look: simple shapes, a few colours, soft noise.
Start from the matching file in `texturas/base/` when there is one. To make
the PNG, use any tool you have (for example Python with only the standard
library: `zlib` and `struct` write a valid PNG).
