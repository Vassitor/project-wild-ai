class_name WildSurvivalSimulation
extends RefCounted
## 统一分钟模拟。普通实时与睡眠共用步进；动作 / 目标边界拆步，同刻死亡优先。

static func create(actor: String, seed_text: String) -> WildSurvivalState:
	var run := WildSurvivalState.new()
	run.bodies[actor] = WildBodyState.new()
	WildIllnessRules.seed_body(run.bodies[actor],seed_text,actor)
	var random: RandomNumberGenerator = WildWorldGenerator._stream(seed_text,"actions")
	run.random_state = str(random.state)
	return run

static func queue_time(run: WildSurvivalState, seconds: float, activity: String) -> void:
	if not is_finite(seconds) or seconds <= 0 or run.outcome != "running": return
	run.pending_seconds += seconds
	if not run.segments.is_empty() and run.segments.back()["activity"] == activity: run.segments.back()["seconds"] += seconds
	else: run.segments.append({"activity":activity,"seconds":seconds})

## 强制模式用于操作前消化已积累的不足一分钟时间，不能把旧时间记到新动作上。
static func process(state: WildBaseState, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent, force: bool = false, actor_states: Dictionary = {}, actor_activities: Dictionary = {}) -> Dictionary:
	var run: WildSurvivalState = state.survival
	var events: Dictionary = {"save":false,"world_changed":false,"sleep_interrupted":false}
	if WildProgressionWorld.initialize(state,content): events["world_changed"] = true
	while run.pending_seconds > 0.000001 and run.outcome == "running":
		var step: float = minf(config.simulation_step_seconds, config.target_survival_hours * 3600 - run.elapsed_seconds)
		for action: Dictionary in run.actions.values(): step = minf(step,action["remaining"])
		if not force and run.pending_seconds + 0.000001 < step: break
		step = minf(step,run.pending_seconds)
		if step <= 0.000001: break
		var old_day: int = int(run.elapsed_seconds / 86400)
		var remaining: float = step
		while remaining > 0.000001:
			var segment: Dictionary = run.segments.front()
			var used: float = minf(remaining,segment["seconds"])
			for actor: String in run.bodies:
				var personal: WildBaseState = actor_states.get(actor,state)
				var activity: String = run.actions[actor]["activity"] if run.actions.has(actor) else str(actor_activities.get(actor,segment["activity"]))
				if activity == "sprint" and run.bodies[actor].stamina <= 0: activity = "walk"
				var overload: float = clampf((personal.carried_weight(catalog,config,actor)-config.soft_weight_limit_kg)/(config.hard_weight_limit_kg-config.soft_weight_limit_kg),0,1)
				var hp_multiplier: float = config.skill_rules.healing_multiplier if WildSkillRules.level(personal.skills,"healing") >= 3 else 1.0
				var camp: Dictionary = run.buildings.get(run.actions.get(actor,{}).get("building_id",""),{})
				if camp.get("kind","") == "camp": hp_multiplier *= content.camp_hp_multipliers[int(camp.get("level",1))-1]
				WildBodyRules.advance(run.bodies[actor],config,content,used,activity,overload,hp_multiplier)
			segment["seconds"] -= used
			remaining -= used
			if segment["seconds"] <= 0.000001: run.segments.pop_front()
			run.pending_seconds = maxf(0,run.pending_seconds - used)
		run.elapsed_seconds += step
		_age_items(state,catalog,step)
		# 合作库存按玩家分开；世界输出和火源只推进一次，不能按在线人数加速。
		for personal: WildBaseState in actor_states.values():
			if personal != state: _age_items(personal,catalog,step,false)
		if _world_tick(state,step): events["world_changed"] = true
		if WildProgressionWorld.tick(state,actor_states,content,config):
			events["world_changed"] = true
			events["save"] = true
		# 完成同一时刻的消耗与危急判断后，才允许产出 / 胜利；结束后动作无产出。
		var all_dead: bool = true
		for body: WildBodyState in run.bodies.values():
			if body.hp > 0: all_dead = false
		if (actor_states.is_empty() and run.bodies[state.player_id].hp <= 0) or (not actor_states.is_empty() and all_dead):
			run.outcome = "lost"
		elif run.elapsed_seconds + 0.000001 >= config.target_survival_hours * 3600:
			run.outcome = "won"
		if run.outcome != "running":
			run.actions.clear()
			run.pending_seconds = 0
			run.segments.clear()
			events["save"] = true
			break
		for actor: String in run.actions.keys():
			var action: Dictionary = run.actions[actor]
			action["remaining"] = maxf(0,action["remaining"] - step)
			if run.bodies[actor].hp <= 0:
				run.actions.erase(actor)
				events["save"] = true
			elif action["type"] in ["cook","boil","craft"] and not action["fire_id"].is_empty() and (not run.buildings.has(action["fire_id"]) or not run.buildings[action["fire_id"]]["lit"]):
				run.actions.erase(actor)
				run.notice = "火已熄灭，料理中断，原料仍保留。"
				events["save"] = true
			elif action["type"] == "sleep" and (run.bodies[actor].hp <= 20 or run.bodies[actor].water <= 20 or run.bodies[actor].bleeding):
				run.actions.erase(actor)
				run.notice = "身体出现危急状况，已提前醒来。"
				events["sleep_interrupted"] = true
				events["save"] = true
			elif action["remaining"] <= 0.000001:
				WildSurvivalActions.finish(actor_states.get(actor,state),actor,config,catalog,content)
				events["save"] = true
				events["world_changed"] = true
		if old_day != int(run.elapsed_seconds / 86400): events["save"] = true
	return events

