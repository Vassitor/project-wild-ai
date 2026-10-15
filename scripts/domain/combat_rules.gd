class_name WildCombatRules
extends RefCounted
## 玩家只提交方向和请求 ID；武器、耗箭、命中、伤害、掉落与经验均由权威事务决定。

static func line_clear(world: WildWorldData, start: Vector2, end: Vector2) -> bool:
	var steps: int = maxi(1,ceili(start.distance_to(end)/4))
	for index: int in range(steps+1):
		if not world.walkable(world.cell_at(start.lerp(end,float(index)/steps))): return false
	return true

static func weapon(state: WildBaseState) -> Dictionary:
	for placement: Dictionary in state.containers["main_hand"].placements.values():
		var item: WildItemInstance = placement["item"]
		if item.item_id in [&"knife",&"axe",&"bow"] and item.durability >= 1: return {"item":item,"container":state.containers["main_hand"]}
	return {}

## 空挥 / 空箭也消耗体力、磨损和冷却；无击杀不发狩猎经验，客户端不能指定伤害或掉落。
static func attack(state: WildBaseState, actor: String, data: Dictionary, config: WildGameConfig, catalog: WildItemCatalog) -> WildOperationResult:
	var run: WildSurvivalState = state.survival
	if run == null or state.phase != WildRunFlow.Phase.WILDERNESS or run.outcome != "running" or not run.bodies.has(actor) or run.bodies[actor].hp <= 0: return WildOperationResult.reject(&"INVALID_PHASE")
	if state.player_id != actor: return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	if run.actions.has(actor): return WildOperationResult.reject(&"ACTION_BUSY")
	var raw: Variant = data.get("direction",null)
	if not raw is Array or raw.size() != 2 or not WildDataValidation.number(raw[0]) or not WildDataValidation.number(raw[1]): return WildOperationResult.reject(&"INVALID_REQUEST")
	var direction := Vector2(raw[0],raw[1])
	if direction.length_squared() < 0.000001: return WildOperationResult.reject(&"INVALID_REQUEST")
	direction = direction.normalized()
	var equipped: Dictionary = weapon(state)
	if equipped.is_empty(): return WildOperationResult.reject(&"MISSING_WEAPON")
	var item: WildItemInstance = equipped["item"]
	var rules: Dictionary = config.combat_rules.weapons[str(item.item_id)]
	if run.elapsed_seconds < float(run.attack_ready_at.get(actor,0)): return WildOperationResult.reject(&"ATTACK_COOLDOWN")
	var ammunition: WildOperationResult = WildOperationResult.accept({"reservations":[]})
	if item.item_id == &"bow":
		if WildSkillRules.level(state.skills,"hunting") < 1: return WildOperationResult.reject(&"SKILL_REQUIRED")
		ammunition = WildInventoryOperations.reserve(state,{"arrow":1})
		if not ammunition.successful: return WildOperationResult.reject(&"NO_ARROWS")
	var overload: float = clampf((state.carried_weight(catalog,config)-config.soft_weight_limit_kg)/(config.hard_weight_limit_kg-config.soft_weight_limit_kg),0,1)
	var fee: float = float(rules["stamina"])*(1+config.maximum_weight_stamina_penalty*overload)
	if run.bodies[actor].stamina+0.000001 < fee: return WildOperationResult.reject(&"INSUFFICIENT_STAMINA")
	WildCombatWorld.initialize(state,config)
	run.bodies[actor].stamina -= fee
	run.attack_ready_at[actor] = run.elapsed_seconds+float(rules["cooldown"])*config.game_seconds_per_real_second
	item.durability = maxf(0,item.durability-1)
	(equipped["container"] as WildInventoryContainer).version += 1
	var origin: Vector2 = state.world.players[actor]
	run.combat_feedback[actor] = {"at":run.elapsed_seconds,"kind":"swing","damage":0.0,"x":origin.x,"y":origin.y,"dx":direction.x,"dy":direction.y}
	if item.item_id == &"bow":
		WildInventoryOperations.consume(state,ammunition.payload["reservations"])
		var id: String = WildStableId.create("arrow")
		run.projectiles[id] = {"id":id,"owner":actor,"x":origin.x,"y":origin.y,"dx":direction.x,"dy":direction.y,"remaining":config.combat_rules.arrow_range_tiles*state.world.tile_pixels,"damage":rules["damage"]}
	else:
		var nearest: Dictionary = {}
		var distance: float = config.combat_rules.melee_range_tiles*state.world.tile_pixels+0.001
		for animal: Dictionary in run.prey.values():
			if not animal["alive"]: continue
			var point: Vector2 = WildCombatWorld.position(animal,state.world)
			var offset: Vector2 = point-origin
			if offset.length() < distance and (offset.length() < 0.01 or offset.normalized().dot(direction) >= 0.5) and line_clear(state.world,origin,point):
				nearest = animal
				distance = offset.length()
		if not nearest.is_empty(): hit(state,actor,nearest,float(rules["damage"]),config,catalog)
	return WildOperationResult.accept({"weapon":str(item.item_id),"stamina":fee})

