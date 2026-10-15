extends SceneTree
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const F = preload("res://tests/p6_fixtures.gd")
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
	var path: String = PATHS.profile("p6-ui")
	var actor: String = WildProfileIdentityStore.new(path).load_or_create().payload["player_id"]
	var state: WildBaseState = F.create(actor)
	var animal: Dictionary = F.focus(state)
	F.equip(state,"knife")
	state.skills.levels["hunting"] = 2
	check(WildBaseStateStore.new(path.get_basename()+"_base.json").save_record(state.record()).successful,"isolated combat scene record")
	var main: WildMain = preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = path
	root.add_child(main)
	main.session.set_focus_lost(false)
	await process_frame
	check(main.wilderness_world.visible and main.wilderness_world._prey.size() == 29,"actual world displays dynamic species")
	check(InputMap.has_action(&"attack"),"LMB attack binding installed")
	check(main.wilderness_world.request_attack(Vector2.RIGHT).successful,"world UI submits directional intent")
	var service: WildBaseService = main.session._base_services[actor]
	check(service.world_dynamic()["prey"][animal["id"]]["hp"] == 6,"UI authority applies weapon damage")
	check(not main.wilderness_world._feedback.is_empty(),"actual hit feedback reaches renderer")
	check(main.wilderness_world.request_attack(Vector2.RIGHT).code == &"ATTACK_COOLDOWN","UI cooldown explains rejected repeat")
	main._open_skills()
	check(paused and main.skill_panel.visible,"single skill menu pauses combat")
	var hp: float = service.world_dynamic()["prey"][animal["id"]]["hp"]
	main.session.advance_world(actor,2,"idle")
	check(service.world_dynamic()["prey"][animal["id"]]["hp"] == hp,"paused session does not simulate attacks")
	check(not main.wilderness_world.request_attack(Vector2.RIGHT).successful,"menu blocks attack intent")
	main._close_station()
	check(not paused,"closing menu resumes")
	main._inspect_resource(service.world_dynamic()["prey"][animal["id"]])
	check(main.survival_panel.visible and paused,"actual animal E inspect opens health / tracking")
	main._close_station()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var before: float = service.snapshot()["containers"]["main_hand"]["entries"][0]["item"]["durability"]
	main._unhandled_input(click)
	check(service.snapshot()["containers"]["main_hand"]["entries"][0]["item"]["durability"] == before,"actual LMB dispatch respects cooldown")
	check(not main.wilderness_world._prey[animal["id"]].has("random_state"),"display lacks future AI RNG")
	main.session.submit(WildGameCommand.new(actor,&"survival.abandon"))
	check(not main.wilderness_world.visible,"return clears combat world")
	main.queue_free()
	await process_frame
	print("P6 UI checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)
