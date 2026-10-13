class_name WildProgressionActions
extends RefCounted
## P5 动作条件与交付。调用方统一扣体力、保存 / 回滚和完成材料提交。
const TYPES: Array[String] = ["fish","craft","upgrade","trap_bait","trap_collect","trap_maintain","demolish"]
const BUILDABLE: Array[String] = ["camp","fire","storage_box","cooking_table","small_trap","large_trap"]

static func recipe_allowed(state: WildBaseState, recipe: Dictionary) -> WildOperationResult:
	if recipe.has("skill") and WildSkillRules.level(state.skills,recipe["skill"]) < int(recipe["tier"]): return WildOperationResult.reject(&"SKILL_REQUIRED")
	return WildOperationResult.accept()

static func reserve_recipe(state: WildBaseState, recipe: Dictionary, catalog: WildItemCatalog, action: Dictionary) -> WildOperationResult:
	var materials: Dictionary = recipe["materials"].duplicate()
	if action.get("recipe","") == "stew":
		var fish: WildOperationResult = WildInventoryOperations.reserve(state,{"raw_fish":1},true)
		materials["raw_fish" if fish.successful else "raw_meat"] = 1
	var values: Array[Dictionary] = []
	for material: String in materials:
		var fresh: bool = catalog.find(StringName(material)).shelf_life_hours >= 0
		var result: WildOperationResult = WildInventoryOperations.reserve(state,{material:materials[material]},fresh)
		if not result.successful: return result
		values.append_array(result.payload["reservations"])
	action["reservations"] = values
	action["materials"] = materials
	return WildOperationResult.accept()

## 为当前动作检查新增有效陷阱名额；其他人的建造 / 报废修复预留也计入，排除自身预留。
static func trap_limit(run: WildSurvivalState, maximum: int, actor: String) -> bool:
	var total: int = 0
	for building: Dictionary in run.buildings.values():
		if building["kind"] in ["small_trap","large_trap"] and building.get("uses_left",0) > 0: total += 1
	for other: String in run.actions:
		if other == actor: continue
		var pending: Dictionary = run.actions[other]
		if pending.get("recipe","") in ["small_trap","large_trap"]: total += 1
		# 修复耗尽的陷阱也占一个有效名额，避免多人同时修复突破上限。
		elif pending.get("type","") == "trap_maintain" and run.buildings.get(pending.get("building_id",""),{}).get("uses_left",0) == 0: total += 1
	return total < maximum

