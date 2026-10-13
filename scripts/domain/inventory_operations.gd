class_name WildInventoryOperations
extends RefCounted
## 动作与结算的库存原语。只处理实例 / 数量，不决定动作、经验或货币。

static func find(state: WildBaseState, id: String) -> Dictionary:
	for container: WildInventoryContainer in state.containers.values():
		if container.carried and container.placements.has(id): return {"item":container.placements[id]["item"],"container":container}
	return {}

static func choose(state: WildBaseState, definition: StringName, minimum_durability: float = 0.0) -> String:
	for slot: String in ["main_hand","off_hand","backpack"]:
		for entry: Dictionary in state.containers[slot].placements.values():
			var item: WildItemInstance = entry["item"]
			if item.item_id == definition and item.durability >= minimum_durability: return item.instance_id
	return ""

static func reserve(state: WildBaseState, materials: Dictionary, fresh: bool = false) -> WildOperationResult:
	var reservations: Array[Dictionary] = []
	for definition: String in materials:
		var needed: int = int(materials[definition])
		for slot: String in ["backpack","main_hand","off_hand"]:
			for entry: Dictionary in state.containers[slot].placements.values():
				var item: WildItemInstance = entry["item"]
				if str(item.item_id) != definition or (fresh and item.freshness_hours <= 0): continue
				var amount: int = mini(needed, item.quantity)
				if amount > 0: reservations.append({"id":item.instance_id,"quantity":amount,"fresh":fresh})
				needed -= amount
		if needed > 0: return WildOperationResult.reject(&"MISSING_MATERIALS")
	return WildOperationResult.accept({"reservations":reservations})

static func reservations_valid(state: WildBaseState, values: Array) -> bool:
	for reserved: Dictionary in values:
		var entry: Dictionary = find(state, reserved["id"])
		if entry.is_empty(): return false
		var item: WildItemInstance = entry["item"]
		if item.quantity < int(reserved["quantity"]) or (reserved.get("fresh",false) and item.freshness_hours <= 0): return false
	return true

static func consume(state: WildBaseState, values: Array) -> void:
	for reserved: Dictionary in values:
		var entry: Dictionary = find(state, reserved["id"])
		var item: WildItemInstance = entry["item"]
		var container: WildInventoryContainer = entry["container"]
		item.quantity -= int(reserved["quantity"])
		if item.quantity == 0: container.placements.erase(item.instance_id)
		container.version += 1

## 返回未能入包的剩余量。先合并再找格，产出被调用方保存在工作点，不丢失。
static func insert(state: WildBaseState, catalog: WildItemCatalog, config: WildGameConfig, item: WildItemInstance, target_id: String = "backpack") -> bool:
	var target: WildInventoryContainer = state.containers[target_id]
	var definition: WildItemDefinition = catalog.find(item.item_id)
	for entry: Dictionary in target.placements.values():
		var other: WildItemInstance = entry["item"]
		if other.item_id != item.item_id or other.free_supply != item.free_supply or definition.max_stack <= 1: continue
		if not is_equal_approx(other.nutrition_multiplier,item.nutrition_multiplier) or not is_equal_approx(other.shelf_life_multiplier,item.shelf_life_multiplier): continue
		var amount: int = mini(item.quantity, definition.max_stack - other.quantity)
		if not target.equipment_slot and definition.unit_volume_l > 0: amount = mini(amount, floori((target.capacity_l - target.volume(catalog) + 0.00001) / definition.unit_volume_l))
		if target.carried and definition.unit_weight_kg > 0: amount = mini(amount, floori((config.hard_weight_limit_kg - state.carried_weight(catalog,config) + 0.00001) / definition.unit_weight_kg))
		if amount > 0:
			other.quantity += amount
			other.freshness_hours = minf(other.freshness_hours, item.freshness_hours)
			item.quantity -= amount
			target.version += 1
		if item.quantity == 0: return true
	var result: WildOperationResult = WildInventoryRules.first_fit(state,catalog,config,state.player_id,target,item)
	if not result.successful: return false
	target.placements[item.instance_id] = {"item":item,"position":result.payload["position"],"rotated":result.payload["rotated"]}
	target.version += 1
	return true
