class_name WildSettlementRules
extends RefCounted
## 结算与返仓是一个保存单元。收据以任务 ID 去重，满仓进入持久待领取列表。
const REWARDED_ACTIVITIES: Array[String] = WildExpeditionReport.ACTIVITIES

static func settle(state: WildBaseState, config: WildGameConfig, catalog: WildItemCatalog) -> bool:
	if state.survival == null or state.survival.outcome == "running": return false
	var run: WildSurvivalState = state.survival
	var run_id: String = state.active_run["run_id"]
	var receipt_id: String = "settlement:" + run_id
	if state.receipts.has(receipt_id): return false
	var won: bool = run.outcome == "won"
	var items: Array[Dictionary] = []
	if won:
		for container: WildInventoryContainer in state.containers.values():
			if not container.carried: continue
			for entry: Dictionary in container.placements.values(): items.append({"item":entry["item"],"rotated":entry["rotated"]})
	var report: Dictionary = WildExpeditionReport.create(state.world,run,state.player_id,config,won,items)
	var reward: int = WildExpeditionReport.reward(report)
	if won: WildReturnInventory.apply(state,items,config,catalog)
	for container: WildInventoryContainer in state.containers.values():
		if container.carried:
			container.placements.clear()
			container.version += 1
	state.currency += reward
	state.last_settlement = {"run_id":run_id,"won":won,"reward":reward,"elapsed_seconds":run.elapsed_seconds,"reason":"存活到期" if won else ("主动放弃" if run.outcome == "abandoned" else "血量归零"),"pending_count":state.pending.size()}
	state.last_settlement["report"] = report
	state.receipts[receipt_id] = {"signature":receipt_id,"successful":true,"code":"OK","payload":state.last_settlement.duplicate(true)}
	state.world = null
	state.survival = null
	state.active_run = {}
	state.phase = WildRunFlow.Phase.BASE
	return true

