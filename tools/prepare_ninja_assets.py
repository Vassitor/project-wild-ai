"""提取官方 Ninja Adventure CC0 素材；只生成表现资源与可复现来源清单。

用法：python tools/prepare_ninja_assets.py <Ninja Adventure 解压根目录>
依赖 Pillow。图集坐标使用 16px 网格；人物原表每帧 32px，列为朝向、行为帧向下排列。
"""
import argparse
import json
from pathlib import Path
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    source = parser.parse_args().source.resolve()
    output = Path(__file__).resolve().parent.parent / "assets/ninja_adventure"
    output.mkdir(parents=True, exist_ok=True)
    manifest = {}

    def load(relative):
        return Image.open(source / relative).convert("RGBA")

    def save(name, relative, rect=None):
        image = load(relative)
        if rect:
            x, y, width, height = rect
            image = image.crop((x, y, x + width, y + height))
        image.save(output / f"{name}.png")
        manifest[name] = {"source": relative, "pixel_rect": rect, "adaptation": "original pixels / crop"}
        return image

    def tile(name, sheet, x, y, width=1, height=1):
        return save(name, f"Backgrounds/Tilesets/{sheet}.png", [x*16, y*16, width*16, height*16])

    for name, rect in {
        "pine": (0, 2, 3, 3), "tree": (0, 0, 2, 2), "tree_tall": (6, 0, 2, 2),
        "stump": (0, 8, 2, 2), "bush": (6, 8, 2, 2), "berry": (3, 11, 1, 1),
        "stone": (6, 14, 1, 1), "stone_2": (7, 12, 1, 1), "stone_3": (9, 12, 1, 1),
        "herb": (6, 11, 1, 1), "fiber": (4, 10, 1, 1),
        "spring_pool": (10, 13, 1, 1),
    }.items():
        tile(name, "TilesetNature", *rect)
    # 浆果丛与无果丛由同一灌木形成状态差分，不增加资源或采集命令。
    bush = load("Backgrounds/Tilesets/TilesetNature.png").crop((96,128,128,160))
    fruit = load("Backgrounds/Tilesets/TilesetNature.png").crop((48,176,64,192))
    bush.alpha_composite(fruit, (4, 8))
    bush.save(output / "berry_bush.png")
    manifest["berry_bush"] = {"source": "Backgrounds/Tilesets/TilesetNature.png", "pixel_rects": [[96,128,32,32],[48,176,16,16]], "adaptation": "fruit over bush"}
    for name, rect in {"supply": (0,0,4,3), "storage": (4,0,4,3), "crate": (16,18,1,1), "barrel": (16,20,1,1)}.items():
        tile(name, "TilesetHouse", *rect)
    tile("sign", "TilesetElement", 1, 5)
    tile("target", "TilesetNature", 9, 8)
    tile("bench", "TilesetElement", 8, 0)
    tile("rope", "tileset_camp", 11, 7)
    tile("hide", "tileset_camp", 8, 5, 2, 2)
    tile("campfire", "tileset_camp", 6, 4)
    tile("path", "TilesetFloor", 1, 8)

    items = {
        "knife": "Projectile/Kunai.png", "axe": "Weapons/AxeTool/Sprite.png",
        "flint": "Resource/Rock.png", "fishing_kit": "Weapons/Fishing Rod/Sprite.png",
        "bottle": "Potion/WaterPot.png", "ration": "Food/Onigiri.png",
        "bandage": "Potion/Medipack.png", "herbal_medicine": "Potion/LifePot.png",
        "leather_armor": "Object/Bag.png", "bow": "Weapons/Bow/Sprite.png",
        "arrow": "Weapons/Bow/Arrow.png", "wood": "Resource/Branch.png",
        "branch": "Resource/Branch.png", "root": "Food/SeedBig2.png",
        "raw_fish": "Food/Fish.png", "fish": "Food/Fish.png",
        "raw_meat": "Food/Beaf.png", "cooked_meat": "Food/Meat.png",
        "stew": "Food/Noodle.png", "spring": "Resource/Water.png",
    }
    for name, relative in items.items():
        save(name, f"Items/{relative}")
    for action in ["Idle", "Walk"]:
        save(f"explorer_{action.lower()}", f"Actor/CharacterAnimated/NinjaGreen/Separate/{action}.png")
    save("fire_animation", "FX/Particle/Fire.png")
    save("water_animation", "Backgrounds/Animated/Water Ripples/SpriteSheet16x16.png")
    # 泉水是可接触的圆形水洼，不使用物品水桶或白色球体作为世界资源。
    silhouette = Image.open(output / "spring_pool.png").convert("RGBA")
    pool = load("Backgrounds/Animated/Water Ripples/SpriteSheet16x16.png").crop((0,0,16,16))
    pool.putalpha(silhouette.getchannel("A"))
    for y in range(16):
        for x in range(16):
            color = silhouette.getpixel((x,y))
            if color[3] and sum(color[:3]) < 150:
                pool.putpixel((x,y),color)
    pool.save(output / "spring_pool.png")
    manifest["spring_pool"] = {"source": ["Backgrounds/Tilesets/TilesetNature.png", "Backgrounds/Animated/Water Ripples/SpriteSheet16x16.png"], "pixel_rects": [[160,208,16,16],[0,0,16,16]], "adaptation": "water clipped to circular silhouette; original dark outline retained"}

    # 原生 16px 地面放大至业务已有的 32px。四列是变体，水的四帧垂直排列。
    atlas = Image.new("RGBA", (128, 192))
    floor = load("Backgrounds/Tilesets/TilesetFloor.png")
    ripples = load("Backgrounds/Animated/Water Ripples/SpriteSheet16x16.png")
    cells = []
    for row, start in [(0, 11), (1, 0)]:
        for variant in range(4):
            cell = [start+variant, 12]
            cells.append(cell)
            image = floor.crop((cell[0]*16,192,cell[0]*16+16,208))
            atlas.paste(image.resize((32,32),Image.Resampling.NEAREST), (variant*32,row*32))
    for frame in range(4):
        for variant in range(4):
            image = ripples.crop((frame*16,0,frame*16+16,16))
            atlas.paste(image.resize((32,32),Image.Resampling.NEAREST), (variant*32,(frame+2)*32))
    atlas.save(output / "terrain.png")
    manifest["terrain"] = {"source": ["Backgrounds/Tilesets/TilesetFloor.png", "Backgrounds/Animated/Water Ripples/SpriteSheet16x16.png"], "ground_cells": cells, "adaptation": "nearest 2x, water frames vertical; source palette preserved"}
    # 游戏窗口图标也使用本包元素，不继续显示引擎默认图标。
    icon = Image.new("RGBA", (64,64), "#34493c")
    tree = Image.open(output / "pine.png").convert("RGBA")
    icon.alpha_composite(tree, (8, 8))
    fire = load("FX/Particle/Fire.png").crop((24,0,36,12)).resize((24,24),Image.Resampling.NEAREST)
    icon.alpha_composite(fire, (20,36))
    icon.resize((128,128),Image.Resampling.NEAREST).save(output / "game_icon.png")
    manifest["game_icon"] = {"source": ["pine", "fire_animation"], "adaptation": "composition, nearest 2x"}
    (output / "LICENSE.txt").write_bytes((source / "LICENSE.txt").read_bytes())
    (output / "AUTHOR-README.md").write_bytes((source / "README.md").read_bytes())
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Prepared {len(manifest)} Ninja Adventure presentation images")


if __name__ == "__main__":
    main()
