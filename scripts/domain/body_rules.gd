class_name WildBodyRules
extends RefCounted
## 统一区间积分；消化、阈值、病程、小时风险检查均拆步，避免追溯整分钟伤害。
static func advance(body: WildBodyState, config: WildGameConfig, content: WildSurvivalContent, seconds: float, activity: String, overload: float, hp_recovery_multiplier: float = 1.0) -> void:
	if not is_finite(seconds) or seconds <= 0 or body.hp <= 0: return
	var rules: WildHealthConfig = config.health_rules
	var remaining: float = seconds
	while remaining > 0.000001 and body.hp > 0:
		WildIllnessRules.synchronize(body,rules)
		var rates: Array[float] = nutrition_rates(config,activity)
		var step: float = minf(remaining,60)
		step = minf(step,rules.pollution_check_seconds-body.pollution_check_elapsed)
		for task: Dictionary in body.digestion:
			step = minf(step,task["remaining_seconds"])
			for index: int in range(5): rates[index] += float(task["per_second"][index])*3600
		for index: int in range(5):
			step = _crossing_step(step,body.nutrition[index],rates[index]/3600,[0.0,10.0,20.0,30.0,100.0])
			if body.nutrition[index] < rules.shortage_enter and body.low_nutrition_seconds[index] < rules.weakness_delay_seconds: step = minf(step,rules.weakness_delay_seconds-body.low_nutrition_seconds[index])
		var water_rate: float = water_consumption(body,config,activity)
		step = _crossing_step(step,body.water,-water_rate/3600,[0.0,20.0,30.0,40.0])
		for timer: float in [body.gastro_remaining_seconds,body.medicine_cooldown_seconds]:
			if timer > 0: step = minf(step,timer)
		if body.starvation_seconds < content.starvation_delay_seconds and body.nutrition[0] < 10 and body.nutrition[1] < 10: step = minf(step,content.starvation_delay_seconds-body.starvation_seconds)
		if body.weakness and body.nutrition.min() >= rules.shortage_exit: step = minf(step,rules.weakness_recovery_seconds-body.weakness_recovery_seconds)
		assert(step > 0,"Body boundary must advance: %s" % body.record())
		# 阈值上的下降趋势属于下一区间；中点判定避免零长度循环。
		var midpoint: Array[float] = []
		for index: int in range(5): midpoint.append(clampf(body.nutrition[index]+rates[index]*step/7200,0,100))
		var middle_water: float = maxf(0,body.water-water_rate*step/7200)
		var shortage_count: int = 0
		for index: int in range(5):
			if midpoint[index] < rules.shortage_enter: body.shortages[index] = true
			elif midpoint[index] >= rules.shortage_exit: body.shortages[index] = false
			if body.shortages[index]: shortage_count += 1
		if middle_water < rules.shortage_enter: body.dehydrated = true
		elif middle_water >= rules.shortage_exit: body.dehydrated = false
		var hours: float = step/3600
		var health_loss: float = minf(rules.shortage_health_cap,shortage_count*rules.shortage_health_per_hour)
		if body.dehydrated: health_loss += rules.dehydration_health_per_hour
		if body.bleeding: health_loss += rules.bleeding_health_per_hour
		if body.gastro_remaining_seconds > 0: health_loss += rules.gastro_health_per_hour
		var hp_loss: float = rules.bleeding_hp_per_hour if body.bleeding else 0.0
		if middle_water <= 0: hp_loss += content.dehydration_damage_per_hour
		if body.starvation_seconds >= content.starvation_delay_seconds and midpoint[0] < 20 and midpoint[1] < 20: hp_loss += content.starvation_damage_per_hour
		var resting: bool = activity in ["rest","sleep"]
		var recovery: float = recovery_factor(body,config)
		var hp_gain: float = content.resting_hp_per_hour*minf(1,minf(body.nutrition[2]/50,body.health/60))*WildIllnessRules.recovery_multiplier(body,rules)*hp_recovery_multiplier if resting else 0.0
		body.hp = clampf(body.hp+(hp_gain-hp_loss)*hours,0,100)
		var health_gain: float = rules.safe_rest_health_per_hour if resting and middle_water >= 40 and midpoint.min() >= rules.shortage_exit and not body.bleeding and body.gastro_remaining_seconds <= 0 else 0.0
		body.health = clampf(body.health+(health_gain-health_loss)*hours,0,100)
		if activity == "sprint": body.stamina = maxf(0,body.stamina-config.sprint_stamina_per_game_minute*step/60*(1+config.maximum_weight_stamina_penalty*overload))
		elif activity != "work":
			var rate: float = content.resting_stamina_per_minute if resting else (content.walking_recovery_per_minute if activity == "walk" else config.idle_stamina_recovery_per_game_minute)
			var cost: float = content.moving_stamina_per_minute if activity == "walk" and body.stamina > 0 else 0.0
			body.stamina = clampf(body.stamina+(rate*recovery-cost)*step/60,0,100)
		for index: int in range(5):
			body.nutrition[index] = clampf(body.nutrition[index]+rates[index]*hours,0,100)
			body.low_nutrition_seconds[index] = minf(rules.weakness_delay_seconds,body.low_nutrition_seconds[index]+step) if midpoint[index] < rules.shortage_enter else 0.0
			if body.low_nutrition_seconds[index] >= rules.weakness_delay_seconds: body.weakness = true
		body.water = maxf(0,body.water-water_rate*hours)
		if midpoint[0] >= 20 or midpoint[1] >= 20: body.starvation_seconds = 0
		elif midpoint[0] < 10 and midpoint[1] < 10: body.starvation_seconds = minf(content.starvation_delay_seconds,body.starvation_seconds+step)
		elif body.starvation_seconds < content.starvation_delay_seconds: body.starvation_seconds = 0
		if body.weakness:
			body.weakness_recovery_seconds = body.weakness_recovery_seconds+step if midpoint.min() >= rules.shortage_exit else 0.0
			if body.weakness_recovery_seconds+0.000001 >= rules.weakness_recovery_seconds:
				body.weakness = false
				body.weakness_recovery_seconds = 0
		for task: Dictionary in body.digestion.duplicate():
			task["remaining_seconds"] -= step
			if task["remaining_seconds"] <= 0.000001: body.digestion.erase(task)
		body.gastro_remaining_seconds = maxf(0,body.gastro_remaining_seconds-step)
		body.medicine_cooldown_seconds = maxf(0,body.medicine_cooldown_seconds-step)
		body.pollution = maxf(0,body.pollution-rules.pollution_decay_per_hour*hours)
		body.pollution_check_elapsed += step
		if body.pollution_check_elapsed+0.000001 >= rules.pollution_check_seconds:
			body.pollution_check_elapsed = 0
			if body.hp > 0: WildIllnessRules.check_pollution(body,rules)
		WildIllnessRules.synchronize(body,rules)
		remaining -= step

