class_name WildWorldCodec
extends RefCounted
## 完整地图档案解码器。只读取保存的地形 / 实体，不调用生成器重建世界。


static func decode(data: Dictionary, config: WildGameConfig) -> WildWorldData:
	if data.get("generator_version", 0) != config.generator_version or not WildWorldGenerator.valid_seed(data.get("seed", null)):
		return null
	var dimensions: Variant = data.get("size", null)
	# JSON 将整数读为 float；Array 的严格比较不会认为 [128.0] 等于 [128]。
	if not dimensions is Array or dimensions.size() != 2 or not WildDataValidation.whole(dimensions[0]) or not WildDataValidation.whole(dimensions[1]):
		return null
	if int(dimensions[0]) != config.wilderness_grid.x or int(dimensions[1]) != config.wilderness_grid.y or data.get("tile_pixels", 0) != config.terrain_tile_pixels:
		return null
	for field: String in ["version", "attempts"]:
		if not WildDataValidation.whole(data.get(field, -1)) or float(data[field]) < 0:
			return null
	if int(data["attempts"]) < 1 or int(data["attempts"]) > config.generation_max_attempts or not data.get("fallback", null) is bool:
		return null
	var world := WildWorldData.new()
	world.size = config.wilderness_grid
	world.tile_pixels = config.terrain_tile_pixels
	world.generator_version = config.generator_version
	world.seed_text = data["seed"]
	world.tiles = _decode_rows(data.get("tiles", null), world.size)
	world.initial_tiles = _decode_rows(data.get("initial_tiles", null), world.size)
	if world.tiles.is_empty() or world.initial_tiles.is_empty() or world.tiles != world.initial_tiles:
		return null # P2 不修改地形；未来建筑占位保存为独立实体。
	var spawn: Variant = data.get("spawn", null)
	if not spawn is Array or spawn.size() != 2 or not WildDataValidation.whole(spawn[0]) or not WildDataValidation.whole(spawn[1]):
		return null
	world.spawn = Vector2i(int(spawn[0]), int(spawn[1]))
	if not WildWorldRules.feet_clear(world, world.centre(world.spawn)):
		return null
	if not data.get("resources", null) is Dictionary or not data.get("initial_resources", null) is Dictionary or not data.get("players", null) is Dictionary or not data.get("rng_states", null) is Dictionary:
		return null
	world.resources = data["resources"].duplicate(true)
	world.initial_resources = data["initial_resources"].duplicate(true)
	world.rng_states = data["rng_states"].duplicate(true)
	if world.rng_states.size() != 3:
		return null
	for stream: String in ["terrain", "resources", "spawn"]:
		if not WildWorldGenerator.valid_seed(world.rng_states.get(stream, null), true):
			return null
	if not _resources_valid(world, config):
		return null
	var players: Dictionary = data["players"]
	if players.is_empty() or players.size() > config.maximum_cooperative_players:
		return null
	for actor: Variant in players:
		var position: Variant = players[actor]
		if not actor is String or actor.is_empty() or not position is Array or position.size() != 2 or not WildDataValidation.number(position[0]) or not WildDataValidation.number(position[1]):
			return null
		var point := Vector2(float(position[0]), float(position[1]))
		if not WildWorldRules.feet_clear(world, point):
			return null
		world.players[actor] = point
	world.version = int(data["version"])
	world.attempts = int(data["attempts"])
	world.used_fallback = data["fallback"]
	return world


static func _decode_rows(value: Variant, size: Vector2i) -> PackedByteArray:
	var result := PackedByteArray()
	if not value is Array or value.size() != size.y:
		return result
	for row: Variant in value:
		if not row is String or row.length() != size.x:
			return PackedByteArray()
		for cell: String in row:
			if cell not in ["0", "1", "2"]:
				return PackedByteArray()
			result.append(int(cell))
	return result


static func _resources_valid(world: WildWorldData, config: WildGameConfig) -> bool:
	var counts: Dictionary = {}
	var occupied: Dictionary = {}
	var near: Dictionary = world.distances(world.spawn, config.spawn_water_path_tiles)
	var food: int = 0
	var berries: int = 0
	var roots: int = 0
	var branches: int = 0
	var water: int = 0
	if world.resources.size() != world.initial_resources.size():
		return false
	for id: Variant in world.initial_resources:
		var initial: Variant = world.initial_resources[id]
		var current: Variant = world.resources.get(id)
		if not id is String or not initial is Dictionary or not current is Dictionary:
			return false
		var kind: Variant = initial.get("kind", null)
		if not kind is String or not WildWorldData.RESOURCE_COUNTS.has(kind) or initial.get("id", "") != id or current.get("id", "") != id or current.get("kind", "") != kind:
			return false
		for field: String in ["x", "y", "remaining", "version"]:
			if not WildDataValidation.whole(initial.get(field, null)) or not WildDataValidation.whole(current.get(field, null)):
				return false
		var cell := Vector2i(int(initial["x"]), int(initial["y"]))
		if current.has("regrow_at") and (not WildDataValidation.number(current["regrow_at"]) or current["regrow_at"] < 0 or kind not in ["berry","root"] or current["remaining"] != 0): return false
		var stock: int = 6 if kind == "fish" else 1
		if not world.walkable(cell) or cell == world.spawn or occupied.has(cell) or current["x"] != initial["x"] or current["y"] != initial["y"] or initial["remaining"] != stock or initial["version"] != 0 or current["remaining"] < 0 or current["remaining"] > stock or current["version"] < 0:
			return false
		if id != "%s:%d:%d" % [kind, cell.x, cell.y] or (kind == "fish" and not world.has_water_neighbor(cell)):
			return false
		occupied[cell] = true
		counts[kind] = int(counts.get(kind, 0)) + 1
		var distance: int = near.get(cell, 999999)
		if distance <= config.spawn_food_path_tiles and kind in ["berry", "root"]:
			food += 1
			berries += 1 if kind == "berry" else 0
			roots += 1 if kind == "root" else 0
		if distance <= config.spawn_wood_path_tiles and kind == "branch":
			branches += 1
		if distance <= config.spawn_water_path_tiles and kind == "spring":
			water += 1
	if counts != WildWorldData.RESOURCE_COUNTS or food < 3 or berries < 1 or roots < 1 or branches < 4 or water < 1:
		return false
	var terrain_counts: Array[int] = [0, 0, 0]
	for terrain: int in world.tiles:
		terrain_counts[terrain] += 1
	var total: float = world.tiles.size()
	if absf(terrain_counts[0] / total - 0.5) > 0.05 or absf(terrain_counts[1] / total - 0.3) > 0.05 or absf(terrain_counts[2] / total - 0.2) > 0.05:
		return false
	var reachable: Dictionary = world.distances(world.spawn)
	if reachable.size() < (terrain_counts[0] + terrain_counts[1]) * config.minimum_connected_land_ratio:
		return false
	for cell: Vector2i in occupied:
		if not reachable.has(cell):
			return false
	return true
