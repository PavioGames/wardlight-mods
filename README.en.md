# Wardlight: mods and texture packs

[Português](README.md)

Everything to make things for Wardlight, by hand or with an AI (Claude or
another): templates, examples, the game's textures as a base, and a checker.

| Folder | What it holds |
|---|---|
| `texturas/` | Texture packs. `modelo/` to copy; `base/` with the game's textures, already a pack |
| `mods/` | Mods: blocks, items, recipes, sounds and scripts. `modelo/` to copy; `exemplo/` and `exemplo-wasm/` ready to run |
| `nomes.txt` | The names of the textures a pack may replace |
| `tools/check.py` | Checks a pack or mod before it goes into the game |

## Texture pack or mod?

- **Texture pack:** changes only the look. It is pictures only, so it is safe
  by nature. A world or server may have several, and each player chooses one,
  or the game's own textures.
- **Mod:** adds or changes parts of the game (blocks, items, recipes, sounds,
  scripts). It runs in the host's world.

## Making a texture pack

1. Copy `texturas/modelo/` to `texturas/<pack-name>/`.
2. Fill in `pack.txt`: name, author, version and license.
3. Choose the resolution in `pack.txt`: `resolution = 16`, `32`, `64` or
   `128`. Every picture in the pack is that size, square.
4. For each drawing you change, put a **PNG** in the pack's folder named as
   in `nomes.txt` (`stone.png`, `grass_top.png`, `kiln_front.png`...). What
   the pack leaves out keeps the game's texture. Start from
   `texturas/base/`. A mod's block uses its own name (or `_top`, `_side`,
   `_bottom`).
5. Run `python3 tools/check.py texturas/<pack-name>`.
6. In the game: zip the folder and add it with the world's **Textures**
   button (on PC, the folder goes beside the save).

A pack holds only `pack.txt` and the PNGs (and, if you like, `README.md` and
`LICENSE`). No scripts and no new blocks: that is a mod.

**Resolution and phones:** each device shows the pack as far as its graphics
quality allows (Light up to 16, Medium up to 32, Fine the pack's own). A
128 pack opens on a simple phone, only less sharp.

**Playing together:** packs live in the host's world. Whoever joins sees the
list and picks one, or the game's textures, and receives only that pack's
pictures, as data, kept in memory while playing. A joining player's own pack
does not apply in someone else's game. The host may lock it to one pack.

> Replacing the game's textures and choosing per player are being built now;
> the format may change a little until an update ships them.

## Making a mod

Copy `mods/modelo/` to `mods/<mod-name>/`, fill in `pack.txt`, and see
`mods/exemplo/`: a new block, a food, recipes and a script. The files
(`things.txt`, `recipes.txt`, `textures/`, `sounds/`, `init.lua`, `*.wasm`),
every key, the script events and calls are described in [README.md](README.md),
with the same names in both languages.

## What a mod can and cannot do

Anything inside the game; nothing outside it: a mod reads and deletes no
files, reaches no network and runs no programs. Lua gets only `table`,
`string`, `math`, `utf8` and `coroutine`, up to 32 MB; WebAssembly up to
64 MB. A script that hangs stops only that mod. Mods carry no shaders.

## Sending to this repository

Open a pull request with your folder in `mods/` or `texturas/` once
`python3 tools/check.py` passes. Everything here must be original: no
characters, textures or sounds from other games or works.

## Licenses

- Textures and sounds: **CC BY 4.0** ([LICENSE-ART.md](LICENSE-ART.md)).
- Scripts and tools: **GPL-3.0** ([LICENSE](LICENSE)), the game's own.
