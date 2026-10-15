class_name WildAnimalAI
extends RefCounted
## 权威游走 / 警觉 / 逃跑 / 追击 / 返回；分步碰撞，目标仅稳定玩家 ID。

static func clear(world: WildWorldData, point: Vector2) -> bool:
	for offset: Vector2 in [Vector2(-5,-5),Vector2(5,-5),Vector2(-5,5),Vector2(5,5)]:
		if not world.walkable(world.cell_at(point+offset)): return false
	return true

static func move(animal: Dictionary, world: WildWorldData, direction: Vector2, real_seconds: float, speed: float, run: WildSurvivalState, config: WildGameConfig) -> void:
	var point: Vector2 = WildCombatWorld.position(animal,world)
	var displacement: Vector2 = direction.limit_length(1)*real_seconds*speed
	var steps: int = maxi(1,ceili(displacement.length()/4))
	for index: int in range(steps):
		for offset: Vector2 in [Vector2(displacement.x/steps,0),Vector2(0,displacement.y/steps)]:
			var next: Vector2 = point+offset
			if clear(world,next) and (animal["kind"] == "rabbit" or not WildCombatWorld.protected(world,run,next,config)): point = next
	animal["px"] = point.x
	animal["py"] = point.y
	var cell: Vector2i = world.cell_at(point)
	if (cell.x != animal["x"] or cell.y != animal["y"]) and run.elapsed_seconds-animal["last_track"] >= 300:
		run.tracks.append({"animal_id":animal["id"],"kind":animal["kind"],"x":animal["x"],"y":animal["y"],"at":run.elapsed_seconds})
		while run.tracks.size() > config.combat_rules.maximum_tracks: run.tracks.pop_front()
		animal["last_track"] = run.elapsed_seconds
	animal["x"] = cell.x
	animal["y"] = cell.y

## 直线受阻时选择四邻接短路径第一步，搜索限 20 格，避免绕全地图或穿建筑。
static func toward(world: WildWorldData, point: Vector2, goal: Vector2) -> Vector2:
	var start: Vector2i = world.cell_at(point)
	var end: Vector2i = world.cell_at(goal)
	if start == end: return (goal-point).normalized()
	var direct: Vector2 = (goal-point).normalized()
	if clear(world,point+direct*12): return direct
	var queue: Array[Vector2i] = [start]
	var first: Dictionary = {start:start}
	var depth: Dictionary = {start:0}
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		if depth[cell] >= 20: continue
		for offset: Vector2i in WildWorldData.DIRECTIONS:
			var next: Vector2i = cell+offset
			if first.has(next) or not clear(world,world.centre(next)): continue
			first[next] = next if cell == start else first[cell]
			depth[next] = depth[cell]+1
			if next == end: return (world.centre(first[next])-point).normalized()
			queue.append(next)
	return Vector2.ZERO

static func tick(state: WildBaseState, actor_states: Dictionary, config: WildGameConfig, real_seconds: float) -> bool:
	var run: WildSurvivalState = state.survival
	var world: WildWorldData = state.world
	var attacked: bool = false
	for animal: Dictionary in run.prey.values():
		if not animal["alive"]: continue
		var point: Vector2 = WildCombatWorld.position(animal,world)
		var home: Vector2 = world.centre(Vector2i(animal["home_x"],animal["home_y"]))
		var rules: Dictionary = config.combat_rules.animals[animal["kind"]]
		var target: String = animal["target"]
		if not target.is_empty() and (not run.bodies.has(target) or run.bodies[target].hp <= 0 or world.players[target].distance_to(home) > config.combat_rules.leash_tiles*world.tile_pixels or WildCombatWorld.protected(world,run,world.players[target],config)):
			animal["target"] = ""
			animal["mode"] = "return"
			target = ""
		if point.distance_to(home) > config.combat_rules.leash_tiles*world.tile_pixels:
			animal["mode"] = "return"
			animal["target"] = ""
			target = ""
		if animal["mode"] == "return":
			if point.distance_to(home) < 8: animal["mode"] = "wander"
			else:
				move(animal,world,toward(world,point,home),real_seconds,float(rules["speed"]),run,config)
				continue
		var nearest: String = ""
		var distance: float = float(rules["alert"])*world.tile_pixels
		for actor: String in world.players:
			if run.bodies[actor].hp <= 0 or (animal["kind"] != "rabbit" and WildCombatWorld.protected(world,run,world.players[actor],config)): continue
			var candidate: float = point.distance_to(world.players[actor])
			if candidate < distance and WildCombatRules.line_clear(world,point,world.players[actor]):
				distance = candidate
				nearest = actor
		if animal["kind"] == "wolf" and target.is_empty() and not nearest.is_empty():
			animal["target"] = nearest
			target = nearest
			animal["mode"] = "chase"
		var direction := Vector2.ZERO
		if animal["kind"] == "rabbit" and not nearest.is_empty():
			animal["mode"] = "flee"
			direction = (point-world.players[nearest]).normalized()
		elif not target.is_empty():
			animal["mode"] = "chase"
			var goal: Vector2 = world.players[target]
			if point.distance_to(goal) <= world.tile_pixels and WildCombatRules.line_clear(world,point,goal):
				if run.elapsed_seconds >= animal["ready_at"]:
					var personal: WildBaseState = actor_states.get(target,state)
					var hit: WildOperationResult = WildDamageRules.apply(personal,target,float(rules["damage"])*WildCombatWorld.health_scale(run,animal["kind"]),"physical",config.health_rules)
					if hit.successful:
						animal["ready_at"] = run.elapsed_seconds+float(rules["cooldown"])*config.game_seconds_per_real_second
						run.combat_feedback[target] = {"at":run.elapsed_seconds,"kind":"hurt","damage":hit.payload["damage"],"x":goal.x,"y":goal.y}
						run.notice = "被%s攻击，受到 %.1f 物理伤害。" % ["野猪" if animal["kind"] == "boar" else "狼",hit.payload["damage"]]
						attacked = true
			else: direction = toward(world,point,goal)
		elif animal["kind"] == "boar" and not nearest.is_empty():
			animal["mode"] = "alert"
		else:
			animal["mode"] = "wander"
			if run.elapsed_seconds >= animal["wander_at"]:
				var random := RandomNumberGenerator.new()
				random.state = str(animal["random_state"]).to_int()
				var angle: float = random.randf_range(0,TAU)
				animal["direction"] = [cos(angle),sin(angle)]
				animal["wander_at"] = run.elapsed_seconds+random.randf_range(2,4)*config.game_seconds_per_real_second
				animal["random_state"] = str(random.state)
			direction = Vector2(animal["direction"][0],animal["direction"][1])
			if point.distance_to(home) >= config.combat_rules.wander_tiles*world.tile_pixels: direction = toward(world,point,home)
		move(animal,world,direction,real_seconds,float(rules["speed"])*(0.35 if animal["mode"] == "wander" else 1.0),run,config)
	return attacked
