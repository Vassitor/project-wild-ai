extends SceneTree
## 无人工输入的默认速度自动驾驶；每个种子独立进程、独立工作区结果。
const PATHS = preload("res://tests/verification_paths.gd")
func _initialize() -> void:
	Engine.max_fps = 30
	if not PATHS.arguments_are_isolated(): quit(1); return
	_run.call_deferred()

func _run() -> void:
	var seed_text: String = "17"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): seed_text = argument.trim_prefix("--seed=")
	if seed_text not in ["17","18","7936","15855","31693"]: quit(1); return
	var journey: Node = load("res://tests/p8_realtime_journey.gd").new()
	root.add_child(journey)
	var began: int = Time.get_ticks_msec()
	var state: WildBaseState = await journey.run(seed_text)
	var wall: float = (Time.get_ticks_msec()-began)/1000.0
	var won: bool = state != null and journey.failure.is_empty() and state.survival.outcome == "won"
	var data: Dictionary = {"seed":seed_text,"won":won,"failure":journey.failure,"wall_seconds":wall,"active_game_seconds":journey.active_game_seconds,"sleep_game_seconds":journey.sleep_game_seconds,"default_clock":120,"scope":"30 FPS headless automatic driver, actual frame delta, only legal sleep skips; not manual playtest"}
	if state != null:
		data["elapsed_seconds"] = state.survival.elapsed_seconds
		data["hp"] = state.survival.bodies["p"].hp
		won = won and absf(data["elapsed_seconds"]-604800)<0.01 and wall+0.2 >= data["active_game_seconds"]/120
	FileAccess.open("res://.godot/verification/p8-realtime-"+seed_text+".json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	print("P8 realtime journey "+JSON.stringify(data))
	journey.queue_free()
	quit(0 if won else 1)
