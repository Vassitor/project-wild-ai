class_name WildHealthConfig
extends Resource
## P4 游戏数值，时间均为游戏秒，损耗均为每游戏小时；只读配置。
@export var shortage_enter: float = 20.0
@export var shortage_exit: float = 30.0
@export var shortage_health_per_hour: float = 1.0
@export var shortage_health_cap: float = 4.0
@export var dehydration_health_per_hour: float = 2.0
@export var safe_rest_health_per_hour: float = 0.5
@export var bleeding_hp_per_hour: float = 4.0
@export var bleeding_health_per_hour: float = 1.0
@export var bleeding_damage_threshold: float = 10.0
@export var bleeding_probability: float = 0.2
@export var gastro_seconds: float = 43200.0
@export var gastro_water_per_hour: float = 2.0
@export var gastro_health_per_hour: float = 2.0
@export var medicine_reduction_seconds: float = 21600.0
@export var medicine_cooldown_seconds: float = 7200.0
@export var bandage_seconds: float = 300.0
@export var medicine_seconds: float = 600.0
@export var weakness_delay_seconds: float = 86400.0
@export var weakness_recovery_seconds: float = 21600.0
@export var weakness_speed_multiplier: float = 0.85
@export var weakness_recovery_multiplier: float = 0.7
@export var pollution_decay_per_hour: float = 5.0
@export var pollution_check_seconds: float = 3600.0
@export var pollution_threshold: float = 50.0
@export var leather_physical_reduction: float = 0.35
@export var maximum_physical_reduction: float = 0.6
@export var armor_wear_per_hit: float = 2.0

func validate() -> bool:
	for field: Dictionary in get_property_list():
		if field["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and field["type"] == TYPE_FLOAT:
			var value: float = get(field["name"])
			if not is_finite(value) or value < 0: return false
	return shortage_enter > 0 and shortage_exit > shortage_enter and shortage_exit <= 100 and pollution_check_seconds > 0 and weakness_delay_seconds > 0 and weakness_recovery_seconds > 0 and gastro_seconds > 0 and medicine_reduction_seconds > 0 and medicine_cooldown_seconds > 0 and bandage_seconds > 0 and medicine_seconds > 0 and bleeding_probability <= 1 and maximum_physical_reduction <= 1 and weakness_speed_multiplier <= 1 and weakness_recovery_multiplier <= 1
