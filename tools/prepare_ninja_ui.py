"""从官方 CC0 木质 UI 提取按钮状态与九宫格，适配营地色板。

用法：python tools/prepare_ninja_ui.py <Ninja Adventure 解压根目录>
只处理表现图片；最近邻放大两倍，保留原透明边缘。依赖 Pillow。
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageColor, ImageDraw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    source = parser.parse_args().source.resolve()
    output = Path(__file__).resolve().parent.parent / "assets/ninja_adventure/ui"
    output.mkdir(parents=True, exist_ok=True)
    manifest = {}
    names = ["nine_path_panel", "button_normal", "button_hover", "button_pressed", "button_disabled"]
    for name in names:
        relative = f"Ui/Theme/Theme Wood/{name}.png"
        image = Image.open(source / relative).convert("RGBA")
        if name == "nine_path_panel":
            palette = [("#a68052", .68), ("#bfa078", .55), ("#745338", .35), ("#3b2e23", 0)]
        else:
            state = name.removeprefix("button_")
            top = {"normal":"#a58056", "hover":"#e1bc7c", "pressed":"#8c6d47", "disabled":"#66594a"}[state]
            middle = {"normal":"#644934", "hover":"#806046", "pressed":"#493b2d", "disabled":"#403b33"}[state]
            palette = [(top,.68), (middle,.4), ("#3f2f25",.25), ("#182a24",0)]
        for y in range(image.height):
            for x in range(image.width):
                red, green, blue, alpha = image.getpixel((x,y))
                if not alpha:
                    continue
                brightness = (red+green+blue)/(3*255)
                color = next(color for color, threshold in palette if brightness >= threshold)
                image.putpixel((x,y), (*ImageColor.getrgb(color),alpha))
        if name == "nine_path_panel":
            ImageDraw.Draw(image).rectangle((4,4,11,11),fill="#172b25")
        image.resize((image.width*2,image.height*2),Image.Resampling.NEAREST).save(output / f"{name}.png")
        manifest[name] = {"source":relative,"adaptation":"earth-tone palette; panel interior dark; nearest 2x"}
    (output / "manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")


if __name__ == "__main__":
    main()
