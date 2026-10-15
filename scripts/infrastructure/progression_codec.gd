class_name WildProgressionCodec
extends RefCounted
## P5 实体、计时与动作链接校验。旧档缺少本字段时保持空状态，首次模拟再初始化。
static func restore(raw: Variant, run: WildSurvivalState, world: WildWorldData, config: WildGameConfig, dynamic: bool = false) -> bool:
	if raw == null: return true
	if not raw is Dictionary or raw.get("version",0) != 1 or not raw.get("initialized",null) is bool: return false
	for field: String in ["prey","fish_refills","fishing_random_states","build_experience_counts"]:
		if not raw.get(field,null) is Dictionary: return false
		if not raw["initialized"] and not raw[field].is_empty(): return false
	run.progression_initialized = raw["initialized"]
	run.prey = raw["prey"].duplicate(true)
	run.fish_refills = raw["fish_refills"].duplicate()
	run.fishing_random_states = raw["fishing_random_states"].duplicate()
	run.build_experience_counts = raw["build_experience_counts"].duplicate(true)
	if run.progression_initialized and ((not dynamic and run.prey.size() != 26) or run.fish_refills.size() != 12): return false
	var positions: Dictionary = {}
	for id: Variant in run.prey:
		var prey: Variant = run.prey[id]
		if not id is String or not prey is Dictionary or prey.get("id",null) != id or prey.get("kind","") not in (["rabbit","boar","wolf"] if dynamic else ["rabbit","boar"]) or not prey.get("alive",null) is bool: return false
		for key: String in ["x","y"]:
			if not WildDataValidation.whole(prey.get(key,null)): return false
		var cell := Vector2i(prey["x"],prey["y"])
		if not world.contains(cell): return false
		if not dynamic and (world.tiles[cell.y*world.size.x+cell.x] != WildWorldData.Terrain.FOREST or positions.has(cell) or cell.distance_to(world.spawn) < 30): return false
		positions[cell] = true
	for id: Variant in run.fish_refills:
		if not id is String or not world.resources.has(id) or world.resources[id]["kind"] != "fish" or not WildDataValidation.number(run.fish_refills[id]) or run.fish_refills[id] < run.elapsed_seconds: return false
	for actor: Variant in run.fishing_random_states:
		if not run.bodies.has(actor) or not WildWorldGenerator.valid_seed(run.fishing_random_states[actor],true): return false
	for actor: Variant in run.build_experience_counts:
		if not run.bodies.has(actor) or not run.build_experience_counts[actor] is Dictionary: return false
		for recipe: Variant in run.build_experience_counts[actor]:
			var count: Variant = run.build_experience_counts[actor][recipe]
			if recipe not in WildProgressionActions.BUILDABLE and recipe not in ["camp_2","camp_3"]: return false
			if not WildDataValidation.whole(count) or count < 0 or count > config.skill_rules.maximum_build_experience_per_recipe: return false
	return true

static func dimensions(building: Dictionary) -> Vector2i:
	match building["kind"]:
		"camp":
			var tier: Variant = building.get("level",1)
			if not WildDataValidation.whole(tier) or tier < 1 or tier > 3: return Vector2i.ZERO
			return Vector2i(int(tier)+1,int(tier)+1)
		"cooking_table": return Vector2i(2,1)
		"large_trap": return Vector2i(2,2)
	return Vector2i.ONE

static func building_valid(building: Dictionary, run: WildSurvivalState, config: WildGameConfig, captured: Dictionary) -> bool:
	var content := WildSurvivalContent.new()
	var stored_materials: Variant = building.get("investment",content.recipe(building["kind"]).get("materials",{}))
	if not stored_materials is Dictionary: return false
	var materials: Dictionary = stored_materials
	for material: Variant in materials:
		if material not in ["wood","stone","fiber","rope","hide"] or not WildDataValidation.whole(materials[material]) or materials[material] < 0 or materials[material] > 1000000: return false
	building["investment"] = materials.duplicate()
	if building["kind"] == "fire":
		for key: String in ["fuel_supplied_seconds","ignition_awarded_fuel"]:
			if building.has(key) and (not WildDataValidation.number(building[key]) or building[key] < 0): return false
		building["fuel_supplied_seconds"] = building.get("fuel_supplied_seconds",building["fuel_seconds"])
		building["ignition_awarded_fuel"] = building.get("ignition_awarded_fuel",building["fuel_seconds"] if building["lit"] else 0.0)
		if building["fuel_supplied_seconds"] < building["fuel_seconds"] or building["ignition_awarded_fuel"] > building["fuel_supplied_seconds"]: return false
	if building["kind"] not in ["small_trap","large_trap"]: return true
	if not run.progression_initialized or not run.bodies.has(building.get("owner","")) or not WildWorldGenerator.valid_seed(building.get("trap_random_state",null),true) or not building.get("capture",null) is Dictionary: return false
	for key: String in ["bait","uses_left"]:
		if not WildDataValidation.whole(building.get(key,null)) or building[key] < 0 or building[key] > 3: return false
	if not WildDataValidation.number(building.get("next_check",null)) or building["next_check"] < run.elapsed_seconds or not WildDataValidation.number(building.get("probability_bonus",null)) or building["probability_bonus"] < 0 or building["probability_bonus"] > config.skill_rules.trap_success_bonus: return false
	var capture: Dictionary = building["capture"]
	if not capture.is_empty():
		var id: Variant = capture.get("prey_id",null)
		if not id is String or not run.prey.has(id) or run.prey[id]["alive"] or captured.has(id) or capture.get("kind",null) != run.prey[id]["kind"] or capture["kind"] != ("rabbit" if building["kind"] == "small_trap" else "boar"): return false
		if not WildDataValidation.number(capture.get("captured_at",null)) or capture["captured_at"] < 0 or capture["captured_at"] > run.elapsed_seconds: return false
		captured[id] = true
	return true

