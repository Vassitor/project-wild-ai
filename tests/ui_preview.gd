extends "res://tests/p5_preview.gd"
## 复用 P5 随机档案与实际配方夹具；另存 UI 预览，不覆盖阶段验收截图。

func _frame(label: String) -> void:
	var main: WildMain
	for child: Node in get_children():
		if child is WildMain: main = child
	await _capture_size(label.trim_prefix("p5-"),Vector2i(1280,720))
	if label in ["p5-skills","p5-food"]:
		await _capture_size(label.trim_prefix("p5-")+"-small",Vector2i(960,540))
		await _resize(Vector2i(1280,720))
	if label == "p5-food":
		main._close_station()
		await _capture_size("hud",Vector2i(1280,720))
		main._open_body_details()
		await _capture_size("body",Vector2i(1280,720))
		await _capture_size("body-small",Vector2i(960,540))
		main._close_station()
		assert(main.session.submit(WildGameCommand.new(main.local_player_id,&"survival.abandon")).successful)
		main._close_station()
		await _resize(Vector2i(1280,720))
		main._open_station(&"supply")
		await _capture_size("base",Vector2i(1280,720))
		await _capture_size("base-small",Vector2i(960,540))

func _resize(area: Vector2i) -> void:
	get_tree().root.content_scale_size = area
	get_tree().root.size = area
	for index: int in range(12): await get_tree().process_frame

func _capture_size(label: String, area: Vector2i) -> void:
	await _resize(area)
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("res://.godot/verification/ui-%s.png" % label) == OK)
