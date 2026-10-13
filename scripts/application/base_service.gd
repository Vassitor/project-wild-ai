class_name WildBaseService
extends RefCounted
## 基地事务应用服务：协调库存 / 商店 / 准备，保存成功后才提交候选状态。
## 文件与投放检查由 Callable 注入，界面 / 未来网络只能提交命令、读取快照。

signal changed
signal world_content_changed

var _config: WildGameConfig
var _catalog: WildItemCatalog
var _load: Callable
var _save: Callable
var _spawn_check: Callable
var _state: WildBaseState
var _generate: Callable
var _world_dirty: bool = false
var _last_activity: String = "idle"
var _content: WildSurvivalContent
var _save_blocked: bool = false


func _init(config: WildGameConfig, catalog: WildItemCatalog, load_records: Callable, save_record: Callable, spawn_check: Callable = Callable(), generate_world: Callable = Callable(), survival_content: WildSurvivalContent = null) -> void:
	_config = config
	_catalog = catalog
	_load = load_records
	_save = save_record
	_spawn_check = spawn_check
	_generate = generate_world
	_content = survival_content


func initialize(owner: String) -> WildOperationResult:
	if not _catalog.validate():
		return WildOperationResult.reject(&"INVALID_CATALOG")
	var loaded: WildOperationResult = _load.call()
	if not loaded.successful:
		return loaded
	var recovered: bool = false
	var initial: WildBaseState
	if not loaded.payload.get("exists", false):
		initial = WildBaseState.new(owner, _config)
		var supply: WildOperationResult = _ensure_supply(initial)
		if not supply.successful:
			return supply
	else:
		var primary: Dictionary = loaded.payload.get("primary", {})
		if WildSaveVersions.future(primary): return WildOperationResult.reject(&"INVALID_SAVE")
		# 新版本 / 其他玩家的有效元信息不是损坏，不可用旧备份悄悄覆盖。
		if (primary.has("save_version") and primary["save_version"] != 1) or (primary.has("player_id") and primary["player_id"] != owner):
			return WildOperationResult.reject(&"INVALID_SAVE")
		initial = WildBaseStateCodec.decode(loaded.payload.get("primary", {}), owner, _config, _catalog)
		if initial == null:
			initial = WildBaseStateCodec.decode(loaded.payload.get("backup", {}), owner, _config, _catalog)
			recovered = initial != null
		if initial == null:
			return WildOperationResult.reject(&"INVALID_SAVE")
	var migrated: bool = initial.phase == WildRunFlow.Phase.PREPARATION and not initial.active_run.has("seed")
	if migrated:
		initial.active_run["seed"] = WildWorldGenerator.random_seed()
	if recovered or migrated or not loaded.payload.get("exists", false):
		var saved: WildOperationResult = _save.call(initial.record(), recovered)
		if not saved.successful:
			return saved
	_state = initial
	return WildOperationResult.accept({"recovered_backup": recovered})


func current_phase() -> WildRunFlow.Phase:
	return _state.phase


func snapshot() -> Dictionary:
	var view: Dictionary = {"currency": _state.currency, "phase": _state.phase, "run_id": _state.active_run.get("run_id", ""), "seed": _state.active_run.get("seed", ""), "exploration_only": _state.active_run.get("exploration_only", false), "survival_enabled":_state.survival != null,"pending_count":_state.pending.size(),"last_settlement":_state.last_settlement.duplicate(true), "containers": {}}
	for id: String in _state.containers:
		var container: WildInventoryContainer = _state.containers[id]
		var record: Dictionary = container.record()
		record["grid"] = [container.grid_size.x, container.grid_size.y]
		record["capacity_l"] = container.capacity_l
		record["volume_l"] = container.volume(_catalog)
		record["weight_kg"] = container.weight(_catalog)
		record["equipment_slot"] = container.equipment_slot
		view["containers"][id] = record
	view["carried_weight_kg"] = _state.carried_weight(_catalog, _config)
	var overload: float = clampf((view["carried_weight_kg"] - _config.soft_weight_limit_kg) / (_config.hard_weight_limit_kg - _config.soft_weight_limit_kg), 0.0, 1.0)
	view["movement_multiplier"] = 1.0 - overload * _config.maximum_weight_slowdown
	view["skills"] = WildSkillRules.snapshot(_state.skills,_config.skill_rules)
	return view


