class_name WildSkillRules
extends RefCounted
## 经验与学习的纯规则。应用服务持久化整个候选事务，UI 不直接授予成长。
static func points(profile: WildSkillProfile, branch: String, catalog: WildSkillCatalog) -> int:
	return floori(float(profile.experience.get(branch,0))/catalog.experience_per_point)-int(profile.spent_points.get(branch,0))

static func level(profile: WildSkillProfile, branch: String) -> int:
	return int(profile.levels.get(branch,0))

## 同一节点可用基地货币或本分支点数学习；校验完成后只修改候选状态，写盘由服务提交。
static func learn(state: WildBaseState, data: Dictionary, catalog: WildSkillCatalog, money: bool) -> WildOperationResult:
	var branch: Variant = data.get("branch",null)
	var tier: Variant = data.get("tier",null)
	if not branch is String or branch not in WildSkillCatalog.BRANCHES or not WildDataValidation.whole(tier) or tier < 1 or tier > 3: return WildOperationResult.reject(&"INVALID_SKILL")
	var current: int = level(state.skills,branch)
	if current >= int(tier): return WildOperationResult.reject(&"SKILL_ALREADY_LEARNED")
	if current+1 != int(tier): return WildOperationResult.reject(&"SKILL_PREREQUISITE")
	if money:
		if state.phase != WildRunFlow.Phase.BASE: return WildOperationResult.reject(&"BASE_LEARNING_ONLY")
		var cost: int = catalog.training_costs[int(tier)-1]
		if state.currency < cost: return WildOperationResult.reject(&"INSUFFICIENT_CURRENCY")
		state.currency -= cost
	else:
		var cost: int = catalog.point_costs[int(tier)-1]
		if points(state.skills,branch,catalog) < cost: return WildOperationResult.reject(&"INSUFFICIENT_SKILL_POINTS")
		state.skills.spent_points[branch] += cost
	state.skills.levels[branch] = int(tier)
	return WildOperationResult.accept({"branch":branch,"tier":int(tier)})

## 仅由已确认有效的动作完成路径调用；接收者为执行者的个人档案。
static func award(state: WildBaseState, branch: String, catalog: WildSkillCatalog) -> void:
	if catalog.experience_rewards.has(branch): state.skills.experience[branch] += int(catalog.experience_rewards[branch])

static func snapshot(profile: WildSkillProfile, catalog: WildSkillCatalog) -> Dictionary:
	var view: Dictionary = profile.record()
	view["points"] = {}
	for branch: String in WildSkillCatalog.BRANCHES: view["points"][branch] = points(profile,branch,catalog)
	return view
