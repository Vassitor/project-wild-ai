class_name WildSurvivalCodec
extends RefCounted
## 生存档案恢复与结构校验。不重置身体、不重做动作、不靠节点恢复运行状态。

static func decode(data: Dictionary, state: WildBaseState, config: WildGameConfig, catalog: WildItemCatalog, actor_states: Dictionary = {}) -> WildSurvivalState:
	var cooperative: bool = not actor_states.is_empty()
	if state.world == null or data.get("outcome","") not in (["running","won","lost"] if cooperative else ["running"]): return null
	for key: String in ["elapsed_seconds","pending_seconds"]:
		if not WildDataValidation.number(data.get(key,null)) or float(data[key]) < 0: return null
	if float(data["elapsed_seconds"]) > config.target_survival_hours*3600 or (not cooperative and float(data["elapsed_seconds"]) >= config.target_survival_hours*3600) or not data.get("segments",null) is Array or not data.get("notice",null) is String: return null
	if not WildWorldGenerator.valid_seed(data.get("random_state",null),true): return null
	for key: String in ["bodies","actions","buildings","outputs","explored","activities"]:
		if not data.get(key,null) is Dictionary: return null
	var run := WildSurvivalState.new()
	run.outcome = data["outcome"]
	run.elapsed_seconds = float(data["elapsed_seconds"])
	run.pending_seconds = float(data["pending_seconds"])
	run.notice = data["notice"]
	run.random_state = data["random_state"]
	var total: float = 0
	for segment: Variant in data["segments"]:
		if not segment is Dictionary or segment.get("activity","") not in ["idle","walk","sprint","work","rest","sleep"] or not WildDataValidation.number(segment.get("seconds",null)) or float(segment["seconds"]) <= 0: return null
		total += float(segment["seconds"])
		run.segments.append(segment.duplicate(true))
	if not is_equal_approx(total,run.pending_seconds): return null
	for actor: Variant in data["bodies"]:
		if not actor is String or not state.world.players.has(actor) or not data["bodies"][actor] is Dictionary: return null
		var raw: Dictionary = data["bodies"][actor]
		var body: WildBodyState = _body(raw)
		if body == null or (not cooperative and body.hp <= 0): return null
		if not WildBodyHealthCodec.restore(raw,body,config.health_rules,state.world.seed_text,actor): return null
		run.bodies[actor] = body
	if not run.bodies.has(state.player_id) or run.bodies.size() != state.world.players.size(): return null
	if not WildProgressionCodec.restore(data.get("progression",null),run,state.world,config): return null
	if cooperative:
		var living: bool = false
		for body: WildBodyState in run.bodies.values():
			if body.hp > 0: living = true
		if run.outcome == "won" and (not living or run.elapsed_seconds < config.target_survival_hours*3600): return null
		if run.outcome == "lost" and living: return null
		if run.outcome == "running" and (not living or run.elapsed_seconds >= config.target_survival_hours*3600): return null
	run.actions = data["actions"].duplicate(true)
	run.buildings = data["buildings"].duplicate(true)
	run.outputs = data["outputs"].duplicate(true)
	run.explored = data["explored"].duplicate(true)
	run.activities = data["activities"].duplicate(true)
	var occupied: Dictionary = {}
	var captured: Dictionary = {}
	for id: Variant in run.buildings:
		var building: Variant = run.buildings[id]
		if not id is String or id.is_empty() or not building is Dictionary or building.get("id","") != id or building.get("kind","") not in (["camp","fire","storage_box","cooking_table","small_trap","large_trap"] if cooperative else ["camp","fire","cooking_table","small_trap","large_trap"]): return null
		for key: String in ["x","y","width","height"]:
			if not WildDataValidation.whole(building.get(key,null)): return null
		var dimensions: Vector2i = WildProgressionCodec.dimensions(building)
		if dimensions == Vector2i.ZERO or building["width"] != dimensions.x or building["height"] != dimensions.y or not building.get("lit",null) is bool or not WildDataValidation.number(building.get("fuel_seconds",null)) or float(building["fuel_seconds"]) < 0 or float(building["fuel_seconds"]) > 43200*maxf(1,config.skill_rules.fuel_multiplier): return null
		if building["kind"] != "fire" and (building["lit"] or building["fuel_seconds"] != 0): return null
		if building["lit"] and building["fuel_seconds"] <= 0: return null
		if not WildProgressionCodec.building_valid(building,run,config,captured): return null
		var rectangle: Rect2i = WildBuildingRules.occupied(building)
		for y: int in range(rectangle.position.y,rectangle.end.y):
			for x: int in range(rectangle.position.x,rectangle.end.x):
				var cell := Vector2i(x,y)
				if not state.world.walkable(cell) or cell == state.world.spawn or occupied.has(cell): return null
				for resource: Dictionary in state.world.resources.values():
					if resource["x"] == x and resource["y"] == y: return null
				occupied[cell] = true
	WildBuildingRules.rebuild_obstacles(state.world,run)
	for point: Vector2 in state.world.players.values():
		if not WildWorldRules.feet_clear(state.world,point): return null
	for actor: Variant in run.actions:
		if not actor is String or not run.bodies.has(actor) or not run.actions[actor] is Dictionary: return null
		var action: Dictionary = run.actions[actor]
		if action.get("type","") not in WildSurvivalActions.TYPES or action.get("activity","") not in ["idle","work","rest","sleep"] or not action.get("parameters",null) is Dictionary or not action.get("reservations",null) is Array: return null
		for key: String in ["duration","remaining","fee","wear","x","y"]:
			if not WildDataValidation.number(action.get(key,null)): return null
		if action["duration"] <= 0 or action["remaining"] <= 0 or action["remaining"] > action["duration"] or action["fee"] < 0 or action["wear"] < 0: return null
		for key: String in ["tool_id","fire_id","resource_id","building_id","item_id"]:
			if not action.get(key,null) is String: return null
		if run.bodies[actor].hp <= 0 or not _action_links_valid(action,actor_states.get(actor,state),run,actor,catalog,cooperative): return null
		if not WildProgressionCodec.action_valid(action,actor_states.get(actor,state),run,actor,catalog): return null
	for output_id: Variant in run.outputs:
		var output: Variant = run.outputs[output_id]
		if not output_id is String or output_id.is_empty() or not output is Dictionary or output.get("id",null) != output_id or not output.get("owner",null) is String or not run.bodies.has(output["owner"]) or not output.get("items",null) is Array or output["items"].is_empty(): return null
		if not WildDataValidation.number(output.get("x",null)) or not WildDataValidation.number(output.get("y",null)) or not state.world.contains(state.world.cell_at(Vector2(output["x"],output["y"]))): return null
		for raw: Variant in output["items"]:
			if not item_record_valid(raw,catalog): return null
	for cell_id: Variant in run.explored:
		if not cell_id is String or run.explored[cell_id] != true: return null
		var parts: PackedStringArray = cell_id.split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return null
		var cell := Vector2i(parts[0].to_int(),parts[1].to_int())
		if not state.world.contains(cell) or state.world.tiles[cell.y*state.world.size.x+cell.x] == WildWorldData.Terrain.WATER: return null
	for actor: Variant in run.activities:
		if not run.bodies.has(actor) or not run.activities[actor] is Array: return null
		var unique: Dictionary = {}
		for kind: Variant in run.activities[actor]:
			if not kind is String or kind not in WildSettlementRules.REWARDED_ACTIVITIES or unique.has(kind): return null
			unique[kind] = true
	return run