## 预览走同一规则但只修改副本，不保存、不产生收据。
func preview_transfer(actor: String, payload: Dictionary) -> WildOperationResult:
	if actor != _state.player_id:
		return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	if _state.survival != null and _state.survival.actions.has(actor): return WildOperationResult.reject(&"ACTION_BUSY")
	if not _inventory_allowed():
		return WildOperationResult.reject(&"INVALID_PHASE")
	if _state.phase == WildRunFlow.Phase.WILDERNESS and (payload.get("source", "") == "warehouse" or payload.get("target", "") == "warehouse"):
		return WildOperationResult.reject(&"FORBIDDEN_CONTAINER")
	return WildInventoryRules.transfer(_state.copy(_config), _catalog, _config, actor, payload)


func submit(command: WildGameCommand) -> WildOperationResult:
	if command.actor_id != _state.player_id:
		return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	if command.request_id.is_empty():
		return WildOperationResult.reject(&"INVALID_REQUEST")
	var signature: String = "%s|%s|%s" % [command.actor_id, command.operation, JSON.stringify(command.payload, "", true)]
	if _state.receipts.has(command.request_id):
		var receipt: Dictionary = _state.receipts[command.request_id]
		if receipt["signature"] != signature:
			return WildOperationResult.reject(&"REQUEST_ID_CONFLICT")
		return WildOperationResult.new(receipt["successful"], StringName(receipt["code"]), receipt["payload"])
	var candidate: WildBaseState = _state.copy(_config)
	var ended_before_command: bool = false
	if candidate.survival != null:
		WildSurvivalSimulation.process(candidate,_config,_catalog,_content,true)
		ended_before_command = WildSettlementRules.settle(candidate,_config,_catalog)
	var result: WildOperationResult = WildOperationResult.new(false,&"INVALID_PHASE",{"committed_rollback":true}) if ended_before_command else _execute(candidate, command)
	# 投放检查失败是已执行的回滚，需要保存恢复后的基地，而非留在准备态。
	if not result.successful and not result.payload.get("committed_rollback", false):
		return result
	candidate.receipts[command.request_id] = {"signature": signature, "successful": result.successful, "code": str(result.code), "payload": result.payload.duplicate(true)}
	var saved: WildOperationResult = _save.call(candidate.record(), false)
	if not saved.successful:
		return saved
	_state = candidate
	_world_dirty = false
	_save_blocked = false
	changed.emit()
	if _state.survival != null: world_content_changed.emit()
	return result


