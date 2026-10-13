extends SceneTree
## 真实渲染的动画预览；四方向输入只控制随机隔离的基地角色，不打开正式档案。

const MAIN: PackedScene = preload("res://scenes/main.tscn")

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var main: WildMain = MAIN.instantiate() as WildMain
	main._profile_path = "res://.godot/verification/ninja_capture_%s.cfg" % WildStableId.create("capture")
	root.add_child(main)
	if main.session == null:
		quit(1)
		return
	main.session.set_focus_lost(false)
	var index: int = 0
	for action: StringName in [&"move_right", &"move_up", &"move_left", &"move_down"]:
		Input.action_press(action)
		for frame: int in range(5):
			await create_timer(0.1).timeout
			await RenderingServer.frame_post_draw
			var result: Error = root.get_texture().get_image().save_png("res://.godot/verification/ninja-motion-%02d.png" % index)
			if result != OK:
				quit(1)
				return
			index += 1
		Input.action_release(action)
	print("Ninja animated preview: 20 real gameplay frames saved; isolated profile")
	quit()
