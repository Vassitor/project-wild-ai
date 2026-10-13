extends Control
## 隔离图形验证：伤病由测试布置，不代表动物攻击已经实现。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const FIXTURE = preload("res://tests/p4_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")

func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	if not PATHS.arguments_are_isolated(): get_tree().quit(1); return
	var path: String = PATHS.profile("p4-preview")
	var actor: String = WildProfileIdentityStore.new(path).load_or_create().payload["player_id"]
	var state: WildBaseState = FIXTURE.create_state(CONFIG,actor,WildWorldGenerator.new(CONFIG).generate("17").payload["world"])
	FIXTURE.give(state,&"bandage",CATALOG,CONFIG,2)
	FIXTURE.give(state,&"herbal_medicine",CATALOG,CONFIG,2)
	var body: WildBodyState = state.survival.bodies[actor]
	body.hp = 68
	body.health = 62
	body.water = 28
	body.stamina = 35
	body.nutrition.assign([42.0,35.0,28.0,19.0,26.0])
	body.bleeding = true
	body.weakness = true
	body.gastro_remaining_seconds = 36000
	body.pollution = 55
	WildIllnessRules.synchronize(body,CONFIG.health_rules)
	WildBaseStateStore.new(path.get_basename()+"_base.json").save_record(state.record())
	var main: WildMain = preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = path
	add_child(main)
	main.session.set_focus_lost(false)
	main._open_body_details()
	await _frame("p4-body")
	main.body_details.care_requested.emit()
	await _frame("p4-medical")
	main._close_station()
	main._open_body_details()
	print("P4 graphical preview: isolated body and medical screens saved")
	await get_tree().create_timer(45,true).timeout
	get_tree().quit()

func _frame(label: String) -> void:
	for index: int in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/verification/%s.png" % label)