static func sleep(state: WildBaseState, actor: String, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent) -> void:
	var run: WildSurvivalState = state.survival
	while run.actions.has(actor) and run.actions[actor]["type"] == "sleep" and run.outcome == "running":
		var step: float = minf(60.0,run.actions[actor]["remaining"])
		queue_time(run,step,"sleep")
		var events: Dictionary = process(state,config,catalog,content,true)
		if events["sleep_interrupted"]: break

static func explore(state: WildBaseState, actor: String) -> void:
	var world: WildWorldData = state.world
	var cell: Vector2i = world.cell_at(world.players[actor])
	for y: int in range(cell.y-3,cell.y+4):
		for x: int in range(cell.x-3,cell.x+4):
			var point := Vector2i(x,y)
			if world.contains(point) and world.tiles[y*world.size.x+x] != WildWorldData.Terrain.WATER: state.survival.explored["%d:%d" % [x,y]] = true

static func _age_items(state: WildBaseState, catalog: WildItemCatalog, seconds: float, age_outputs: bool = true) -> void:
	for container: WildInventoryContainer in state.containers.values():
		if not container.carried: continue
		for entry: Dictionary in container.placements.values():
			var item: WildItemInstance = entry["item"]
			if catalog.find(item.item_id).shelf_life_hours >= 0 and item.freshness_hours > 0:
				item.freshness_hours = maxf(0,item.freshness_hours - seconds/3600)
		# 连续腐坏不改变容器布局 / 数量版本，避免合作菜单每半秒失效。
		# 进食 / 制作仍以房主当前新鲜度校验；转移、数量、水量和耐久变更更新版本。
	if not age_outputs: return
	for output: Dictionary in state.survival.outputs.values():
		for raw: Dictionary in output["items"]:
			if float(raw["freshness_hours"]) >= 0: raw["freshness_hours"] = maxf(0,float(raw["freshness_hours"]) - seconds/3600)

static func _world_tick(state: WildBaseState, seconds: float) -> bool:
	var changed: bool = false
	var run: WildSurvivalState = state.survival
	for building: Dictionary in run.buildings.values():
		if building["kind"] == "fire" and building["lit"]:
			building["fuel_seconds"] = maxf(0,building["fuel_seconds"] - seconds)
			if building["fuel_seconds"] <= 0:
				building["lit"] = false
				changed = true
	for resource: Dictionary in state.world.resources.values():
		if resource.get("regrow_at",INF) <= run.elapsed_seconds:
			resource["remaining"] = 1
			resource["version"] += 1
			resource.erase("regrow_at")
			state.world.version += 1
			changed = true
	return changed
