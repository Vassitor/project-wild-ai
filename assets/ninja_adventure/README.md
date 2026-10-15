# Ninja Adventure 当前使用素材

作者：Pixel-boy、AAA。官方页面：https://pixel-boy.itch.io/ninja-adventure-asset-pack 。2026-10-13（Asia/Shanghai）通过官方免费入口下载 `Ninja Adventure - Asset Pack.zip`。

授权 **CC0 1.0 Universal**，免费用于个人 / 商业游戏，允许修改；保留原包 `LICENSE.txt` 与 `AUTHOR-README.md`。ZIP SHA-256：`95A06F4FDCFD1882F061A45FF313B7C905DBE2DE1E8512B281D7937DF62A7B15`。

官方包存于 `.godot/asset-downloads/ninja/`，游戏只引用此目录的选用图片。每张图片的原文件、裁剪坐标和组合方式记录在 `manifest.json`。保留原包配色，普通图集按 16px 网格提取；地面最近邻放大到现有 32px 业务格。

复现提取（Python + Pillow）：

```powershell
python tools/prepare_ninja_assets.py "<Ninja Adventure - Asset Pack 解压目录>"
```

## 已接入的动画与差分

- NinjaGreen 新版人物：四方向待机 / 行走，原表每帧 32×32，列依次向下、向上、向左、向右，四帧沿纵向排列。游戏内放大两倍，只播放当前已有移动行为。
- 水：原包四帧涟漪；适配为 TileSet 水格动画。火：原包八帧火焰与营地石圈组合。
- 三种树形和三种石块，按资源格坐标选择，不使用世界随机流；森林 / 草地各四种纹理。
- 树→树桩、浆果丛→无果丛，读取现有快照的 `remaining`。当前没有玩家采集入口，差分仅为加载耗尽资源后的表现准备。
- 两种营地建筑、营地家具、物品图标及窗口图标使用同包素材；中文继续使用系统字体。

## 通用图标替代

原包没有一一对应的皮甲、绷带、打火石专属图标：皮甲暂用皮革袋，绷带用医疗包，打火石用石块；草药制剂用药瓶，干粮用饭团，根茎用根菜图标。熟鱼、烤根茎以原料图像着色区分；物品中文详情与稳定 ID 是识别依据。衣物图标不代表新装备规则。

完整攻击、游泳、受伤和死亡动作仍在官方原包中，没有接入为可执行玩法。当前只有待机 / 行走与环境装饰动画。

## 2026-10-14 UI 样式适配

`ui/` 新增五张木质主题 PNG，来源为同包 `Ui/Theme/Theme Wood/` 的九宫格面板、普通 / 悬停 / 按下 / 禁用按钮。适配为棕木边框、深森林绿内衬与金色悬停状态，最近邻放大两倍；逐图来源见 `ui/manifest.json`。沿用此目录的 CC0 原许可，不新增付费素材或分发字体。

```powershell
python tools/prepare_ninja_ui.py "<Ninja Adventure - Asset Pack 解压目录>"
```

游戏直接读取提取后的图片，不依赖 `.godot/asset-downloads/` 缓存。UI 改版与验证见 [记录](../../docs/16-ui-redesign.md)。
