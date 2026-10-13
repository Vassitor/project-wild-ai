class_name WildItemDefinition
extends Resource
## 只读物品定义，尺寸、价格、重量 / 体积来自 catalog.tres；实例状态另外保存。

@export var item_id: StringName
@export var display_name: String
@export var grid_size: Vector2i = Vector2i.ONE
@export var unit_weight_kg: float = 0.0
@export var unit_volume_l: float = 0.0
@export var max_stack: int = 1
@export var price: int = 0
@export var purchasable: bool = false
@export var category: StringName = &"resource"
@export var water_capacity_l: float = 0.0
@export var shelf_life_hours: float = -1.0
@export var color: Color = Color("64775a")


func valid() -> bool:
	return not item_id.is_empty() and not display_name.is_empty() and grid_size.x > 0 and grid_size.y > 0 and max_stack > 0 and unit_weight_kg >= 0.0 and unit_volume_l >= 0.0 and price >= 0 and water_capacity_l >= 0.0
