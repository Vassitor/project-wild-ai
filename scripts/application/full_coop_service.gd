class_name WildFullCoopService
extends WildCoopService
## 完整合作用实际个人租约，旧双人验证仍复用父类。存档 / outbox / 死亡属于同一提交。
var _real_clock: Callable
var _realtime_anchor: float
var _realtime_base: float = 0.0

func _init(config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent, save_record: Callable, real_clock: Callable = Callable()) -> void:
	super(config,catalog,content,save_record)
	_real_clock = real_clock if real_clock.is_valid() else func() -> float: return Time.get_ticks_msec()/1000.0
	_realtime_anchor = float(_real_clock.call())

## 提案期限使用单调现实钟，不能因低帧率或游戏时钟的追赶上限延长三十秒。
func _refresh_realtime(room: WildCoopState) -> void:
	room.lifecycle["real_seconds"] = maxf(float(room.lifecycle["real_seconds"]),_realtime_base+maxf(0,float(_real_clock.call())-_realtime_anchor))

func maximum_members() -> int:
	return 4

func uses_personal_profiles() -> bool:
	return true

func join(actor: String, nickname: String, token: String) -> WildOperationResult:
	if not state.members.has(actor) and state.lifecycle["phase"] != "lobby": return WildOperationResult.reject(&"ROSTER_LOCKED")
	var result: WildOperationResult = super.join(actor,nickname,token)
	if result.successful and result.payload.get("reconnected",false) and not state.lifecycle["vote"].is_empty():
		var candidate: WildCoopState = state.copy(_config)
		WildCoopSleep.cancel(candidate,"原成员重新上线，睡眠需重新征得同意。")
		var saved: WildOperationResult = _commit(candidate)
		if not saved.successful:
			online[actor] = false
			_pending_disconnects[actor] = true
			return saved
	return result

func _add_member(room: WildCoopState, actor: String, nickname: String, token: String) -> void:
	if room.lifecycle.is_empty(): WildCoopDeliveries.initialize(room)
	room.members[actor] = WildBaseState.new(actor,_config)
	room.members[actor].currency = 0
	room.names[actor] = nickname
	room.token_hashes[actor] = token.sha256_text()
	room.world.players[actor] = room.world.centre(room.world.spawn)
	room.survival.bodies[actor] = WildBodyState.new()
	WildIllnessRules.seed_body(room.survival.bodies[actor],room.world.seed_text,actor)
	room.bind_shared()

func restore(raw: Dictionary, host: String) -> WildOperationResult:
	if not raw.get("lifecycle",null) is Dictionary or raw["lifecycle"].is_empty(): return WildOperationResult.reject(&"WRONG_ROOM_MODE")
	var result: WildOperationResult = super.restore(raw,host)
	if not result.successful: return result
	_realtime_base = float(state.lifecycle["real_seconds"])
	_realtime_anchor = float(_real_clock.call())
	# 恢复不重置角色；旧投票 / 赠送与生产动作取消，未消耗材料留在原容器。
	state.survival.actions.clear()
	state.lifecycle["vote"] = {}
	state.lifecycle["gifts"] = {}
	return _commit(state.copy(_config))

