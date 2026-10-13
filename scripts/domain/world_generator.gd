class_name WildWorldGenerator
extends RefCounted
## 版本 1 生成器：连续噪声分位数控制比例，四邻接检查，独立随机流，有限重试。
## 固定安全模板不依赖噪声或本次种子；所有路径仍经过同一出生与资源校验。

var _config: WildGameConfig


func _init(config: WildGameConfig) -> void:
	_config = config


static func valid_seed(value: Variant, signed: bool = false) -> bool:
	if not value is String or value.is_empty():
		return false
	var digits: String = value
	var maximum: String = "9223372036854775807"
	if signed and digits.begins_with("-"):
		digits = digits.substr(1)
		maximum = "9223372036854775808"
	if digits.is_empty() or digits.length() > 19 or (digits.length() > 1 and digits.begins_with("0")):
		return false
	for character: String in digits:
		if character < "0" or character > "9":
			return false
	return digits.length() < 19 or digits <= maximum


static func random_seed() -> String:
	var random := RandomNumberGenerator.new()
	random.randomize()
	return str(random.randi_range(1, 2147483647))


## 结果包含完整地图记录，而非场景；应用服务在保存成功后才正式切换世界。
func generate(seed_text: String, force_fallback: bool = false) -> WildOperationResult:
	if not valid_seed(seed_text) or _config.wilderness_grid.x < 64 or _config.wilderness_grid.y < 64:
		return WildOperationResult.reject(&"INVALID_SEED")
	for attempt: int in range(1, _config.generation_max_attempts + 1):
		if force_fallback:
			continue
		var world: WildWorldData = _terrain(seed_text, attempt)
		if _populate(world, seed_text + ":" + str(attempt)):
			world.attempts = attempt
			return WildOperationResult.accept({"world": world.record()})
	var fallback: WildWorldData = _safe_template(seed_text)
	if not _populate(fallback, "safe-template-v1"):
		return WildOperationResult.reject(&"GENERATION_FAILED")
	fallback.attempts = _config.generation_max_attempts
	fallback.used_fallback = true
	return WildOperationResult.accept({"world": fallback.record()})


func _new_world(seed_text: String) -> WildWorldData:
	var world := WildWorldData.new()
	world.size = _config.wilderness_grid
	world.tile_pixels = _config.terrain_tile_pixels
	world.generator_version = _config.generator_version
	world.seed_text = seed_text
	world.tiles.resize(world.size.x * world.size.y)
	return world


func _terrain(seed_text: String, attempt: int) -> WildWorldData:
	var world: WildWorldData = _new_world(seed_text)
	var terrain_random: RandomNumberGenerator = _stream(seed_text + ":" + str(attempt), "terrain")
	var noise := FastNoiseLite.new()
	noise.seed = terrain_random.randi_range(0, 2147483647)
	noise.frequency = _config.terrain_noise_frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3
	var ranked: Array[Vector2] = []
	for y: int in range(world.size.y):
		for x: int in range(world.size.x):
			ranked.append(Vector2(noise.get_noise_2d(x, y), y * world.size.x + x))
	# 噪声相等时按格索引排序，使排序结果不依赖不稳定的并列顺序。
	ranked.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x if a.x != b.x else a.y < b.y)
	var count: int = ranked.size()
	for rank: int in range(count):
		world.tiles[int(ranked[rank].y)] = WildWorldData.Terrain.WATER if rank < int(count * 0.2) else (WildWorldData.Terrain.GRASS if rank < int(count * 0.5) else WildWorldData.Terrain.FOREST)
	world.rng_states["terrain"] = str(terrain_random.state)
	return world


func _safe_template(seed_text: String) -> WildWorldData:
	var world: WildWorldData = _new_world(seed_text)
	for y: int in range(world.size.y):
		for x: int in range(world.size.x):
			var fraction: float = float(x) / world.size.x
			world.tiles[y * world.size.x + x] = WildWorldData.Terrain.WATER if fraction < 0.2 else (WildWorldData.Terrain.GRASS if fraction < 0.5 else WildWorldData.Terrain.FOREST)
	world.rng_states["terrain"] = str(_stream("safe-template-v1", "terrain").state)
	return world


