class_name WildBaseStateStore
extends RefCounted
## 文件适配器，保存完整事务单元。先写临时文件再替换，失败保留正式档案。

var _path: String


func _init(path: String) -> void:
	_path = path


func load_records() -> WildOperationResult:
	return WildOperationResult.accept({"exists": FileAccess.file_exists(_path) or FileAccess.file_exists(_path + ".bak"), "primary": _read(_path), "backup": _read(_path + ".bak")})


func save_record(data: Dictionary, preserve_backup: bool = false) -> WildOperationResult:
	var absolute: String = ProjectSettings.globalize_path(_path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return WildOperationResult.reject(&"SAVE_FAILED")
	var temporary: String = absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return WildOperationResult.reject(&"SAVE_FAILED")
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return WildOperationResult.reject(&"SAVE_FAILED")
	# 备份恢复时不再用损坏的主文件覆盖良好备份。
	if FileAccess.file_exists(absolute) and not preserve_backup:
		if DirAccess.copy_absolute(absolute, absolute + ".bak") != OK:
			return WildOperationResult.reject(&"SAVE_FAILED")
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		return WildOperationResult.reject(&"SAVE_FAILED")
	return WildOperationResult.accept()


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data as Dictionary
