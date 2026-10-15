class_name WildCoopService
extends RefCounted
## 房主应用服务：身份绑定以外的所有事务在这里处理，网络 / UI 不拥有状态。
## 候选状态含全部玩家与共享容器，写盘失败不提交，不发送成功收据。

var _config: WildGameConfig
var _catalog: WildItemCatalog
var _content: WildSurvivalContent
var _save: Callable
var state: WildCoopState
var online: Dictionary = {}
var activities: Dictionary = {}
var save_blocked: bool = false
var _pending_disconnects: Dictionary = {}

func _init(config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent, save_record: Callable) -> void:
	_config = config
	_catalog = catalog
	_content = content
	_save = save_record

## 验证版本独立物资包；绝不复制永久仓库进入合作世界。
func create(host: String, nickname: String, seed_text: String, token: String) -> WildOperationResult:
	var generator := WildWorldGenerator.new(_config)
	var generated: WildOperationResult = generator.generate(seed_text)
	if not generated.successful: return generated
	var room := WildCoopState.new()
	room.host_id = host
	var world_record: Dictionary = generated.payload["world"]
	world_record["players"] = {host:world_record["spawn"].map(func(value: Variant) -> float: return (float(value)+0.5)*_config.terrain_tile_pixels)}
	room.world = WildWorldCodec.decode(world_record,_config)
	if room.world == null: return WildOperationResult.reject(&"GENERATION_FAILED")
	room.survival = WildSurvivalSimulation.create(host,seed_text)
	_add_member(room,host,nickname,token)
	WildProgressionWorld.initialize(room.members[host],_content)
	var result: WildOperationResult = _commit(room)
	if result.successful: online[host] = true
	return result

func restore(raw: Dictionary, host: String) -> WildOperationResult:
	if not raw.get("lifecycle",{}) is Dictionary or (not raw.get("lifecycle",{}).is_empty()) != uses_personal_profiles(): return WildOperationResult.reject(&"WRONG_ROOM_MODE")
	var restored: WildCoopState = WildCoopCodec.decode(raw,_config,_catalog,_content)
	if restored == null or restored.host_id != host: return WildOperationResult.reject(&"INVALID_SAVE")
	if restored.started and WildCombatWorld.initialize(restored.members[host],_config,restored.members.size()):
		var migrated: WildOperationResult = _save.call(restored.record(),false)
		if not migrated.successful: return migrated
	# 网络连接不会随存档恢复；原成员的角色、位置与物资完整保留。
	state = restored
	online.clear()
	return WildOperationResult.accept()

func join(actor: String, nickname: String, token: String) -> WildOperationResult:
	if state.members.has(actor):
		if token.sha256_text() != state.token_hashes[actor]: return WildOperationResult.reject(&"IDENTITY_DENIED")
		if online.get(actor,false): return WildOperationResult.reject(&"ALREADY_CONNECTED")
		if _pending_disconnects.has(actor) and not checkpoint().successful: return WildOperationResult.reject(&"SAVE_FAILED")
		online[actor] = true
		return WildOperationResult.accept({"reconnected":true,"token":token})
	if state.started: return WildOperationResult.reject(&"ROSTER_LOCKED")
	if state.members.size() >= maximum_members(): return WildOperationResult.reject(&"ROOM_FULL")
	if actor.is_empty() or actor.length() > 128 or nickname.is_empty() or nickname.length() > 32: return WildOperationResult.reject(&"INVALID_REQUEST")
	var secret: String = WildStableId.create("reconnect") + WildStableId.create("secret")
	var candidate: WildCoopState = state.copy(_config)
	_add_member(candidate,actor,nickname,secret)
	var result: WildOperationResult = _commit(candidate)
	if result.successful:
		online[actor] = true
		return WildOperationResult.accept({"reconnected":false,"token":secret})
	return result

## 验证房间保留双人上限；完整合作服务覆盖此容量策略。
func maximum_members() -> int:
	return 2

