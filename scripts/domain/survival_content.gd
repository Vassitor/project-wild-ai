class_name WildSurvivalContent
extends Resource
## P3 玩法静态配置，配方 / 食谱 / 行动费用不写入运行实例。
@export var foods: Dictionary = {"ration": [35,12,10,8,5], "berry": [12,0,1,4,15], "root": [20,1,2,8,8], "roasted_root": [30,1,3,8,6], "raw_fish": [0,12,22,8,2], "raw_meat": [0,12,22,8,2], "cooked_fish": [0,15,30,10,2], "cooked_meat": [0,15,30,10,2], "stew": [30,12,25,18,15]}
@export var recipes: Dictionary = {
	"camp": {"materials": {"wood":8,"fiber":6}, "minutes":60.0,"stamina":20.0,"width":2,"height":2},
	"fire": {"materials":{"stone":3,"wood":2},"minutes":10.0,"stamina":4.0,"width":1,"height":1},
	"storage_box": {"materials":{"wood":6,"fiber":4},"minutes":30.0,"stamina":4.0,"width":1,"height":1},
	"roasted_root": {"materials":{"root":1},"minutes":10.0,"stamina":2.0,"output":"roasted_root"}
}
## 新配方与旧字段分开，旧动作档案仍可完成；所有耗时单位为游戏分钟。
@export var advanced_recipes: Dictionary = {
	"cooking_table":{"materials":{"wood":6,"stone":4,"rope":1},"minutes":45.0,"stamina":15.0,"width":2,"height":1,"skill":"building","tier":2},
	"small_trap":{"materials":{"fiber":4,"wood":1},"minutes":20.0,"stamina":4.0,"width":1,"height":1,"skill":"trap","tier":1},
	"large_trap":{"materials":{"wood":4,"rope":2,"stone":2},"minutes":30.0,"stamina":6.0,"width":2,"height":2,"skill":"trap","tier":2},
	"camp_2":{"materials":{"wood":12,"rope":2,"hide":2},"minutes":90.0,"stamina":25.0,"width":3,"height":3,"skill":"building","tier":1},
	"camp_3":{"materials":{"wood":18,"stone":6,"rope":3,"hide":3},"minutes":90.0,"stamina":25.0,"width":4,"height":4,"skill":"building","tier":3},
	"rope":{"materials":{"fiber":4},"minutes":10.0,"stamina":4.0,"output":"rope","quantity":1},
	"arrow":{"materials":{"wood":1,"stone":1,"fiber":1},"minutes":15.0,"stamina":4.0,"output":"arrow","quantity":3,"skill":"hunting","tier":1},
	"bow":{"materials":{"wood":3,"rope":1},"minutes":30.0,"stamina":4.0,"output":"bow","quantity":1,"skill":"hunting","tier":1},
	"leather_armor":{"materials":{"hide":4,"rope":2},"minutes":60.0,"stamina":4.0,"output":"leather_armor","quantity":1,"skill":"building","tier":2},
	"cooked_fish":{"materials":{"raw_fish":1},"minutes":10.0,"stamina":2.0,"output":"cooked_fish","quantity":1,"fire":true},
	"cooked_meat":{"materials":{"raw_meat":1},"minutes":10.0,"stamina":2.0,"output":"cooked_meat","quantity":1,"fire":true},
	"stew":{"materials":{"root":1,"berry":1},"minutes":20.0,"stamina":2.0,"output":"stew","quantity":1,"fire":true,"table":true,"water_l":0.25,"skill":"cooking","tier":1},
	"herbal_medicine":{"materials":{"herb":2},"minutes":15.0,"stamina":4.0,"output":"herbal_medicine","quantity":1,"fire":true,"water_l":0.25,"skill":"healing","tier":1}}
@export var fishing_minutes: float = 30.0
@export var fishing_stamina: float = 6.0
@export var fishing_probability: float = 0.6
@export var fishing_probability_cap: float = 0.9
@export var fish_refill_seconds: float = 43200.0
@export var fish_refill_quantity: int = 2
@export var maximum_traps: int = 5
@export var small_trap_seconds: float = 21600.0
@export var large_trap_seconds: float = 28800.0
@export var small_trap_probability: float = 0.4
@export var large_trap_probability: float = 0.35
@export var trap_probability_cap: float = 0.8
@export var trap_habitat_radius_tiles: float = 6.0
@export var trap_maximum_uses: int = 3
@export var camp_hp_multipliers: PackedFloat32Array = PackedFloat32Array([1,1.5,2])
@export var camp_disturbance_multipliers: PackedFloat32Array = PackedFloat32Array([1,0.6,0.3])

func recipe(id: String) -> Dictionary:
	return recipes.get(id,advanced_recipes.get(id,{})).duplicate(true)
@export var gather_minutes: float = 5.0
@export var gather_stamina: float = 2.0
@export var axe_minutes: float = 15.0
@export var axe_stamina: float = 10.0
@export var knife_minutes: float = 45.0
@export var knife_stamina: float = 18.0
@export var eat_minutes: float = 1.0
@export var water_minutes: float = 1.0
@export var digestion_seconds: float = 600.0
@export var fire_initial_seconds: float = 14400.0
@export var fire_wood_seconds: float = 7200.0
@export var fire_maximum_seconds: float = 43200.0
@export var water_quantum_l: float = 0.25
@export var starvation_delay_seconds: float = 7200.0
@export var starvation_damage_per_hour: float = 3.0
@export var dehydration_damage_per_hour: float = 6.0
@export var resting_hp_per_hour: float = 2.0
@export var resting_stamina_per_minute: float = 4.0
@export var moving_stamina_per_minute: float = 0.25
@export var walking_recovery_per_minute: float = 1.0
