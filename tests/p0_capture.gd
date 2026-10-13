extends SceneTree
## 通过真实 Compatibility 渲染器输出预览图；不截图或读取其他应用。

const MAIN: PackedScene = preload("res://scenes/main.tscn")


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var main: WildMain = MAIN.instantiate() as WildMain
	root.add_child(main)
	var output: String = "res://.godot/verification/p0-base.png"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-panel="):
			var station_id: String = argument.trim_prefix("--capture-panel=")
			main.session.submit(WildGameCommand.new(main.local_player_id, &"base.open_station", {"station_id": station_id}))
			output = "res://.godot/verification/p0-panel.png"
	for frame: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(output)
	if error != OK:
		printerr("Preview capture failed: ", error)
	quit(0 if error == OK else 1)
