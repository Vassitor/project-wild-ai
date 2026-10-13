class_name WildWorldRules
extends RefCounted
## 世界移动 / 交互权限。输入驱动权威坐标，界面不能提交任意目的位置。


static func feet_clear(world: WildWorldData, position: Vector2) -> bool:
	# 与人物 Feet 碰撞形状一致；边界外和水格都是不可通行地形。
	for corner: Vector2 in [Vector2(-6, 1), Vector2(6, 1), Vector2(-6, 9), Vector2(6, 9)]:
		if not world.walkable(world.cell_at(position + corner)):
			return false
	return true


## 每次最多推进 0.1 秒，位移分步检查，按轴滑动，防止穿水和斜向加速。
static func move(world: WildWorldData, actor: String, direction: Vector2, seconds: float, speed: float) -> Vector2:
	if not world.players.has(actor):
		return Vector2.ZERO
	var position: Vector2 = world.players[actor]
	if not direction.is_finite() or not is_finite(seconds) or seconds <= 0.0 or seconds > 0.1 or not is_finite(speed) or speed <= 0.0:
		return position
	var displacement: Vector2 = direction.limit_length(1.0) * seconds * speed
	var steps: int = maxi(1, ceili(displacement.length() / 4.0))
	var step: Vector2 = displacement / steps
	for index: int in range(steps):
		var next: Vector2 = position + Vector2(step.x, 0)
		if feet_clear(world, next):
			position = next
		next = position + Vector2(0, step.y)
		if feet_clear(world, next):
			position = next
	world.players[actor] = position
	return position


static func interaction(world: WildWorldData, actor: String, id: String, expected_version: int, range_tiles: float = 1.5) -> WildOperationResult:
	if not world.players.has(actor):
		return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	if not world.resources.has(id):
		return WildOperationResult.reject(&"UNKNOWN_RESOURCE")
	var entry: Dictionary = world.resources[id]
	if entry["version"] != expected_version:
		return WildOperationResult.reject(&"STALE_VERSION")
	if entry["remaining"] <= 0:
		return WildOperationResult.reject(&"RESOURCE_EMPTY")
	var cell := Vector2i(entry["x"], entry["y"])
	if world.players[actor].distance_to(world.centre(cell)) > range_tiles * world.tile_pixels:
		return WildOperationResult.reject(&"OUT_OF_REACH")
	# 同时检查短路径，防止隔岸采集；几何接近不代表通行可达。
	var reachable: Dictionary = world.distances(world.cell_at(world.players[actor]), 3)
	if not reachable.has(cell) or int(reachable[cell]) > 3:
		return WildOperationResult.reject(&"OUT_OF_REACH")
	return WildOperationResult.accept(entry.duplicate(true))


## P3 动作完成后的提交原语，调用方必须在候选状态上同时提交物资产出。
## P2 没有直接暴露采集命令；该接口用于验证资源变更的存档恢复。
static func consume(world: WildWorldData, actor: String, id: String, expected_version: int, amount: int) -> WildOperationResult:
	var valid: WildOperationResult = interaction(world, actor, id, expected_version)
	if not valid.successful:
		return valid
	var entry: Dictionary = world.resources[id]
	if entry["kind"] == "spring" or amount <= 0 or amount > int(entry["remaining"]):
		return WildOperationResult.reject(&"INVALID_QUANTITY")
	entry["remaining"] -= amount
	entry["version"] += 1
	world.version += 1
	return WildOperationResult.accept()
