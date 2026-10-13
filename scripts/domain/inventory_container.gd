class_name WildInventoryContainer
extends RefCounted
## 容器数据。placements 仅由规则层修改，展示层拿到序列化副本。

var container_id: String
var owner_id: String
var grid_size: Vector2i
var capacity_l: float
var carried: bool = false
var public_access: bool = false
var accepted_categories: PackedStringArray = PackedStringArray()
var equipment_slot: bool = false
var version: int = 0
var placements: Dictionary[String, Dictionary] = {}


func _init(id: String, owner: String, grid: Vector2i, capacity: float) -> void:
	container_id = id
	owner_id = owner
	grid_size = grid
	capacity_l = capacity


func footprint(definition: WildItemDefinition, rotated: bool) -> Vector2i:
	if equipment_slot:
		return Vector2i.ONE
	return Vector2i(definition.grid_size.y, definition.grid_size.x) if rotated else definition.grid_size


func volume(catalog: WildItemCatalog) -> float:
	if equipment_slot:
		return 0.0
	var total: float = 0.0
	for placement: Dictionary in placements.values():
		var instance: WildItemInstance = placement["item"]
		total += instance.volume(catalog.find(instance.item_id))
	return total


func weight(catalog: WildItemCatalog) -> float:
	var total: float = 0.0
	for placement: Dictionary in placements.values():
		var instance: WildItemInstance = placement["item"]
		total += instance.weight(catalog.find(instance.item_id))
	return total


func item_at(cell: Vector2i, catalog: WildItemCatalog, ignored_id: String = "") -> String:
	for id: String in placements:
		if id == ignored_id:
			continue
		var entry: Dictionary = placements[id]
		var instance: WildItemInstance = entry["item"]
		var bounds := Rect2i(entry["position"], footprint(catalog.find(instance.item_id), entry["rotated"]))
		if bounds.has_point(cell):
			return id
	return ""


func record() -> Dictionary:
	var entries: Array = []
	for entry: Dictionary in placements.values():
		var position: Vector2i = entry["position"]
		entries.append({"item": (entry["item"] as WildItemInstance).record(), "position": [position.x, position.y], "rotated": entry["rotated"]})
	return {"id": container_id, "version": version, "entries": entries}


func copy() -> WildInventoryContainer:
	var duplicate := WildInventoryContainer.new(container_id, owner_id, grid_size, capacity_l)
	duplicate.carried = carried
	duplicate.public_access = public_access
	duplicate.accepted_categories = accepted_categories.duplicate()
	duplicate.equipment_slot = equipment_slot
	duplicate.version = version
	for id: String in placements:
		var entry: Dictionary = placements[id]
		duplicate.placements[id] = {"item": (entry["item"] as WildItemInstance).copy(), "position": entry["position"], "rotated": entry["rotated"]}
	return duplicate
