class_name WildTrapRules
extends RefCounted
## 陷阱只移除地图中实际存在的猎物。无饵、报废、占用或无猎物时不消费鱼饵。
static func initialize(building: Dictionary, actor: String, seed_text: String, run_time: float, content: WildSurvivalContent, profile: WildSkillProfile, skills: WildSkillCatalog) -> void:
	building["owner"] = actor
	building["bait"] = 0
	building["uses_left"] = content.trap_maximum_uses
	building["capture"] = {}
	building["next_check"] = run_time+interval(building,content)
	building["trap_random_state"] = str(WildWorldGenerator._stream(seed_text,"trap:"+building["id"]).state)
	building["probability_bonus"] = skills.trap_success_bonus if WildSkillRules.level(profile,"trap") >= 3 else 0.0

static func interval(building: Dictionary, content: WildSurvivalContent) -> float:
	return content.small_trap_seconds if building["kind"] == "small_trap" else content.large_trap_seconds

static func candidate(building: Dictionary, run: WildSurvivalState, _world: WildWorldData, content: WildSurvivalContent) -> String:
	var kind: String = "rabbit" if building["kind"] == "small_trap" else "boar"
	var centre := Vector2(building["x"]+building["width"]*0.5,building["y"]+building["height"]*0.5)
	for id: String in run.prey:
		var animal: Dictionary = run.prey[id]
		if animal["alive"] and animal["kind"] == kind and centre.distance_to(Vector2(animal["x"]+0.5,animal["y"]+0.5)) <= content.trap_habitat_radius_tiles: return id
	return ""

static func tick(building: Dictionary, run: WildSurvivalState, world: WildWorldData, content: WildSurvivalContent, _config: WildGameConfig) -> bool:
	var changed: bool = false
	while building["next_check"] <= run.elapsed_seconds+0.000001:
		var checked_at: float = building["next_check"]
		building["next_check"] += interval(building,content)
		if building["uses_left"] <= 0 or building["bait"] <= 0 or not building["capture"].is_empty(): continue
		var id: String = candidate(building,run,world,content)
		if id.is_empty(): continue
		building["bait"] -= 1
		var random := RandomNumberGenerator.new()
		random.state = str(building["trap_random_state"]).to_int()
		var probability: float = content.small_trap_probability if building["kind"] == "small_trap" else content.large_trap_probability
		var success: bool = random.randf() < minf(content.trap_probability_cap,probability+building["probability_bonus"])
		building["trap_random_state"] = str(random.state)
		changed = true
		if success:
			run.prey[id]["alive"] = false
			building["uses_left"] -= 1
			building["capture"] = {"prey_id":id,"kind":run.prey[id]["kind"],"captured_at":checked_at}
	return changed
