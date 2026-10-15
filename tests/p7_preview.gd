extends Control
## 图形预览严格注入随机工作区档案；画面来自实际 UI / 会话，路线实验另行运行。
const PATHS = preload("res://tests/verification_paths.gd")
var main: WildMain

func _ready() -> void:
	Engine.max_fps = 30
	_capture.call_deferred()

func _capture() -> void:
	if not PATHS.arguments_are_isolated(): get_tree().quit(1); return
	main = preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = PATHS.profile("p7-preview")
	assert(PATHS.isolated_path(main._profile_path))
	add_child(main)
	main._open_guide()
	await _frame("p7-guide")
	main.field_guide._select(2)
	await _frame("p7-recipes")
	main._close_station()
	main._open_station(&"expedition")
	await _frame("p7-departure")
	main._close_station()
	assert(main.session.submit(WildGameCommand.new(main.local_player_id,&"expedition.prepare",{"seed":"17"})).successful)
	assert(main.session.submit(WildGameCommand.new(main.local_player_id,&"expedition.commit")).successful)
	# 已授权的隔离显示夹具仅调整任务时刻，胜利仍由领域模拟和正式结算事务执行。
	var service: WildBaseService = main.session._base_services[main.local_player_id]
	service._state.survival.elapsed_seconds = main.CONFIG.target_survival_hours*3600-60
	assert(main.session.advance_world(main.local_player_id,0.5,"idle").successful)
	await _frame("p7-result")
	main._close_station()
	main.queue_free()
	await get_tree().process_frame
	var coop: WildFullCoopMain = preload("res://scenes/coop_full.tscn").instantiate() as WildFullCoopMain
	coop._profile_override = PATHS.profile("p7-coop-preview")
	coop._room_root = coop._profile_override.get_basename()+"_rooms"
	add_child(coop)
	coop._open_guide()
	coop.field_guide._select(6)
	await _frame("p7-coop-guide")
	print("P7 graphical preview: isolated guide / recipes / briefing / authoritative result / cooperation rules")
	await get_tree().create_timer(45).timeout
	get_tree().quit()

func _frame(title: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("res://.godot/verification/"+title+".png") == OK)