func _execute(state: WildBaseState, command: WildGameCommand) -> WildOperationResult:
	var operation: StringName = command.operation
	if operation in [&"skill.unlock",&"skill.train"]:
		if state.phase not in [WildRunFlow.Phase.BASE,WildRunFlow.Phase.WILDERNESS]: return WildOperationResult.reject(&"INVALID_PHASE")
		if state.survival != null and state.survival.actions.has(command.actor_id): return WildOperationResult.reject(&"ACTION_BUSY")
		return WildSkillRules.learn(state,command.payload,_config.skill_rules,operation == &"skill.train")
	if str(operation).begins_with("survival."):
		return WildSurvivalCommands.execute(state,command,_config,_catalog,_content)
	if operation == &"inventory.transfer":
		if state.survival != null and state.survival.actions.has(command.actor_id): return WildOperationResult.reject(&"ACTION_BUSY")
		if not _inventory_allowed():
			return WildOperationResult.reject(&"INVALID_PHASE")
		if state.phase == WildRunFlow.Phase.WILDERNESS and (command.payload.get("source", "") == "warehouse" or command.payload.get("target", "") == "warehouse"):
			return WildOperationResult.reject(&"FORBIDDEN_CONTAINER")
		return WildInventoryRules.transfer(state, _catalog, _config, command.actor_id, command.payload)
	if operation == &"expedition.cancel" and state.phase == WildRunFlow.Phase.PREPARATION:
		_restore_origin(state)
		return WildOperationResult.accept()
	if operation == &"expedition.return_placeholder" and state.phase == WildRunFlow.Phase.WILDERNESS and state.active_run.get("prototype_only", false):
		_restore_origin(state)
		return WildOperationResult.accept()
	if operation == &"expedition.return_exploration" and state.phase == WildRunFlow.Phase.WILDERNESS and state.active_run.get("exploration_only", false):
		_restore_origin(state)
		return WildOperationResult.accept()
	if operation == &"expedition.commit" and state.phase == WildRunFlow.Phase.PREPARATION:
		state.phase = WildRunFlow.Phase.GENERATING
		if _spawn_check.is_valid() and not bool(_spawn_check.call()):
			_restore_origin(state)
			return WildOperationResult.new(false, &"GENERATION_FAILED", {"committed_rollback": true})
		if _generate.is_valid():
			var generated: WildOperationResult = _generate.call(state.active_run["seed"])
			if generated.successful and generated.payload.get("world", null) is Dictionary:
				var generated_record: Dictionary = generated.payload["world"].duplicate(true)
				generated_record["players"] = {state.player_id: generated_record.get("spawn", [0, 0]).map(func(value: Variant) -> float: return (float(value) + 0.5) * _config.terrain_tile_pixels)}
				state.world = WildWorldCodec.decode(generated_record, _config)
			if state.world == null or state.world.seed_text != state.active_run["seed"]:
				_restore_origin(state)
				return WildOperationResult.new(false, &"GENERATION_FAILED", {"committed_rollback": true})
			if _content != null:
				state.survival = WildSurvivalSimulation.create(state.player_id,state.active_run["seed"])
				WildProgressionWorld.initialize(state,_content)
				WildSurvivalSimulation.explore(state,state.player_id)
			else: state.active_run["exploration_only"] = true
		else:
			state.active_run["prototype_only"] = true # P1 独立事务验证仍可注入无生成器适配器。
		state.phase = WildRunFlow.Phase.WILDERNESS
		return WildOperationResult.accept({"run_id": state.active_run["run_id"]})
	if state.phase != WildRunFlow.Phase.BASE:
		return WildOperationResult.reject(&"INVALID_PHASE")
	match operation:
		&"pending.claim": return WildSurvivalCommands.claim_pending(state,_config,_catalog)
		&"shop.buy":
			return _buy(state, command.payload)
		&"shop.sell":
			return _sell(state, command.payload)
		&"supply.claim":
			return _ensure_supply(state)
		&"expedition.prepare":
			var seed_value: Variant = command.payload.get("seed", "")
			if not seed_value is String or (not seed_value.is_empty() and not WildWorldGenerator.valid_seed(seed_value)):
				return WildOperationResult.reject(&"INVALID_SEED")
			var supply: WildOperationResult = _ensure_supply(state)
			if not supply.successful:
				return supply
			state.active_run = {"run_id": WildStableId.create("run"), "seed": WildWorldGenerator.random_seed() if seed_value.is_empty() else seed_value, "origin_containers": state.record()["containers"]}
			state.phase = WildRunFlow.Phase.PREPARATION
			return WildOperationResult.accept({"run_id": state.active_run["run_id"]})
		_:
			return WildOperationResult.reject(&"UNKNOWN_COMMAND")


