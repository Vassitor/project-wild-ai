class_name WildExpeditionReport
extends RefCounted
## 单机 / 房主共用的只读结算明细。统计在清空行装前冻结，返仓与发钱仍由原事务执行。
const ACTIVITIES: Array[String] = ["gathering","logging","fire","cooking","building","fishing","hunting","trap","healing"]

## items 为随身返还项（实例或序列化记录）；合作只统计 actor 的探索，失败的奖励分项全部归零。
static func create(world: WildWorldData, run: WildSurvivalState, actor: String, config: WildGameConfig, won: bool, items: Array[Dictionary], cooperative: bool = false) -> Dictionary:
	var land: int = 0
	for terrain: int in world.tiles:
		if terrain != WildWorldData.Terrain.WATER: land += 1
	var explored: int = run.explored_by_actor.get(actor,{}).size() if cooperative else run.explored.size()
	var activities: Array[String] = []
	for kind: String in ACTIVITIES:
		if kind in run.activities.get(actor,[]): activities.append(kind)
	var units: int = 0
	for entry: Dictionary in items:
		var item: Variant = entry["item"]
		units += item.quantity if item is WildItemInstance else int(item["quantity"])
	return {"version":1,"base":config.success_base_reward if won else 0,"exploration":floori(100.0*explored/maxi(1,land)) if won else 0,"activity":activities.size()*10 if won else 0,"activities":activities,"explored_cells":explored,"land_cells":land,"returned_stacks":items.size(),"returned_units":units}

## 只对已创建 / 校验的明细求和；调用方负责持久化后提交货币变化。
static func reward(report: Dictionary) -> int:
	return int(report["base"])+int(report["exploration"])+int(report["activity"])

## 新明细是可选字段，旧收据无需补造统计；若存在则必须与奖励和成功状态一致。
static func valid(report: Variant, total: int, won: bool) -> bool:
	if not report is Dictionary or report.get("version",0) != 1: return false
	for key: String in ["base","exploration","activity","explored_cells","land_cells","returned_stacks","returned_units"]:
		if not WildDataValidation.whole(report.get(key,null)) or report[key] < 0: return false
	if report["exploration"] > 100 or report["explored_cells"] > report["land_cells"] or report["returned_units"] < report["returned_stacks"]: return false
	if report["exploration"] != (floori(100.0*report["explored_cells"]/maxi(1,int(report["land_cells"]))) if won else 0): return false
	if not report.get("activities",null) is Array or report["activities"].size() > ACTIVITIES.size(): return false
	var seen: Dictionary = {}
	for kind: Variant in report["activities"]:
		if not kind is String or kind not in ACTIVITIES or seen.has(kind): return false
		seen[kind] = true
	if not won and (total != 0 or report["returned_units"] != 0): return false
	return reward(report) == total and report["activity"] == (seen.size()*10 if won else 0)
