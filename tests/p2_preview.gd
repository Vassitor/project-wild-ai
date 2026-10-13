extends Control
## Godot MCP 可直接运行此场景进行图形检查。仅创建随机命名的工作区验证档案。

const MAIN: PackedScene = preload("res://scenes/main.tscn")

func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var main: WildMain = MAIN.instantiate() as WildMain
	main._profile_path = "res://.godot/verification/p2_preview_%s.cfg" % WildStableId.create("capture")
	add_child(main)
	if main.session == null:
		get_tree().quit(1)
		return
	main.session.set_focus_lost(false)
	await _save_frame("p2-base")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.open_station", {"station_id": "expedition"}))
	await _save_frame("p2-preparation")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"expedition.prepare", {"seed": "17"}))
	var result: WildOperationResult = main.session.submit(WildGameCommand.new(main.local_player_id, &"expedition.commit"))
	if not result.successful:
		push_error("Preview departure failed: %s" % result.code)
		get_tree().quit(1)
		return
	await _save_frame("p2-wilderness")
	# 使用真实权威移动逐格走到保证可达的泉水，不用任意位置写入绕过移动校验。
	var world: WildWorldData = WildWorldCodec.decode(main.session.world_snapshot(main.local_player_id), WildMain.CONFIG)
	var distances: Dictionary = world.distances(world.spawn, 12)
	var destination := Vector2i.ZERO
	for entry: Dictionary in world.resources.values():
		var cell := Vector2i(entry["x"], entry["y"])
		if entry["kind"] == "spring" and distances.has(cell):
			destination = cell
			break
	var path: Array[Vector2i] = [destination]
	while destination != world.spawn:
		for direction: Vector2i in WildWorldData.DIRECTIONS:
			var previous: Vector2i = destination + direction
			if distances.get(previous, 999999) == distances[destination] - 1:
				destination = previous
				path.append(destination)
				break
	path.reverse()
	for cell: Vector2i in path:
		var target: Vector2 = world.centre(cell)
		for step: int in range(10):
			var difference: Vector2 = target - main.session.world_position(main.local_player_id)
			if difference.length() < 0.01: break
			main.session.move_world_player(main.local_player_id, difference.normalized(), minf(difference.length() / 96.0, 0.1), false)
	main.wilderness_world._update_position()
	main.wilderness_world.request_interaction()
	await _save_frame("p2-resource")
	print("P2 graphical preview: preparation, wilderness, resource saved; isolated profile")
	# 留出 MCP 读取调试输出的窗口，之后自动退出，不持续占用调试进程。
	await get_tree().create_timer(12.0, true).timeout
	get_tree().quit()

func _save_frame(title: String) -> void:
	for frame: int in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png("res://.godot/verification/%s.png" % title)
	if error != OK:
		push_error("Preview save failed: %s" % title)
