class_name WildSkillProfile
extends RefCounted
## 永久技能实例。钱学与点数学共享等级，已花点单独保存，避免钱学赠点。
var experience: Dictionary = {}
var levels: Dictionary = {}
var spent_points: Dictionary = {}

func _init() -> void:
	for branch: String in WildSkillCatalog.BRANCHES:
		experience[branch] = 0
		levels[branch] = 0
		spent_points[branch] = 0

func record() -> Dictionary:
	return {"skills_version":1,"experience":experience.duplicate(),"levels":levels.duplicate(),"spent_points":spent_points.duplicate()}

func copy() -> WildSkillProfile:
	var other := WildSkillProfile.new()
	other.experience = experience.duplicate()
	other.levels = levels.duplicate()
	other.spent_points = spent_points.duplicate()
	return other
