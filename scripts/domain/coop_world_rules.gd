class_name WildCoopWorldRules
extends RefCounted
## 完整合作资源倍率只在出发时应用一次，保存完整结果；断线不重新缩放。
static func food_multiplier(players: int) -> float:
	return 1+0.5*(players-1)

static func counts(players: int) -> Dictionary:
	var result: Dictionary = WildWorldData.RESOURCE_COUNTS.duplicate()
	for kind: String in result:
		if kind in ["fish","spring"]: continue
		result[kind] = ceili(int(result[kind])*(food_multiplier(players) if kind in ["berry","root"] else 1+0.25*(players-1)))
	return result

static func scale(world: WildWorldData, players: int) -> bool:
	if world.resource_players != 1 or players < 2 or players > 4: return false
	var desired: Dictionary = counts(players)
	var occupied: Dictionary = {}
	var current: Dictionary = {}
	for resource: Dictionary in world.resources.values():
		occupied[Vector2i(resource["x"],resource["y"])] = true
		current[resource["kind"]] = int(current.get(resource["kind"],0))+1
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in world.distances(world.spawn):
		if cell != world.spawn and not occupied.has(cell): candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y*world.size.x+a.x < b.y*world.size.x+b.x)
	var random: RandomNumberGenerator = WildWorldGenerator._stream(world.seed_text,"cooperative-resources:%d" % players)
	for kind: String in desired:
		for index: int in range(int(desired[kind])-int(current.get(kind,0))):
			if candidates.is_empty(): return false
			var selected: int = random.randi_range(0,candidates.size()-1)
			var cell: Vector2i = candidates[selected]
			candidates.remove_at(selected)
			var id: String = "%s:%d:%d" % [kind,cell.x,cell.y]
			world.resources[id] = {"id":id,"kind":kind,"x":cell.x,"y":cell.y,"remaining":1,"version":0}
	for resource: Dictionary in world.resources.values():
		if resource["kind"] == "fish": resource["remaining"] = ceili(6*food_multiplier(players))
	world.initial_resources = world.resources.duplicate(true)
	world.resource_players = players
	world.version += 1
	return true