func _buy(state: WildBaseState, data: Dictionary) -> WildOperationResult:
	var definition: WildItemDefinition = _catalog.find(StringName(str(data.get("definition_id", ""))))
	if definition == null or not definition.purchasable:
		return WildOperationResult.reject(&"NOT_FOR_SALE")
	if not WildDataValidation.whole(data.get("quantity", 1)):
		return WildOperationResult.reject(&"INVALID_QUANTITY")
	var quantity: int = int(data.get("quantity", 1))
	if quantity < 1 or quantity > definition.max_stack:
		return WildOperationResult.reject(&"INVALID_QUANTITY")
	var cost: int = definition.price * quantity
	if state.currency < cost:
		return WildOperationResult.reject(&"INSUFFICIENT_CURRENCY")
	var item := WildItemInstance.new(definition, quantity)
	var warehouse: WildInventoryContainer = state.containers["warehouse"]
	var fit: WildOperationResult = WildInventoryRules.first_fit(state, _catalog, _config, state.player_id, warehouse, item)
	if not fit.successful:
		return fit
	warehouse.placements[item.instance_id] = {"item": item, "position": fit.payload["position"], "rotated": fit.payload["rotated"]}
	warehouse.version += 1
	state.currency -= cost
	return WildOperationResult.accept({"instance_id": item.instance_id})


func _sell(state: WildBaseState, data: Dictionary) -> WildOperationResult:
	var warehouse: WildInventoryContainer = state.containers["warehouse"]
	if not WildDataValidation.whole(data.get("version", -1)) or int(data.get("version", -1)) != warehouse.version:
		return WildOperationResult.reject(&"STALE_VERSION")
	var id: String = str(data.get("item_id", ""))
	if not warehouse.placements.has(id):
		return WildOperationResult.reject(&"UNKNOWN_ITEM")
	var item: WildItemInstance = warehouse.placements[id]["item"]
	var definition: WildItemDefinition = _catalog.find(item.item_id)
	if item.free_supply:
		return WildOperationResult.reject(&"FREE_SUPPLY")
	if definition.shelf_life_hours >= 0.0 and item.freshness_hours <= 0.0:
		return WildOperationResult.reject(&"SPOILED_FOOD")
	if not WildDataValidation.whole(data.get("quantity", item.quantity)):
		return WildOperationResult.reject(&"INVALID_QUANTITY")
	var quantity: int = int(data.get("quantity", item.quantity))
	if quantity < 1 or quantity > item.quantity:
		return WildOperationResult.reject(&"INVALID_QUANTITY")
	state.currency += int(floorf(definition.price * 0.4)) * quantity
	item.quantity -= quantity
	if item.quantity == 0:
		warehouse.placements.erase(id)
	warehouse.version += 1
	return WildOperationResult.accept()


func _ensure_supply(state: WildBaseState) -> WildOperationResult:
	for definition_id: StringName in [&"knife", &"flint", &"bottle"]:
		var found: bool = false
		for container: WildInventoryContainer in state.containers.values():
			for entry: Dictionary in container.placements.values():
				var existing: WildItemInstance = entry["item"]
				if existing.item_id == definition_id and existing.free_supply:
					found = true
		for raw: Dictionary in state.pending:
			if raw["item_id"] == str(definition_id) and raw["free_supply"]: found = true
		if found:
			continue
		var item := WildItemInstance.new(_catalog.find(definition_id))
		item.free_supply = true
		var warehouse: WildInventoryContainer = state.containers["warehouse"]
		var fit: WildOperationResult = WildInventoryRules.first_fit(state, _catalog, _config, state.player_id, warehouse, item)
		if not fit.successful:
			return fit
		warehouse.placements[item.instance_id] = {"item": item, "position": fit.payload["position"], "rotated": fit.payload["rotated"]}
		warehouse.version += 1
	return WildOperationResult.accept()


