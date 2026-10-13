class_name WildSurvivalActions
extends RefCounted
## 行动开始校验 / 锁定，完成才消耗材料与交付。取消保留已花时间和体力。
const TYPES: Array[String] = ["gather","eat","drink","fill","build","light","fuel","cook","boil","rest","sleep","treat","fish","craft","upgrade","trap_bait","trap_collect","trap_maintain","demolish"]

static func start(state: WildBaseState, actor: String, data: Dictionary, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent, allow_public_storage: bool = false) -> WildOperationResult:
	var run: WildSurvivalState = state.survival
	if run == null or run.outcome != "running": return WildOperationResult.reject(&"INVALID_PHASE")
	if not run.bodies.has(actor) or not state.world.players.has(actor): return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	if run.bodies[actor].hp <= 0: return WildOperationResult.reject(&"DEAD_ACTOR")
	if run.actions.has(actor): return WildOperationResult.reject(&"ACTION_BUSY")
	var kind: String = str(data.get("action",""))
	if not TYPES.has(kind): return WildOperationResult.reject(&"ACTION_UNAVAILABLE")
	var action: Dictionary = {"type":kind,"duration":60.0,"remaining":60.0,"reservations":[],"fee":0.0,"parameters":data.duplicate(true),"tool_id":"","wear":0.0,"fire_id":"","resource_id":"","resource_version":0,"building_id":"","item_id":"","x":state.world.players[actor].x,"y":state.world.players[actor].y,"activity":"work"}
	var materials: Dictionary = {}
	if kind in WildProgressionActions.TYPES:
		var prepared: WildOperationResult = WildProgressionActions.prepare(state,actor,data,action,config,catalog,content)
		if not prepared.successful: return prepared
	match kind:
		"treat":
			var entry: Dictionary = WildInventoryOperations.find(state,str(data.get("item_id","")))
			if entry.is_empty(): return WildOperationResult.reject(&"NOT_MEDICINE")
			var medicine: WildItemInstance = entry["item"]
			var valid: WildOperationResult = WildMedicalRules.validate(run.bodies[actor],medicine.item_id)
			if not valid.successful: return valid
			action["item_id"] = medicine.instance_id
			action["reservations"] = [{"id":medicine.instance_id,"quantity":1,"fresh":false}]
			action["duration"] = config.health_rules.bandage_seconds if medicine.item_id == &"bandage" else config.health_rules.medicine_seconds
			action["activity"] = "idle"
		"gather":
			if not WildDataValidation.whole(data.get("version",-1)): return WildOperationResult.reject(&"INVALID_REQUEST")
			var valid: WildOperationResult = WildWorldRules.interaction(state.world,actor,str(data.get("resource_id","")),int(data["version"]))
			if not valid.successful: return valid
			var resource: Dictionary = valid.payload
			var resource_kind: String = resource["kind"]
			if resource_kind == "tree":
				var wear_multiplier: float = config.skill_rules.logging_wear_multiplier if WildSkillRules.level(state.skills,"logging") >= 3 else 1.0
				action["tool_id"] = WildInventoryOperations.choose(state,&"axe",2.0*wear_multiplier)
				var axe: bool = not action["tool_id"].is_empty()
				if not axe: action["tool_id"] = WildInventoryOperations.choose(state,&"knife",5.0*wear_multiplier)
				if action["tool_id"].is_empty(): return WildOperationResult.reject(&"MISSING_TOOL")
				action["duration"] = (content.axe_minutes if axe else content.knife_minutes) * 60
				action["fee"] = content.axe_stamina if axe else content.knife_stamina
				action["wear"] = 2.0 if axe else 5.0
				action["output"] = "wood"
				action["quantity"] = 4 if axe else 2
			else:
				if not WildWorldData.RESOURCE_YIELDS.has(resource_kind): return WildOperationResult.reject(&"ACTION_UNAVAILABLE")
				action["output"] = WildWorldData.RESOURCE_YIELDS[resource_kind][0]
				action["quantity"] = WildWorldData.RESOURCE_YIELDS[resource_kind][1]
				action["duration"] = content.gather_minutes * 60
				action["fee"] = content.gather_stamina
			action["resource_id"] = resource["id"]
			action["resource_version"] = resource["version"]
			if resource_kind == "tree":
				if WildSkillRules.level(state.skills,"logging") >= 1: action["duration"] *= config.skill_rules.logging_duration_multiplier
				if WildSkillRules.level(state.skills,"logging") >= 2: action["quantity"] += 1
				if WildSkillRules.level(state.skills,"logging") >= 3: action["wear"] *= config.skill_rules.logging_wear_multiplier
			else:
				if resource_kind in ["berry","root","fiber","herb"] and WildSkillRules.level(state.skills,"gathering") >= 2: action["quantity"] += 1
				if WildSkillRules.level(state.skills,"gathering") >= 3: action["duration"] *= config.skill_rules.gathering_duration_multiplier
		"eat":
			var entry: Dictionary = WildInventoryOperations.find(state,str(data.get("item_id","")))
			if entry.is_empty() or not content.foods.has(str((entry["item"] as WildItemInstance).item_id)): return WildOperationResult.reject(&"NOT_EDIBLE")
			action["item_id"] = (entry["item"] as WildItemInstance).instance_id
			materials[str((entry["item"] as WildItemInstance).item_id)] = 1
			action["reservations"] = [{"id":action["item_id"],"quantity":1,"fresh":false}]
			action["duration"] = content.eat_minutes * 60
			action["activity"] = "idle"
		"drink","fill":
			var litres: Variant = data.get("litres",0.5)
			if not WildDataValidation.number(litres) or float(litres) <= 0 or float(litres) > 1 or not is_equal_approx(float(litres) / content.water_quantum_l, roundf(float(litres) / content.water_quantum_l)): return WildOperationResult.reject(&"INVALID_QUANTITY")
			action["litres"] = float(litres)
			action["activity"] = "idle"
			action["duration"] = content.water_minutes * 60
			var item_id: String = str(data.get("item_id",""))
			var source_id: String = str(data.get("resource_id",""))
			if kind == "fill" or source_id.is_empty():
				var entry: Dictionary = WildInventoryOperations.find(state,item_id)
				if entry.is_empty() or (entry["item"] as WildItemInstance).item_id != &"bottle": return WildOperationResult.reject(&"MISSING_BOTTLE")
				var bottle: WildItemInstance = entry["item"]
				action["item_id"] = item_id
				if kind == "drink":
					if bottle.water_l + 0.00001 < float(litres): return WildOperationResult.reject(&"NOT_ENOUGH_WATER")
					action["clean"] = bottle.clean_water
				else:
					if bottle.water_l + float(litres) > catalog.find(&"bottle").water_capacity_l + 0.00001: return WildOperationResult.reject(&"BOTTLE_FULL")
					if state.carried_weight(catalog,config) + float(litres) > config.hard_weight_limit_kg + 0.00001: return WildOperationResult.reject(&"WEIGHT_LIMIT")
			if not source_id.is_empty():
				var clean: bool = false
				if source_id == "shore":
					if not state.world.has_water_neighbor(state.world.cell_at(state.world.players[actor])): return WildOperationResult.reject(&"OUT_OF_REACH")
				else:
					if not WildDataValidation.whole(data.get("version",-1)): return WildOperationResult.reject(&"INVALID_REQUEST")
					var valid: WildOperationResult = WildWorldRules.interaction(state.world,actor,source_id,int(data["version"]))
					if not valid.successful: return valid
					if valid.payload["kind"] != "spring": return WildOperationResult.reject(&"UNKNOWN_RESOURCE")
					clean = true
				action["clean"] = clean
				if kind == "fill":
					var bottle: WildItemInstance = WildInventoryOperations.find(state,item_id)["item"]
					if bottle.water_l > 0 and bottle.clean_water != clean: return WildOperationResult.reject(&"WATER_MISMATCH")
			elif kind == "fill": return WildOperationResult.reject(&"UNKNOWN_RESOURCE")
		"build":
			var recipe_id: String = str(data.get("recipe",""))
			if recipe_id not in WildProgressionActions.BUILDABLE or (recipe_id == "storage_box" and not allow_public_storage): return WildOperationResult.reject(&"ACTION_UNAVAILABLE")
			var recipe: Dictionary = content.recipe(recipe_id)
			var allowed: WildOperationResult = WildProgressionActions.recipe_allowed(state,recipe)
			if not allowed.successful: return allowed
			if recipe_id in ["small_trap","large_trap"] and not WildProgressionActions.trap_limit(run,content.maximum_traps,actor): return WildOperationResult.reject(&"TRAP_LIMIT")
			var site: WildOperationResult
			if data.has("x") or data.has("y"):
				if not WildDataValidation.whole(data.get("x",null)) or not WildDataValidation.whole(data.get("y",null)): return WildOperationResult.reject(&"INVALID_REQUEST")
				site = WildBuildingRules.can_build(state,actor,Vector2i(data["x"],data["y"]),Vector2i(recipe["width"],recipe["height"]))
			else: site = WildBuildingRules.auto_site(state,actor,Vector2i(recipe["width"],recipe["height"]))
			if not site.successful: return site
			action["site"] = site.payload
			action["recipe"] = recipe_id
			action["duration"] = recipe["minutes"] * 60
			action["fee"] = recipe["stamina"]
			materials = recipe["materials"]
		"light","fuel","cook","boil":
			var fire_id: String = str(data.get("building_id",WildBuildingRules.nearby(state,actor,"fire",kind in ["cook","boil"])))
			if not run.buildings.has(fire_id) or run.buildings[fire_id]["kind"] != "fire" or not WildBuildingRules.in_reach(state.world,actor,run.buildings[fire_id]): return WildOperationResult.reject(&"MISSING_FIRE")
			var fire: Dictionary = run.buildings[fire_id]
			action["fire_id"] = fire_id
			if kind in ["cook","boil"] and not fire["lit"]: return WildOperationResult.reject(&"FIRE_NOT_LIT")
			if kind == "light":
				if fire["lit"] or fire["fuel_seconds"] <= 0: return WildOperationResult.reject(&"INVALID_FIRE")
				action["tool_id"] = WildInventoryOperations.choose(state,&"flint",1)
				action["duration"] = 1200.0 if action["tool_id"].is_empty() else 300.0
				action["fee"] = 10.0 if action["tool_id"].is_empty() else 4.0
				action["wear"] = 0.0 if action["tool_id"].is_empty() else 1.0
				if WildSkillRules.level(state.skills,"fire") >= 3: action["duration"] *= config.skill_rules.fire_duration_multiplier
			elif kind == "fuel":
				var extra: float = content.fire_wood_seconds*(config.skill_rules.fuel_multiplier if WildSkillRules.level(state.skills,"fire") >= 2 else 1.0)
				var maximum: float = content.fire_maximum_seconds*(config.skill_rules.fuel_multiplier if WildSkillRules.level(state.skills,"fire") >= 2 else 1.0)
				if fire["fuel_seconds"] + extra > maximum + 0.00001: return WildOperationResult.reject(&"FUEL_FULL")
				action["fuel_added_seconds"] = extra
				materials = {"wood":1}
				action["activity"] = "idle"
			elif kind == "cook":
				var recipe: Dictionary = content.recipes["roasted_root"]
				materials = recipe["materials"]
				action["duration"] = recipe["minutes"] * 60
				action["fee"] = recipe["stamina"]
				action["output"] = recipe["output"]
				action["quantity"] = 1
			else:
				var entry: Dictionary = WildInventoryOperations.find(state,str(data.get("item_id","")))
				if entry.is_empty(): return WildOperationResult.reject(&"MISSING_BOTTLE")
				var bottle: WildItemInstance = entry["item"]
				if bottle.item_id != &"bottle" or bottle.water_l <= 0 or bottle.clean_water: return WildOperationResult.reject(&"INVALID_WATER")
				action["item_id"] = bottle.instance_id
				action["duration"] = bottle.water_l * 600.0
				action["fee"] = 2.0
		"rest","sleep":
			var camp_id: String = str(data.get("building_id",WildBuildingRules.nearby(state,actor,"camp")))
			if not run.buildings.has(camp_id) or run.buildings[camp_id]["kind"] != "camp" or not WildBuildingRules.in_reach(state.world,actor,run.buildings[camp_id]): return WildOperationResult.reject(&"MISSING_CAMP")
			var hours: Variant = data.get("hours",1)
			if not WildDataValidation.whole(hours) or int(hours) not in [1,2,4,8]: return WildOperationResult.reject(&"INVALID_QUANTITY")
			if kind == "sleep" and (run.bodies[actor].hp <= 20 or run.bodies[actor].water <= 20 or run.bodies[actor].bleeding): return WildOperationResult.reject(&"SLEEP_UNSAFE")
			action["building_id"] = camp_id
			action["duration"] = float(hours) * 3600
			action["activity"] = kind
	if action["reservations"].is_empty() and not materials.is_empty():
		var reserved: WildOperationResult = WildInventoryOperations.reserve(state,materials,kind == "cook")
		if not reserved.successful: return reserved
		action["reservations"] = reserved.payload["reservations"]
	var overload: float = clampf((state.carried_weight(catalog,config) - config.soft_weight_limit_kg) / (config.hard_weight_limit_kg - config.soft_weight_limit_kg),0,1)
	var fee: float = action["fee"] * (1 + config.maximum_weight_stamina_penalty * overload)
	if run.bodies[actor].stamina + 0.00001 < fee: return WildOperationResult.reject(&"NOT_ENOUGH_STAMINA")
	run.bodies[actor].stamina = maxf(0,run.bodies[actor].stamina - fee)
	if action.has("start_consumptions"):
		WildInventoryOperations.consume(state,action["start_consumptions"])
		action.erase("start_consumptions") # 投饵立即消耗，取消 / 失败不会退饵。
	action["remaining"] = action["duration"]
	run.actions[actor] = action
	run.notice = ""
	return WildOperationResult.accept({"duration_seconds":action["duration"]})

