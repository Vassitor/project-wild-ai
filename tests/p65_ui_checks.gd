extends SceneTree
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const PATHS = preload("res://tests/verification_paths.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	if not PATHS.arguments_are_isolated(): quit(1); return
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		push_error(label)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var main: WildFullCoopMain = preload("res://scenes/coop_full.tscn").instantiate() as WildFullCoopMain
	var profile_path: String = PATHS.profile("p65-ui")
	assert(PATHS.isolated_path(profile_path))
	# 直接注入与 SceneTree 导航交接同时约束，测试路径不能回退到正式档案。
	main._profile_override = profile_path
	set_meta("profile_scene_handoff",{"profile":profile_path,"base":profile_path.get_basename()+"_base.json"})
	main._room_root = profile_path.get_basename()+"_rooms"
	viewport.add_child(main)
	await process_frame
	check(main.profile != null and main.network.full_cooperation,"actual full scene opens isolated personal profile")
	check(main._identity_path == profile_path and PATHS.isolated_path(main.profile_store._path) and not has_meta("profile_scene_handoff"),"scene handoff consumes same isolated profile / base path")
	check(main._lobby.visible and main._rooms != null,"room selection and lobby")
	check(main.network.content_fingerprint.length() == 64,"content compatibility fingerprint")
	main._open_preparation(&"supply")
	check(main.preparation_panel.visible and main.preparation_panel.cooperation_preparation,"actual shop / personal grids with cooperative footer")
	check(not paused,"preparation panel does not pause tree")
	main._open_preparation_skills()
	check(main.preparation_skills.visible,"personal permanent learning before departure")
	main._close_menus()
	check(not main.preparation_panel.visible and not main.preparation_skills.visible,"Esc closes local preparation")
	check(main.profile_link.reserve_and_offer().code == &"NOT_CONNECTED" and not WildCoopProfileRules.blocked(main.profile._state),"offline click cannot lock new escrow")
	var actor: String = main.network.actor_id
	var service := WildFullCoopService.new(CONFIG,CATALOG,CONTENT,func(_raw: Dictionary,_backup: bool) -> WildOperationResult: return WildOperationResult.accept())
	check(service.create(actor,"房主","17","secret").successful,"isolated full UI room")
	check(service.join("other","队友","").successful,"UI second member")
	for owner: String in service.state.members:
		var profile := WildBaseState.new(owner,CONFIG)
		var lease: WildOperationResult = WildCoopProfileRules.execute(profile,"coop.reserve",{"room_id":service.state.room_id,"run_id":service.state.run_id},CONFIG,CATALOG)
		check(WildCoopLifecycle.offer(service.state,owner,{"manifest":lease.payload["manifest"]},CONFIG,CATALOG).successful,"UI accepted lease")
		service.state.lifecycle["ready"][owner] = true
	service.online["other"] = true
	check(WildCoopLifecycle.start(service.state,service.online,CONFIG).successful,"UI start loading")
	main.network.latest = service.snapshot(actor,true)
	main.session._on_snapshot(main.network.latest)
	main._on_snapshot(main.network.latest)
	check(main.world_view.visible and not main._loaded_key.is_empty(),"actual renderer validates / loads scaled map")
	check(main._ready_button.disabled,"loading cannot change ready")
	service.state.lifecycle["phase"] = "running"
	var frame_probe := WildENetRoom.new()
	frame_probe.full_cooperation = true
	frame_probe.authority = service
	service.state.survival.bodies[actor].hp = 0.001
	check(frame_probe._position_frame()["compact_players"][actor][2] > 0,"compact body frame cannot quantize a living actor to death")
	service.state.survival.bodies[actor].hp = 100
	frame_probe.free()
	_prediction_and_channels(service,actor)
	check(service.apply_world_damage(actor,1000,"physical").successful,"UI own death fixture")
	main.network.latest = service.snapshot(actor,true)
	main.session._on_snapshot(main.network.latest)
	main._on_snapshot(main.network.latest)
	main.world_view._update_position()
	check(not main.world_view.explorer.visible and main.world_view._spectator == "other","death hides own sprite / follows living teammate")
	check(main.world_view._corpses.has(actor),"corpse marker rendered from snapshot")
	main._open_inventory()
	check(main._inventory.visible and not paused,"actual private inventory keeps co-op unpaused")
	main._close_menus()
	main._process(0.016)
	check(main._hud.text.contains("观战"),"HUD explains spectating")
	viewport.size = Vector2i(960,540)
	for tick: int in range(12): await process_frame
	for tick: int in range(12): await process_frame
	check(main._bottom_panel.get_global_rect().end.y <= 541 and main._bottom_panel.position.y >= 110,"small window toolbar stays in viewport")
	for row: Control in [main._bottom_panel.get_child(0).get_child(1),main._wild_controls]:
		for button: Control in row.get_children():
			if button.visible: check(button.get_global_rect().end.x <= 961 and button.get_global_rect().end.y <= 541,"wrapped action remains reachable: "+str(button.get("text"))+" "+str(button.get_global_rect()))
	main._lobby.visible = true
	check(main._lobby.get_global_rect().end.y <= main._bottom_panel.position.y,"small lobby does not cover toolbar")
	main._remember_profile()
	var base_main: WildMain = preload("res://scenes/main.tscn").instantiate() as WildMain
	viewport.add_child(base_main)
	await process_frame
	check(base_main.local_player_id == main.network.actor_id and base_main._base_store._path == main.profile_store._path,"return to single scene keeps exact profile and save path")
	base_main.queue_free()
	main.queue_free()
	viewport.queue_free()
	await process_frame
	print("P6.5 UI checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _prediction_and_channels(service: WildFullCoopService, actor: String) -> void:
	var network := WildENetRoom.new()
	network.full_cooperation = true
	var replica := WildCoopReplicaSession.new()
	replica.configure(network,actor,CONFIG,CATALOG)
	var sample: Dictionary = service.snapshot(actor,true)
	sample.merge({"type":"state","revision":100,"frame_sequence":10,"input_ack":0},true)
	network._accept_packet(sample)
	var encoded: PackedByteArray = var_to_bytes(sample)
	var compressed: PackedByteArray = encoded.compress(FileAccess.COMPRESSION_DEFLATE)
	print("P6.5 snapshot encoding: %d raw bytes / %d DEFLATE bytes" % [encoded.size(),compressed.size()])
	check(compressed.size() < encoded.size()/2,"full state snapshot compresses below half original payload")
	network._snapshot_blob(compressed)
	check(network.latest["world"]["resource_players"] == service.state.members.size(),"bounded compressed snapshot restores actual authoritative state")
	var initial: Vector2 = replica.world_position(actor)
	replica.move_world_player(actor,Vector2.RIGHT,0.05,false)
	check(replica.world_position(actor).x > initial.x,"local movement predicts before roundtrip")
	var frame: Dictionary = {"type":"frame","revision":101,"frame_sequence":12,"input_ack":1,"elapsed_seconds":0.0,"pending_seconds":0.0,"players":{}}
	for owner: String in sample["players"]:
		frame["players"][owner] = {"position":[initial.x+4,initial.y],"body":{"health_points":99.0,"health":100.0,"hydration":100.0,"stamina":100.0}}
	network._accept_packet(frame)
	check(replica.world_position(actor) == initial+Vector2(4,0) and replica._prediction_steps.is_empty(),"host input ACK reconciles predicted movement")
	var delayed: Dictionary = sample.duplicate(true)
	delayed["currency"] = 777
	delayed["frame_sequence"] = 11
	network._accept_packet(delayed)
	check(network.latest["currency"] == 777 and network.latest["revision"] == 101,"reliable state can arrive after a newer position frame")
	check(replica.world_position(actor) == initial+Vector2(4,0) and network.latest["players"][actor]["body"]["health_points"] == 99,"late reliable state cannot roll back current position / immediate body")
	network.free()