func _restore_origin(state: WildBaseState) -> void:
	var origin: Dictionary = state.record()
	origin["phase"] = WildRunFlow.Phase.BASE
	origin["containers"] = state.active_run["origin_containers"].duplicate(true)
	origin["active_run"] = {}
	var restored: WildBaseState = WildBaseStateCodec.decode(origin, state.player_id, _config, _catalog)
	for id: String in state.containers:
		restored.containers[id].version = state.containers[id].version + 1
	state.containers = restored.containers
	state.active_run = {}
	state.world = null
	state.survival = null
	state.phase = WildRunFlow.Phase.BASE


func _inventory_allowed() -> bool:
	return _state.phase in [WildRunFlow.Phase.BASE, WildRunFlow.Phase.PREPARATION] or (_state.world != null and _state.phase == WildRunFlow.Phase.WILDERNESS)


## 完整快照只在场景创建或读档时请求；每帧移动使用轻量接口。
func world_record() -> Dictionary:
	return _state.world.record() if _state.world != null else {}


func player_position(actor: String) -> Vector2:
	return _state.world.players.get(actor, Vector2.ZERO) if _state.world != null else Vector2.ZERO


## 输入是方向和固定物理步长，不接受客户端任意坐标；以后由房主调用同一规则。
func move_player(actor: String, direction: Vector2, seconds: float, sprint: bool) -> Vector2:
	if _state.world == null or actor != _state.player_id or _state.phase != WildRunFlow.Phase.WILDERNESS:
		return Vector2.ZERO
	if _save_blocked or (_state.survival != null and _state.survival.actions.has(actor)): return player_position(actor)
	var weight: float = _state.carried_weight(_catalog, _config)
	var overload: float = clampf((weight - _config.soft_weight_limit_kg) / (_config.hard_weight_limit_kg - _config.soft_weight_limit_kg), 0, 1)
	var speed: float = (_config.sprinting_speed_pixels_per_second if sprint else _config.walking_speed_pixels_per_second) * (1.0 - overload * _config.maximum_weight_slowdown)
	if _state.survival != null and _state.survival.bodies[actor].stamina <= 0.001: speed = _config.exhausted_speed_pixels_per_second * (1.0 - overload * _config.maximum_weight_slowdown)
	var before: Vector2 = player_position(actor)
	if _state.survival != null: speed *= WildIllnessRules.movement_multiplier(_state.survival.bodies[actor],_config.health_rules)
	var after: Vector2 = WildWorldRules.move(_state.world, actor, direction, seconds, speed)
	_world_dirty = _world_dirty or before != after
	if _state.survival != null: WildSurvivalSimulation.explore(_state,actor)
	return after


func inspect_resource(actor: String, payload: Dictionary) -> WildOperationResult:
	if _state.world == null or _state.phase != WildRunFlow.Phase.WILDERNESS:
		return WildOperationResult.reject(&"INVALID_PHASE")
	if not WildDataValidation.whole(payload.get("version", -1)):
		return WildOperationResult.reject(&"INVALID_REQUEST")
	var id: String = str(payload.get("resource_id",""))
	if _state.survival != null:
		if _state.survival.buildings.has(id):
			var building: Dictionary = _state.survival.buildings[id]
			return WildOperationResult.accept(building.duplicate(true)) if WildBuildingRules.in_reach(_state.world,actor,building) else WildOperationResult.reject(&"OUT_OF_REACH")
		if _state.survival.outputs.has(id):
			var output: Dictionary = _state.survival.outputs[id]
			return WildOperationResult.accept(output.duplicate(true)) if output["owner"] == actor and _state.world.players[actor].distance_to(Vector2(output["x"],output["y"])) <= _state.world.tile_pixels*1.5 else WildOperationResult.reject(&"OUT_OF_REACH")
	return WildWorldRules.interaction(_state.world, actor, str(payload.get("resource_id", "")), int(payload.get("version", -1)))


## 周期 / 暂停 / 正常退出的检查点，不产生物品或货币收据。失败保留脏状态可重试。
func checkpoint() -> WildOperationResult:
	if not _world_dirty:
		return WildOperationResult.accept()
	var saved: WildOperationResult = _save.call(_state.record(), false)
	if saved.successful:
		_world_dirty = false
	return saved


