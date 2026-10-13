"""汇总隔离 Godot 截图和真实输入动画；不生成或改动游戏素材。依赖 Pillow。

先运行 tests/p2_preview.tscn、tests/p1_capture.gd、tests/ninja_preview.gd。
"""
from pathlib import Path
from shutil import copyfile
from PIL import Image, ImageDraw


def main():
    root = Path(__file__).resolve().parent.parent
    verification = root / ".godot/verification"
    output = root / "docs/previews"
    for source, target in [("p2-base", "ninja-base"), ("p2-wilderness", "ninja-wilderness"), ("p2-resource", "ninja-resource"), ("p1-storage", "ninja-inventory")]:
        copyfile(verification / f"{source}.png", output / f"{target}.png")
    frames = [Image.open(verification / f"ninja-motion-{index:02}.png").crop((420,240,920,560)).convert("RGB") for index in range(20)]
    frames[0].save(output / "ninja-motion.gif", save_all=True, append_images=frames[1:], duration=100, loop=0, optimize=True)
    labels = [("pine", "Tree A"), ("tree", "Tree B"), ("tree_tall", "Tree C"), ("stump", "Depleted"), ("stone", "Rock A"), ("stone_2", "Rock B"), ("stone_3", "Rock C"), ("berry_bush", "Fruit"), ("bush", "Empty bush")]
    canvas = Image.new("RGB", (900,210), "#273d35")
    draw = ImageDraw.Draw(canvas)
    for index, (name, label) in enumerate(labels):
        asset = Image.open(root / f"assets/ninja_adventure/{name}.png").convert("RGBA")
        asset = asset.resize((asset.width*2, asset.height*2), Image.Resampling.NEAREST)
        x = index*100+(100-asset.width)//2
        canvas.paste(asset, (x,145-asset.height), asset)
        draw.text((index*100+10,165),label,fill="#eadfbc")
    canvas.save(output / "ninja-variants.png")
    print("Ninja screenshot, gameplay animation and variant previews assembled")


if __name__ == "__main__":
    main()
