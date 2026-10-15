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
	var main: WildMain = preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = PATHS.profile("p7-ui")
	assert(PATHS.isolated_path(main._profile_path))
	viewport.add_child(main)
	await process_frame
	check(PATHS.isolated_path(main._base_store._path),"actual UI uses only isolated save")
	var before: String = WildCanonicalData.digest(main.session.base_snapshot(main.local_player_id))
	main._open_guide()
	check(main.field_guide.visible and paused,"single guide follows menu pause policy")
	check(main.field_guide.pages.size() == 8,"all eight actionable handbook sections")
	for index: int in range(main.field_guide.pages.size()):
		main.field_guide._select(index)
		check(not main.field_guide.text_view.text.is_empty(),"guide section renders: "+str(index))
	check(before == WildCanonicalData.digest(main.session.base_snapshot(main.local_player_id)),"reading guide cannot change inventory / money / growth")
	var recipes: String = main.field_guide.pages[2]["text"]
	check(recipes.contains("炖食") and recipes.contains("生鱼或生肉") and recipes.contains("清水 0.25 L"),"advanced recipe requirements are visible")
	check(main.field_guide.pages[3]["text"].contains("300 / 600 / 1200"),"training costs derive from config")
	main._close_station()
	check(not main.field_guide.visible and not paused,"closing guide resumes single play")
	main._open_station(&"expedition")
	await process_frame
	check(_labels(main._base_panel).contains("没有件数上限"),"departure checklist accessible at expedition station")
	main._open_guide()
	check(not main._base_panel.visible and main.field_guide.visible,"guide replaces other modal")
	main._close_station()
	viewport.size = Vector2i(960,540)
	main._open_guide()
	for tick: int in range(8): await process_frame
	check(Rect2(Vector2.ZERO,Vector2(960,540)).encloses(main.field_guide.get_global_rect()),"handbook fits 960x540")
	main.field_guide._select(2)
	check(main.field_guide.text_view.scroll_active and not main.field_guide.text_view.fit_content,"long recipe reference scrolls within fixed panel")
	main._close_station()
	main._open_station(&"expedition")
	for tick: int in range(8): await process_frame
	check(main._base_panel.get_global_rect().end.y <= 540,"briefing footer stays in small viewport")
	main._close_station()
	check(WildExpeditionText.countdown(0,CONFIG) == "距返航 7 日 00:00","initial exact seven day countdown")
	check(WildExpeditionText.countdown(CONFIG.target_survival_hours*3600-1,CONFIG) == "距返航 0 日 00:01","countdown rounds up before actual victory")
	check(WildExpeditionText.countdown(CONFIG.target_survival_hours*3600+1,CONFIG) == "距返航 0 日 00:00","countdown never negative")
	var legacy: Dictionary = {"run_id":"old","won":true,"reason":"存活到期","reward":600,"elapsed_seconds":604800,"pending_count":1}
	var display: String = WildExpeditionText.result(legacy,CONFIG)
	check(display.contains("600") and display.contains("待领取") and not display.contains("基础 600"),"legacy summary readable without fabricating breakdown")
	check(main.session.submit(WildGameCommand.new(main.local_player_id,&"expedition.prepare",{"seed":"17"})).successful,"single result fixture prepares")
	check(main.session.submit(WildGameCommand.new(main.local_player_id,&"expedition.commit")).successful,"single result fixture enters actual world")
	main.session._base_services[main.local_player_id]._state.survival.elapsed_seconds = CONFIG.target_survival_hours*3600-60
	check(main.session.advance_world(main.local_player_id,0.5,"idle").successful,"single authoritative deadline settlement")
	for tick: int in range(8): await process_frame
	check(main._modal.visible and main._modal_description.text.contains("基础 600 + 探索"),"single result opens real detailed reward")
	check(Rect2(Vector2.ZERO,Vector2(960,540)).encloses(main._modal.get_global_rect()),"long single result cannot expand beyond viewport")
	check(main._modal_close.get_global_rect().end.y <= 540,"result continue button remains reachable")
	main._close_station()
	main.queue_free()
	await process_frame
	var coop: WildFullCoopMain = preload("res://scenes/coop_full.tscn").instantiate() as WildFullCoopMain
	coop._profile_override = PATHS.profile("p7-coop-ui")
	coop._room_root = coop._profile_override.get_basename()+"_rooms"
	viewport.add_child(coop)
	await process_frame
	check(PATHS.isolated_path(coop.profile_store._path),"cooperative UI isolated profile")
	coop._open_guide()
	check(coop.field_guide.visible and not paused,"cooperative guide accessible before connection and never pauses")
	check(coop.field_guide.pages[0]["text"].contains("合作个人菜单不暂停"),"mode-specific reading warning")
	coop._close_menus()
	coop._open_preparation(&"supply")
	await process_frame
	check(_labels(coop.preparation_panel).contains("没有件数上限"),"cooperative preparation shares briefing")
	coop._open_guide()
	check(not coop.preparation_panel.visible and coop.field_guide.visible,"cooperative handbook replaces preparation")
	coop._layout_ui()
	for tick: int in range(8): await process_frame
	check(coop.field_guide.get_global_rect().end.y <= 540,"cooperative handbook fits small viewport")
	coop._close_menus()
	check(not coop.field_guide.visible and not paused,"cooperative close keeps world running")
	var actor: String = coop.network.actor_id
	var host := WildFullCoopService.new(CONFIG,CATALOG,CONTENT,func(_data: Dictionary,_backup: bool) -> WildOperationResult: return WildOperationResult.accept())
	check(host.create(actor,"host","17","secret").successful and host.join("other","guest","").successful,"cooperative result UI fixture")
	for member: String in host.state.members:
		var personal: WildBaseState = coop.profile._state.copy(CONFIG) if member == actor else WildBaseState.new(member,CONFIG)
		var lease: WildOperationResult = coop.profile.submit(WildGameCommand.new(actor,&"coop.reserve",{"room_id":host.state.room_id,"run_id":host.state.run_id})) if member == actor else WildCoopProfileRules.execute(personal,"coop.reserve",{"room_id":host.state.room_id,"run_id":host.state.run_id},CONFIG,CATALOG)
		check(WildCoopLifecycle.offer(host.state,member,lease.payload,CONFIG,CATALOG).successful,"result fixture personal offer")
		host.state.lifecycle["ready"][member] = true
	check(WildCoopLifecycle.start(host.state,host.online,CONFIG).successful,"result fixture departure")
	host.state.lifecycle["phase"] = "running"
	host.state.survival.elapsed_seconds = CONFIG.target_survival_hours*3600
	host.state.survival.outcome = "won"
	WildCoopLifecycle.reconcile(host.state,CONFIG,CATALOG)
	for event: Dictionary in WildCoopDeliveries.pending(host.state,actor):
		check(coop.profile.submit(WildGameCommand.new(actor,&"coop.apply_event",event)).successful,"result UI receives actual personal event")
	coop.network.latest = host.snapshot(actor,true)
	coop.session._on_snapshot(coop.network.latest)
	coop._process(0)
	check(coop.field_guide.visible and coop.field_guide.text_view.text.contains("基础 600 + 探索"),"confirmed cooperative result opens detailed summary automatically")
	coop._close_menus()
	coop._process(0)
	check(not coop.field_guide.visible,"same result frame cannot reopen closed summary")
	for code: StringName in [&"INSUFFICIENT_STAMINA",&"LEASE_CLOSED",&"UNKNOWN_LEASE",&"MATERIAL_RESERVED",&"WRONG_ROOM_MODE"]:
		check(not WildErrorMessages.describe(code).begins_with("操作未能完成"),"actionable interaction reason: "+str(code))
	coop.queue_free()
	viewport.queue_free()
	await process_frame
	print("P7 UI checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _labels(node: Node) -> String:
	var text: String = node.text if node is Label else ""
	for child: Node in node.get_children(): text += "\n"+_labels(child)
	return text