## 检查领域条件并填入动作草案（游戏秒、体力与预留）；此处不交付物资或持久化。
static func prepare(state: WildBaseState, actor: String, data: Dictionary, action: Dictionary, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent) -> WildOperationResult:
	var kind: String = action["type"]
	var run: WildSurvivalState = state.survival
	if kind == "fish":
		if not WildDataValidation.whole(data.get("version",null)) or not data.get("double",false) is bool: return WildOperationResult.reject(&"INVALID_REQUEST")
		var valid: WildOperationResult = WildWorldRules.interaction(state.world,actor,str(data.get("resource_id","")),int(data["version"]))
		if not valid.successful: return valid
		if valid.payload["kind"] != "fish": return WildOperationResult.reject(&"UNKNOWN_RESOURCE")
		var attempts: int = 2 if data.get("double",false) else 1
		if attempts == 2 and WildSkillRules.level(state.skills,"fishing") < 2: return WildOperationResult.reject(&"SKILL_REQUIRED")
		if valid.payload["remaining"] < attempts: return WildOperationResult.reject(&"INSUFFICIENT_FISH")
		action["tool_id"] = WildInventoryOperations.choose(state,&"fishing_kit",1)
		if action["tool_id"].is_empty(): return WildOperationResult.reject(&"MISSING_FISHING_KIT")
		var bait: Variant = data.get("bait","berry")
		if not bait is String or bait not in ["berry","fiber"]: return WildOperationResult.reject(&"INVALID_BAIT")
		var reserved: WildOperationResult = WildInventoryOperations.reserve(state,{bait:attempts})
		if not reserved.successful: return reserved
		action["start_consumptions"] = reserved.payload["reservations"]
		action["bait_definition"] = bait
		action["attempts"] = attempts
		action["duration"] = content.fishing_minutes*60*(config.skill_rules.fishing_duration_multiplier if WildSkillRules.level(state.skills,"fishing") >= 3 else 1.0)
		action["fee"] = content.fishing_stamina
		action["wear"] = 1.0
		action["resource_id"] = valid.payload["id"]
		action["resource_version"] = valid.payload["version"]
		return WildOperationResult.accept()
	if kind in ["craft","upgrade"]:
		var recipe_id: String = str(data.get("recipe",""))
		if kind == "upgrade":
			var upgrade_camp: Dictionary = run.buildings.get(str(data.get("building_id","")),{})
			if upgrade_camp.is_empty() or upgrade_camp["kind"] != "camp" or not WildBuildingRules.in_reach(state.world,actor,upgrade_camp): return WildOperationResult.reject(&"MISSING_CAMP")
			var next_tier: int = int(upgrade_camp.get("level",1)) + 1
			if next_tier > 3: return WildOperationResult.reject(&"CAMP_MAX_LEVEL")
			recipe_id = "camp_%d" % next_tier
			action["building_id"] = upgrade_camp["id"]
			action["upgrade_from"] = next_tier-1
		var recipe: Dictionary = content.recipe(recipe_id)
		if recipe.is_empty() or (kind == "craft" and not recipe.has("output")): return WildOperationResult.reject(&"ACTION_UNAVAILABLE")
		var allowed: WildOperationResult = recipe_allowed(state,recipe)
		if not allowed.successful: return allowed
		action["recipe"] = recipe_id
		if kind == "upgrade":
			var current_camp: Dictionary = run.buildings[action["building_id"]]
			var site: WildOperationResult = WildBuildingRules.can_expand(state,actor,current_camp,Vector2i(recipe["width"],recipe["height"]),config)
			if not site.successful: return site
			action["site"] = site.payload
		if recipe.get("fire",false):
			action["fire_id"] = WildBuildingRules.nearby(state,actor,"fire",true)
			if action["fire_id"].is_empty(): return WildOperationResult.reject(&"MISSING_FIRE")
		if recipe.get("table",false):
			action["table_id"] = WildBuildingRules.nearby(state,actor,"cooking_table")
			if action["table_id"].is_empty(): return WildOperationResult.reject(&"MISSING_COOKING_TABLE")
		if recipe.get("water_l",0) > 0:
			var entry: Dictionary = clean_water_bottle(state,float(recipe["water_l"]))
			if entry.is_empty() or not (entry["item"] as WildItemInstance).clean_water or (entry["item"] as WildItemInstance).water_l < recipe["water_l"]: return WildOperationResult.reject(&"CLEAN_WATER_REQUIRED")
			action["water_item_id"] = (entry["item"] as WildItemInstance).instance_id
			action["water_l"] = float(recipe["water_l"])
		var reserved: WildOperationResult = reserve_recipe(state,recipe,catalog,action)
		if not reserved.successful: return reserved
		action["duration"] = recipe["minutes"]*60
		action["fee"] = recipe["stamina"]
		if recipe.has("output"):
			action["output"] = recipe["output"]
			action["quantity"] = recipe.get("quantity",1)
		return WildOperationResult.accept()
	var id: String = str(data.get("building_id",""))
	var building: Dictionary = run.buildings.get(id,{})
	if building.is_empty() or not WildBuildingRules.in_reach(state.world,actor,building): return WildOperationResult.reject(&"OUT_OF_REACH")
	action["building_id"] = id
	if kind == "demolish":
		if building["kind"] == "storage_box" and not data.get("checked_empty_box",false): return WildOperationResult.reject(&"BOX_NOT_EMPTY")
		if building.get("capture",{}).size() > 0: return WildOperationResult.reject(&"TRAP_OCCUPIED")
		action["duration"] = 900.0
		action["fee"] = 5.0
		return WildOperationResult.accept()
	if building["kind"] not in ["small_trap","large_trap"]: return WildOperationResult.reject(&"NOT_TRAP")
	var tier: int = 1 if building["kind"] == "small_trap" else 2
	if WildSkillRules.level(state.skills,"trap") < tier: return WildOperationResult.reject(&"SKILL_REQUIRED")
	if kind == "trap_collect":
		if building["capture"].is_empty(): return WildOperationResult.reject(&"TRAP_EMPTY")
		action["capture_id"] = building["capture"]["prey_id"]
		action["duration"] = 300.0
		action["fee"] = 2.0
	elif kind == "trap_bait":
		if not WildDataValidation.whole(data.get("quantity",1)) or int(data.get("quantity",1)) not in [1,2,3]: return WildOperationResult.reject(&"INVALID_QUANTITY")
		if building["uses_left"] <= 0 or not building["capture"].is_empty() or building["bait"]+int(data.get("quantity",1)) > 3: return WildOperationResult.reject(&"TRAP_NOT_READY")
		var reserved: WildOperationResult = WildInventoryOperations.reserve(state,{"berry":int(data.get("quantity",1))})
		if not reserved.successful: return reserved
		action["reservations"] = reserved.payload["reservations"]
		action["bait_quantity"] = int(data.get("quantity",1))
		action["activity"] = "idle"
	else:
		if building["uses_left"] >= content.trap_maximum_uses or not building["capture"].is_empty(): return WildOperationResult.reject(&"TRAP_NOT_READY")
		if building["uses_left"] == 0 and not trap_limit(run,content.maximum_traps,actor): return WildOperationResult.reject(&"TRAP_LIMIT")
		var reserved: WildOperationResult = WildInventoryOperations.reserve(state,{"fiber":2})
		if not reserved.successful: return reserved
		action["reservations"] = reserved.payload["reservations"]
		action["duration"] = 600.0
		action["fee"] = 4.0
	return WildOperationResult.accept()

