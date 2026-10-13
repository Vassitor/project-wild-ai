extends SceneTree
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const FIXTURE = preload("res://tests/p4_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")
var passed: int = 0
var failed: int = 0
var main: WildMain

func _initialize() -> void:
	if not PATHS.arguments_are_isolated(): quit(1); return
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		push_error(label)

func buttons(parent: Node, text: String) -> Button:
	for child: Node in parent.get_children():
		if child is Button and child.text.begins_with(text): return child
		var found: Button = buttons(child,text)
		if found != null: return found
	return null

func _run() -> void:
	var path: String = PATHS.profile("p4-ui")
	var actor: String = WildProfileIdentityStore.new(path).load_or_create().payload["player_id"]
	var state: WildBaseState = FIXTURE.create_state(CONFIG,actor,WildWorldGenerator.new(CONFIG).generate("17").payload["world"])
	FIXTURE.give(state,&"bandage",CATALOG,CONFIG,2)
	FIXTURE.give(state,&"herbal_medicine",CATALOG,CONFIG,2)
	state.survival.bodies[actor].bleeding = true
	state.survival.bodies[actor].gastro_remaining_seconds = 43200
	state.survival.bodies[actor].weakness = true
	state.survival.bodies[actor].health = 60
	check(WildBaseStateStore.new(path.get_basename()+"_base.json").save_record(state.record()).successful,"isolated P4 UI save")
	main = preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = path
	root.add_child(main)
	main.session.set_focus_lost(false)
	await process_frame
	check(InputMap.has_action(&"body_details"),"H body input installed")
	main._open_body_details()
	check(main.body_details.visible and paused,"single body menu pauses")
	check(main.body_details._conditions.text.contains("出血") and main.body_details._conditions.text.contains("肠胃不适") and main.body_details._conditions.text.contains("衰弱"),"body symptoms visible")
	check(main.body_details._explanation.text.contains("体力恢复系数") and main.body_details._nutrition.text.contains("蛋白质"),"rates and nutrition explanations")
	var before: float = main.session.survival_snapshot(actor)["elapsed_seconds"]
	await create_timer(0.1,true).timeout
	check(main.session.survival_snapshot(actor)["elapsed_seconds"] == before,"paused body menu no time")
	main.body_details.care_requested.emit()
	check(main.survival_panel.visible and not main.body_details.visible,"care button opens common actions")
	var bandage: Button = buttons(main.survival_panel,"包扎出血")
	check(bandage != null,"bandage action available")
	bandage.pressed.emit()
	check(not paused and not main.survival_panel.visible,"treatment confirmation returns to simulation")
	check(main.session.survival_snapshot(actor)["action"].get("type","") == "treat","UI submits treatment intent")
	main.session.advance_world(actor,2.5,"idle")
	check(not main.session.player_snapshot(actor)["bleeding"],"UI treatment effective")
	main._open_body_details()
	check(not main.body_details._conditions.text.contains("出血"),"body panel reflects cured state")
	main._close_station()
	main.session.submit(WildGameCommand.new(actor,&"survival.abandon"))
	check(not main.body_details.visible and not main._details_button.visible,"return to base hides survival body controls")
	main._close_station()
	main.queue_free()
	await process_frame
	var room := WildENetRoom.new()
	root.add_child(room)
	var replica := WildCoopReplicaSession.new()
	replica.configure(room,"guest",CONFIG,CATALOG)
	room.latest = {"players":{"guest":{"body":state.survival.bodies[actor].snapshot("guest")}}}
	var details := WildBodyDetails.new()
	details.configure(replica)
	root.add_child(details)
	replica.submit(WildGameCommand.new("guest",&"base.open_pause"))
	details.open("guest")
	check(not paused and not replica.is_paused(),"cooperative body menu never pauses")
	check(details._explanation.text.contains("合作个人菜单持续推进"),"cooperative policy visible")
	room.latest["players"]["guest"]["body"]["gastro_remaining_seconds"] = 3600
	details.refresh()
	check(details._conditions.text.contains("剩余 1.0 h"),"cooperative live snapshots update illness")
	details.queue_free()
	room.queue_free()
	await process_frame
	print("P4 UI checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)
