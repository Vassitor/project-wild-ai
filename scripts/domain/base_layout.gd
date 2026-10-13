class_name WildBaseLayout
extends RefCounted
## 基地占位布局及站点稳定 ID。屏幕像素坐标仅用于基地视图，不参与未来随机地图。

const SPAWN := Vector2(320, 235)
const INTERACTION_RADIUS: float = 62.0
const STATIONS: Dictionary = {
	&"supply": {"name": "补给站", "position": Vector2(146, 153), "bounds": Rect2(105, 92, 82, 64), "description": "工具、食物与医疗物资的采购入口。\n补给站正在整理货架，暂不提供交易。"},
	&"storage": {"name": "仓库", "position": Vector2(465, 151), "bounds": Rect2(420, 92, 88, 64), "description": "整理库存，决定要带入荒野的装备。\n这里将存放你的永久物资。"},
	&"training": {"name": "训练场", "position": Vector2(499, 272), "bounds": Rect2(475, 221, 48, 48), "description": "学习九类生存技能，依序解锁各分支节点。\n用分支点数或基地货币学习，实践成长在失败后保留。"},
	&"expedition": {"name": "出发点", "position": Vector2(140, 272), "bounds": Rect2(125, 223, 30, 44), "description": "荒野挑战：累计生存 7 个游戏日。\n先备好行装，荒野入口暂未开放。"},
}


static func station(id: StringName) -> Dictionary:
	if id == &"pause":
		return {"name": "稍作休息", "description": "你正停留在永久基地。\n准备好后，继续整理行装。"}
	return (STATIONS.get(id, {}) as Dictionary).duplicate(true)
