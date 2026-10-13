class_name WildItemInstance
extends RefCounted
## 可保存的运行实例。水量影响重量，但不重复计水壶外部体积。

var instance_id: String
var item_id: StringName
var quantity: int = 1
var durability: float = 100.0
var freshness_hours: float = -1.0
var water_l: float = 0.0
var clean_water: bool = true
var free_supply: bool = false
## 制作者技能烘焙为实例属性，转移 / 返仓不依赖原制作者当前技能。
var nutrition_multiplier: float = 1.0
var shelf_life_multiplier: float = 1.0


func _init(definition: WildItemDefinition = null, amount: int = 1) -> void:
	instance_id = WildStableId.create("item")
	if definition != null:
		item_id = definition.item_id
		freshness_hours = definition.shelf_life_hours
	quantity = amount


func weight(definition: WildItemDefinition) -> float:
	return quantity * definition.unit_weight_kg + water_l


func volume(definition: WildItemDefinition) -> float:
	return quantity * definition.unit_volume_l


func record() -> Dictionary:
	return {"id": instance_id, "item_id": str(item_id), "quantity": quantity, "durability": durability, "freshness_hours": freshness_hours, "water_l": water_l, "clean_water": clean_water, "free_supply": free_supply,"nutrition_multiplier":nutrition_multiplier,"shelf_life_multiplier":shelf_life_multiplier}


func copy() -> WildItemInstance:
	return from_record(record())


static func from_record(data: Dictionary) -> WildItemInstance:
	var instance := WildItemInstance.new()
	instance.instance_id = str(data.get("id", ""))
	instance.item_id = StringName(str(data.get("item_id", "")))
	instance.quantity = int(data.get("quantity", 0))
	instance.durability = float(data.get("durability", 100.0))
	instance.freshness_hours = float(data.get("freshness_hours", -1.0))
	instance.water_l = float(data.get("water_l", 0.0))
	instance.clean_water = bool(data.get("clean_water", true))
	instance.free_supply = bool(data.get("free_supply", false))
	instance.nutrition_multiplier = float(data.get("nutrition_multiplier",1.0))
	instance.shelf_life_multiplier = float(data.get("shelf_life_multiplier",1.0))
	return instance


func valid(definition: WildItemDefinition) -> bool:
	if definition == null or instance_id.is_empty() or quantity < 1 or quantity > definition.max_stack:
		return false
	if not is_finite(durability) or durability < 0.0 or durability > 100.0 or not is_finite(freshness_hours):
		return false
	if not is_finite(water_l) or water_l < 0.0 or water_l > definition.water_capacity_l:
		return false
	if definition.shelf_life_hours < 0.0 and freshness_hours != -1.0:
		return false
	if not is_finite(nutrition_multiplier) or not is_finite(shelf_life_multiplier) or nutrition_multiplier < 1 or nutrition_multiplier > 2 or shelf_life_multiplier < 1 or shelf_life_multiplier > 2: return false
	if item_id not in [&"roasted_root",&"cooked_fish",&"cooked_meat",&"stew"] and (nutrition_multiplier != 1 or shelf_life_multiplier != 1): return false
	if definition.shelf_life_hours >= 0.0 and (freshness_hours < 0.0 or freshness_hours > definition.shelf_life_hours*shelf_life_multiplier):
		return false
	return not free_supply or item_id in [&"knife", &"flint", &"bottle"]

static func metadata_valid(raw: Dictionary) -> bool:
	for field: String in ["nutrition_multiplier","shelf_life_multiplier"]:
		if raw.has(field) and not WildDataValidation.number(raw[field]): return false
	return true
