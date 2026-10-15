class_name WildWorldData
extends RefCounted
## 有限世界的权威数据；不保存节点、纹理或 peer ID。地形与资源初始快照独立保留。

enum Terrain { FOREST, GRASS, WATER }
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const RESOURCE_COUNTS: Dictionary = {"tree": 180, "stone": 100, "berry": 40, "root": 40, "fiber": 60, "herb": 24, "branch": 60, "fish": 12, "spring": 3}
const RESOURCE_YIELDS: Dictionary = {"stone": ["stone", 3], "berry": ["berry", 3], "root": ["root", 3], "fiber": ["fiber", 5], "herb": ["herb", 2], "branch": ["wood", 1]}

var generator_version: int = 1
var seed_text: String
var size := Vector2i(128, 128)
var tile_pixels: int = 32
var tiles := PackedByteArray()
var initial_tiles := PackedByteArray()
var spawn := Vector2i.ZERO
var resources: Dictionary = {}
var initial_resources: Dictionary = {}
var players: Dictionary[String, Vector2] = {}
var rng_states: Dictionary = {}
var version: int = 0
var attempts: int = 0
var used_fallback: bool = false
var blocked_cells: Dictionary = {} # 运行派生的建筑占位，不改地形初始快照。
var resource_players: int = 1 # 1 为单机 / 旧验证地图；完整合作出发时固定。


func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func walkable(cell: Vector2i) -> bool:
	return contains(cell) and tiles[cell.y * size.x + cell.x] != Terrain.WATER and not blocked_cells.has(cell)


func centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * tile_pixels


func cell_at(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / tile_pixels), floori(position.y / tile_pixels))


## 四邻接最短路径；用于连通性和出生资源校验，不把直线距离当作可达距离。
func distances(start: Vector2i, limit: int = -1) -> Dictionary:
	var result: Dictionary = {}
	if not walkable(start):
		return result
	var queue: Array[Vector2i] = [start]
	result[start] = 0
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		var distance: int = result[cell]
		if limit >= 0 and distance >= limit:
			continue
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = cell + direction
			if walkable(next) and not result.has(next):
				result[next] = distance + 1
				queue.append(next)
	return result


func largest_component() -> Array[Vector2i]:
	var visited: Dictionary = {}
	var largest: Array[Vector2i] = []
	for y: int in range(size.y):
		for x: int in range(size.x):
			var cell := Vector2i(x, y)
			if not walkable(cell) or visited.has(cell):
				continue
			var component: Dictionary = distances(cell)
			for point: Vector2i in component:
				visited[point] = true
			if component.size() > largest.size():
				largest.assign(component.keys())
	return largest


func has_water_neighbor(cell: Vector2i) -> bool:
	for direction: Vector2i in DIRECTIONS:
		var next: Vector2i = cell + direction
		if contains(next) and tiles[next.y * size.x + next.x] == Terrain.WATER:
			return true
	return false


func copy() -> WildWorldData:
	var other := WildWorldData.new()
	other.generator_version = generator_version
	other.seed_text = seed_text
	other.size = size
	other.tile_pixels = tile_pixels
	other.tiles = tiles.duplicate()
	other.initial_tiles = initial_tiles.duplicate()
	other.spawn = spawn
	other.resources = resources.duplicate(true)
	other.initial_resources = initial_resources.duplicate(true)
	other.players.assign(players)
	other.rng_states = rng_states.duplicate(true)
	other.version = version
	other.attempts = attempts
	other.used_fallback = used_fallback
	other.blocked_cells = blocked_cells.duplicate()
	other.resource_players = resource_players
	return other


## 地形按行编码，仍保存每一格；种子 / RNG 状态用字符串避免 JSON 大整数失真。
func record() -> Dictionary:
	var raw: Dictionary = _record()
	raw["resource_players"] = resource_players
	return raw

func _record() -> Dictionary:
	var positions: Dictionary = {}
	for actor: String in players:
		positions[actor] = [players[actor].x, players[actor].y]
	return {"generator_version": generator_version, "seed": seed_text, "size": [size.x, size.y], "tile_pixels": tile_pixels, "tiles": _rows(tiles), "initial_tiles": _rows(initial_tiles), "spawn": [spawn.x, spawn.y], "resources": resources.duplicate(true), "initial_resources": initial_resources.duplicate(true), "players": positions, "rng_states": rng_states.duplicate(true), "version": version, "attempts": attempts, "fallback": used_fallback}


func _rows(values: PackedByteArray) -> Array[String]:
	var rows: Array[String] = []
	for y: int in range(size.y):
		var row: String = ""
		for x: int in range(size.x):
			row += str(values[y * size.x + x])
		rows.append(row)
	return rows
