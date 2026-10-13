# 免费素材来源与授权

历史素材备份：当前游戏已切换到 [Ninja Adventure](../ninja_adventure/README.md)，此目录通过 `.gdignore` 排除游戏资源扫描。

核对与接入日期：2026-10-13（Asia/Shanghai）。作者 Kenney；RPG 包原许可还注明 Lynn Evers 协助。

| 包 | 官方页面 | 版本 | 当前用途 |
| --- | --- | --- | --- |
| Roguelike/RPG Pack | https://kenney.nl/assets/roguelike-rpg-pack | 1.0 | 森林 / 草地 / 水、树、植物、营地建筑、篝火、物品 |
| Roguelike Characters | https://kenney.nl/assets/roguelike-characters | 2.0 | 组合人物、刀 / 斧 / 弓 / 箭 / 护甲 |

两包均为 **Creative Commons Zero（CC0）**，允许免费用于个人和商业项目、修改素材；署名不是强制要求。这里保留作者信息与原包许可证 `LICENSE-rpg.txt`、`LICENSE-characters.txt`。许可链接：https://creativecommons.org/publicdomain/zero/1.0/ 。

## 下载与复现

官方 ZIP：

- https://kenney.nl/media/pages/assets/roguelike-rpg-pack/12c03cd78b-1677697420/kenney_roguelike-rpg-pack.zip
- https://kenney.nl/media/pages/assets/roguelike-characters/53ffff4133-1729196490/kenney_roguelike-characters.zip

下载包 SHA-256（大写十六进制）：

- RPG：`8E7D2378F8F794245645F6D7DC7AEEB246791410A7E512293C594B46A5A9524B`
- Characters：`05C4C0AF7326584CFFFBBB196571EB9E102981D2033E90E225C5BA8DA8771284`

素材为 16×16 px、格间距 1 px。`manifest.json` 记录选用格坐标（零起点）、组合与改动。原包暂存在 `.godot/asset-downloads/`，游戏不依赖暂存目录，只打包这里选中的 PNG。

已安装 Pillow 的 Python 可重新提取：

```powershell
python tools/prepare_art_assets.py <RPG解压目录> <Characters解压目录>
```

## 适配说明

- 拼接树木 / 浆果丛和两栋木屋；人物由底层、衣物、头发、鞋组合。删除原图集格间留白。
- 地形保留原有 4×3、每格 32 px 图集契约，最近邻放大并映射到森林绿 / 草地绿；水降低亮度。领域地形 ID、格子通行和地图生成保持原规则。
- 落枝使用枯木下半格旋转 90°。库存显示裁掉透明边缘，按整数倍率适配当前占格；旋转图像不改变业务规则。
- 打火石使用石块、绷带使用白色卷状图标、根茎 / 食物等使用相近物品图形；这是通用图标替代，并非专属写实插画。熟食复用原料图标并着色，具体种类由物品详情识别。
- 原包没有完整人物行走序列。本次接入静态人物与左右镜像，背向附行装提示，不宣称已经实现行走动画。
- 篝火、训练靶、木箱与木桶是基地装饰；训练、采集、饮水等功能仍以阶段报告为准。
