class_name WildIllnessRules
extends RefCounted
## 每名角色自己的随机流；读档、人数和动作随机流不会改变疾病结果。
static func seed_body(body: WildBodyState, seed_text: String, actor: String) -> void:
	body.health_random_state = str(WildWorldGenerator._stream(seed_text,"health:" + actor).state)

static func random_draw(body: WildBodyState) -> float:
	var random := RandomNumberGenerator.new()
	random.state = body.health_random_state.to_int()
	var value: float = random.randf()
	body.health_random_state = str(random.state)
	return value

static func synchronize(body: WildBodyState, rules: WildHealthConfig) -> void:
	for index: int in range(5):
		if body.nutrition[index] < rules.shortage_enter: body.shortages[index] = true
		elif body.nutrition[index] >= rules.shortage_exit: body.shortages[index] = false
	if body.water < rules.shortage_enter: body.dehydrated = true
	elif body.water >= rules.shortage_exit: body.dehydrated = false

static func movement_multiplier(body: WildBodyState, rules: WildHealthConfig) -> float:
	return rules.weakness_speed_multiplier if body.weakness else 1.0

static func recovery_multiplier(body: WildBodyState, rules: WildHealthConfig) -> float:
	return rules.weakness_recovery_multiplier if body.weakness else 1.0

## 污染至少 50 才作小时检查；已有肠胃病不重复叠加病程。
static func check_pollution(body: WildBodyState, rules: WildHealthConfig) -> void:
	if body.pollution < rules.pollution_threshold or body.gastro_remaining_seconds > 0: return
	var probability: float = clampf((body.pollution - 40) / 100 * (1 + (100 - body.health) / 200),0,0.8)
	if random_draw(body) < probability:
		body.gastro_remaining_seconds = rules.gastro_seconds
		body.pollution = 0