func body_snapshot(actor: String) -> Dictionary:
	return WildBodyView.create(_state,actor,_config,_catalog,_last_activity)

## 内部世界伤害事务，未来动物系统调用；客户端命令分发不开放此入口。
func apply_world_damage(actor: String, amount: float, cause: String) -> WildOperationResult:
	if actor != _state.player_id or _state.survival == null: return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	var candidate: WildBaseState = _state.copy(_config)
	WildSurvivalSimulation.process(candidate,_config,_catalog,_content,true)
	if WildSettlementRules.settle(candidate,_config,_catalog): return WildOperationResult.reject(&"INVALID_PHASE")
	var result: WildOperationResult = WildDamageRules.apply(candidate,actor,amount,cause,_config.health_rules)
	if not result.successful: return result
	if candidate.survival.bodies[actor].hp <= 0:
		candidate.survival.outcome = "lost"
		WildSettlementRules.settle(candidate,_config,_catalog)
	var saved: WildOperationResult = _save.call(candidate.record(),false)
	if not saved.successful: return saved
	_state = candidate
	_world_dirty = false
	changed.emit()
	return result


func survival_snapshot(actor: String) -> Dictionary:
	if _state.survival == null: return {}
	var run: WildSurvivalState = _state.survival
	return {"elapsed_seconds":run.elapsed_seconds + run.pending_seconds,"pending_seconds":run.pending_seconds,"body":body_snapshot(actor),"action":run.actions.get(actor,{}).duplicate(true),"notice":run.notice,"save_blocked":_save_blocked,"buildings":WildProgressionView.buildings(run),"outputs":run.outputs.duplicate(true),"carried_weight_kg":_state.carried_weight(_catalog,_config)}


func world_dynamic() -> Dictionary:
	if _state.world == null: return {}
	return {"resources":_state.world.resources.duplicate(true),"buildings":_state.survival.buildings.duplicate(true) if _state.survival != null else {},"outputs":_state.survival.outputs.duplicate(true) if _state.survival != null else {},"blocked_cells":_state.world.blocked_cells.duplicate(),"prey":_state.survival.prey.duplicate(true) if _state.survival != null else {}}


## 应用层唯一时间入口。分钟边界在候选状态上推进；关键点保存失败不提交产出 / 结算。
func advance_world(actor: String, seconds: float, activity: String) -> WildOperationResult:
	if _state.survival == null: return WildOperationResult.accept()
	if actor != _state.player_id or not is_finite(seconds) or seconds < 0 or activity not in ["idle","walk","sprint"]: return WildOperationResult.reject(&"INVALID_REQUEST")
	_last_activity = activity
	if not _save_blocked:
		WildSurvivalSimulation.queue_time(_state.survival,seconds * _config.game_seconds_per_real_second,activity)
		_world_dirty = true
	var boundary: float = minf(_config.simulation_step_seconds,_config.target_survival_hours*3600 - _state.survival.elapsed_seconds)
	for action: Dictionary in _state.survival.actions.values(): boundary = minf(boundary,action["remaining"])
	if not _save_blocked and _state.survival.pending_seconds + 0.000001 < boundary: return WildOperationResult.accept()
	var candidate: WildBaseState = _state.copy(_config)
	var events: Dictionary = WildSurvivalSimulation.process(candidate,_config,_catalog,_content)
	var settled: bool = WildSettlementRules.settle(candidate,_config,_catalog)
	if events["save"] or settled:
		var saved: WildOperationResult = _save.call(candidate.record(),false)
		if not saved.successful:
			_save_blocked = true
			return saved
		_world_dirty = false
	_state = candidate
	_save_blocked = false
	if settled: changed.emit()
	elif events["world_changed"]: world_content_changed.emit()
	return WildOperationResult.accept()