func _populate(world: WildWorldData, stream_key: String) -> bool:
	var component: Array[Vector2i] = world.largest_component()
	var land_count: int = 0
	for terrain: int in world.tiles:
		if terrain != WildWorldData.Terrain.WATER:
			land_count += 1
	if component.size() < land_count * _config.minimum_connected_land_ratio:
		return false
	var spawn_random: RandomNumberGenerator = _stream(stream_key, "spawn")
	# 按稳定格序排列后再洗牌，避免依赖 Dictionary 实现的遍历细节。
	component.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * world.size.x + a.x < b.y * world.size.x + b.x)
	_shuffle(component, spawn_random)
	var found: bool = false
	for cell: Vector2i in component:
		if cell.x < 8 or cell.y < 8 or cell.x >= world.size.x - 8 or cell.y >= world.size.y - 8:
			continue
		if world.distances(cell, 4).size() >= 35:
			world.spawn = cell
			found = true
			break
	if not found:
		return false
	var random: RandomNumberGenerator = _stream(stream_key, "resources")
	var reachable: Dictionary = world.distances(world.spawn)
	var nearby: Array[Vector2i] = []
	var food_cells: Array[Vector2i] = []
	var branch_cells: Array[Vector2i] = []
	var shore: Array[Vector2i] = []
	for cell: Vector2i in component:
		if cell == world.spawn:
			continue
		var distance: int = reachable[cell]
		if distance <= _config.spawn_water_path_tiles:
			nearby.append(cell)
		if distance <= _config.spawn_food_path_tiles:
			food_cells.append(cell)
		if distance <= _config.spawn_wood_path_tiles:
			branch_cells.append(cell)
		if world.has_water_neighbor(cell):
			shore.append(cell)
	_shuffle(nearby, random)
	_shuffle(food_cells, random)
	_shuffle(branch_cells, random)
	_shuffle(shore, random)
	var occupied: Dictionary = {world.spawn: true}
	if not _reserve(world, "spring", 1, nearby, occupied) or not _reserve(world, "berry", 2, food_cells, occupied) or not _reserve(world, "root", 1, food_cells, occupied) or not _reserve(world, "branch", 4, branch_cells, occupied):
		return false
	_shuffle(component, random)
	for kind: String in WildWorldData.RESOURCE_COUNTS:
		var present: int = 0
		for entry: Dictionary in world.resources.values():
			if entry["kind"] == kind:
				present += 1
		if not _reserve(world, kind, WildWorldData.RESOURCE_COUNTS[kind] - present, shore if kind == "fish" else component, occupied):
			return false
	world.rng_states["spawn"] = str(spawn_random.state)
	world.rng_states["resources"] = str(random.state)
	world.initial_tiles = world.tiles.duplicate()
	world.initial_resources = world.resources.duplicate(true)
	return true


func _reserve(world: WildWorldData, kind: String, amount: int, cells: Array[Vector2i], occupied: Dictionary) -> bool:
	var count: int = 0
	for cell: Vector2i in cells:
		if count >= amount:
			return true
		if occupied.has(cell):
			continue
		var id: String = "%s:%d:%d" % [kind, cell.x, cell.y]
		var stock: int = 6 if kind == "fish" else 1
		world.resources[id] = {"id": id, "kind": kind, "x": cell.x, "y": cell.y, "remaining": stock, "version": 0}
		occupied[cell] = true
		count += 1
	return count == amount


## SHA-256 的前 60 位作为独立流种子，避免大整数转浮点或不稳定的全局 RNG。
static func _stream(key: String, purpose: String) -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = (key + ":" + purpose).sha256_text().substr(0, 15).hex_to_int()
	return random


static func _shuffle(values: Array[Vector2i], random: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = random.randi_range(0, index)
		var value: Vector2i = values[index]
		values[index] = values[other]
		values[other] = value
