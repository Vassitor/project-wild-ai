class_name WildPlayerState
extends RefCounted
## 独立玩家状态，由会话拥有。UI 只能读取快照，不能持有可写身体引用。

const NUTRIENT_IDS: Array[StringName] = [&"carbohydrate", &"fat", &"protein", &"mineral", &"vitamin"]

var player_id: String
var display_name: String
var health_points: float
var health: float
var hydration: float
var stamina: float
var nutrition: Dictionary[StringName, float] = {}


func _init(id: String, name_for_display: String, config: WildGameConfig) -> void:
	player_id = id
	display_name = name_for_display
	health_points = config.initial_stat_value
	health = config.initial_stat_value
	hydration = config.initial_stat_value
	stamina = config.initial_stat_value
	for nutrient: StringName in NUTRIENT_IDS:
		nutrition[nutrient] = config.initial_stat_value


## 返回副本，不把可变字典泄露给展示层。
func snapshot() -> Dictionary:
	return {
		"player_id": player_id,
		"display_name": display_name,
		"health_points": health_points,
		"health": health,
		"hydration": hydration,
		"stamina": stamina,
		"nutrition": nutrition.duplicate(),
	}
