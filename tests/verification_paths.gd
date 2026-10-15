extends RefCounted
## 验证脚本内部也保证隔离，不依赖调用者记得传命令行参数。
static func profile(prefix: String) -> String:
	return "res://.godot/verification/%s_%s.cfg" % [prefix,WildStableId.create("test")]

static func isolated_path(path: String) -> bool:
	return path.begins_with("res://.godot/verification/") and not path.contains("..") and not path.contains("\\")

static func arguments_are_isolated() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--profile-store=") or argument.begins_with("--base-store=") or argument.begins_with("--coop-profile=") or argument.begins_with("--coop-room=") or argument.begins_with("--profile=") or argument.begins_with("--case-root="):
			var path: String = argument.substr(argument.find("=")+1)
			if not isolated_path(path): return false
	return true
