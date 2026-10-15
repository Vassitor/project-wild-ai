extends Control
## 图形显示夹具：只使用随机工作区身份；四进程真实通信由 p65_network 单独验证。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const PATHS = preload("res://tests/verification_paths.gd")
var main: WildFullCoopMain
var service: WildFullCoopService

func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	if not PATHS.arguments_are_isolated(): get_tree().quit(1); return
	main = preload("res://scenes/coop_full.tscn").instantiate() as WildFullCoopMain
	main._profile_override = PATHS.profile("p65-preview")
	main._room_root = main._profile_override.get_basename()+"_rooms"
	add_child(main)
	await _frame("p65-lobby")
	main._open_preparation(&"supply")
	await _frame("p65-preparation")
	main._close_menus()
	var actor: String = main.network.actor_id
	service = WildFullCoopService.new(CONFIG,CATALOG,CONTENT,func(_raw: Dictionary,_backup: bool) -> WildOperationResult: return WildOperationResult.accept())
	assert(service.create(actor,"林间旅人","17","secret").successful)
	for member: String in ["队友-青松","队友-落叶","队友-溪流"]: assert(service.join(member,member,"").successful)
	for member: String in service.state.members:
		var personal := WildBaseState.new(member,CONFIG)
		var manifest: WildOperationResult = WildCoopProfileRules.execute(personal,"coop.reserve",{"room_id":service.state.room_id,"run_id":service.state.run_id},CONFIG,CATALOG)
		assert(WildCoopLifecycle.offer(service.state,member,{"manifest":manifest.payload["manifest"]},CONFIG,CATALOG).successful)
		service.state.lifecycle["ready"][member] = true
	assert(WildCoopLifecycle.start(service.state,service.online,CONFIG).successful)
	service.state.lifecycle["phase"] = "running"
	main.network.latest = service.snapshot(actor,true)
	main.session._on_snapshot(main.network.latest)
	main._on_snapshot(main.network.latest)
	main._set_status("图形显示夹具 · 四人 / 死亡 / 尸体视图；真实 ENet 验证单独运行。")
	await _frame("p65-four-players")
	assert(service.apply_world_damage("队友-溪流",1000,"environment").successful)
	main.network.latest = service.snapshot(actor,true)
	main.session._on_snapshot(main.network.latest)
	main._on_snapshot(main.network.latest)
	main._set_status("显示夹具 · 队友死亡后留下尸体，无复活；靠近尸体按 E 或 Tab 取物。")
	await _frame("p65-corpse")
	assert(service.apply_world_damage(actor,1000,"environment").successful)
	main.network.latest = service.snapshot(actor,true)
	main.session._on_snapshot(main.network.latest)
	main._on_snapshot(main.network.latest)
	main._set_status("显示夹具 · 自己死亡后观战，切换观战只改变相机，不能代队友操作。")
	await _frame("p65-spectating")
	print("P6.5 graphical preview: isolated personal preparation / four members / corpses / spectating display fixtures")
	await get_tree().create_timer(45).timeout
	get_tree().quit()

func _frame(title: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("res://.godot/verification/"+title+".png") == OK)
