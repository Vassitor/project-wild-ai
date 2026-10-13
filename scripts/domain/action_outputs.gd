class_name WildActionOutputs
extends RefCounted
## 统一延迟产出交付：拆为合法堆叠，装不下的余量保留在执行者工作点。
static func deliver(state: WildBaseState, actor: String, action: Dictionary, definition: String, quantity: int, catalog: WildItemCatalog, config: WildGameConfig, food_age_hours: float = 0.0) -> void:
	var item_definition: WildItemDefinition = catalog.find(StringName(definition))
	var leftovers: Array[Dictionary] = []
	while quantity > 0:
		var amount: int = mini(quantity,item_definition.max_stack)
		var item := WildItemInstance.new(item_definition,amount)
		if definition in ["roasted_root","cooked_fish","cooked_meat","stew"]:
			if WildSkillRules.level(state.skills,"cooking") >= 2: item.nutrition_multiplier = config.skill_rules.cooked_nutrition_multiplier
			if WildSkillRules.level(state.skills,"cooking") >= 3: item.shelf_life_multiplier = config.skill_rules.cooked_shelf_life_multiplier
			item.freshness_hours *= item.shelf_life_multiplier
		if item.freshness_hours >= 0: item.freshness_hours = maxf(0,item.freshness_hours-food_age_hours)
		if not WildInventoryOperations.insert(state,catalog,config,item): leftovers.append(item.record())
		quantity -= amount
	if not leftovers.is_empty():
		var id: String = WildStableId.create("output")
		state.survival.outputs[id] = {"id":id,"owner":actor,"x":action["x"],"y":action["y"],"items":leftovers}
		state.survival.notice = "背包放不下，剩余产出保留在工作点。"