static func _crossing_step(step: float, value: float, rate: float, thresholds: Array) -> float:
	if absf(rate) < 0.0000001: return step
	for threshold: float in thresholds:
		var time: float = (threshold-value)/rate
		if time > 0.000001: step = minf(step,time)
	return step

## 负值表示每游戏小时消耗；消化正值只在积分区间内叠加。
static func nutrition_rates(config: WildGameConfig, activity: String) -> Array[float]:
	var result: Array[float] = []
	for index: int in range(5):
		var factor: float = 1
		if index < 2: factor = 0.5 if activity == "sleep" else (1.5 if activity in ["work","sprint"] else 1.0)
		elif index == 2: factor = 0.75 if activity == "sleep" else (1.1 if activity in ["work","sprint"] else 1.0)
		result.append(-config.nutrition_consumption_per_hour[index]*factor)
	return result

static func water_consumption(body: WildBodyState, config: WildGameConfig, activity: String) -> float:
	var base: float = config.sleeping_water_consumption_per_hour if activity == "sleep" else (config.working_water_consumption_per_hour if activity in ["work","sprint"] else config.water_consumption_per_hour)
	return base+(config.health_rules.gastro_water_per_hour if body.gastro_remaining_seconds > 0 else 0.0)

static func recovery_factor(body: WildBodyState, config: WildGameConfig) -> float:
	return clampf(minf(body.nutrition[0]/40,minf(body.water/40,body.health/60)),0.25,1)*WildIllnessRules.recovery_multiplier(body,config.health_rules)

static func eat(body: WildBodyState, content: WildSurvivalContent, item: WildItemInstance) -> void:
	var values: Array = content.foods[str(item.item_id)]
	var rates: Array[float] = []
	for value: Variant in values: rates.append(float(value)*item.nutrition_multiplier/content.digestion_seconds*(0.5 if item.freshness_hours <= 0 else 1.0))
	body.digestion.append({"remaining_seconds":content.digestion_seconds,"per_second":rates})
	if item.freshness_hours <= 0 or item.item_id in [&"raw_meat",&"raw_fish"]: body.pollution = minf(100,body.pollution+40)

static func drink(body: WildBodyState, config: WildGameConfig, litres: float, clean: bool) -> void:
	body.water = minf(100,body.water+litres/0.5*config.hydration_per_half_litre)
	if not clean: body.pollution = minf(100,body.pollution+litres/0.5*25)
	WildIllnessRules.synchronize(body,config.health_rules)

## 非物理持续损伤不经过装备减免。
static func damage(body: WildBodyState, amount: float) -> void:
	if is_finite(amount) and amount > 0: body.hp = maxf(0,body.hp-amount)
