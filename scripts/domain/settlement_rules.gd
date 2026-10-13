class_name WildSettlementRules
extends RefCounted
## 结算与返仓是一个保存单元。收据以任务 ID 去重，满仓进入持久待领取列表。
const REWARDED_ACTIVITIES: Array[String] = ["gathering","logging","fire","cooking","building","fishing","hunting","trap","healing"]

static func settle(state: WildBaseState, config: WildGameConfig, catalog: WildItemCatalog) -> bool:
	if state.survival == null or state.survival.outcome == "running": return false
	var run: WildSurvivalState = state.survival
	var run_id: String = state.active_run["run_id"]
	var receipt_id: String = "settlement:" + run_id
	if state.receipts.has(receipt_id): return false
	var reward: int = 0
	var won: bool = run.outcome == "won"
	if won:
		var land: int = 0
		for terrain: int in state.world.tiles:
			if terrain != WildWorldData.Terrain.WATER: land += 1
		reward = config.success_base_reward + floori(100.0 * run.explored.size() / maxi(1,land))
		for kind: String in run.activities.get(state.player_id,[]):
			if REWARDED_ACTIVITIES.has(kind): reward += 10
		var items: Array[Dictionary] = []
		for container: WildInventoryContainer in state.containers.values():
			if not container.carried: continue
			for entry: Dictionary in container.placements.values(): items.append({"item":entry["item"],"rotated":entry["rotated"]})
		items.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			var first: WildItemInstance = a["item"]
			var second: WildItemInstance = b["item"]
			var first_def: WildItemDefinition = catalog.find(first.item_id)
			var second_def: WildItemDefinition = catalog.find(second.item_id)
			if not is_equal_approx(first.volume(first_def),second.volume(second_def)): return first.volume(first_def) > second.volume(second_def)
			if first_def.grid_size.x*first_def.grid_size.y != second_def.grid_size.x*second_def.grid_size.y: return first_def.grid_size.x*first_def.grid_size.y > second_def.grid_size.x*second_def.grid_size.y
			return first.instance_id < second.instance_id)
		var warehouse: WildInventoryContainer = state.containers["warehouse"]
		for entry: Dictionary in items:
			var item: WildItemInstance = entry["item"]
			var placed: bool = false
			for rotated: bool in [bool(entry["rotated"]),not bool(entry["rotated"])]:
				for y: int in range(warehouse.grid_size.y):
					for x: int in range(warehouse.grid_size.x):
						if placed: break
						if WildInventoryRules.can_place(state,catalog,config,state.player_id,warehouse,item,Vector2i(x,y),rotated).successful:
							warehouse.placements[item.instance_id] = {"item":item,"position":Vector2i(x,y),"rotated":rotated}
							placed = true
					if placed: break
				if placed: break
			if not placed: state.pending.append(item.record())
		warehouse.version += 1
	for container: WildInventoryContainer in state.containers.values():
		if container.carried:
			container.placements.clear()
			container.version += 1
	state.currency += reward
	state.last_settlement = {"run_id":run_id,"won":won,"reward":reward,"elapsed_seconds":run.elapsed_seconds,"reason":"存活到期" if won else ("主动放弃" if run.outcome == "abandoned" else "血量归零"),"pending_count":state.pending.size()}
	state.receipts[receipt_id] = {"signature":receipt_id,"successful":true,"code":"OK","payload":state.last_settlement.duplicate(true)}
	state.world = null
	state.survival = null
	state.active_run = {}
	state.phase = WildRunFlow.Phase.BASE
	return true
