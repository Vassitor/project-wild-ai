class_name WildBuildingRules
extends RefCounted
## 建筑占地与交互规则。建造前防止封死通路；占位由存档中的建筑实体派生。

static func occupied(building: Dictionary) -> Rect2i:
	return Rect2i(Vector2i(building["x"],building["y"]),Vector2i(building["width"],building["height"]))

static func rebuild_obstacles(world: WildWorldData, run: WildSurvivalState) -> void:
	world.blocked_cells.clear()
	for building: Dictionary in run.buildings.values():
		var bounds: Rect2i = occupied(building)
		for y: int in range(bounds.position.y,bounds.end.y):
			for x: int in range(bounds.position.x,bounds.end.x): world.blocked_cells[Vector2i(x,y)] = true

static func in_reach(world: WildWorldData, actor: String, building: Dictionary) -> bool:
	if not world.players.has(actor): return false
	var rectangle := Rect2(Vector2(building["x"],building["y"]) * world.tile_pixels, Vector2(building["width"],building["height"]) * world.tile_pixels)
	var point: Vector2 = world.players[actor]
	var closest := Vector2(clampf(point.x,rectangle.position.x,rectangle.end.x),clampf(point.y,rectangle.position.y,rectangle.end.y))
	if point.distance_to(closest) > world.tile_pixels * 1.5: return false
	var near: Dictionary = world.distances(world.cell_at(point),3)
	for cell: Vector2i in near:
		for direction: Vector2i in WildWorldData.DIRECTIONS:
			if occupied(building).has_point(cell + direction): return true
	return false

static func nearby(state: WildBaseState, actor: String, kind: String, lit: bool = false) -> String:
	for id: String in state.survival.buildings:
		var building: Dictionary = state.survival.buildings[id]
		if building["kind"] == kind and (not lit or building.get("lit",false)) and in_reach(state.world,actor,building): return id
	return ""

static func can_build(state: WildBaseState, actor: String, anchor: Vector2i, dimensions: Vector2i) -> WildOperationResult:
	var world: WildWorldData = state.world
	var area := Rect2i(anchor,dimensions)
	if world.players[actor].distance_to(world.centre(anchor)) > 3 * world.tile_pixels: return WildOperationResult.reject(&"OUT_OF_REACH")
	var cells: Dictionary = {}
	for y: int in range(anchor.y,area.end.y):
		for x: int in range(anchor.x,area.end.x):
			var cell := Vector2i(x,y)
			if not world.walkable(cell) or cell == world.spawn: return WildOperationResult.reject(&"INVALID_BUILD_SITE")
			if state.survival != null:
				for animal: Dictionary in state.survival.prey.values():
					if animal["alive"] and animal["x"] == x and animal["y"] == y: return WildOperationResult.reject(&"INVALID_BUILD_SITE")
			for point: Vector2 in world.players.values():
				if world.cell_at(point) == cell: return WildOperationResult.reject(&"INVALID_BUILD_SITE")
			for resource: Dictionary in world.resources.values():
				if resource["x"] == x and resource["y"] == y: return WildOperationResult.reject(&"INVALID_BUILD_SITE") # 再生点也不能被盖住。
			cells[cell] = true
	# 在副本上暂时封闭新占地，要求原可达区除建筑格外仍全部连通。
	var before: Dictionary = world.distances(world.cell_at(world.players[actor]))
	var test: WildWorldData = world.copy()
	for cell: Vector2i in cells: test.blocked_cells[cell] = true
	var after: Dictionary = test.distances(test.cell_at(test.players[actor]))
	for cell: Vector2i in before:
		if not cells.has(cell) and not after.has(cell): return WildOperationResult.reject(&"BLOCKS_PATH")
	return WildOperationResult.accept({"x":anchor.x,"y":anchor.y})

static func auto_site(state: WildBaseState, actor: String, dimensions: Vector2i) -> WildOperationResult:
	var cell: Vector2i = state.world.cell_at(state.world.players[actor])
	for offset: Vector2i in [Vector2i(1,-1),Vector2i(-dimensions.x,-1),Vector2i(0,-dimensions.y),Vector2i(0,1),Vector2i(1,0),Vector2i(-dimensions.x,0)]:
		var result: WildOperationResult = can_build(state,actor,cell + offset,dimensions)
		if result.successful: return result
	return WildOperationResult.reject(&"INVALID_BUILD_SITE")

## 扩建在副本上打开原占地，再按新矩形检查资源、角色与全区连通。
static func can_expand(state: WildBaseState, actor: String, building: Dictionary, dimensions: Vector2i, config: WildGameConfig) -> WildOperationResult:
	var test: WildBaseState = state.copy(config)
	var old: Rect2i = occupied(building)
	for y: int in range(old.position.y,old.end.y):
		for x: int in range(old.position.x,old.end.x): test.world.blocked_cells.erase(Vector2i(x,y))
	return can_build(test,actor,old.position,dimensions)