func uses_personal_profiles() -> bool:
	return false

func _add_member(room: WildCoopState, actor: String, nickname: String, token: String) -> void:
	room.members[actor] = WildBaseState.new(actor,_config)
	room.names[actor] = nickname
	room.token_hashes[actor] = token.sha256_text()
	room.world.players[actor] = room.world.centre(room.world.spawn) + Vector2(0,4 * (room.members.size()-1))
	room.survival.bodies[actor] = WildBodyState.new()
	WildIllnessRules.seed_body(room.survival.bodies[actor],room.world.seed_text,actor)
	room.bind_shared()
	for definition: String in ["knife","flint","bottle","wood","fiber","stone","ration","bandage","herbal_medicine","fishing_kit"]:
		var quantity: int = {"wood":16,"fiber":10,"stone":3,"ration":3,"bandage":2,"herbal_medicine":2}.get(definition,1)
		var item_definition: WildItemDefinition = _catalog.find(StringName(definition))
		while quantity > 0:
			var amount: int = mini(quantity,item_definition.max_stack)
			var item := WildItemInstance.new(item_definition,amount)
			assert(WildInventoryOperations.insert(room.members[actor],_catalog,_config,item),"Verification kit must fit")
			quantity -= amount

func body_snapshot(actor: String) -> Dictionary:
	return WildBodyView.create(state.members[actor],actor,_config,_catalog,str(activities.get(actor,"idle"))) if state.members.has(actor) else {}

## 房主世界系统内部调用；没有对应的客户端 operation。
func apply_world_damage(actor: String, amount: float, cause: String) -> WildOperationResult:
	if not state.started or not state.members.has(actor): return WildOperationResult.reject(&"INVALID_PHASE")
	var candidate: WildCoopState = state.copy(_config)
	_simulate(candidate,true)
	if candidate.survival.outcome != "running": return WildOperationResult.reject(&"INVALID_PHASE")
	var result: WildOperationResult = WildDamageRules.apply(candidate.members[actor],actor,amount,cause,_config.health_rules)
	if not result.successful: return result
	if candidate.survival.bodies[actor].hp <= 0:
		candidate.survival.actions.erase(actor)
		var living: bool = false
		for body: WildBodyState in candidate.survival.bodies.values():
			if body.hp > 0: living = true
		if not living:
			candidate.survival.outcome = "lost"
			candidate.survival.actions.clear()
	var saved: WildOperationResult = _commit(candidate)
	return result if saved.successful else saved

## 断线取消进行中的动作；已用时间 / 体力不返还，材料尚未消耗。
func member_disconnected(actor: String) -> WildOperationResult:
	if not state.members.has(actor): return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	var candidate: WildCoopState = state.copy(_config)
	_pending_disconnects[actor] = true
	candidate.survival.actions.erase(actor)
	var result: WildOperationResult = _commit(candidate)
	online[actor] = false
	activities[actor] = "idle"
	return result