static func action_valid(action: Dictionary, state: WildBaseState, run: WildSurvivalState, _actor: String, _catalog: WildItemCatalog) -> bool:
	var kind: String = action["type"]
	var content := WildSurvivalContent.new()
	if kind == "fish":
		if not state.world.resources.has(action["resource_id"]) or state.world.resources[action["resource_id"]]["kind"] != "fish" or not WildDataValidation.whole(action.get("attempts",null)) or action["attempts"] not in [1,2] or action.get("bait_definition","") not in ["berry","fiber"]: return false
		var tool: Dictionary = WildInventoryOperations.find(state,action["tool_id"])
		if tool.is_empty() or (tool["item"] as WildItemInstance).item_id != &"fishing_kit" or not action["reservations"].is_empty(): return false
	if kind in ["craft","upgrade"]:
		if not action.get("recipe",null) is String: return false
		var recipe: Dictionary = content.recipe(action.get("recipe",""))
		if recipe.is_empty(): return false
		if kind == "craft":
			if not recipe.has("output") or action.get("output",null) != recipe["output"] or action.get("quantity",0) != recipe.get("quantity",1): return false
		else:
			if action.get("recipe","") not in ["camp_2","camp_3"] or not WildDataValidation.whole(action.get("upgrade_from",null)) or not run.buildings.has(action["building_id"]) or run.buildings[action["building_id"]]["kind"] != "camp": return false
			if not action.get("site",null) is Dictionary or not WildDataValidation.whole(action["site"].get("x",null)) or not WildDataValidation.whole(action["site"].get("y",null)): return false
			var building: Dictionary = run.buildings[action["building_id"]]
			if action["upgrade_from"] != building.get("level",1) or action["recipe"] != "camp_%d" % (int(action["upgrade_from"])+1) or action["site"]["x"] != building["x"] or action["site"]["y"] != building["y"]: return false
		if recipe.get("fire",false) and (action["fire_id"].is_empty() or run.buildings[action["fire_id"]]["kind"] != "fire"): return false
		if recipe.get("table",false) and (not run.buildings.has(action.get("table_id","")) or run.buildings[action["table_id"]]["kind"] != "cooking_table"): return false
		if recipe.get("water_l",0) > 0:
			var water: Dictionary = WildInventoryOperations.find(state,action.get("water_item_id",""))
			if water.is_empty() or (water["item"] as WildItemInstance).item_id != &"bottle" or not WildDataValidation.number(action.get("water_l",null)) or action["water_l"] != recipe["water_l"]: return false
	if kind in ["trap_bait","trap_collect","trap_maintain"]:
		if not run.buildings.has(action["building_id"]) or run.buildings[action["building_id"]]["kind"] not in ["small_trap","large_trap"]: return false
		if kind == "trap_collect" and action.get("capture_id","") != run.buildings[action["building_id"]]["capture"].get("prey_id",null): return false
		if kind == "trap_bait" and (not WildDataValidation.whole(action.get("bait_quantity",null)) or action["bait_quantity"] not in [1,2,3]): return false
	if action.has("fuel_added_seconds") and (not WildDataValidation.number(action["fuel_added_seconds"]) or action["fuel_added_seconds"] <= 0): return false
	if kind in ["craft","upgrade","build","trap_bait","trap_maintain"]:
		var expected: Dictionary = {}
		if kind in ["craft","upgrade","build"]: expected = content.recipe(action["recipe"])["materials"].duplicate()
		elif kind == "trap_bait": expected = {"berry":int(action["bait_quantity"])}
		else: expected = {"fiber":2}
		var actual: Dictionary = {}
		for reservation: Dictionary in action["reservations"]:
			var item: WildItemInstance = WildInventoryOperations.find(state,reservation["id"])["item"]
			actual[str(item.item_id)] = int(actual.get(str(item.item_id),0))+int(reservation["quantity"])
		if action.get("recipe","") == "stew":
			if actual.get("raw_fish",0) == 1 and not actual.has("raw_meat"): expected["raw_fish"] = 1
			elif actual.get("raw_meat",0) == 1 and not actual.has("raw_fish"): expected["raw_meat"] = 1
			else: return false
		if expected.size() != actual.size(): return false
		for definition: String in expected:
			if expected[definition] != actual.get(definition,0): return false
	return true
