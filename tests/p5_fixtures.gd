extends RefCounted
## 隔离夹具：布置技能 / 位置 / 确定性随机结果，不给正式 UI 或客户端设置状态入口。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const BASE_FIXTURE = preload("res://tests/p4_fixtures.gd")
static var _world: Dictionary = {}

static func create_state(actor: String = "p") -> WildBaseState:
	if _world.is_empty(): _world = WildWorldGenerator.new(CONFIG).generate("17").payload["world"]
	var result: WildBaseState = BASE_FIXTURE.create_state(CONFIG,actor,_world)
	WildProgressionWorld.initialize(result,CONTENT)
	return result

static func give(state: WildBaseState, kind: String, amount_to_add: int = 1) -> String:
	var definition: WildItemDefinition = CATALOG.find(StringName(kind))
	var id: String = ""
	while amount_to_add > 0:
		var amount: int = mini(amount_to_add,definition.max_stack)
		var item := WildItemInstance.new(definition,amount)
		assert(WildInventoryOperations.insert(state,CATALOG,CONFIG,item),"fixture item must fit: "+kind)
		amount_to_add -= amount
		id = WildInventoryOperations.choose(state,StringName(kind))
	return id

static func quantity(state: WildBaseState, kind: String) -> int:
	var result: int = 0
	for container: WildInventoryContainer in state.containers.values():
		for entry: Dictionary in container.placements.values():
			if str((entry["item"] as WildItemInstance).item_id) == kind: result += (entry["item"] as WildItemInstance).quantity
	for output: Dictionary in state.survival.outputs.values():
		for raw: Dictionary in output["items"]:
			if raw["item_id"] == kind: result += int(raw["quantity"])
	return result

static func time(state: WildBaseState, seconds: float, activity: String = "idle") -> void:
	WildSurvivalSimulation.queue_time(state.survival,seconds,activity)
	WildSurvivalSimulation.process(state,CONFIG,CATALOG,CONTENT,true)

static func start(state: WildBaseState, payload: Dictionary) -> WildOperationResult:
	return WildSurvivalActions.start(state,state.player_id,payload,CONFIG,CATALOG,CONTENT)

static func finish(state: WildBaseState) -> void:
	time(state,state.survival.actions[state.player_id]["remaining"])

static func at_resource(state: WildBaseState, kind: String) -> Dictionary:
	for resource: Dictionary in state.world.resources.values():
		if resource["kind"] == kind and resource["remaining"] > 0:
			state.world.players[state.player_id] = state.world.centre(Vector2i(resource["x"],resource["y"]))
			return resource
	return {}

## 先廉价筛掉资源 / 水面矩形，再只对候选调用真实通路校验。
static func open_site(state: WildBaseState, dimensions: Vector2i, near: Vector2i = Vector2i(-1,-1)) -> Dictionary:
	var occupied: Dictionary = {}
	for resource: Dictionary in state.world.resources.values(): occupied[Vector2i(resource["x"],resource["y"])] = true
	for animal: Dictionary in state.survival.prey.values():
		if animal["alive"]: occupied[Vector2i(animal["x"],animal["y"])] = true
	var min_x: int = 2 if near.x < 0 else maxi(2,near.x-3)
	var min_y: int = 2 if near.y < 0 else maxi(2,near.y-3)
	var max_x: int = state.world.size.x-dimensions.x-1 if near.x < 0 else mini(state.world.size.x-dimensions.x-1,near.x+4)
	var max_y: int = state.world.size.y-dimensions.y-1 if near.y < 0 else mini(state.world.size.y-dimensions.y-1,near.y+4)
	for y: int in range(min_y,max_y):
		for x: int in range(min_x,max_x):
			var free: bool = true
			for row: int in range(y,y+dimensions.y):
				for column: int in range(x,x+dimensions.x):
					var cell := Vector2i(column,row)
					if not state.world.walkable(cell) or occupied.has(cell) or cell == state.world.spawn: free = false
			var point := Vector2i(x-1,y)
			if not free or not state.world.walkable(point): continue
			state.world.players[state.player_id] = state.world.centre(point)
			if WildBuildingRules.can_build(state,state.player_id,Vector2i(x,y),dimensions).successful: return {"x":x,"y":y}
	return {}

static func random_state_for(success: bool, probability: float, attempts: int = 1) -> String:
	for seed_value: int in range(10000):
		var random := RandomNumberGenerator.new()
		random.seed = seed_value
		var original: String = str(random.state)
		var matched: bool = true
		for attempt: int in range(attempts):
			if (random.randf() < probability) != success: matched = false
		if matched: return original
	return ""
