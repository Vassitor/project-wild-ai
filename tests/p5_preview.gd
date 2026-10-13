extends Control
## MCP 图形夹具：完成实际配方后写随机工作区档案，技能初值与传送仅测试布置。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const F = preload("res://tests/p5_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")

func _ready() -> void:
	_capture.call_deferred()

func _build(state: WildBaseState, recipe: String, site: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"action":"build","recipe":recipe}
	payload.merge(site)
	assert(F.start(state,payload).successful)
	F.finish(state)
	for building: Dictionary in state.survival.buildings.values():
		if building["kind"] == recipe: return building
	return {}

func _capture() -> void:
	if not PATHS.arguments_are_isolated(): get_tree().quit(1); return
	var path: String = PATHS.profile("p5-preview")
	var actor: String = WildProfileIdentityStore.new(path).load_or_create().payload["player_id"]
	var state: WildBaseState = F.create_state(actor)
	for branch: String in WildSkillCatalog.BRANCHES:
		var tier: int = 2 if branch in ["building","cooking","logging"] else 1
		state.skills.levels[branch] = tier
		state.skills.spent_points[branch] = 3 if tier == 2 else 1
		state.skills.experience[branch] = 300
	var site: Dictionary = F.open_site(state,Vector2i(4,4))
	F.give(state,"wood",8)
	F.give(state,"fiber",6)
	var camp: Dictionary = _build(state,"camp",site)
	F.give(state,"wood",12)
	F.give(state,"rope",2)
	F.give(state,"hide",2)
	assert(F.start(state,{"action":"upgrade","building_id":camp["id"]}).successful)
	F.finish(state)
	var camp_position: Vector2 = state.world.players[actor]
	F.give(state,"wood",2)
	F.give(state,"stone",3)
	F.give(state,"flint")
	var fire: Dictionary = _build(state,"fire")
	assert(F.start(state,{"action":"light","building_id":fire["id"]}).successful)
	F.finish(state)
	F.give(state,"raw_fish")
	assert(F.start(state,{"action":"craft","recipe":"cooked_fish"}).successful)
	F.finish(state)
	var prey: Dictionary = state.survival.prey.values()[0]
	site = F.open_site(state,Vector2i.ONE,Vector2i(prey["x"],prey["y"]))
	F.give(state,"wood")
	F.give(state,"fiber",4)
	var trap: Dictionary = _build(state,"small_trap",site)
	var trap_position: Vector2 = state.world.players[actor]
	F.give(state,"berry",3)
	assert(F.start(state,{"action":"trap_bait","building_id":trap["id"],"quantity":3}).successful)
	F.finish(state)
	trap["trap_random_state"] = F.random_state_for(true,0.4)
	state.world.players[actor] = camp_position
	F.time(state,21600)
	assert(not trap["capture"].is_empty())
	assert(WildBaseStateStore.new(path.get_basename()+"_base.json").save_record(state.record()).successful)
	var main: WildMain = preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = path
	add_child(main)
	main.session.set_focus_lost(false)
	main._open_skills()
	await _frame("p5-skills")
	main._close_station()
	main._open_survival_options(main.session.survival_snapshot(actor)["buildings"][camp["id"]])
	await _frame("p5-camp")
	main._close_station()
	main.session._base_services[actor]._state.world.players[actor] = trap_position
	main.wilderness_world._update_position()
	main._open_survival_options(main.session.survival_snapshot(actor)["buildings"][trap["id"]])
	await _frame("p5-trap")
	main._close_station()
	main._open_station(&"storage")
	var id: String = WildInventoryOperations.choose(main.session._base_services[actor]._state,&"cooked_fish")
	main._base_panel._select_item("backpack",id)
	await _frame("p5-food")
	print("P5 graphical preview: isolated skill tree, upgraded camp, actual trap capture and chef food saved")
	await get_tree().create_timer(45,true).timeout
	get_tree().quit()

func _frame(label: String) -> void:
	for index: int in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/verification/%s.png" % label)
