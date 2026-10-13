"""Extract selected CC0 Kenney sprites. Run with the two unpacked official ZIP directories.

Only presentation images are produced; gameplay IDs, grid sizes and saved data stay in Godot.
Requires Pillow. Source coordinates use 16px tiles with a 1px gap, starting at (0, 0).
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageEnhance


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rpg", type=Path)
    parser.add_argument("characters", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = root / "assets" / "kenney"
    output.mkdir(parents=True, exist_ok=True)
    sheets = {
        "rpg": Image.open(args.rpg / "Spritesheet/roguelikeSheet_transparent.png").convert("RGBA"),
        "characters": Image.open(args.characters / "Spritesheet/roguelikeChar_transparent.png").convert("RGBA"),
    }
    for name, source in [("rpg", args.rpg), ("characters", args.characters)]:
        (output / f"LICENSE-{name}.txt").write_bytes((source / "License.txt").read_bytes())
    manifest = {}

    def tile(sheet, x, y):
        return sheets[sheet].crop((x * 17, y * 17, x * 17 + 16, y * 17 + 16))

    def save(name, cells, sheet="rpg", layout=None):
        image = Image.new("RGBA", layout or (16, 16))
        for index, (x, y) in enumerate(cells):
            image.alpha_composite(tile(sheet, x, y), (0, index * 16) if layout else (0, 0))
        image.save(output / f"{name}.png")
        manifest[name] = {"sheet": sheet, "cells": cells, "layout": layout, "adaptation": "gap removal / composition only"}
        return image

    props = {
        "pine": ([(15, 10), (15, 11)], (16, 32)),
        "tree": ([(13, 9), (13, 11)], (16, 32)),
        "bush": ([(23, 10), (23, 11)], (16, 32)),
        "rock": ([(8, 18)], None), "herb": ([(28, 10)], None),
        "fiber": ([(22, 10)], None), "root": ([(54, 13)], None),
        "branch": ([(27, 11)], None),
        "fish": ([(56, 12)], None), "spring": ([(50, 9)], None),
        "campfire": ([(14, 8)], None), "sign": ([(21, 0)], None),
        "target": ([(45, 0)], None), "crate": ([(28, 2)], None),
        "barrel": ([(23, 0)], None), "bench": ([(20, 6)], None),
        "ration": ([(55, 13)], None), "bottle": ([(54, 12)], None),
        "herbal_medicine": ([(55, 12)], None), "stew": ([(56, 15)], None),
        "bandage": ([(54, 13)], None), "rope": ([(51, 12)], None),
        "hide": ([(25, 2)], None), "berry": ([(54, 14)], None),
        "raw_meat": ([(55, 14)], None), "fishing_kit": ([(52, 16)], None),
    }
    for name, (cells, layout) in props.items():
        save(name, cells, layout=layout)
    branch = Image.open(output / "branch.png").rotate(90)
    branch.save(output / "branch.png")
    manifest["branch"]["adaptation"] = "lower deadwood tile rotated 90 degrees"
    for name, cell in {"knife": (44, 0), "axe": (49, 0), "bow": (53, 0), "arrow": (42, 0), "leather_armor": (6, 4)}.items():
        save(name, [cell], "characters")
    save("explorer", [(0, 0), (6, 5), (19, 0), (3, 0)], "characters")
    # Three-by-two wooden cabins: tile joins are packed with the original 1px gaps removed.
    for name, roof in [("supply", (34, 21)), ("storage", (27, 21))]:
        image = Image.new("RGBA", (48, 32))
        cells = []
        for y in range(2):
            for x in range(3):
                cell = [(roof[0], roof[1]), (39 if name == "supply" else 32, 21), (roof[0] + 1, roof[1])][x] if y == 0 else (34 + x, 14)
                image.alpha_composite(tile("rpg", *cell), (x * 16, y * 16))
                cells.append(cell)
        image.alpha_composite(tile("rpg", 36, 5), (16, 16))
        image.save(output / f"{name}.png")
        manifest[name] = {"sheet": "rpg", "cells": cells + [(36, 5)], "adaptation": "3x2 cabin composition with door"}
    # Preserve the existing 4 variants x 3 terrain rows contract. No random gameplay calls.
    atlas = Image.new("RGBA", (128, 96))
    for row in range(3):
        for variant in range(4):
            ground = tile("rpg", *( (5, 0) if row < 2 else (0, 0) ))
            if row < 2:
                if variant in (1, 3):
                    ground = tile("rpg", 9, 1)
                palette = (52, 78, 57) if row == 0 else (87, 111, 65)
                pixels = list(ground.convert("RGBA").get_flattened_data()) if hasattr(ground, "get_flattened_data") else list(ground.getdata())
                ground.putdata([tuple(min(255, int(channel * (0.3*r+0.6*g+0.1*b) / 165)) for channel in palette) + (a,) for r, g, b, a in pixels])
            else:
                ground.alpha_composite(tile("rpg", variant, 1)) if variant < 2 else None
                ground = ImageEnhance.Brightness(ground).enhance(0.72)
            atlas.paste(ground.resize((32, 32), Image.Resampling.NEAREST), (variant * 32, row * 32))
    atlas.save(output / "terrain.png")
    manifest["terrain"] = {"sheet": "rpg", "cells": [[5, 0], [9, 1], [0, 0], [0, 1], [1, 1]], "adaptation": "nearest 2x scale; luminance-mapped forest RGB 52/78/57; grass 87/111/65; water brightness 0.72"}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Prepared {len(manifest)} presentation assets in {output}")


if __name__ == "__main__":
    main()
