class_name WildReturnInventory
extends RefCounted
## 返仓统一算法：按体积 / 面积 / ID 排序，保留朝向优先，放不下进入持久待领取。
static func apply(state: WildBaseState, entries: Array[Dictionary], config: WildGameConfig, catalog: WildItemCatalog) -> void:
	entries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var first: WildItemInstance = a["item"]
		var second: WildItemInstance = b["item"]
		var first_def: WildItemDefinition = catalog.find(first.item_id)
		var second_def: WildItemDefinition = catalog.find(second.item_id)
		if not is_equal_approx(first.volume(first_def),second.volume(second_def)): return first.volume(first_def) > second.volume(second_def)
		if first_def.grid_size.x*first_def.grid_size.y != second_def.grid_size.x*second_def.grid_size.y: return first_def.grid_size.x*first_def.grid_size.y > second_def.grid_size.x*second_def.grid_size.y
		return first.instance_id < second.instance_id)
	var warehouse: WildInventoryContainer = state.containers["warehouse"]
	for entry: Dictionary in entries:
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
