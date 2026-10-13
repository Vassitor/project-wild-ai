class_name WildCoopReservations
extends RefCounted
## 资源与建筑占地锁直接由已保存的动作派生，无第二份可失步的锁表。
## 材料仍留在私人容器；活动期间禁止转移该玩家库存，完成才扣除。

static func validate(run: WildSurvivalState, actor: String, action: Dictionary, content: WildSurvivalContent) -> WildOperationResult:
	for other: String in run.actions:
		if other == actor: continue
		var locked: Dictionary = run.actions[other]
		if action["type"] in ["gather","fish"] and locked["type"] in ["gather","fish"] and action["resource_id"] == locked["resource_id"]:
			return WildOperationResult.reject(&"RESOURCE_RESERVED")
		if action["type"] in ["build","upgrade"] and locked["type"] in ["build","upgrade"]:
			if rectangle(action,content).intersects(rectangle(locked,content)):
				return WildOperationResult.reject(&"SITE_RESERVED")
		if not action["building_id"].is_empty() and action["building_id"] == locked["building_id"] and action["type"] in ["upgrade","demolish","trap_bait","trap_collect","trap_maintain"] and locked["type"] in ["upgrade","demolish","trap_bait","trap_collect","trap_maintain"]: return WildOperationResult.reject(&"BUILDING_RESERVED")
		if action["type"] == "demolish" and action["building_id"] in [locked["building_id"],locked["fire_id"],locked.get("table_id","")]: return WildOperationResult.reject(&"BUILDING_RESERVED")
		if locked["type"] == "demolish" and locked["building_id"] in [action["building_id"],action["fire_id"],action.get("table_id","")]: return WildOperationResult.reject(&"BUILDING_RESERVED")
	return WildOperationResult.accept()

static func rectangle(action: Dictionary, content: WildSurvivalContent) -> Rect2i:
	var recipe: Dictionary = content.recipe(action["recipe"])
	return Rect2i(Vector2i(action["site"]["x"],action["site"]["y"]),Vector2i(recipe["width"],recipe["height"]))