## 只接受权威碰撞的实际动物引用；原子死亡标记先于掉落，重放 / 另一发箭不能重复领取。
static func hit(state: WildBaseState, actor: String, animal: Dictionary, damage: float, config: WildGameConfig, catalog: WildItemCatalog) -> void:
	if not animal["alive"]: return
	var run: WildSurvivalState = state.survival
	animal["hp"] = maxf(0,float(animal["hp"])-damage)
	var point: Vector2 = WildCombatWorld.position(animal,state.world)
	run.combat_feedback[actor] = {"at":run.elapsed_seconds,"kind":"hit","damage":damage,"x":point.x,"y":point.y}
	if animal["hp"] > 0:
		if animal["kind"] == "boar":
			animal["target"] = actor
			animal["mode"] = "chase"
		return
	animal["alive"] = false
	animal["mode"] = "dead"
	animal["target"] = ""
	if animal["loot_claimed"]: return
	animal["loot_claimed"] = true
	var definition: Dictionary = config.combat_rules.animals[animal["kind"]]
	var meat: int = int(definition["meat"])+(1 if WildSkillRules.level(state.skills,"hunting") >= 3 else 0)
	var action: Dictionary = {"x":point.x,"y":point.y}
	WildActionOutputs.deliver(state,actor,action,"raw_meat",meat,catalog,config)
	WildActionOutputs.deliver(state,actor,action,"hide",int(definition["hide"]),catalog,config)
	WildSkillRules.award(state,"hunting",config.skill_rules)
	run.mark_activity(actor,"hunting")
	run.notice = "猎杀%s，获得肉 %d / 皮 %d。" % [{"rabbit":"兔","boar":"野猪","wolf":"狼"}[animal["kind"]],meat,definition["hide"]]

static func _projectiles(state: WildBaseState, actors: Dictionary, config: WildGameConfig, catalog: WildItemCatalog, seconds: float) -> bool:
	var run: WildSurvivalState = state.survival
	var changed: bool = false
	for id: String in run.projectiles.keys():
		var arrow: Dictionary = run.projectiles[id]
		var displacement: float = minf(float(arrow["remaining"]),config.combat_rules.arrow_speed_tiles_per_second*state.world.tile_pixels*seconds)
		var steps: int = maxi(1,ceili(displacement/4))
		var point := Vector2(arrow["x"],arrow["y"])
		for index: int in range(steps):
			point += Vector2(arrow["dx"],arrow["dy"])*displacement/steps
			if not state.world.walkable(state.world.cell_at(point)):
				run.projectiles.erase(id)
				break
			var collided: bool = false
			for animal: Dictionary in run.prey.values():
				if animal["alive"] and point.distance_to(WildCombatWorld.position(animal,state.world)) <= 10:
					hit(actors.get(arrow["owner"],state),arrow["owner"],animal,float(arrow["damage"]),config,catalog)
					run.projectiles.erase(id)
					collided = true
					changed = true
					break
			if collided: break
		if not run.projectiles.has(id): continue
		arrow["x"] = point.x
		arrow["y"] = point.y
		arrow["remaining"] = maxf(0,float(arrow["remaining"])-displacement)
		if arrow["remaining"] <= 0: run.projectiles.erase(id)
	return changed

## 游戏时间统一转现实时间；子步限制 AI / 投射碰撞，离屏与睡眠采用同一规则。
static func needs_small_step(state: WildBaseState) -> bool:
	var run: WildSurvivalState = state.survival
	if not run.combat_initialized: return false
	if not run.projectiles.is_empty(): return true
	for animal: Dictionary in run.prey.values():
		if not animal["alive"]: continue
		for point: Vector2 in state.world.players.values():
			if WildCombatWorld.position(animal,state.world).distance_squared_to(point) < pow(10*state.world.tile_pixels,2): return true
	return false

static func tick(state: WildBaseState, actors: Dictionary, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent, game_seconds: float) -> bool:
	var run: WildSurvivalState = state.survival
	if not run.combat_initialized: return false
	var remaining: float = game_seconds/config.game_seconds_per_real_second
	var changed: bool = false
	while remaining > 0.000001:
		var step: float = minf(remaining,0.1 if not run.projectiles.is_empty() else 0.25)
		if _projectiles(state,actors,config,catalog,step): changed = true
		if WildAnimalAI.tick(state,actors,config,step): changed = true
		remaining -= step
	if WildCombatWorld.hourly(state,actors,config,content): changed = true
	return changed
