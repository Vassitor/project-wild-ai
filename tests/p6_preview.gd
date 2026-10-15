extends Control
## 随机工作区图形夹具；初值 / 位置仅用于布置，攻击、耗箭与伤害经真实规则。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const F = preload("res://tests/p6_fixtures.gd")
const P5 = preload("res://tests/p5_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")
var main: WildMain

func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	if not PATHS.arguments_are_isolated(): get_tree().quit(1); return
	var path: String = PATHS.profile("p6-preview")
	var actor: String = WildProfileIdentityStore.new(path).load_or_create().payload["player_id"]
	var state: WildBaseState = F.create(actor)
	var rabbit: Dictionary = F.focus(state)
	F.place(rabbit,state.world,Vector2i(rabbit["x"]+2,rabbit["y"]))
	state.skills.levels["hunting"] = 3
	F.equip(state,"bow")
	P5.give(state,"arrow",5)
	var origin: Vector2i = Vector2i(rabbit["x"],rabbit["y"])
	for kind: String in ["boar","wolf"]:
		for animal: Dictionary in state.survival.prey.values():
			if animal["kind"] != kind: continue
			F.place(animal,state.world,origin+Vector2i(3,1 if kind == "boar" else 2))
			animal["hp"] = animal["max_hp"]
			animal["alive"] = true
			animal["mode"] = "alert"
			animal["loot_claimed"] = false
			animal["ready_at"] = 12000.0
			break
	assert(WildBaseStateStore.new(path.get_basename()+"_base.json").save_record(state.record()).successful)
	main = preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = path
	add_child(main)
	main.session.set_focus_lost(false)
	main.set_process(false)
	main.set_physics_process(false)
	main._update_survival_hud()
	await _frame("p6-animals")
	assert(main.wilderness_world.request_attack(Vector2.RIGHT).successful)
	var service: WildBaseService = main.session._base_services[actor]
	main.session.advance_world(actor,0.1,"idle")
	# 图形夹具强制消化不足半秒的合法时间，使飞行过程能单独截帧；不改箭速或结果。
	WildSurvivalSimulation.process(service._state,CONFIG,CATALOG,preload("res://data/survival_content.tres"),true)
	main._refresh_world_content()
	main._update_survival_hud()
	await _frame("p6-arrow")
	main.session.advance_world(actor,0.5,"idle")
	main._update_survival_hud()
	await _frame("p6-hit")
	main._open_station(&"storage")
	await _frame("p6-loot")
	main._close_station()
	var wolf: Dictionary = {}
	for animal: Dictionary in service._state.survival.prey.values():
		if animal["kind"] == "wolf": wolf = animal; break
	var point: Vector2 = service._state.world.players[actor]
	wolf["px"] = point.x+24
	wolf["py"] = point.y
	wolf["x"] = service._state.world.cell_at(Vector2(wolf["px"],wolf["py"])).x
	wolf["y"] = service._state.world.cell_at(Vector2(wolf["px"],wolf["py"])).y
	wolf["target"] = actor
	wolf["mode"] = "chase"
	wolf["ready_at"] = service._state.survival.elapsed_seconds
	main.session.advance_world(actor,0.5,"idle")
	main._update_survival_hud()
	await _frame("p6-hurt")
	main._open_body_details()
	await _frame("p6-body")
	print("P6 graphical preview: isolated dynamic wildlife, actual arrow / hunting loot and animal injury")
	await get_tree().create_timer(45).timeout
	get_tree().quit()

func _frame(title: String) -> void:
	await get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("res://.godot/verification/"+title+".png") == OK)
