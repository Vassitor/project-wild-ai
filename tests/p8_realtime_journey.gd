class_name WildP8RealtimeJourney
extends Node
## P8 默认时钟自动驾驶；只有合法睡眠跳时，其他行动按真实帧时间等待。
## 策略沿用 P3，记录真实耗时与普通 / 睡眠游戏秒；不代表人工体验验收。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
var state: WildBaseState
var failure: String = ""
var _last_cooking_day: int = -1

class MemoryStore extends RefCounted:
	var record: Dictionary = {}
	func load_records() -> WildOperationResult:
		return WildOperationResult.accept({"exists":not record.is_empty(),"primary":record.duplicate(true),"backup":{}})
	func save_record(data: Dictionary,_preserve: bool = false) -> WildOperationResult:
		record = data.duplicate(true)
		return WildOperationResult.accept()

func run(seed_text: String, stop_after_setup: bool = false) -> WildBaseState:
	var generator := WildWorldGenerator.new(CONFIG)
	var memory := MemoryStore.new()
	var service := WildBaseService.new(CONFIG,CATALOG,memory.load_records,memory.save_record,Callable(),generator.generate,CONTENT)
	if not service.initialize("p").successful: return null
	for index: int in range(5):
		if not service.submit(WildGameCommand.new("p",&"shop.buy",{"definition_id":"ration","quantity":1 if index == 4 else 4})).successful: return null
	if not service.submit(WildGameCommand.new("p",&"shop.buy",{"definition_id":"bandage","quantity":2})).successful: return null
	var view: Dictionary = service.snapshot()
	for entry: Dictionary in view["containers"]["warehouse"]["entries"]:
		var current: Dictionary = service.snapshot()
		service.submit(WildGameCommand.new("p",&"inventory.transfer",{"source":"warehouse","target":"backpack","item_id":entry["item"]["id"],"source_version":current["containers"]["warehouse"]["version"],"target_version":current["containers"]["backpack"]["version"],"auto":true}))
	service.submit(WildGameCommand.new("p",&"expedition.prepare",{"seed":seed_text}))
	if not service.submit(WildGameCommand.new("p",&"expedition.commit")).successful: return null
	state = WildBaseStateCodec.decode(memory.record,"p",CONFIG,CATALOG)
	if state == null: return null
	# 初始材料来自真实资源，营地 / 火堆材料与体力按同一规则消耗。
	for index: int in range(10):
		if not await gather("branch"): return state
	for index: int in range(2):
		if not await gather("fiber"): return state
	if not await gather("stone"): return state
	if not await walk_to(state.world.spawn): return state
	if not await act({"action":"build","recipe":"camp"}): return state
	if not await act({"action":"build","recipe":"fire"}): return state
	if stop_after_setup:
		if not await gather("root") or not await approach_building("fire") or not await act({"action":"light"}) or not await act({"action":"cook"}): return state
		return state
	var iterations: int = 0
	while state.survival.outcome == "running" and iterations < 1000 and failure.is_empty():
		iterations += 1
		if not await maintain(): break
		if state.survival.outcome != "running": break
		var day: int = int(state.survival.elapsed_seconds/86400)
		if day != _last_cooking_day:
			_last_cooking_day = day
			# P6 外部风险下先使用已携带的原料，避免每天无用重复远行采集。
			if count(&"root") == 0 and not await gather("root"): break
			if not await return_to_camp(): break
			var fire: String = WildBuildingRules.nearby(state,"p","fire")
			if fire.is_empty():
				# 营地另一侧不一定同时够到篝火，沿建筑外缘寻找可达交互格。
				if not await approach_building("fire"): break
				fire = WildBuildingRules.nearby(state,"p","fire")
			if state.survival.buildings[fire]["fuel_seconds"] < 900:
				if count(&"wood") == 0 and not await gather("branch"): break
				if not await approach_building("fire") or not await act({"action":"fuel"}): break
			if not state.survival.buildings[fire]["lit"] and not await act({"action":"light"}): break
			if not await act({"action":"cook"}): break
			var cooked: String = WildInventoryOperations.choose(state,&"roasted_root")
			if not cooked.is_empty() and not await act({"action":"eat","item_id":cooked}): break
		if not await return_to_camp(): break
		if state.survival.outcome != "running": break
		if not await act({"action":"sleep","hours":4}): break
	if iterations >= 1000: failure = "自动策略达到迭代上限"
	return state

func maintain() -> bool:
	if state.survival.outcome != "running": return true
	var body: WildBodyState = state.survival.bodies["p"]
	if body.bleeding and not await _stop_bleeding(): return false
	if body.water < 60:
		var spring: Dictionary = nearest_resource("spring")
		if spring.is_empty() or not await walk_to(Vector2i(spring["x"],spring["y"])): return false
		while body.water < 85 and state.survival.outcome == "running":
			if not await act({"action":"drink","resource_id":spring["id"],"version":spring["version"],"litres":0.5},false): return false
	if body.nutrition[0] < 70:
		var food_id: String = WildInventoryOperations.choose(state,&"ration")
		if food_id.is_empty(): food_id = WildInventoryOperations.choose(state,&"root")
		if food_id.is_empty():
			if not await gather("root",false): return false
			food_id = WildInventoryOperations.choose(state,&"root")
		if not await act({"action":"eat","item_id":food_id},false): return false
	if body.stamina < 24: await advance(3600,"idle")
	return true

