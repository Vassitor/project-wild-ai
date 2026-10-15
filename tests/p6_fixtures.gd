extends RefCounted
## P6 隔离夹具：显式布置目标与地形，不向游戏 UI / 网络开放状态写入口。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const P5 = preload("res://tests/p5_fixtures.gd")

static func create(actor: String = "p", players: int = 1) -> WildBaseState:
	var state: WildBaseState = P5.create_state(actor)
	WildCombatWorld.initialize(state,CONFIG,players)
	return state

static func equip(state: WildBaseState, kind: String) -> WildItemInstance:
	var id: String = P5.give(state,kind)
	var entry: Dictionary = WildInventoryOperations.find(state,id)
	var item: WildItemInstance = entry["item"]
	(entry["container"] as WildInventoryContainer).placements.erase(id)
	state.containers["main_hand"].placements.clear()
	state.containers["main_hand"].placements[id] = {"item":item,"position":Vector2i.ZERO,"rotated":false}
	return item

static func area(world: WildWorldData) -> Vector2i:
	for y: int in range(3,world.size.y-7):
		for x: int in range(3,world.size.x-10):
			var cell := Vector2i(x,y)
			if cell.distance_to(world.spawn) < 35: continue
			var valid: bool = true
			for row: int in range(y,y+5):
				for col: int in range(x,x+9):
					if world.tiles[row*world.size.x+col] != WildWorldData.Terrain.FOREST or not world.walkable(Vector2i(col,row)): valid = false
			if valid: return cell+Vector2i(2,2)
	assert(false,"forest test area")
	return Vector2i.ZERO

static func focus(state: WildBaseState, kind: String = "rabbit") -> Dictionary:
	var chosen: Dictionary = {}
	for animal: Dictionary in state.survival.prey.values():
		animal["alive"] = false
		animal["hp"] = 0.0
		animal["mode"] = "dead"
		animal["loot_claimed"] = true
		animal["target"] = ""
		if chosen.is_empty() and animal["kind"] == kind: chosen = animal
	var cell: Vector2i = area(state.world)
	place(chosen,state.world,cell)
	chosen["hp"] = chosen["max_hp"]
	chosen["alive"] = true
	chosen["mode"] = "wander"
	chosen["loot_claimed"] = false
	state.world.players[state.player_id] = WildCombatWorld.position(chosen,state.world)-Vector2(24,0)
	return chosen

static func place(animal: Dictionary, world: WildWorldData, cell: Vector2i) -> void:
	animal["x"] = cell.x
	animal["y"] = cell.y
	animal["px"] = world.centre(cell).x
	animal["py"] = world.centre(cell).y
	animal["home_x"] = cell.x
	animal["home_y"] = cell.y

static func attack(state: WildBaseState, direction: Vector2 = Vector2.RIGHT) -> WildOperationResult:
	return WildCombatRules.attack(state,state.player_id,{"direction":[direction.x,direction.y]},CONFIG,CATALOG)

static func time(state: WildBaseState, seconds: float) -> void:
	P5.time(state,seconds)

static func quantity(state: WildBaseState, kind: String) -> int:
	return P5.quantity(state,kind)
