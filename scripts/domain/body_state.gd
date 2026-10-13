class_name WildBodyState
extends RefCounted
## 可持久化身体数据；消化任务与饥饿累计独立于 UI 和游戏节点。
var hp: float = 100.0
var health: float = 100.0
var water: float = 100.0
var stamina: float = 100.0
var nutrition: Array[float] = [100.0,100.0,100.0,100.0,100.0]
var digestion: Array[Dictionary] = []
var starvation_seconds: float = 0.0
var pollution: float = 0.0
## 迟滞标志避免 20–30 区间反复开关；衰弱按每项连续低营养计时。
var shortages: Array[bool] = [false,false,false,false,false]
var low_nutrition_seconds: Array[float] = [0,0,0,0,0]
var dehydrated: bool = false
var bleeding: bool = false
var weakness: bool = false
var weakness_recovery_seconds: float = 0.0
var gastro_remaining_seconds: float = 0.0
var medicine_cooldown_seconds: float = 0.0
var pollution_check_elapsed: float = 0.0
var health_random_state: String = "0"

func record() -> Dictionary:
	return {"hp":hp,"health":health,"water":water,"stamina":stamina,"nutrition":nutrition.duplicate(),"digestion":digestion.duplicate(true),"starvation_seconds":starvation_seconds,"pollution":pollution,"body_version":1,"shortages":shortages.duplicate(),"low_nutrition_seconds":low_nutrition_seconds.duplicate(),"dehydrated":dehydrated,"bleeding":bleeding,"weakness":weakness,"weakness_recovery_seconds":weakness_recovery_seconds,"gastro_remaining_seconds":gastro_remaining_seconds,"medicine_cooldown_seconds":medicine_cooldown_seconds,"pollution_check_elapsed":pollution_check_elapsed,"health_random_state":health_random_state}

func snapshot(actor: String) -> Dictionary:
	var values: Dictionary = {}
	for index: int in range(5): values[WildPlayerState.NUTRIENT_IDS[index]] = nutrition[index]
	return {"player_id":actor,"health_points":hp,"health":health,"hydration":water,"stamina":stamina,"nutrition":values,"pollution":pollution,"shortages":shortages.duplicate(),"dehydrated":dehydrated,"bleeding":bleeding,"weakness":weakness,"gastro_remaining_seconds":gastro_remaining_seconds,"medicine_cooldown_seconds":medicine_cooldown_seconds,"weakness_recovery_seconds":weakness_recovery_seconds,"low_nutrition_seconds":low_nutrition_seconds.duplicate()}

func copy() -> WildBodyState:
	var other := WildBodyState.new()
	other.hp = hp
	other.health = health
	other.water = water
	other.stamina = stamina
	other.nutrition.assign(nutrition)
	other.digestion.assign(digestion.duplicate(true))
	other.starvation_seconds = starvation_seconds
	other.pollution = pollution
	other.shortages.assign(shortages)
	other.low_nutrition_seconds.assign(low_nutrition_seconds)
	other.dehydrated = dehydrated
	other.bleeding = bleeding
	other.weakness = weakness
	other.weakness_recovery_seconds = weakness_recovery_seconds
	other.gastro_remaining_seconds = gastro_remaining_seconds
	other.medicine_cooldown_seconds = medicine_cooldown_seconds
	other.pollution_check_elapsed = pollution_check_elapsed
	other.health_random_state = health_random_state
	return other
