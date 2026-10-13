class_name WildMedicalRules
extends RefCounted
## 只处理当前角色的治疗条件和效果。物品预留 / 消耗由行动事务管理。
static func validate(body: WildBodyState, item: StringName) -> WildOperationResult:
	if body.hp <= 0: return WildOperationResult.reject(&"DEAD_ACTOR")
	if item == &"bandage":
		return WildOperationResult.accept() if body.bleeding else WildOperationResult.reject(&"NO_BLEEDING")
	if item == &"herbal_medicine":
		if body.gastro_remaining_seconds <= 0: return WildOperationResult.reject(&"NO_GASTRO")
		return WildOperationResult.accept() if body.medicine_cooldown_seconds <= 0 else WildOperationResult.reject(&"MEDICINE_COOLDOWN")
	return WildOperationResult.reject(&"NOT_MEDICINE")

static func apply(body: WildBodyState, item: StringName, rules: WildHealthConfig) -> bool:
	if not validate(body,item).successful: return false
	if item == &"bandage": body.bleeding = false
	else:
		body.gastro_remaining_seconds = maxf(0,body.gastro_remaining_seconds - rules.medicine_reduction_seconds)
		body.medicine_cooldown_seconds = rules.medicine_cooldown_seconds
	return true
