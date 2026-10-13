class_name WildArtLibrary
extends RefCounted
## CC0 图像表现层目录：语义名与图片路径分离，不写入物品 / 世界存档。
## 原作者、来源、图集坐标和改动记录在 assets/ninja_adventure/；不承载玩法状态。

const TERRAIN: Texture2D = preload("res://assets/ninja_adventure/terrain.png")
const EXPLORER_IDLE: Texture2D = preload("res://assets/ninja_adventure/explorer_idle.png")
const EXPLORER_WALK: Texture2D = preload("res://assets/ninja_adventure/explorer_walk.png")
const FIRE: Texture2D = preload("res://assets/ninja_adventure/fire_animation.png")
const PATH: Texture2D = preload("res://assets/ninja_adventure/path.png")
const TERRAIN_COLORS: Array[Color] = [Color("779d3d"), Color("adb735"), Color("71ddee")]
static var _icon_cache: Dictionary[StringName, AtlasTexture] = {}
const IMAGES: Dictionary[StringName, Texture2D] = {
	&"pine": preload("res://assets/ninja_adventure/pine.png"),
	&"tree": preload("res://assets/ninja_adventure/tree.png"),
	&"tree_tall": preload("res://assets/ninja_adventure/tree_tall.png"),
	&"stump": preload("res://assets/ninja_adventure/stump.png"),
	&"berry_bush": preload("res://assets/ninja_adventure/berry_bush.png"),
	&"stone_2": preload("res://assets/ninja_adventure/stone_2.png"),
	&"stone_3": preload("res://assets/ninja_adventure/stone_3.png"),
	&"bush": preload("res://assets/ninja_adventure/bush.png"),
	&"stone": preload("res://assets/ninja_adventure/stone.png"),
	&"flint": preload("res://assets/ninja_adventure/flint.png"),
	&"branch": preload("res://assets/ninja_adventure/branch.png"),
	&"wood": preload("res://assets/ninja_adventure/wood.png"),
	&"spring": preload("res://assets/ninja_adventure/spring.png"),
	&"spring_pool": preload("res://assets/ninja_adventure/spring_pool.png"),
	&"fiber": preload("res://assets/ninja_adventure/fiber.png"),
	&"root": preload("res://assets/ninja_adventure/root.png"),
	&"herb": preload("res://assets/ninja_adventure/herb.png"),
	&"berry": preload("res://assets/ninja_adventure/berry.png"),
	&"fish": preload("res://assets/ninja_adventure/raw_fish.png"),
	&"raw_fish": preload("res://assets/ninja_adventure/raw_fish.png"),
	&"cooked_fish": preload("res://assets/ninja_adventure/raw_fish.png"),
	&"raw_meat": preload("res://assets/ninja_adventure/raw_meat.png"),
	&"cooked_meat": preload("res://assets/ninja_adventure/cooked_meat.png"),
	&"roasted_root": preload("res://assets/ninja_adventure/root.png"),
	&"knife": preload("res://assets/ninja_adventure/knife.png"),
	&"axe": preload("res://assets/ninja_adventure/axe.png"),
	&"fishing_kit": preload("res://assets/ninja_adventure/fishing_kit.png"),
	&"bottle": preload("res://assets/ninja_adventure/bottle.png"),
	&"ration": preload("res://assets/ninja_adventure/ration.png"),
	&"bandage": preload("res://assets/ninja_adventure/bandage.png"),
	&"herbal_medicine": preload("res://assets/ninja_adventure/herbal_medicine.png"),
	&"leather_armor": preload("res://assets/ninja_adventure/leather_armor.png"),
	&"bow": preload("res://assets/ninja_adventure/bow.png"),
	&"arrow": preload("res://assets/ninja_adventure/arrow.png"),
	&"rope": preload("res://assets/ninja_adventure/rope.png"),
	&"hide": preload("res://assets/ninja_adventure/hide.png"),
	&"stew": preload("res://assets/ninja_adventure/stew.png"),
	&"campfire": preload("res://assets/ninja_adventure/campfire.png"),
	&"sign": preload("res://assets/ninja_adventure/sign.png"),
	&"target": preload("res://assets/ninja_adventure/target.png"),
	&"crate": preload("res://assets/ninja_adventure/crate.png"),
	&"barrel": preload("res://assets/ninja_adventure/barrel.png"),
	&"bench": preload("res://assets/ninja_adventure/bench.png"),
	&"supply": preload("res://assets/ninja_adventure/supply.png"),
	&"storage": preload("res://assets/ninja_adventure/storage.png"),
}


## 未收录的语义名返回 null，调用方保留中文回退提示。
static func texture(id: StringName) -> Texture2D:
	return IMAGES.get(id)


## 只用于图像着色，熟食与原料的区别仍由物品 ID 和说明决定。
static func tint(id: StringName) -> Color:
	return Color("bc946c") if id in [&"cooked_fish", &"cooked_meat", &"roasted_root"] else Color.WHITE


## 图标按整数倍率居中；旋转仅改变图像朝向，业务占格由库存快照决定。
static func draw_icon(canvas: CanvasItem, id: StringName, bounds: Rect2, rotated: bool = false) -> bool:
	var source: Texture2D = texture(id)
	if source == null:
		return false
	# 原图集中工具边缘留白较多；裁掉透明边缘后，细长工具也能读清。
	if not _icon_cache.has(id):
		var trimmed := AtlasTexture.new()
		trimmed.atlas = source
		trimmed.region = Rect2(source.get_image().get_used_rect())
		_icon_cache[id] = trimmed
	var icon: Texture2D = _icon_cache[id]
	var native: Vector2 = icon.get_size()
	var available := bounds.size - Vector2(8, 8)
	var fit_size := Vector2(native.y, native.x) if rotated else native
	var factor: float = maxf(1.0, floorf(minf(available.x / fit_size.x, available.y / fit_size.y)))
	canvas.draw_set_transform(bounds.get_center().floor(), PI / 2.0 if rotated else 0.0)
	canvas.draw_texture_rect(icon, Rect2(-native * factor / 2.0, native * factor), false, tint(id))
	canvas.draw_set_transform(Vector2.ZERO)
	return true


## 按格子派生变体，绝不调用世界 RNG。耗尽差分只读取现有 remaining 快照。
static func resource_texture(kind: StringName, variant: int, depleted: bool) -> Texture2D:
	if depleted:
		return texture(&"stump") if kind == &"tree" else (texture(&"bush") if kind == &"berry" else null)
	if kind == &"tree":
		return texture([&"pine", &"tree", &"tree_tall"][posmod(variant, 3)])
	if kind == &"stone":
		return texture([&"stone", &"stone_2", &"stone_3"][posmod(variant, 3)])
	if kind == &"spring":
		return texture(&"spring_pool")
	return texture(&"berry_bush" if kind == &"berry" else kind)


## 篝火石圈与八帧火焰组合；秒数由暂停策略下的视图提供，不产生取火效果。
static func draw_campfire(canvas: CanvasItem, foot: Vector2, seconds: float, factor: int = 2) -> void:
	var base: Texture2D = texture(&"campfire")
	canvas.draw_texture_rect(base, Rect2(foot - Vector2(8, 16) * factor, Vector2(16, 16) * factor), false)
	var frame: int = posmod(floori(seconds * 8.0), 8)
	canvas.draw_texture_rect_region(FIRE, Rect2(foot - Vector2(6, 21) * factor, Vector2(12, 12) * factor), Rect2(frame * 12, 0, 12, 12))