## 已绑定的网络身份单独传入。报文内 actor_id 无权改变执行者。
func submit(actor: String, envelope: Dictionary) -> WildOperationResult:
	if not state.members.has(actor) or not online.get(actor,false): return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	if envelope.get("room_id","") != state.room_id or envelope.get("run_id","") != state.run_id: return WildOperationResult.reject(&"WRONG_SESSION")
	if not envelope.get("request_id",null) is String or envelope["request_id"].is_empty() or envelope["request_id"].length() > 128 or not envelope.get("operation",null) is String or not envelope.get("payload",null) is Dictionary: return WildOperationResult.reject(&"INVALID_REQUEST")
	var request: String = actor + ":" + envelope["request_id"]
	var signature: String = JSON.stringify({"operation":envelope["operation"],"payload":envelope["payload"]},"",true)
	if state.receipts.has(request):
		var receipt: Dictionary = state.receipts[request]
		if receipt["signature"] != signature: return WildOperationResult.reject(&"REQUEST_ID_CONFLICT")
		return WildOperationResult.new(receipt["successful"],StringName(receipt["code"]),receipt["payload"])
	var candidate: WildCoopState = state.copy(_config)
	var payload: Dictionary = envelope["payload"].duplicate(true)
	# 快照版本先与已提交状态核对；随后刷新同一事务的腐坏时间不能把自身变成旧版本。
	if envelope["operation"] == "inventory.transfer":
		var previous: WildBaseState = state.view(actor,_config,true)
		if previous.containers.has(str(payload.get("source",""))) and previous.containers.has(str(payload.get("target",""))) and payload.get("source","") != "warehouse" and payload.get("target","") != "warehouse" and not state.survival.actions.has(actor):
			for field: String in ["source","target"]:
				var id: String = str(payload.get(field,""))
				if not WildDataValidation.whole(payload.get(field+"_version",null)): return WildOperationResult.reject(&"INVALID_REQUEST")
				if int(payload[field+"_version"]) != previous.containers[id].version: return WildOperationResult.reject(&"STALE_VERSION")
	_simulate(candidate,true)
	if envelope["operation"] == "inventory.transfer":
		var refreshed: WildBaseState = candidate.view(actor,_config,true)
		for field: String in ["source","target"]:
			var id: String = str(payload.get(field,""))
			if refreshed.containers.has(id): payload[field+"_version"] = refreshed.containers[id].version
	var result: WildOperationResult = _execute(candidate,actor,envelope["operation"],payload)
	if not result.successful: return result
	candidate.receipts[request] = {"signature":signature,"successful":true,"code":str(result.code),"payload":result.payload.duplicate(true)}
	var saved: WildOperationResult = _commit(candidate)
	return result if saved.successful else saved

func _execute(room: WildCoopState, actor: String, operation: String, data: Dictionary) -> WildOperationResult:
	if operation == "skill.train":
		if room.started: return WildOperationResult.reject(&"BASE_LEARNING_ONLY")
		# 尚未出发的验证大厅使用独立验证资金，复用基地规则，不触碰正式基地。
		var trainee: WildBaseState = room.members[actor]
		trainee.phase = WildRunFlow.Phase.BASE
		var learned: WildOperationResult = WildSkillRules.learn(trainee,data,_config.skill_rules,true)
		trainee.phase = WildRunFlow.Phase.WILDERNESS
		return learned
	if operation == "room.start":
		if actor != room.host_id: return WildOperationResult.reject(&"HOST_ONLY")
		if room.started or room.members.size() != 2 or online.values().count(true) != 2: return WildOperationResult.reject(&"ROOM_NOT_READY")
		room.started = true
		WildCombatWorld.initialize(room.members[room.host_id],_config,room.members.size())
		return WildOperationResult.accept()
	if not room.started or room.survival.outcome != "running" or room.survival.bodies[actor].hp <= 0: return WildOperationResult.reject(&"INVALID_PHASE")
	var personal: WildBaseState = room.members[actor]
	match operation:
		"combat.attack": return WildCombatRules.attack(personal,actor,data,_config,_catalog)
		"skill.unlock":
			if room.survival.actions.has(actor): return WildOperationResult.reject(&"ACTION_BUSY")
			return WildSkillRules.learn(personal,data,_config.skill_rules,false)
		"survival.start":
			if data.get("action","") == "sleep": return WildOperationResult.reject(&"COOP_SLEEP_PENDING")
			data.erase("checked_empty_box")
			if data.get("action","") == "demolish":
				var box_id: String = "camp_box:"+str(data.get("building_id",""))
				if room.boxes.has(box_id):
					if not room.boxes[box_id].placements.is_empty(): return WildOperationResult.reject(&"BOX_NOT_EMPTY")
					data["checked_empty_box"] = true
			var result: WildOperationResult = WildSurvivalActions.start(personal,actor,data,_config,_catalog,_content,true)
			if not result.successful: return result
			return WildCoopReservations.validate(room.survival,actor,room.survival.actions[actor],_content)
		"survival.cancel":
			room.survival.actions.erase(actor)
			return WildOperationResult.accept()
		"survival.claim_output":
			return WildSurvivalCommands.execute(personal,WildGameCommand.new(actor,&"survival.claim_output",data),_config,_catalog,_content)
		"inventory.transfer":
			if room.survival.actions.has(actor): return WildOperationResult.reject(&"ACTION_BUSY")
			for field: String in ["source","target"]:
				var id: String = str(data.get(field,""))
				if id == "warehouse": return WildOperationResult.reject(&"FORBIDDEN_CONTAINER")
				if room.boxes.has(id) and not WildBuildingRules.in_reach(room.world,actor,room.survival.buildings[id.trim_prefix("camp_box:")]): return WildOperationResult.reject(&"OUT_OF_REACH")
				if room.boxes.has(id):
					for action: Dictionary in room.survival.actions.values():
						if action["type"] == "demolish" and "camp_box:"+action["building_id"] == id: return WildOperationResult.reject(&"BUILDING_RESERVED")
			return WildInventoryRules.transfer(room.view(actor,_config,true),_catalog,_config,actor,data)
		_:
			return WildOperationResult.reject(&"UNKNOWN_COMMAND")

