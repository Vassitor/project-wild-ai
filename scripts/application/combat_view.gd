class_name WildCombatView
extends RefCounted
## 只读显示数据：隐藏未来动物随机选择，足迹只提供给解锁追踪的玩家。
static func animals(run: WildSurvivalState) -> Dictionary:
	var result: Dictionary = run.prey.duplicate(true)
	for animal: Dictionary in result.values():
		for key: String in ["random_state","wander_at","direction","ready_at","last_track","target"]: animal.erase(key)
	return result

static func create(state: WildBaseState, actor: String) -> Dictionary:
	var run: WildSurvivalState = state.survival
	if run == null: return {"projectiles":{},"tracks":[],"feedback":{},"combat_time":0.0}
	return {"projectiles":run.projectiles.duplicate(true),"tracks":run.tracks.duplicate(true) if WildSkillRules.level(state.skills,"hunting") >= 2 else [],"feedback":run.combat_feedback.duplicate(true),"combat_time":run.elapsed_seconds,"attack_ready_at":run.attack_ready_at.get(actor,0)}
