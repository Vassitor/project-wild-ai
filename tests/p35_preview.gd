extends Control
const FIXTURES = preload("res://tests/p35_fixtures.gd")
const VERIFICATION = preload("res://tests/verification_paths.gd")
## MCP 图形验证使用随机工作区身份 / 房间，第二角色是明确的显示夹具。
## 真实双进程通信由 p35_network.tscn 验证，此场景仅检查 UI / 动画。
var ui: WildCoopMain

func _ready() -> void:
	if not VERIFICATION.arguments_are_isolated():
		push_error("Preview requires workspace verification paths")
		get_tree().quit(1)
		return
	_capture.call_deferred()

func _capture() -> void:
	ui = preload("res://scenes/coop.tscn").instantiate() as WildCoopMain
	ui._profile_override = "res://.godot/verification/p35-preview-"+WildStableId.create("capture")+".cfg"
	ui._room_path = ui._profile_override.get_basename()+"-room.json"
	add_child(ui)
	ui.network.bind_address = "127.0.0.1"
	ui._port.value = 41000+randi()%10000
	ui._seed.text = "17"
	ui._name_input.text = "房主"
	await _frame("p35-lobby")
	ui._host(false)
	assert(ui.network.authority != null,"preview host setup")
	var service: WildCoopService = ui.network.authority
	assert(service.join("preview-guest","队友","").successful,"preview member fixture")
	ui.network.request("room.start",{})
	await get_tree().create_timer(0.2).timeout
	var actor: String = ui.network.actor_id
	var host_point: Vector2 = service.state.world.players[actor]
	for offset: Vector2 in [Vector2(24,0),Vector2(-24,0),Vector2(0,24)]:
		if WildWorldRules.feet_clear(service.state.world,host_point+offset):
			service.state.world.players["preview-guest"] = host_point+offset
			break
	assert(service.submit(actor,{"room_id":service.state.room_id,"run_id":service.state.run_id,"request_id":"preview-camp","operation":"survival.start","payload":{"action":"build","recipe":"camp"}}).successful,"preview domain camp")
	WildSurvivalSimulation.queue_time(service.state.survival,3600,"idle")
	service._simulate(service.state,true)
	var box_site: WildOperationResult = FIXTURES.box_site(service.state.members[actor],actor)
	assert(box_site.successful,"preview box site")
	assert(service.submit(actor,{"room_id":service.state.room_id,"run_id":service.state.run_id,"request_id":"preview-box","operation":"survival.start","payload":{"action":"build","recipe":"storage_box","x":box_site.payload["x"],"y":box_site.payload["y"]}}).successful,"preview domain box")
	WildSurvivalSimulation.queue_time(service.state.survival,1800,"idle")
	service._simulate(service.state,true)
	service.checkpoint()
	ui.network._broadcast(true)
	await _frame("p35-world")
	assert(ui.world_view._remote_explorers.size() == 1,"one remote avatar")
	ui._open_inventory()
	await _frame("p35-inventory")
	ui._close_menus()
	ui._open_actions(service.state.survival.buildings.values()[0])
	await _frame("p35-actions")
	print("P3.5 graphical preview: lobby, two avatars, private inventory / public box, cooperative actions")
	await get_tree().create_timer(45).timeout
	await ui._leave()
	get_tree().quit()

func _frame(title: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	assert(frame.save_png("res://.godot/verification/"+title+".png") == OK)
