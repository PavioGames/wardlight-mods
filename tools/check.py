#!/usr/bin/env python3
"""Checks Wardlight mods and texture packs before they go into the game.

    python3 tools/check.py texturas/meu-pacote
    python3 tools/check.py mods/meu-mod
    python3 tools/check.py            (everything in mods/ and texturas/)

Only reads files; standard library only.
"""
import os, struct, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FACES = ("", "_top", "_side", "_bottom")
PACK_FILES = {"pack.txt", "README.md", "LICENSE", "LICENSE.md", "preview.png"}


def names():
    with open(os.path.join(HERE, "nomes.txt"), encoding="utf-8") as f:
        return {l.strip() for l in f if l.strip() and not l.startswith("#")}


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", head[16:24])


def pack_txt(folder, errors):
    path = os.path.join(folder, "pack.txt")
    if not os.path.isfile(path):
        errors.append("falta pack.txt / pack.txt is missing")
        return {}
    keys = {}
    for line in open(path, encoding="utf-8"):
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            keys[k.strip()] = v.strip()
    for k in ("name", "version", "author", "license"):
        if not keys.get(k):
            errors.append(f"pack.txt sem '{k}' / pack.txt has no '{k}'")
    return keys


def check_textures(folder, known, errors, warnings, base_names=True):
    tex = os.path.join(folder, "textures")
    if not os.path.isdir(tex):
        return
    for name in sorted(os.listdir(tex)):
        if name.startswith("."):
            continue
        path = os.path.join(tex, name)
        if not name.endswith(".png"):
            errors.append(f"textures/{name}: só PNG / PNG only")
            continue
        size = png_size(path)
        if size is None:
            errors.append(f"textures/{name}: não é um PNG válido / not a valid PNG")
        elif size != (16, 16):
            errors.append(f"textures/{name}: {size[0]}x{size[1]}, precisa ser 16x16 / must be 16x16")
        stem = name[:-4]
        if base_names and not any(stem == n + s for n in known for s in FACES):
            warnings.append(f"textures/{name}: nome fora de nomes.txt (ok se for bloco de mod) / "
                            "not in nomes.txt (fine for a mod's block)")


def check_texture_pack(folder):
    errors, warnings = [], []
    pack_txt(folder, errors)
    for name in os.listdir(folder):
        if name.startswith(".") or name == "textures" or name in PACK_FILES:
            continue
        errors.append(f"{name}: um pacote de textura só tem pack.txt e textures/ "
                      "/ a texture pack holds only pack.txt and textures/")
    check_textures(folder, names(), errors, warnings)
    return errors, warnings


def check_mod(folder):
    errors, warnings = [], []
    pack_txt(folder, errors)
    check_textures(folder, names(), errors, warnings, base_names=False)
    return errors, warnings


def run(folder):
    kind = os.path.basename(os.path.dirname(os.path.abspath(folder)))
    errors, warnings = (check_texture_pack if kind == "texturas" else check_mod)(folder)
    for w in warnings:
        print(f"  aviso / warning: {w}")
    for e in errors:
        print(f"  ERRO / ERROR: {e}")
    print(f"{folder}: {'ok' if not errors else f'{len(errors)} erro(s)'}")
    return not errors


def main():
    folders = sys.argv[1:]
    if not folders:
        for kind in ("mods", "texturas"):
            base = os.path.join(HERE, kind)
            folders += [os.path.join(base, d) for d in sorted(os.listdir(base))
                        if os.path.isdir(os.path.join(base, d)) and d != "base"]
    ok = all([run(f) for f in folders])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