static func clean_water_bottle(state: WildBaseState, litres: float) -> Dictionary:
	for slot: String in ["off_hand","main_hand","backpack"]:
		for placement: Dictionary in state.containers[slot].placements.values():
			var item: WildItemInstance = placement["item"]
			if item.item_id == &"bottle" and item.clean_water and item.water_l >= litres: return {"item":item,"container":state.containers[slot]}
	return {}

## 完成前重新检查动态条件，不能通过菜单或读档绕过火源 / 扩地 / 猎物锁。
static func completion_valid(state: WildBaseState, actor: String, action: Dictionary, config: WildGameConfig, content: WildSurvivalContent) -> bool:
	var run: WildSurvivalState = state.survival
	if action["type"] == "build" and action["recipe"] in ["small_trap","large_trap"] and not trap_limit(run,content.maximum_traps,actor): return false
	if action.has("table_id") and (not run.buildings.has(action["table_id"]) or not WildBuildingRules.in_reach(state.world,actor,run.buildings[action["table_id"]])): return false
	if not action["fire_id"].is_empty() and action["type"] == "craft" and (not run.buildings.has(action["fire_id"]) or not run.buildings[action["fire_id"]]["lit"]): return false
	if action.has("water_item_id"):
		var water: Dictionary = WildInventoryOperations.find(state,action["water_item_id"])
		if water.is_empty() or not (water["item"] as WildItemInstance).clean_water or (water["item"] as WildItemInstance).water_l < action["water_l"]: return false
	if action["type"] == "fish":
		var resource: Dictionary = state.world.resources.get(action["resource_id"],{})
		return not resource.is_empty() and resource["kind"] == "fish" and resource["remaining"] >= int(action["attempts"]) and WildWorldRules.interaction(state.world,actor,resource["id"],int(resource["version"])).successful
	if action["type"] in ["upgrade","demolish","trap_bait","trap_collect","trap_maintain"]:
		var building: Dictionary = run.buildings.get(action["building_id"],{})
		if building.is_empty() or not WildBuildingRules.in_reach(state.world,actor,building): return false
		match action["type"]:
			"upgrade":
				var recipe: Dictionary = content.recipe(action["recipe"])
				return int(building.get("level",1)) == int(action["upgrade_from"]) and WildBuildingRules.can_expand(state,actor,building,Vector2i(recipe["width"],recipe["height"]),config).successful
			"trap_collect": return building.get("capture",{}).get("prey_id","") == action["capture_id"]
			"trap_bait": return building["uses_left"] > 0 and building["capture"].is_empty() and building["bait"]+action["bait_quantity"] <= 3
			"trap_maintain": return building["uses_left"] < content.trap_maximum_uses and building["capture"].is_empty() and (building["uses_left"] > 0 or trap_limit(run,content.maximum_traps,actor))
			"demolish": return building.get("capture",{}).is_empty()
	return true