func _execute(room: WildCoopState, actor: String, operation: String, data: Dictionary) -> WildOperationResult:
	_refresh_realtime(room)
	match operation:
		"profile.offer": return WildCoopLifecycle.offer(room,actor,data,_config,_catalog)
		"profile.withdraw": return WildCoopLifecycle.withdraw(room,actor)
		"profile.ack": return WildCoopDeliveries.acknowledge(room,actor,data)
		"room.ready":
			if room.lifecycle["phase"] != "lobby" or not data.get("ready",null) is bool or not room.lifecycle["offers"].get(actor,{}).get("active",false): return WildOperationResult.reject(&"ROOM_NOT_READY")
			room.lifecycle["ready"][actor] = data["ready"]
			return WildOperationResult.accept()
		"room.start":
			if actor != room.host_id: return WildOperationResult.reject(&"HOST_ONLY")
			return WildCoopLifecycle.start(room,online,_config)
		"room.loaded": return WildCoopLifecycle.loaded(room,actor,data)
		"sleep.vote": return WildCoopSleep.execute(room,actor,data,online,_config,_catalog,_content)
		"skill.train": return WildOperationResult.reject(&"BASE_LEARNING_ONLY")
	if room.lifecycle["phase"] != "running" or room.survival.bodies[actor].hp <= 0: return WildOperationResult.reject(&"INVALID_PHASE")
	if room.lifecycle["vote"].get("sleeping",false): return WildOperationResult.reject(&"SLEEP_BUSY")
	if operation.begins_with("gift."): return WildCoopGifts.execute(room,actor,operation,data,online,_config,_catalog)
	if WildCoopGifts.locked(room,actor) and operation not in ["survival.cancel"]: return WildOperationResult.reject(&"GIFT_RESERVED")
	if operation == "survival.start":
		if data.get("action","") == "sleep": return WildCoopSleep.execute(room,actor,data,online,_config,_catalog,_content)
		var box: String = str(data.get("materials_box",""))
		if not box.is_empty():
			if data.get("action","") not in WildCoopMaterials.ACTIONS or not room.boxes.has(box): return WildOperationResult.reject(&"FORBIDDEN_CONTAINER")
			if not WildBuildingRules.in_reach(room.world,actor,room.survival.buildings[box.trim_prefix("camp_box:")]): return WildOperationResult.reject(&"OUT_OF_REACH")
		WildCoopMaterials.bind(room,actor,box)
		var result: WildOperationResult = super._execute(room,actor,operation,data)
		if result.successful:
			var action: Dictionary = room.survival.actions[actor]
			action["materials_box"] = ""
			# 只保留实际使用的源依赖；选中过但未取料的空箱仍可由队友拆除。
			if room.boxes.has(box):
				for reserved: Dictionary in action["reservations"]:
					if room.boxes[box].placements.has(reserved["id"]): action["materials_box"] = box
			if not WildCoopMaterials.valid(room): return WildOperationResult.reject(&"MATERIAL_RESERVED")
		return result
	if operation == "inventory.transfer":
		var item_id: String = str(data.get("item_id",""))
		if WildCoopMaterials.locked(room,item_id): return WildOperationResult.reject(&"MATERIAL_RESERVED")
		for field: String in ["source","target"]:
			var id: String = str(data.get(field,""))
			if room.corpses.has(id):
				if field == "target": return WildOperationResult.reject(&"CORPSE_WITHDRAW_ONLY")
				if not WildCoopLifecycle.corpse_in_reach(room,actor,id): return WildOperationResult.reject(&"OUT_OF_REACH")
	return super._execute(room,actor,operation,data)

func move(actor: String, direction: Vector2, seconds: float, sprint: bool) -> Vector2:
	if state.lifecycle["phase"] != "running" or state.lifecycle["vote"].get("sleeping",false): return state.world.players.get(actor,Vector2.ZERO)
	return super.move(actor,direction,seconds,sprint)

func advance(seconds: float) -> WildOperationResult:
	if save_blocked: return checkpoint()
	if state.lifecycle["phase"] != "running": return WildOperationResult.accept()
	if not state.lifecycle["vote"].is_empty():
		var candidate: WildCoopState = state.copy(_config)
		_refresh_realtime(candidate)
		var vote: Dictionary = candidate.lifecycle["vote"]
		if not vote["sleeping"]:
			if candidate.lifecycle["real_seconds"] >= vote["expires"]: WildCoopSleep.cancel(candidate,"睡眠投票超时。")
		else:
			if not WildCoopSleep.safe(candidate): WildCoopSleep.cancel(candidate,"附近有威胁或角色身体危急，已醒来。")
			else:
				var hp: Dictionary = {}
				for actor: String in candidate.members: hp[actor] = candidate.survival.bodies[actor].hp
				var step: float = minf(60,vote["remaining"])
				WildSurvivalSimulation.queue_time(candidate.survival,step,"sleep")
				_simulate(candidate,true)
				vote["remaining"] = maxf(0,float(vote["remaining"])-step)
				var interrupted: bool = not WildCoopSleep.safe(candidate)
				for actor: String in hp:
					if candidate.survival.bodies[actor].hp < hp[actor]: interrupted = true
				if interrupted or vote["remaining"] <= 0: WildCoopSleep.cancel(candidate,"睡眠中断。" if interrupted else "睡眠完成。")
		var result: WildOperationResult = _commit(candidate)
		if not result.successful or vote.get("sleeping",false): return result
	return super.advance(seconds)

func _simulate(room: WildCoopState, force: bool) -> void:
	if room.lifecycle["phase"] != "running": return
	var corpses_before: Array = room.corpses.keys()
	var before: float = room.survival.elapsed_seconds
	WildCoopMaterials.bind_actions(room)
	super._simulate(room,force)
	WildCoopLifecycle.reconcile(room,_config,_catalog)
	for id: String in corpses_before:
		for entry: Dictionary in room.corpses[id].placements.values():
			var item: WildItemInstance = entry["item"]
			if item.freshness_hours > 0: item.freshness_hours = maxf(0,item.freshness_hours-(room.survival.elapsed_seconds-before)/3600)
	for actor: String in room.lifecycle["dead"]: WildCoopGifts.cancel_member(room,actor)

