class_name WildSaveVersions
extends RefCounted
## 未来子版本是兼容性问题，不当作损坏主档用旧备份覆盖。
static func future(record: Dictionary) -> bool:
	if _newer(record.get("cooperation",{}),"version") or _newer(record.get("lifecycle",{}),"version"): return true
	if _newer(record.get("skills",{}),"skills_version"): return true
	var run: Variant = record.get("active_run",{})
	if run is Dictionary and _survival_future(run.get("survival",{})): return true
	if _survival_future(record.get("survival",{})): return true
	var members: Variant = record.get("members",{})
	if members is Dictionary:
		for member: Variant in members.values():
			if member is Dictionary and future(member): return true
	return false

static func _newer(raw: Variant, key: String) -> bool:
	return raw is Dictionary and WildDataValidation.whole(raw.get(key,null)) and raw[key] > 1

static func _survival_future(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	if _newer(raw.get("progression",{}),"version"): return true
	if _newer(raw.get("combat",{}),"version"): return true
	var bodies: Variant = raw.get("bodies",{})
	if bodies is Dictionary:
		for body: Variant in bodies.values():
			if _newer(body,"body_version"): return true
	return false