## 完成校验后在候选事务交付产出 / 有效经验；返回是否有成果，随机状态和捕获记录一并保存。
static func complete(state: WildBaseState, actor: String, action: Dictionary, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent) -> bool:
	var run: WildSurvivalState = state.survival
	var kind: String = action["type"]
	if kind == "fish":
		var caught: int = 0
		var probability: float = minf(content.fishing_probability_cap,content.fishing_probability+(config.skill_rules.fishing_success_bonus if WildSkillRules.level(state.skills,"fishing") >= 1 else 0.0))
		for index: int in range(int(action["attempts"])):
			if WildProgressionWorld.fishing_draw(run,state.world.seed_text,actor) < probability: caught += 1
		if caught > 0:
			state.world.resources[action["resource_id"]]["remaining"] -= caught
			state.world.resources[action["resource_id"]]["version"] += 1
			WildActionOutputs.deliver(state,actor,action,"raw_fish",caught,catalog,config)
			WildSkillRules.award(state,"fishing",config.skill_rules)
			run.mark_activity(actor,"fishing")
		else: run.notice = "未钓到鱼；鱼饵、时间、体力和钓具磨损已经消耗，无经验。"
		return caught > 0
	if kind == "craft":
		if action.has("water_item_id"):
			var entry: Dictionary = WildInventoryOperations.find(state,action["water_item_id"])
			(entry["item"] as WildItemInstance).water_l -= action["water_l"]
			(entry["container"] as WildInventoryContainer).version += 1
		if action["recipe"] in ["roasted_root","cooked_fish","cooked_meat","stew"]:
			WildSkillRules.award(state,"cooking",config.skill_rules)
			run.mark_activity(actor,"cooking")
	elif kind == "upgrade":
		var building: Dictionary = run.buildings[action["building_id"]]
		var recipe: Dictionary = content.recipe(action["recipe"])
		building["level"] = int(action["upgrade_from"])+1
		building["width"] = recipe["width"]
		building["height"] = recipe["height"]
		add_investment(building,recipe["materials"])
		award_build(state,actor,action["recipe"],config.skill_rules)
		WildBuildingRules.rebuild_obstacles(state.world,run)
	elif kind == "trap_collect":
		var building: Dictionary = run.buildings[action["building_id"]]
		var capture: Dictionary = building["capture"]
		var age: float = (run.elapsed_seconds-float(capture["captured_at"]))/3600
		WildActionOutputs.deliver(state,actor,action,"raw_meat",1 if capture["kind"] == "rabbit" else 3,catalog,config,age)
		WildActionOutputs.deliver(state,actor,action,"hide",1 if capture["kind"] == "rabbit" else 2,catalog,config)
		building["capture"] = {}
		building["next_check"] = run.elapsed_seconds+WildTrapRules.interval(building,content)
		WildSkillRules.award(state,"trap",config.skill_rules)
		run.mark_activity(actor,"trap")
	elif kind == "trap_bait":
		var building: Dictionary = run.buildings[action["building_id"]]
		if building["bait"] == 0: building["next_check"] = run.elapsed_seconds+WildTrapRules.interval(building,content)
		building["bait"] += action["bait_quantity"]
	elif kind == "trap_maintain": run.buildings[action["building_id"]]["uses_left"] += 1
	elif kind == "demolish":
		var building: Dictionary = run.buildings[action["building_id"]]
		var factor: float = 0.5*(float(building.get("uses_left",content.trap_maximum_uses))/content.trap_maximum_uses if building["kind"] in ["small_trap","large_trap"] else 1.0)
		for material: String in building.get("investment",{}):
			var returned: int = floori(int(building["investment"][material])*factor)
			if returned > 0: WildActionOutputs.deliver(state,actor,action,material,returned,catalog,config)
		run.buildings.erase(action["building_id"])
		WildBuildingRules.rebuild_obstacles(state.world,run)
	return true

static func add_investment(building: Dictionary, materials: Dictionary) -> void:
	if not building.has("investment"): building["investment"] = {}
	for material: String in materials:
		if material in ["wood","stone","fiber","rope","hide"]: building["investment"][material] = int(building["investment"].get(material,0))+int(materials[material])

static func award_build(state: WildBaseState, actor: String, recipe: String, catalog: WildSkillCatalog) -> void:
	var counts: Dictionary = state.survival.build_experience_counts.get(actor,{})
	if int(counts.get(recipe,0)) < catalog.maximum_build_experience_per_recipe:
		WildSkillRules.award(state,"building",catalog)
		counts[recipe] = int(counts.get(recipe,0))+1
		state.survival.build_experience_counts[actor] = counts
	state.survival.mark_activity(actor,"building")
