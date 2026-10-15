class_name WildNetworkCompatibility
extends RefCounted
## 源码和静态配置摘要仅作好友合作兼容检查，不作为身份或反作弊凭证。
static func fingerprint() -> String:
	# 导出时 .gd 可能变成 .gdc / remap；从构建清单读取同一源码指纹，不能扫描出空摘要。
	if not OS.has_feature("editor"):
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/build_manifest.json"))
		if manifest is Dictionary and manifest.get("version",0) == 1 and manifest.get("content_fingerprint",null) is String and manifest["content_fingerprint"].length() == 64: return manifest["content_fingerprint"]
		return ""
	return source_fingerprint()

## 仅构建 / 编辑器读取源码，用排序后的稳定路径生成平台无关摘要。
static func source_fingerprint() -> String:
	var paths: Array[String] = []
	_collect("res://scripts",paths)
	_collect("res://data",paths)
	paths.sort()
	var records: Dictionary = {}
	for path: String in paths: records[path] = FileAccess.get_sha256(path)
	return WildCanonicalData.digest(records)

static func _collect(root: String, paths: Array[String]) -> void:
	for name: String in DirAccess.get_files_at(root):
		if name.ends_with(".gd") or name.ends_with(".tres"): paths.append(root+"/"+name)
	for name: String in DirAccess.get_directories_at(root): _collect(root+"/"+name,paths)
