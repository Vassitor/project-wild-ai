class_name WildInventoryRules
extends RefCounted
## 网格、容量、负重、权限和转移规则；无 UI / 文件依赖。
## 调用者将成功后的候选状态保存后提交，失败不得改变原状态。


static func can_place(state: WildBaseState, catalog: WildItemCatalog, config: WildGameConfig, actor: String, target: WildInventoryContainer, item: WildItemInstance, cell: Vector2i, rotated: bool, ignored_id: String = "", already_carried: bool = false) -> WildOperationResult:
	if not target.public_access and target.owner_id != actor:
		return WildOperationResult.reject(&"FORBIDDEN_CONTAINER")
	var definition: WildItemDefinition = catalog.find(item.item_id)
	if not item.valid(definition):
		return WildOperationResult.reject(&"INVALID_ITEM")
	if not target.accepted_categories.is_empty() and not target.accepted_categories.has(str(definition.category)):
		return WildOperationResult.reject(&"INVALID_CATEGORY")
	var dimensions: Vector2i = target.footprint(definition, rotated)
	if cell.x < 0 or cell.y < 0 or cell.x + dimensions.x > target.grid_size.x or cell.y + dimensions.y > target.grid_size.y:
		return WildOperationResult.reject(&"OUT_OF_BOUNDS")
	var rectangle := Rect2i(cell, dimensions)
	for id: String in target.placements:
		if id == ignored_id:
			continue
		var entry: Dictionary = target.placements[id]
		var other: WildItemInstance = entry["item"]
		if rectangle.intersects(Rect2i(entry["position"], target.footprint(catalog.find(other.item_id), entry["rotated"]))):
			return WildOperationResult.reject(&"OVERLAP")
	var existing_volume: float = 0.0
	if target.placements.has(ignored_id):
		existing_volume = (target.placements[ignored_id]["item"] as WildItemInstance).volume(definition)
	if not target.equipment_slot and target.volume(catalog) - existing_volume + item.volume(definition) > target.capacity_l + 0.00001:
		return WildOperationResult.reject(&"VOLUME_LIMIT")
	if target.carried and target.owner_id == actor and not already_carried and state.carried_weight(catalog, config, actor) + item.weight(definition) > config.hard_weight_limit_kg + 0.00001:
		return WildOperationResult.reject(&"WEIGHT_LIMIT")
	return WildOperationResult.accept()


static func first_fit(state: WildBaseState, catalog: WildItemCatalog, config: WildGameConfig, actor: String, target: WildInventoryContainer, item: WildItemInstance, already_carried: bool = false) -> WildOperationResult:
	var reason: StringName = &"NO_SPACE"
	for rotated: bool in [false, true]:
		for y: int in range(target.grid_size.y):
			for x: int in range(target.grid_size.x):
				var result: WildOperationResult = can_place(state, catalog, config, actor, target, item, Vector2i(x, y), rotated, "", already_carried)
				if result.successful:
					return WildOperationResult.accept({"position": Vector2i(x, y), "rotated": rotated})
				if result.code in [&"WEIGHT_LIMIT", &"VOLUME_LIMIT", &"INVALID_CATEGORY", &"FORBIDDEN_CONTAINER", &"INVALID_ITEM"]:
					return result
				reason = result.code
	return WildOperationResult.reject(&"NO_SPACE" if reason in [&"OUT_OF_BOUNDS", &"OVERLAP"] else reason)


