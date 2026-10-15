extends "res://tests/p35_preview.gd"
## 复用回环房主和显示队友夹具，检查合作菜单缩放；截图单独保存。

func _frame(label: String) -> void:
	await _capture_size(label.trim_prefix("p35-"),Vector2i(1280,720))
	if label in ["p35-lobby","p35-inventory"]:
		await _capture_size(label.trim_prefix("p35-")+"-small",Vector2i(960,540))
		await _resize(Vector2i(1280,720))

func _resize(area: Vector2i) -> void:
	get_tree().root.content_scale_size = area
	get_tree().root.size = area
	for index: int in range(12): await get_tree().process_frame

func _capture_size(label: String, area: Vector2i) -> void:
	await _resize(area)
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("res://.godot/verification/ui-coop-%s.png" % label) == OK)