static func _body(raw: Dictionary) -> WildBodyState:
	for key: String in ["hp","health","water","stamina","pollution"]:
		if not WildDataValidation.number(raw.get(key,null)) or float(raw[key]) < 0 or float(raw[key]) > 100: return null
	if not WildDataValidation.number(raw.get("starvation_seconds",null)) or float(raw["starvation_seconds"]) < 0 or not raw.get("nutrition",null) is Array or raw["nutrition"].size() != 5 or not raw.get("digestion",null) is Array: return null
	var body := WildBodyState.new()
	body.hp = raw["hp"]
	body.health = raw["health"]
	body.water = raw["water"]
	body.stamina = raw["stamina"]
	body.pollution = raw["pollution"]
	body.starvation_seconds = raw["starvation_seconds"]
	body.nutrition.clear()
	for value: Variant in raw["nutrition"]:
		if not WildDataValidation.number(value) or float(value) < 0 or float(value) > 100: return null
		body.nutrition.append(float(value))
	for task: Variant in raw["digestion"]:
		if not task is Dictionary or not WildDataValidation.number(task.get("remaining_seconds",null)) or task["remaining_seconds"] <= 0 or task["remaining_seconds"] > 600 or not task.get("per_second",null) is Array or task["per_second"].size() != 5: return null
		for rate: Variant in task["per_second"]:
			if not WildDataValidation.number(rate) or float(rate) < 0 or float(rate) > 1: return null
		body.digestion.append(task.duplicate(true))
	return body

