extends SceneTree
## 真实图形预览，演示交易 / 装载仅写入隔离的工作区验证档案。

const MAIN: PackedScene = preload("res://scenes/main.tscn")


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var main: WildMain = MAIN.instantiate() as WildMain
	root.add_child(main)
	if main.session == null or main.session.base_snapshot(main.local_player_id).is_empty():
		quit(1)
		return
	for purchase: Dictionary in [{"definition_id": "axe"}, {"definition_id": "ration", "quantity": 4}, {"definition_id": "bandage", "quantity": 2}]:
		main.session.submit(WildGameCommand.new(main.local_player_id, &"shop.buy", purchase))
	var view: Dictionary = main.session.base_snapshot(main.local_player_id)
	for entry: Dictionary in view["containers"]["warehouse"]["entries"]:
		if entry["item"]["item_id"] in ["axe", "ration", "knife", "bottle"]:
			var current: Dictionary = main.session.base_snapshot(main.local_player_id)
			main.session.submit(WildGameCommand.new(main.local_player_id, &"inventory.transfer", {"source": "warehouse", "target": "backpack", "item_id": entry["item"]["id"], "source_version": current["containers"]["warehouse"]["version"], "target_version": current["containers"]["backpack"]["version"], "auto": true}))
	var panel: String = "storage"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-panel="):
			panel = argument.trim_prefix("--capture-panel=")
	main.session.submit(WildGameCommand.new(main.local_player_id, &"base.open_station", {"station_id": panel}))
	for frame: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png("res://.godot/verification/p1-%s.png" % panel)
	quit(0 if result == OK else 1)