static func finish(state: WildBaseState, actor: String, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent) -> bool:
	var run: WildSurvivalState = state.survival
	var action: Dictionary = run.actions[actor]
	run.actions.erase(actor)
	if not WildInventoryOperations.reservations_valid(state,action["reservations"]):
		run.notice = "材料发生变化或已经腐坏，行动未产出。"
		return false
	var kind: String = action["type"]
	if not WildProgressionActions.completion_valid(state,actor,action,config,content):
		run.notice = "场地、设施或状态已变化，未消耗预留材料。"
		return false
	if kind == "build":
		var recipe: Dictionary = content.recipe(action["recipe"])
		if not WildBuildingRules.can_build(state,actor,Vector2i(action["site"]["x"],action["site"]["y"]),Vector2i(recipe["width"],recipe["height"])).successful:
			run.notice = "建造地点已不可用，材料未消耗。"
			return false
	if not action["fire_id"].is_empty() and kind in ["cook","boil"] and not run.buildings[action["fire_id"]]["lit"]:
		run.notice = "火已熄灭，未消耗料理材料。"
		return false
	if kind == "gather":
		var validation: WildOperationResult = WildWorldRules.interaction(state.world,actor,action["resource_id"],int(action["resource_version"]))
		if not validation.successful: return false
	if not action["tool_id"].is_empty():
		var tool: Dictionary = WildInventoryOperations.find(state,action["tool_id"])
		if tool.is_empty() or (tool["item"] as WildItemInstance).durability < action["wear"]: return false
		(tool["item"] as WildItemInstance).durability -= action["wear"]
		(tool["container"] as WildInventoryContainer).version += 1
	if kind in WildProgressionActions.TYPES:
		var effective: bool = WildProgressionActions.complete(state,actor,action,config,catalog,content)
		WildInventoryOperations.consume(state,action["reservations"])
		if action.has("output"): WildActionOutputs.deliver(state,actor,action,action["output"],int(action["quantity"]),catalog,config)
		return effective
	match kind:
		"treat":
			var medicine: WildItemInstance = WildInventoryOperations.find(state,action["item_id"])["item"]
			if not WildMedicalRules.apply(run.bodies[actor],medicine.item_id,config.health_rules):
				run.notice = "治疗条件已改变，药品未消耗。"
				return false
			run.mark_activity(actor,"healing")
			if medicine.item_id == &"herbal_medicine" and WildSkillRules.level(state.skills,"healing") >= 2: run.bodies[actor].gastro_remaining_seconds = maxf(0,run.bodies[actor].gastro_remaining_seconds-config.skill_rules.medicine_bonus_seconds)
			WildSkillRules.award(state,"healing",config.skill_rules)
		"gather":
			var consumed: WildOperationResult = WildWorldRules.consume(state.world,actor,action["resource_id"],int(action["resource_version"]),1)
			if not consumed.successful: return false
			var resource: Dictionary = state.world.resources[action["resource_id"]]
			if resource["kind"] in ["berry","root"]: resource["regrow_at"] = run.elapsed_seconds + (86400 if resource["kind"] == "berry" else 172800)
			run.mark_activity(actor,"logging" if resource["kind"] == "tree" else ("gathering" if resource["kind"] in ["berry","root"] else ""))
			WildSkillRules.award(state,"logging" if resource["kind"] == "tree" else "gathering",config.skill_rules)
		"eat":
			WildBodyRules.eat(run.bodies[actor],content,WildInventoryOperations.find(state,action["item_id"])["item"])
		"drink","fill","boil":
			var item_id: String = action["item_id"]
			var entry: Dictionary = WildInventoryOperations.find(state,item_id) if not item_id.is_empty() else {}
			if kind == "drink":
				WildBodyRules.drink(run.bodies[actor],config,action["litres"],action["clean"])
				if not entry.is_empty(): (entry["item"] as WildItemInstance).water_l = maxf(0,(entry["item"] as WildItemInstance).water_l - action["litres"])
			elif kind == "fill": (entry["item"] as WildItemInstance).water_l += action["litres"]
			if kind == "fill": (entry["item"] as WildItemInstance).clean_water = action["clean"]
			if kind == "boil": (entry["item"] as WildItemInstance).clean_water = true
			if not entry.is_empty(): (entry["container"] as WildInventoryContainer).version += 1
		"build":
			var recipe: Dictionary = content.recipe(action["recipe"])
			var building_id: String = WildStableId.create("building")
			run.buildings[building_id] = {"id":building_id,"kind":action["recipe"],"x":action["site"]["x"],"y":action["site"]["y"],"width":recipe["width"],"height":recipe["height"],"lit":false,"fuel_seconds":content.fire_initial_seconds if action["recipe"] == "fire" else 0.0}
			var building: Dictionary = run.buildings[building_id]
			WildProgressionActions.add_investment(building,recipe["materials"])
			if action["recipe"] == "camp": building["level"] = 1
			if action["recipe"] == "fire":
				if WildSkillRules.level(state.skills,"fire") >= 2: building["fuel_seconds"] *= config.skill_rules.fuel_multiplier
				building["fuel_supplied_seconds"] = building["fuel_seconds"]
				building["ignition_awarded_fuel"] = 0.0
			if action["recipe"] in ["small_trap","large_trap"]: WildTrapRules.initialize(building,actor,state.world.seed_text,run.elapsed_seconds,content,state.skills,config.skill_rules)
			WildBuildingRules.rebuild_obstacles(state.world,run)
			WildProgressionActions.award_build(state,actor,action["recipe"],config.skill_rules)
		"light":
			var success: bool = true
			if action["tool_id"].is_empty():
				var random := RandomNumberGenerator.new()
				random.state = run.random_state.to_int()
				success = random.randf() < 0.6+(config.skill_rules.fire_success_bonus if WildSkillRules.level(state.skills,"fire") >= 1 else 0.0)
				run.random_state = str(random.state)
			run.buildings[action["fire_id"]]["lit"] = success
			if success:
				run.mark_activity(actor,"fire")
				var fire: Dictionary = run.buildings[action["fire_id"]]
				var supplied: float = fire.get("fuel_supplied_seconds",fire["fuel_seconds"])
				if supplied > float(fire.get("ignition_awarded_fuel",0)):
					WildSkillRules.award(state,"fire",config.skill_rules)
					fire["ignition_awarded_fuel"] = supplied
			else: run.notice = "钻木取火未成功，时间与体力已消耗。"
		"fuel":
			var fire: Dictionary = run.buildings[action["fire_id"]]
			var added: float = action.get("fuel_added_seconds",content.fire_wood_seconds)
			fire["fuel_supplied_seconds"] = float(fire.get("fuel_supplied_seconds",fire["fuel_seconds"]))+added
			fire["fuel_seconds"] += added
		"cook":
			run.mark_activity(actor,"cooking")
			WildSkillRules.award(state,"cooking",config.skill_rules)
	WildInventoryOperations.consume(state,action["reservations"])
	if action.has("output"):
		WildActionOutputs.deliver(state,actor,action,action["output"],int(action["quantity"]),catalog,config)
	return true
