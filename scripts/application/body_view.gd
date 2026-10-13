class_name WildBodyView
extends RefCounted
## 只读身体反馈：数值来自同一权威规则，界面不重复计算恢复或护甲。
static func create(state: WildBaseState, actor: String, config: WildGameConfig, catalog: WildItemCatalog, current_activity: String = "idle") -> Dictionary:
	if state.survival == null or not state.survival.bodies.has(actor): return {}
	var body: WildBodyState = state.survival.bodies[actor]
	var view: Dictionary = body.snapshot(actor)
	var activity: String = state.survival.actions.get(actor,{}).get("activity",current_activity)
	var overload: float = clampf((state.carried_weight(catalog,config)-config.soft_weight_limit_kg)/(config.hard_weight_limit_kg-config.soft_weight_limit_kg),0,1)
	view["activity"] = activity
	view["nutrition_rates_per_hour"] = WildBodyRules.nutrition_rates(config,activity)
	view["water_consumption_per_hour"] = WildBodyRules.water_consumption(body,config,activity)
	view["stamina_recovery_multiplier"] = WildBodyRules.recovery_factor(body,config)
	view["illness_movement_multiplier"] = WildIllnessRules.movement_multiplier(body,config.health_rules)
	view["movement_multiplier"] = (1-overload*config.maximum_weight_slowdown)*float(view["illness_movement_multiplier"])
	view["effort_cost_multiplier"] = 1+overload*config.maximum_weight_stamina_penalty
	view["carried_weight_kg"] = state.carried_weight(catalog,config)
	view["armor"] = WildDamageRules.armor_view(state,config.health_rules)
	view["bleeding_hp_loss_per_hour"] = config.health_rules.bleeding_hp_per_hour if body.bleeding else 0.0
	view["illness_health_loss_per_hour"] = (config.health_rules.bleeding_health_per_hour if body.bleeding else 0.0)+(config.health_rules.gastro_health_per_hour if body.gastro_remaining_seconds > 0 else 0.0)
	return view