static func item_record_valid(raw: Variant, catalog: WildItemCatalog) -> bool:
	if not raw is Dictionary or not raw.get("id",null) is String or not raw.get("item_id",null) is String or not WildDataValidation.whole(raw.get("quantity",null)): return false
	if not WildItemInstance.metadata_valid(raw): return false
	for key: String in ["durability","freshness_hours","water_l"]:
		if not WildDataValidation.number(raw.get(key,null)): return false
	if not raw.get("clean_water",null) is bool or not raw.get("free_supply",null) is bool: return false
	var item: WildItemInstance = WildItemInstance.from_record(raw)
	return item.valid(catalog.find(item.item_id))

static func _action_links_valid(action: Dictionary,state: WildBaseState,run: WildSurvivalState,actor: String,catalog: WildItemCatalog,cooperative: bool = false) -> bool:
	var locked: Dictionary = {}
	for reservation: Variant in action["reservations"]:
		if not reservation is Dictionary or not reservation.get("id",null) is String or not WildDataValidation.whole(reservation.get("quantity",null)) or int(reservation["quantity"]) <= 0 or not reservation.get("fresh",null) is bool: return false
		var entry: Dictionary = WildInventoryOperations.find(state,reservation["id"])
		if entry.is_empty(): return false
		locked[reservation["id"]] = int(locked.get(reservation["id"],0)) + int(reservation["quantity"])
		if locked[reservation["id"]] > (entry["item"] as WildItemInstance).quantity: return false
	for field: String in ["tool_id","item_id"]:
		if not action[field].is_empty() and WildInventoryOperations.find(state,action[field]).is_empty(): return false
	for field: String in ["fire_id","building_id"]:
		if not action[field].is_empty() and not run.buildings.has(action[field]): return false
	if action["type"] == "gather":
		if not state.world.resources.has(action["resource_id"]) or not WildDataValidation.whole(action.get("resource_version",null)): return false
		if not WildWorldRules.interaction(state.world,actor,action["resource_id"],int(action["resource_version"])).successful: return false
	if action["type"] == "build":
		if action.get("recipe","") not in WildProgressionActions.BUILDABLE or (action.get("recipe","") == "storage_box" and not cooperative) or not action.get("site",null) is Dictionary or not WildDataValidation.whole(action["site"].get("x",null)) or not WildDataValidation.whole(action["site"].get("y",null)): return false
	if action["type"] in ["drink","fill"]:
		if not WildDataValidation.number(action.get("litres",null)) or action["litres"] <= 0 or action["litres"] > 1 or not action.get("clean",null) is bool: return false
	if action["type"] == "treat":
		var entry: Dictionary = WildInventoryOperations.find(state,action["item_id"])
		if entry.is_empty() or (entry["item"] as WildItemInstance).item_id not in [&"bandage",&"herbal_medicine"]: return false
		if action["reservations"].size() != 1 or action["reservations"][0]["id"] != action["item_id"] or action["reservations"][0]["quantity"] != 1 or action["reservations"][0]["fresh"] or action["fee"] != 0 or action["activity"] != "idle": return false
	if action.has("output"):
		if not action["output"] is String or catalog.find(StringName(action["output"])) == null or not WildDataValidation.whole(action.get("quantity",null)) or action["quantity"] <= 0 or action["quantity"] > catalog.find(StringName(action["output"])).max_stack: return false
	return true
