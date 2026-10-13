class_name WildProfileIdentityStore
extends RefCounted
## 仅持久化玩家身份，不提前实现 P1 的货币 / 仓库 / 完整存档。
## 路径可注入；自动验证使用工作区临时文件，不碰玩家正式档案。

var _path: String


func _init(path: String = "user://profile_identity.cfg") -> void:
	_path = path


func load_or_create() -> WildOperationResult:
	var file := ConfigFile.new()
	if FileAccess.file_exists(_path):
		var load_error: Error = file.load(_path)
		if load_error != OK:
			return WildOperationResult.reject(&"PROFILE_READ_FAILED")
		var id := str(file.get_value("identity", "player_id", ""))
		if int(file.get_value("identity", "version", 0)) != 1 or id.is_empty():
			return WildOperationResult.reject(&"PROFILE_INVALID")
		return WildOperationResult.accept({"player_id": id, "display_name": str(file.get_value("identity", "display_name", "生存者"))})
	file.set_value("identity", "version", 1)
	file.set_value("identity", "player_id", WildStableId.create("player"))
	file.set_value("identity", "display_name", "生存者")
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_path.get_base_dir()))
	if directory_error != OK:
		return WildOperationResult.reject(&"PROFILE_WRITE_FAILED")
	if file.save(_path) != OK:
		return WildOperationResult.reject(&"PROFILE_WRITE_FAILED")
	return WildOperationResult.accept({"player_id": str(file.get_value("identity", "player_id")), "display_name": "生存者"})
