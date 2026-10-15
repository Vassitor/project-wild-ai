class_name WildCombatWorld
extends RefCounted
## 动物实体升级、离屏刷新、足迹与睡眠风险。领域只读配置，不持有场景或文件。

static func count(run: WildSurvivalState, kind: String, field: String, config: WildGameConfig) -> int:
	var multiplier: float = 1+ (0.5 if kind == "rabbit" else 0.25)*(run.departure_players-1)
	return ceili(int(config.combat_rules.animals[kind][field])*multiplier)

static func health_scale(run: WildSurvivalState, kind: String) -> float:
	return 1.0 if kind == "rabbit" else 1+0.1*(run.departure_players-1)

## 保留 P5 猎物 ID / 已捕获状态，初始化新子字段；仅新任务 / 旧档迁移调用一次。
static func initialize(state: WildBaseState, config: WildGameConfig, players: int = 1) -> bool:
	var run: WildSurvivalState = state.survival
	if run == null or run.combat_initialized: return false
	run.departure_players = clampi(players,1,4)
	run.wildlife_random_state = str(WildWorldGenerator._stream(state.world.seed_text,"wildlife-refill").state)
	run.next_animal_refill = run.elapsed_seconds+config.combat_rules.refill_seconds
	run.next_disturbance = (floorf(run.elapsed_seconds/3600)+1)*3600
	for animal: Dictionary in run.prey.values(): _upgrade(animal,run,state.world,config)
	run.combat_initialized = true
	_spawn(state,config,true)
	return true

static func _upgrade(animal: Dictionary, run: WildSurvivalState, world: WildWorldData, config: WildGameConfig) -> void:
	var point: Vector2 = world.centre(Vector2i(animal["x"],animal["y"]))
	animal["max_hp"] = float(config.combat_rules.animals[animal["kind"]]["hp"])*health_scale(run,animal["kind"])
	animal.merge({"px":point.x,"py":point.y,"home_x":animal["x"],"home_y":animal["y"],"hp":float(config.combat_rules.animals[animal["kind"]]["hp"])*health_scale(run,animal["kind"]) if animal["alive"] else 0.0,"mode":"wander" if animal["alive"] else "dead","target":"","ready_at":run.elapsed_seconds,"wander_at":run.elapsed_seconds,"direction":[1.0,0.0],"loot_claimed":not animal["alive"],"last_track":run.elapsed_seconds,"random_state":str(WildWorldGenerator._stream(world.seed_text,"animal:"+animal["id"]).state)})

static func position(animal: Dictionary, world: WildWorldData) -> Vector2:
	return Vector2(animal["px"],animal["py"]) if animal.has("px") else world.centre(Vector2i(animal["x"],animal["y"]))

static func protected(world: WildWorldData, run: WildSurvivalState, point: Vector2, config: WildGameConfig) -> bool:
	return run.elapsed_seconds < config.combat_rules.safe_seconds and point.distance_to(world.centre(world.spawn)) <= config.combat_rules.safe_radius_tiles*world.tile_pixels

## 刷新只选可达森林、出生安全距离外、所有角色视野外；使用人数锁定的数量上限。
static func _spawn(state: WildBaseState, config: WildGameConfig, initial: bool) -> void:
	var run: WildSurvivalState = state.survival
	var world: WildWorldData = state.world
	var random := RandomNumberGenerator.new()
	random.state = run.wildlife_random_state.to_int()
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in world.distances(world.spawn):
		if world.tiles[cell.y*world.size.x+cell.x] != WildWorldData.Terrain.FOREST or cell.distance_to(world.spawn) < 30 or not WildAnimalAI.clear(world,world.centre(cell)): continue
		var visible_to_player: bool = false
		for point: Vector2 in world.players.values():
			if point.distance_to(world.centre(cell)) < 12*world.tile_pixels: visible_to_player = true
		if not visible_to_player: candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y*world.size.x+a.x < b.y*world.size.x+b.x)
	var occupied: Dictionary = {}
	for animal: Dictionary in run.prey.values():
		if animal["alive"]: occupied[Vector2i(animal["x"],animal["y"])] = true
	for kind: String in config.combat_rules.animals:
		var living: int = 0
		var existing: int = 0
		for animal: Dictionary in run.prey.values():
			if animal["kind"] == kind:
				existing += 1
				if animal["alive"]: living += 1
		# 迁移时已捕获的 P5 猎物不作为缺额补发，只增加新的狼 / 人数扩展。
		var needed: int = maxi(0,count(run,kind,"initial",config)-existing) if initial else mini(count(run,kind,"refill",config),maxi(0,count(run,kind,"maximum",config)-living))
		var created: int = 0
		while created < needed:
			if candidates.is_empty(): break
			var selected: int = random.randi_range(0,candidates.size()-1)
			var cell: Vector2i = candidates[selected]
			candidates.remove_at(selected)
			if occupied.has(cell):
				continue
			var id: String = "wildlife:%s:%d" % [kind,run.next_animal_serial]
			run.next_animal_serial += 1
			var animal: Dictionary = {"id":id,"kind":kind,"x":cell.x,"y":cell.y,"alive":true}
			_upgrade(animal,run,world,config)
			run.prey[id] = animal
			occupied[cell] = true
			created += 1
	run.wildlife_random_state = str(random.state)

## 每名角色独立的受扰随机流；睡眠不能改变疾病概率的后续序列，也不影响动物刷新。
static func sleep_draw(state: WildBaseState, actor: String) -> float:
	var run: WildSurvivalState = state.survival
	var random := RandomNumberGenerator.new()
	if not run.sleep_random_states.has(actor): run.sleep_random_states[actor] = str(WildWorldGenerator._stream(state.world.seed_text,"sleep-disturbance:"+actor).state)
	random.state = str(run.sleep_random_states[actor]).to_int()
	var value: float = random.randf()
	run.sleep_random_states[actor] = str(random.state)
	return value

static func hourly(state: WildBaseState, _actor_states: Dictionary, config: WildGameConfig, content: WildSurvivalContent) -> bool:
	var run: WildSurvivalState = state.survival
	var changed: bool = false
	while run.next_animal_refill <= run.elapsed_seconds+0.000001:
		_spawn(state,config,false)
		run.next_animal_refill += config.combat_rules.refill_seconds
		changed = true
	while run.next_disturbance <= run.elapsed_seconds+0.000001:
		run.next_disturbance += 3600
		for actor: String in run.actions.keys():
			if run.actions[actor]["type"] != "sleep": continue
			var danger: bool = false
			for animal: Dictionary in run.prey.values():
				if animal["alive"] and animal["kind"] != "rabbit" and position(animal,state.world).distance_to(state.world.players[actor]) <= 6*state.world.tile_pixels: danger = true
			if not danger: continue
			var camp: Dictionary = run.buildings.get(run.actions[actor]["building_id"],{})
			var chance: float = config.combat_rules.sleep_disturbance_per_hour*content.camp_disturbance_multipliers[int(camp.get("level",1))-1]
			if sleep_draw(state,actor) < chance:
				run.actions.erase(actor)
				run.notice = "附近危险动物扰动，已提前醒来。"
				changed = true
	# 有界足迹不随离屏销毁；时间跳过和读档使用相同到期时刻。
	for index: int in range(run.tracks.size()-1,-1,-1):
		if run.tracks[index]["at"]+config.combat_rules.track_lifetime_seconds <= run.elapsed_seconds: run.tracks.remove_at(index)
	return changed
