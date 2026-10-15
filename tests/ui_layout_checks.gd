extends SceneTree
## 在独立逻辑视口中验证菜单边界、滚动空间与缩放后输入保留。只用随机工作区档案。
const PATHS = preload("res://tests/verification_paths.gd")
const F = preload("res://tests/p5_fixtures.gd")
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

func settle() -> void:
	for index: int in range(12): await process_frame

func fits(control: Control, bounds: Rect2) -> bool:
	var rect: Rect2 = control.get_global_rect()
	return bounds.grow(1).encloses(rect)

func menu_fits(panel: Control, area: Vector2, label: String) -> void:
	check(fits(panel,Rect2(Vector2.ZERO,area)),label+" panel stays in viewport: "+str(panel.get_global_rect()))
	# 滚动区至少保留三行可阅读内容；不能让标题 / 页脚挤空正文。
	var scrolls: Array[Node] = panel.find_children("*","ScrollContainer",true,false)
	check(not scrolls.is_empty() and (scrolls[0] as Control).size.y >= 140,label+" scroll body remains usable")
	for child: Node in panel.find_children("*","Button",true,false):
		if not (child as Control).is_visible_in_tree(): continue
		var ancestor: Node = child.get_parent()
		var in_scroll: bool = false
		while ancestor != panel and ancestor != null:
			if ancestor is ScrollContainer: in_scroll = true; break
			ancestor = ancestor.get_parent()
		if not in_scroll: check(fits(child,panel.get_global_rect()),label+" footer button "+child.text)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var path: String = PATHS.profile("ui-layout")
	var main: WildMain = preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = path
	viewport.add_child(main)
	main.session.set_focus_lost(false)
	for area: Vector2i in [Vector2i(1280,720),Vector2i(960,540),Vector2i(1600,900)]:
		viewport.size = area
		await settle()
		main._open_station(&"supply")
		await settle()
		menu_fits(main._base_panel,area,"base "+str(area))
		main._base_panel._seed_input.text = "4321"
		main._base_panel._schedule_refresh()
		await settle()
		check(main._base_panel._seed_input.text == "4321","seed survives presentation rebuild")
		main._close_station()
		main._open_skills()
		await settle()
		menu_fits(main.skill_panel,area,"skills "+str(area))
		check(paused,"single menu retains pause behavior")
		main._close_station()
	# 生存菜单使用已有 P5 隔离状态，绕过装载夹具但不绕过界面 / 会话。
	var actor: String = main.local_player_id
	var state: WildBaseState = F.create_state(actor)
	main.session._base_services[actor]._state = state
	main._on_base_state_changed()
	for area: Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900)]:
		viewport.size = area
		await settle()
		check(fits(main._body_panel,Rect2(Vector2.ZERO,area)),"vitals fit "+str(area))
		main._open_survival_options()
		await settle()
		menu_fits(main.survival_panel,area,"actions "+str(area))
		main._close_station()
		main._open_body_details()
		await settle()
		menu_fits(main.body_details,area,"body "+str(area))
		main._close_station()
	main.queue_free()
	await settle()
	var coop: WildCoopMain = preload("res://scenes/coop.tscn").instantiate() as WildCoopMain
	coop._profile_override = PATHS.profile("ui-layout-coop")
	coop._room_path = coop._profile_override.get_basename()+"-room.json"
	viewport.add_child(coop)
	for area: Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900)]:
		viewport.size = area
		await settle()
		menu_fits(coop._lobby,area,"coop lobby "+str(area))
		check(fits(coop._top_panel,Rect2(Vector2.ZERO,area)),"coop header fit "+str(area))
		check(coop._top_panel.get_global_rect().end.y <= coop._lobby.position.y,"coop header does not cover lobby")
		check(coop._lobby.get_global_rect().end.y <= coop._bottom_panel.position.y,"lobby does not cover toolbar")
		check(fits(coop._bottom_panel,Rect2(Vector2.ZERO,area)),"coop toolbar fit "+str(area))
		for child: Node in coop._bottom_panel.find_children("*","Button",true,false):
			check(fits(child,Rect2(Vector2.ZERO,area)),"coop toolbar "+child.text)
	coop.network.bind_address = "127.0.0.1"
	coop._port.value = 41000+randi()%10000
	coop._seed.text = "17"
	coop._host(false)
	check(coop.network.authority != null,"layout fixture has isolated loopback host")
	if coop.network.authority != null:
		assert(coop.network.authority.join("layout-guest","队友","").successful)
		coop._start_run()
		await settle()
		for area: Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900)]:
			viewport.size = area
			coop._open_inventory()
			await settle()
			menu_fits(coop._inventory,area,"coop inventory "+str(area))
			check(not paused and not coop.session.is_paused(),"coop menu keeps simulation active")
			coop._close_menus()
		await coop._leave()
	coop.queue_free()
	await settle()
	print("UI layout checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)
