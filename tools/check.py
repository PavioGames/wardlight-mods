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
PACK_FILES = {"pack.txt", "README.md", "LICENSE", "LICENSE.md"}
RESOLUTIONS = ("16", "32", "64", "128")


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


def check_pictures(folder, files, size_ok, known, errors, warnings, where=""):
    for name in files:
        path = os.path.join(folder, name)
        size = png_size(path)
        if size is None:
            errors.append(f"{where}{name}: não é um PNG válido / not a valid PNG")
            continue
        problem = size_ok(size)
        if problem:
            errors.append(f"{where}{name}: {size[0]}x{size[1]}, {problem}")
        stem = name[:-4]
        if known is not None and stem not in known and not any(stem.endswith(f) for f in FACES[1:]):
            warnings.append(f"{where}{name}: nome fora de nomes.txt (ok se for bloco de mod) / "
                            "not in nomes.txt (fine for a mod's block)")


def check_texture_pack(folder):
    errors, warnings = [], []
    keys = pack_txt(folder, errors)
    res = keys.get("resolution", "16")
    if res not in RESOLUTIONS:
        errors.append(f"pack.txt: resolution = {res}; use 16, 32, 64 ou/or 128")
        res = "16"
    side = int(res)
    pngs = []
    for name in sorted(os.listdir(folder)):
        if name.startswith(".") or name in PACK_FILES:
            continue
        if name.endswith(".png") and os.path.isfile(os.path.join(folder, name)):
            pngs.append(name)
        else:
            errors.append(f"{name}: um pacote de textura só tem pack.txt e PNGs "
                          "/ a texture pack holds only pack.txt and PNGs")
    check_pictures(folder, pngs, lambda s: None if s == (side, side) else
                   f"precisa ser {side}x{side} (resolution) / must be {side}x{side}", names(), errors, warnings)
    return errors, warnings


def check_mod(folder):
    errors, warnings = [], []
    pack_txt(folder, errors)
    tex = os.path.join(folder, "textures")
    if os.path.isdir(tex):
        files = sorted(n for n in os.listdir(tex) if not n.startswith("."))
        for n in files:
            if not n.endswith(".png"):
                errors.append(f"textures/{n}: só PNG / PNG only")
        check_pictures(tex, [n for n in files if n.endswith(".png")],
                       lambda s: None if s[0] == s[1] and s[0] <= 128 else "precisa ser quadrado, até 128 / must be square, up to 128",
                       None, errors, warnings, "textures/")
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
                        if os.path.isdir(os.path.join(base, d))]
    ok = all([run(f) for f in folders])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