func member_disconnected(actor: String) -> WildOperationResult:
	var candidate: WildCoopState = state.copy(_config)
	_pending_disconnects[actor] = true
	candidate.survival.actions.erase(actor)
	WildCoopSleep.cancel(candidate,"成员断线，睡眠提案已取消。")
	WildCoopGifts.cancel_member(candidate,actor)
	candidate.lifecycle["ready"][actor] = false
	var result: WildOperationResult = _commit(candidate)
	online[actor] = false
	activities[actor] = "idle"
	return result

func end_room() -> WildOperationResult:
	var candidate: WildCoopState = state.copy(_config)
	WildCoopSleep.cancel(candidate,"房主保存并结束房间。")
	candidate.lifecycle["gifts"] = {}
	candidate.survival.actions.clear()
	# 全员加载屏障尚未解除时没有世界推进；取消投放要释放原始租约，不能永久占住行装。
	if candidate.lifecycle["phase"] == "loading":
		candidate.started = false
		candidate.lifecycle["phase"] = "cancelled"
	if candidate.lifecycle["phase"] in ["lobby","cancelled"]:
		for actor: String in candidate.members: WildCoopLifecycle.withdraw(candidate,actor)
		candidate.lifecycle["phase"] = "cancelled"
	return _commit(candidate)

func checkpoint() -> WildOperationResult:
	var candidate: WildCoopState = state.copy(_config)
	for actor: String in _pending_disconnects:
		candidate.survival.actions.erase(actor)
		WildCoopGifts.cancel_member(candidate,actor)
		candidate.lifecycle["ready"][actor] = false
	if not _pending_disconnects.is_empty(): WildCoopSleep.cancel(candidate,"成员断线，睡眠已取消。")
	return _commit(candidate)

func _commit(candidate: WildCoopState) -> WildOperationResult:
	if candidate.lifecycle.get("vote",{}).get("sleeping",false):
		for actor: String in candidate.lifecycle["vote"]["agree"]:
			if candidate.survival.actions.get(actor,{}).get("type","") != "sleep":
				WildCoopSleep.cancel(candidate,"睡眠行动中断，所有人醒来。")
				break
	WildCoopLifecycle.reconcile(candidate,_config,_catalog)
	WildCoopDeliveries.growth(candidate)
	return super._commit(candidate)

func snapshot(actor: String, include_world: bool = false) -> Dictionary:
	var result: Dictionary = super.snapshot(actor,include_world)
	var visible: Dictionary = {}
	for id: String in state.corpses:
		if WildCoopLifecycle.corpse_in_reach(state,actor,id) and state.survival.bodies[actor].hp > 0: result["containers"][id] = _container_snapshot(state.corpses[id])
	for id: String in state.lifecycle["gifts"]:
		var gift: Dictionary = state.lifecycle["gifts"][id]
		if actor in [gift["from"],gift["target"]]:
			visible[id] = gift.duplicate(true)
			var found: Dictionary = WildInventoryOperations.find(state.members[gift["from"]],gift["item_id"])
			if not found.is_empty(): visible[id]["item"] = (found["item"] as WildItemInstance).record()
	result["cooperation"] = {"phase":state.lifecycle["phase"],"ready":state.lifecycle["ready"].duplicate(true),"loaded":state.lifecycle["loaded"].duplicate(true),"world_hash":state.lifecycle["world_hash"],"vote":state.lifecycle["vote"].duplicate(true),"dead":state.lifecycle["dead"].duplicate(true),"gifts":visible,"has_loadout":state.lifecycle["offers"].get(actor,{}).get("active",false),"deliveries":WildCoopDeliveries.pending(state,actor)}
	result["can_train"] = false
	var weight: float = state.members[actor].carried_weight(_catalog,_config)
	var overload: float = clampf((weight-_config.soft_weight_limit_kg)/(_config.hard_weight_limit_kg-_config.soft_weight_limit_kg),0,1)
	var multiplier: float = (1-_config.maximum_weight_slowdown*overload)*WildIllnessRules.movement_multiplier(state.survival.bodies[actor],_config.health_rules)
	result["movement_speed"] = {"walk":_config.walking_speed_pixels_per_second*multiplier,"sprint":_config.sprinting_speed_pixels_per_second*multiplier,"exhausted":_config.exhausted_speed_pixels_per_second*multiplier}
	return result
