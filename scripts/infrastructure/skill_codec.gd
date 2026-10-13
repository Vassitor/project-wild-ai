class_name WildSkillCodec
extends RefCounted
## 缺少技能字段的旧档得到空技能树；新字段不接受客户端可伪造的点数总量。
static func decode(raw: Variant, catalog: WildSkillCatalog) -> WildSkillProfile:
	if raw == null: return WildSkillProfile.new()
	if not raw is Dictionary or raw.get("skills_version",0) != 1: return null
	var profile := WildSkillProfile.new()
	for field: String in ["experience","levels","spent_points"]:
		if not raw.get(field,null) is Dictionary or raw[field].size() != WildSkillCatalog.BRANCHES.size(): return null
		for branch: String in WildSkillCatalog.BRANCHES:
			if not WildDataValidation.whole(raw[field].get(branch,null)) or raw[field][branch] < 0 or raw[field][branch] > 100000000: return null
		profile.set(field,raw[field].duplicate())
	for branch: String in WildSkillCatalog.BRANCHES:
		var tier: int = int(profile.levels[branch])
		if tier > 3 or WildSkillRules.points(profile,branch,catalog) < 0: return null
		var maximum_spent: int = 0
		for index: int in range(tier): maximum_spent += catalog.point_costs[index]
		if profile.spent_points[branch] > maximum_spent: return null
	return profile
