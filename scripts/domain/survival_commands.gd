class_name WildSurvivalCommands
extends RefCounted
## 生存事务命令协调器，无 UI / 文件依赖。所有修改由应用服务在候选状态上调用。
static func execute(state: WildBaseState, command: WildGameCommand, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent) -> WildOperationResult:
	var run: WildSurvivalState = state.survival
	if run == null or state.phase != WildRunFlow.Phase.WILDERNESS: return WildOperationResult.reject(&"INVALID_PHASE")
	var actor: String = command.actor_id
	match command.operation:
		&"survival.start":
			var result: WildOperationResult = WildSurvivalActions.start(state,actor,command.payload,config,catalog,content)
			if result.successful and command.payload.get("action","") == "sleep":
				WildSurvivalSimulation.sleep(state,actor,config,catalog,content)
				WildSettlementRules.settle(state,config,catalog)
			return result
		&"survival.cancel":
			if not run.actions.has(actor): return WildOperationResult.reject(&"NO_ACTION")
			var fishing: bool = run.actions[actor]["type"] == "fish"
			run.actions.erase(actor)
			run.notice = "捕鱼已取消，已经投下的鱼饵、时间与体力不退。" if fishing else "行动已取消，未消耗锁定材料；已花时间与体力不退。"
			return WildOperationResult.accept()
		&"survival.abandon":
			run.outcome = "abandoned"
			WildSettlementRules.settle(state,config,catalog)
			return WildOperationResult.accept(state.last_settlement)
		&"survival.claim_output":
			if run.actions.has(actor): return WildOperationResult.reject(&"ACTION_BUSY")
			var id: String = str(command.payload.get("id",""))
			if not run.outputs.has(id): return WildOperationResult.reject(&"UNKNOWN_ITEM")
			var output: Dictionary = run.outputs[id]
			if output["owner"] != actor: return WildOperationResult.reject(&"FORBIDDEN_CONTAINER")
			if state.world.players[actor].distance_to(Vector2(output["x"],output["y"])) > state.world.tile_pixels * 1.5: return WildOperationResult.reject(&"OUT_OF_REACH")
			var leftover: Array = []
			var changed: bool = false
			for raw: Dictionary in output["items"]:
				var item: WildItemInstance = WildItemInstance.from_record(raw)
				var before: int = item.quantity
				var fitted: bool = WildInventoryOperations.insert(state,catalog,config,item)
				if not fitted: leftover.append(item.record())
				if fitted or item.quantity != before: changed = true
			if not changed: return WildOperationResult.reject(&"NO_SPACE")
			if leftover.is_empty(): run.outputs.erase(id)
			else: output["items"] = leftover
			return WildOperationResult.accept()
	return WildOperationResult.reject(&"UNKNOWN_COMMAND")

static func claim_pending(state: WildBaseState, config: WildGameConfig, catalog: WildItemCatalog) -> WildOperationResult:
	var leftovers: Array[Dictionary] = []
	var changed: bool = false
	for raw: Dictionary in state.pending:
		var item: WildItemInstance = WildItemInstance.from_record(raw)
		var before: int = item.quantity
		var fitted: bool = WildInventoryOperations.insert(state,catalog,config,item,"warehouse")
		if not fitted: leftovers.append(item.record())
		if fitted or item.quantity != before: changed = true
	if not changed: return WildOperationResult.reject(&"NO_SPACE")
	state.pending = leftovers
	return WildOperationResult.accept()
