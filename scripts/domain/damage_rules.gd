class_name WildDamageRules
extends RefCounted
## 权威伤害入口，仅由模拟 / 未来动物调用。没有可供客户端提交的伤害命令。
static func armor_view(state: WildBaseState, rules: WildHealthConfig) -> Dictionary:
	for entry: Dictionary in state.containers["armor"].placements.values():
		var item: WildItemInstance = entry["item"]
		if item.item_id == &"leather_armor":
			return {"durability":item.durability,"physical_reduction":minf(rules.leather_physical_reduction,rules.maximum_physical_reduction) if item.durability > 0 else 0.0}
	return {"durability":0.0,"physical_reduction":0.0}

static func apply(state: WildBaseState, actor: String, amount: float, cause: String, rules: WildHealthConfig) -> WildOperationResult:
	if state.survival == null or not state.survival.bodies.has(actor) or state.player_id != actor: return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	if not is_finite(amount) or amount <= 0 or cause not in ["physical","environment","disease"]: return WildOperationResult.reject(&"INVALID_DAMAGE")
	var body: WildBodyState = state.survival.bodies[actor]
	if body.hp <= 0: return WildOperationResult.reject(&"DEAD_ACTOR")
	var final_damage: float = amount
	if cause == "physical":
		final_damage *= 1 - float(armor_view(state,rules)["physical_reduction"])
		for entry: Dictionary in state.containers["armor"].placements.values():
			var item: WildItemInstance = entry["item"]
			if item.item_id == &"leather_armor" and item.durability > 0:
				item.durability = maxf(0,item.durability - rules.armor_wear_per_hit)
				state.containers["armor"].version += 1
		if final_damage >= rules.bleeding_damage_threshold and not body.bleeding and WildIllnessRules.random_draw(body) < rules.bleeding_probability: body.bleeding = true
	WildBodyRules.damage(body,final_damage)
	if state.survival.actions.get(actor,{}).get("type","") == "sleep":
		state.survival.actions.erase(actor)
		state.survival.notice = "受到伤害，已提前醒来。"
	return WildOperationResult.accept({"damage":final_damage})
