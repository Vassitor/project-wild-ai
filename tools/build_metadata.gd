extends SceneTree
## 构建时生成清单和引擎自带许可；不创建玩家或打开任何基地档案。
func _initialize() -> void:
	var dir: String = "res://build/windows"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--build-output="): dir = argument.trim_prefix("--build-output=")
	if not dir.begins_with("res://build/") or dir.contains(".."): quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var manifest: Dictionary = {"version":1,"candidate":"0.2.0-rc1","engine":Engine.get_version_info()["string"],"protocol":WildENetRoom.PROTOCOL,"content_fingerprint":WildNetworkCompatibility.source_fingerprint()}
	FileAccess.open("res://data/build_manifest.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t"))
	FileAccess.open(dir+"/GODOT-LICENSE.txt",FileAccess.WRITE).store_string(Engine.get_license_text())
	FileAccess.open(dir+"/GODOT-THIRD-PARTY.json",FileAccess.WRITE).store_string(JSON.stringify({"copyright":Engine.get_copyright_info(),"licenses":Engine.get_license_info()},"\t"))
	print("Build metadata "+JSON.stringify(manifest))
	quit()