func move(actor: String, direction: Vector2, real_seconds: float, sprint: bool) -> Vector2:
	if not state.world.players.has(actor): return Vector2.ZERO
	if save_blocked or not state.started or not online.get(actor,false) or state.survival.outcome != "running" or state.survival.actions.has(actor) or state.survival.bodies[actor].hp <= 0: return state.world.players[actor]
	var weight: float = state.members[actor].carried_weight(_catalog,_config)
	var speed: float = _config.walking_speed_pixels_per_second if not sprint else _config.sprinting_speed_pixels_per_second
	if state.survival.bodies[actor].stamina <= 0: speed = _config.exhausted_speed_pixels_per_second
	var overload: float = clampf((weight-_config.soft_weight_limit_kg)/(_config.hard_weight_limit_kg-_config.soft_weight_limit_kg),0,1)
	speed *= 1 - _config.maximum_weight_slowdown * overload
	speed *= WildIllnessRules.movement_multiplier(state.survival.bodies[actor],_config.health_rules)
	var point: Vector2 = WildWorldRules.move(state.world,actor,direction,real_seconds,speed)
	activities[actor] = ("sprint" if sprint else "walk") if not direction.is_zero_approx() else "idle"
	WildSurvivalSimulation.explore(state.members[actor],actor)
	return point

## 只由房主时钟调用一次；离线成员也持续推进身体，个人菜单不能暂停。
func advance(real_seconds: float) -> WildOperationResult:
	if not state.started or state.survival.outcome != "running": return WildOperationResult.accept()
	if save_blocked: return checkpoint()
	WildSurvivalSimulation.queue_time(state.survival,minf(real_seconds,0.25)*_config.game_seconds_per_real_second,"idle")
	if state.survival.pending_seconds < _config.simulation_step_seconds: return WildOperationResult.accept()
	var candidate: WildCoopState = state.copy(_config)
	_simulate(candidate,false)
	return _commit(candidate)

func _simulate(room: WildCoopState, force: bool) -> void:
	var before: float = room.survival.elapsed_seconds
	WildSurvivalSimulation.process(room.members[room.host_id],_config,_catalog,_content,force,room.members,activities)
	var elapsed: float = room.survival.elapsed_seconds - before
	for id: String in room.boxes.keys():
		if not room.survival.buildings.has(id.trim_prefix("camp_box:")): room.boxes.erase(id)
	for box: WildInventoryContainer in room.boxes.values():
		for entry: Dictionary in box.placements.values():
			var item: WildItemInstance = entry["item"]
			if item.freshness_hours > 0:
				item.freshness_hours = maxf(0,item.freshness_hours-elapsed/3600)
	# 独立储物箱按配置耗材 / 占地 / 计时建造，稳定 ID 防止恢复生成第二只箱。
	for id: String in room.survival.buildings:
		if room.survival.buildings[id]["kind"] == "storage_box" and not room.boxes.has("camp_box:"+id):
			var box := WildInventoryContainer.new("camp_box:"+id,"",_config.camp_storage_grid,_config.camp_storage_capacity_l)
			box.public_access = true
			room.boxes[box.container_id] = box