func act(payload: Dictionary,care: bool = true) -> bool:
	if state.survival.outcome != "running": return true
	var original_cell: Vector2i = state.world.cell_at(state.world.players["p"])
	if care and not await maintain(): return false
	if state.survival.outcome != "running": return true
	if care and not await walk_to(original_cell): return false
	if payload["action"] == "sleep" and state.survival.bodies["p"].bleeding and not await _stop_bleeding(): return false
	var result: WildOperationResult = WildSurvivalActions.start(state,"p",payload,CONFIG,CATALOG,CONTENT)
	if not result.successful:
		failure = "%s failed: %s at %.1fh" % [payload,result.code,state.survival.elapsed_seconds/3600]
		return false
	if payload["action"] == "sleep":
		var before: float = state.survival.elapsed_seconds
		WildSurvivalSimulation.sleep(state,"p",CONFIG,CATALOG,CONTENT)
		sleep_game_seconds += state.survival.elapsed_seconds-before
	else: await advance(state.survival.actions["p"]["remaining"],"idle")
	return true

func _stop_bleeding() -> bool:
	var id: String = WildInventoryOperations.choose(state,&"bandage")
	if id.is_empty():
		failure = "自动策略绷带已用尽"
		return false
	return await act({"action":"treat","item_id":id},false)

var active_game_seconds: float = 0
var sleep_game_seconds: float = 0
var _telemetry_at: int = 0

## 每帧只推进真实 delta × 默认 120；慢帧夹紧与正式组合根相同，不以批量队列伪装正常速度。
func advance(seconds: float,activity: String) -> void:
	var remaining: float = seconds
	var previous: int = Time.get_ticks_usec()
	while remaining > 0.00001 and state.survival.outcome == "running":
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var used: float = minf(remaining,minf((now-previous)/1000000.0,0.1)*CONFIG.game_seconds_per_real_second)
		previous = now
		remaining -= used
		active_game_seconds += used
		WildSurvivalSimulation.queue_time(state.survival,used,activity)
		WildSurvivalSimulation.process(state,CONFIG,CATALOG,CONTENT,true)
		if Time.get_ticks_msec()-_telemetry_at >= 30000:
			_telemetry_at = Time.get_ticks_msec()
			print("P8 realtime seed %s: %.2f h, HP %.1f, water %.1f" % [state.world.seed_text,state.survival.elapsed_seconds/3600,state.survival.bodies["p"].hp,state.survival.bodies["p"].water])

func gather(kind: String,care: bool = true) -> bool:
	if care and not await maintain(): return false
	var resource: Dictionary = nearest_resource(kind)
	if resource.is_empty():
		failure = "找不到资源 " + kind
		return false
	if not await walk_to(Vector2i(resource["x"],resource["y"])): return false
	return await act({"action":"gather","resource_id":resource["id"],"version":resource["version"]},false)

func nearest_resource(kind: String) -> Dictionary:
	var distances: Dictionary = state.world.distances(state.world.cell_at(state.world.players["p"]))
	var nearest: Dictionary = {}
	var closest: int = 999999
	for entry: Dictionary in state.world.resources.values():
		var cell := Vector2i(entry["x"],entry["y"])
		var distance: int = int(distances.get(cell,999999))
		if entry["kind"] == kind and entry["remaining"] > 0 and distance < closest:
			closest = distance
			nearest = entry
	return nearest

func walk_to(destination: Vector2i) -> bool:
	if state.survival.outcome != "running": return true
	var current: Vector2i = state.world.cell_at(state.world.players["p"])
	var distances: Dictionary = state.world.distances(current)
	if not distances.has(destination):
		failure = "目标不可达"
		return false
	var path: Array[Vector2i] = [destination]
	while destination != current:
		for direction: Vector2i in WildWorldData.DIRECTIONS:
			var previous: Vector2i = destination+direction
			if distances.get(previous,999999) == int(distances[destination])-1:
				destination = previous
				path.append(previous)
				break
	path.reverse()
	for cell: Vector2i in path:
		var target: Vector2 = state.world.centre(cell)
		for step: int in range(20):
			var difference: Vector2 = target - state.world.players["p"]
			if difference.length() < 0.01 or state.survival.outcome != "running": break
			var seconds: float = minf(0.1,difference.length()/CONFIG.walking_speed_pixels_per_second)
			WildWorldRules.move(state.world,"p",difference.normalized(),seconds,CONFIG.walking_speed_pixels_per_second)
			WildSurvivalSimulation.explore(state,"p")
			await advance(seconds*CONFIG.game_seconds_per_real_second,"walk")
	return true

func return_to_camp() -> bool:
	return await approach_building("camp")

func approach_building(kind: String) -> bool:
	if state.survival.outcome != "running": return true
	var distances: Dictionary = state.world.distances(state.world.cell_at(state.world.players["p"]))
	for building: Dictionary in state.survival.buildings.values():
		if building["kind"] != kind: continue
		var rectangle: Rect2i = WildBuildingRules.occupied(building)
		var choices: Array[Vector2i] = []
		for y: int in range(rectangle.position.y-1,rectangle.end.y+1):
			for x: int in range(rectangle.position.x-1,rectangle.end.x+1):
				var cell := Vector2i(x,y)
				if distances.has(cell): choices.append(cell)
		choices.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return distances[a] < distances[b])
		if not choices.is_empty(): return await walk_to(choices[0])
	failure = "找不到可达建筑 " + kind
	return false

func count(kind: StringName) -> int:
	var result: int = 0
	for container: WildInventoryContainer in state.containers.values():
		if container.carried:
			for entry: Dictionary in container.placements.values():
				if (entry["item"] as WildItemInstance).item_id == kind: result += (entry["item"] as WildItemInstance).quantity
	return result
