class_name WildProgressionWorld
extends RefCounted
## 独立猎物 / 捕鱼计时。P5 猎物为持久静态实体，P6 再接游走与战斗。
static func initialize(state: WildBaseState, content: WildSurvivalContent) -> bool:
	var run: WildSurvivalState = state.survival
	if run.progression_initialized: return false
	var world: WildWorldData = state.world
	var random: RandomNumberGenerator = WildWorldGenerator._stream(world.seed_text,"prey")
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in world.distances(world.spawn):
		if world.tiles[cell.y*world.size.x+cell.x] == WildWorldData.Terrain.FOREST and cell.distance_to(world.spawn) >= 30: candidates.append(cell)
	# 排序后独立洗牌，避免哈希迭代顺序改变同种子的猎物初始位置。
	candidates.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y*world.size.x+a.x < b.y*world.size.x+b.x)
	for index: int in range(candidates.size()-1,0,-1):
		var selected: int = random.randi_range(0,index)
		var swap: Vector2i = candidates[index]
		candidates[index] = candidates[selected]
		candidates[selected] = swap
	for index: int in range(mini(26,candidates.size())):
		var kind: String = "rabbit" if index < 20 else "boar"
		var id: String = "prey:%s:%d" % [kind,index]
		run.prey[id] = {"id":id,"kind":kind,"x":candidates[index].x,"y":candidates[index].y,"alive":true}
	for id: String in world.resources:
		if world.resources[id]["kind"] == "fish": run.fish_refills[id] = run.elapsed_seconds+content.fish_refill_seconds
	run.progression_initialized = true
	return true

static func fishing_draw(run: WildSurvivalState, seed_text: String, actor: String) -> float:
	var random := RandomNumberGenerator.new()
	if not run.fishing_random_states.has(actor): run.fishing_random_states[actor] = str(WildWorldGenerator._stream(seed_text,"fishing:"+actor).state)
	random.state = str(run.fishing_random_states[actor]).to_int()
	var value: float = random.randf()
	run.fishing_random_states[actor] = str(random.state)
	return value

static func tick(state: WildBaseState, actor_states: Dictionary, content: WildSurvivalContent, config: WildGameConfig) -> bool:
	var run: WildSurvivalState = state.survival
	var changed: bool = false
	for id: String in run.fish_refills:
		while run.fish_refills[id] <= run.elapsed_seconds+0.000001:
			var resource: Dictionary = state.world.resources[id]
			var old: int = int(resource["remaining"])
			var multiplier: float = WildCoopWorldRules.food_multiplier(state.world.resource_players)
			resource["remaining"] = mini(ceili(6*multiplier),old+ceili(content.fish_refill_quantity*multiplier))
			if resource["remaining"] != old:
				resource["version"] += 1
				changed = true
			run.fish_refills[id] += content.fish_refill_seconds
	for building: Dictionary in run.buildings.values():
		if building["kind"] not in ["small_trap","large_trap"]: continue
		var owner: WildBaseState = actor_states.get(building["owner"],state)
		building["probability_bonus"] = config.skill_rules.trap_success_bonus if WildSkillRules.level(owner.skills,"trap") >= 3 else 0.0
		if WildTrapRules.tick(building,run,state.world,content,config): changed = true
	return changed