func checkpoint() -> WildOperationResult:
	var candidate: WildCoopState = state.copy(_config)
	for actor: String in _pending_disconnects: candidate.survival.actions.erase(actor)
	return _commit(candidate)

## 正常结束连接与断线采用相同的动作取消规则，恢复房间不会完成旧的离线生产。
func end_room() -> WildOperationResult:
	for actor: String in state.members: _pending_disconnects[actor] = true
	return checkpoint()

func _commit(candidate: WildCoopState) -> WildOperationResult:
	candidate.revision += 1
	var result: WildOperationResult = _save.call(candidate.record(),false)
	if result.successful:
		state = candidate
		save_blocked = false
		for actor: String in _pending_disconnects.keys():
			if not state.survival.actions.has(actor): _pending_disconnects.erase(actor)
	else: save_blocked = true
	return result

## 网络快照只包含收件人的私人容器，不泄露其他玩家库存或重连密钥。
func snapshot(actor: String, include_world: bool = false) -> Dictionary:
	var personal: WildBaseState = state.members[actor]
	var containers: Dictionary = {}
	for id: String in personal.containers:
		if id == "warehouse": continue
		containers[id] = _container_snapshot(personal.containers[id])
	for id: String in state.boxes:
		if WildBuildingRules.in_reach(state.world,actor,state.survival.buildings[id.trim_prefix("camp_box:")]): containers[id] = _container_snapshot(state.boxes[id])
	var players: Dictionary = {}
	for id: String in state.members:
		var point: Vector2 = state.world.players[id]
		players[id] = {"position":[point.x,point.y],"body":body_snapshot(id),"name":state.names[id],"online":online.get(id,false),"action":state.survival.actions.get(id,{}).get("type","")}
	var result: Dictionary = {"room_id":state.room_id,"run_id":state.run_id,"revision":state.revision,"host_id":state.host_id,"started":state.started,"players":players,"containers":containers,"elapsed_seconds":state.survival.elapsed_seconds,"pending_seconds":state.survival.pending_seconds,"outcome":state.survival.outcome,"action":state.survival.actions.get(actor,{}).duplicate(true),"notice":state.survival.notice,"carried_weight_kg":personal.carried_weight(_catalog,_config),"save_blocked":save_blocked,"buildings":state.survival.buildings.duplicate(true),"outputs":{},"resources":state.world.resources.duplicate(true)}
	result["skills"] = WildSkillRules.snapshot(personal.skills,_config.skill_rules)
	result["buildings"] = WildProgressionView.buildings(state.survival)
	result["currency"] = personal.currency
	result["can_train"] = not state.started
	result["prey"] = WildCombatView.animals(state.survival)
	result.merge(WildCombatView.create(personal,actor))
	for id: String in state.survival.outputs:
		if state.survival.outputs[id]["owner"] == actor: result["outputs"][id] = state.survival.outputs[id].duplicate(true)
	if include_world: result["world"] = state.world.record()
	return result

func _container_snapshot(container: WildInventoryContainer) -> Dictionary:
	var raw: Dictionary = container.record()
	raw.merge({"grid":[container.grid_size.x,container.grid_size.y],"capacity_l":container.capacity_l,"volume_l":container.volume(_catalog),"weight_kg":container.weight(_catalog),"owner_id":container.owner_id,"public_access":container.public_access,"equipment_slot":container.equipment_slot})
	return raw