static func transfer(state: WildBaseState, catalog: WildItemCatalog, config: WildGameConfig, actor: String, data: Dictionary) -> WildOperationResult:
	var source: WildInventoryContainer = state.containers.get(str(data.get("source", "")))
	var target: WildInventoryContainer = state.containers.get(str(data.get("target", "")))
	var id: String = str(data.get("item_id", ""))
	if source == null or target == null:
		return WildOperationResult.reject(&"UNKNOWN_CONTAINER")
	for field: String in ["source_version", "target_version", "quantity", "x", "y"]:
		if data.has(field) and not WildDataValidation.whole(data[field]):
			return WildOperationResult.reject(&"INVALID_REQUEST")
	for field: String in ["auto", "rotated"]:
		if data.has(field) and not data[field] is bool:
			return WildOperationResult.reject(&"INVALID_REQUEST")
	if (not source.public_access and source.owner_id != actor) or (not target.public_access and target.owner_id != actor):
		return WildOperationResult.reject(&"FORBIDDEN_CONTAINER")
	if int(data.get("source_version", -1)) != source.version or int(data.get("target_version", -1)) != target.version:
		return WildOperationResult.reject(&"STALE_VERSION")
	if not source.placements.has(id):
		return WildOperationResult.reject(&"UNKNOWN_ITEM")
	var original: Dictionary = source.placements[id]
	var item: WildItemInstance = original["item"]
	var definition: WildItemDefinition = catalog.find(item.item_id)
	var amount: int = int(data.get("quantity", item.quantity))
	if amount <= 0 or amount > item.quantity:
		return WildOperationResult.reject(&"INVALID_QUANTITY")
	var part: WildItemInstance = item.copy()
	part.quantity = amount
	var split: bool = amount < item.quantity
	if split:
		part.instance_id = WildStableId.create("item")
	var already_carried: bool = source.carried and source.owner_id == actor
	var rotated: bool = bool(data.get("rotated", original["rotated"]))
	var cell := Vector2i(int(data.get("x", -1)), int(data.get("y", -1)))
	if bool(data.get("auto", false)):
		var fit: WildOperationResult = first_fit(state, catalog, config, actor, target, part, already_carried)
		if not fit.successful:
			return fit
		cell = fit.payload["position"]
		rotated = fit.payload["rotated"]
	var destination_id: String = target.item_at(cell, catalog, id if source == target and not split else "")
	if not destination_id.is_empty():
		if source == target and destination_id == id:
			return WildOperationResult.reject(&"SAME_ITEM")
		var other: WildItemInstance = target.placements[destination_id]["item"]
		if not is_equal_approx(other.nutrition_multiplier,item.nutrition_multiplier) or not is_equal_approx(other.shelf_life_multiplier,item.shelf_life_multiplier): return WildOperationResult.reject(&"DIFFERENT_FOOD_QUALITY")
		if other.item_id != item.item_id or other.free_supply != item.free_supply or definition.max_stack <= 1 or other.quantity + amount > definition.max_stack:
			return WildOperationResult.reject(&"OVERLAP")
		if not target.equipment_slot and target.volume(catalog) + (0.0 if source == target else part.volume(definition)) > target.capacity_l + 0.00001:
			return WildOperationResult.reject(&"VOLUME_LIMIT")
		if target.carried and not already_carried and state.carried_weight(catalog, config, actor) + part.weight(definition) > config.hard_weight_limit_kg + 0.00001:
			return WildOperationResult.reject(&"WEIGHT_LIMIT")
		other.quantity += amount
		other.freshness_hours = minf(other.freshness_hours, part.freshness_hours)
	else:
		# 同容器拆分仍占用原格；体积已计入原堆叠，不能重复加一遍。
		var ignore: String = id if source == target else ""
		var validation: WildOperationResult = can_place(state, catalog, config, actor, target, part, cell, rotated, ignore, already_carried)
		if split and source == target and Rect2i(cell, target.footprint(definition, rotated)).intersects(Rect2i(original["position"], target.footprint(definition, original["rotated"]))):
			return WildOperationResult.reject(&"OVERLAP")
		if not validation.successful:
			return validation
		target.placements[part.instance_id] = {"item": part, "position": cell, "rotated": rotated}
	if split:
		item.quantity -= amount
	else:
		source.placements.erase(id)
		if source == target and destination_id.is_empty():
			target.placements[id] = {"item": part, "position": cell, "rotated": rotated}
	source.version += 1
	if target != source:
		target.version += 1
	return WildOperationResult.accept({"instance_id": part.instance_id})
