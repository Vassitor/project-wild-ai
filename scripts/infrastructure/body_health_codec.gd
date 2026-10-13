class_name WildBodyHealthCodec
extends RefCounted
## 新身体子版本显式校验；旧 P3 档补齐默认疾病字段并生成稳定的个人随机流。
static func restore(raw: Dictionary, body: WildBodyState, rules: WildHealthConfig, seed_text: String, actor: String) -> bool:
	if not raw.has("body_version"):
		WildIllnessRules.seed_body(body,seed_text,actor)
		WildIllnessRules.synchronize(body,rules)
		return true
	if not WildDataValidation.whole(raw["body_version"]) or raw["body_version"] != 1: return false
	for key: String in ["dehydrated","bleeding","weakness"]:
		if not raw.get(key,null) is bool: return false
		body.set(key,raw[key])
	var limits: Dictionary = {"weakness_recovery_seconds":rules.weakness_recovery_seconds,"gastro_remaining_seconds":rules.gastro_seconds,"medicine_cooldown_seconds":rules.medicine_cooldown_seconds,"pollution_check_elapsed":rules.pollution_check_seconds}
	for key: String in limits:
		if not WildDataValidation.number(raw.get(key,null)) or raw[key] < 0 or raw[key] > limits[key]: return false
		body.set(key,float(raw[key]))
	if body.pollution_check_elapsed >= rules.pollution_check_seconds: return false
	if body.weakness and body.weakness_recovery_seconds >= rules.weakness_recovery_seconds: return false
	if not body.weakness and body.weakness_recovery_seconds != 0: return false
	if not WildWorldGenerator.valid_seed(raw.get("health_random_state",null),true): return false
	body.health_random_state = raw["health_random_state"]
	for key: String in ["shortages","low_nutrition_seconds"]:
		if not raw.get(key,null) is Array or raw[key].size() != 5: return false
	for index: int in range(5):
		if not raw["shortages"][index] is bool: return false
		var time: Variant = raw["low_nutrition_seconds"][index]
		if not WildDataValidation.number(time) or time < 0 or time > rules.weakness_delay_seconds: return false
		body.shortages[index] = raw["shortages"][index]
		body.low_nutrition_seconds[index] = float(time)
	return true
