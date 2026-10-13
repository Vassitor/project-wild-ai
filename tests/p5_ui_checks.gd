extends SceneTree
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const F = preload("res://tests/p5_fixtures.gd")
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

func button(parent: Node, match_value: String, by_name: bool = false) -> Button:
	for child: Node in parent.get_children():
		if child is Button and (str(child.name) == match_value if by_name else child.text.begins_with(match_value)): return child
		var found: Button = button(child,match_value,by_name)
		if found != null: return found
	return null

func _run() -> void:
	var path: String = PATHS.profile("p5-ui")
	var actor: String = WildProfileIdentityStore.new(path).load_or_create().payload["player_id"]
	var state := WildBaseState.new(actor,CONFIG)
	state.skills.experience["gathering"] = 100
	check(WildBaseStateStore.new(path.get_basename()+"_base.json").save_record(state.record()).successful,"isolated skill UI save")
	var main: WildMain = preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = path
	root.add_child(main)
	main.session.set_focus_lost(false)
	await process_frame
	check(InputMap.has_action(&"skills"),"K installed")
	main._open_station(&"training")
	check(main.skill_panel.visible and paused and not main._modal.visible,"training station opens actual skill tree")
	check(button(main.skill_panel,"trap_1_train",true) != null and button(main.skill_panel,"healing_3_train",true) != null,"all branches / tiers have controls")
	check(button(main.skill_panel,"trap_2_train",true).disabled,"unmet prerequisite disabled")
	var train: Button = button(main.skill_panel,"trap_1_train",true)
	train.pressed.emit()
	check(main.session.base_snapshot(actor)["currency"] == 300 and main.session.base_snapshot(actor)["skills"]["levels"]["trap"] == 1,"training button submits paid learning")
	train.pressed.emit()
	check(main.session.base_snapshot(actor)["currency"] == 300,"old button repeated learning no money loss")
	button(main.skill_panel,"gathering_1_points",true).pressed.emit()
	check(main.session.base_snapshot(actor)["skills"]["points"]["gathering"] == 0 and main.session.base_snapshot(actor)["skills"]["levels"]["gathering"] == 1,"point button spends corresponding branch point")
	main._close_station()
	check(not paused and not main.skill_panel.visible,"skill close unpauses single player")
	check(main.session.submit(WildGameCommand.new(actor,&"shop.buy",{"definition_id":"fishing_kit","quantity":1})).successful,"normal shop provides fishing kit")
	check(main.session.submit(WildGameCommand.new(actor,&"supply.claim")).successful,"free essentials available after legacy empty warehouse fixture")
	check(main.session.submit(WildGameCommand.new(actor,&"expedition.prepare",{"seed":"17"})).successful,"skill and expedition coexist")
	var view: Dictionary = main.session.base_snapshot(actor)
	var ids: Array[String] = []
	for entry: Dictionary in view["containers"]["warehouse"]["entries"]: ids.append(entry["item"]["id"])
	for id: String in ids:
		view = main.session.base_snapshot(actor)
		check(main.session.submit(WildGameCommand.new(actor,&"inventory.transfer",{"source":"warehouse","target":"backpack","item_id":id,"source_version":view["containers"]["warehouse"]["version"],"target_version":view["containers"]["backpack"]["version"],"auto":true})).successful,"loadout item "+id)
	check(main.session.submit(WildGameCommand.new(actor,&"expedition.commit")).successful,"enter survival with learned skills")
	state = main.session._base_services[actor]._state
	F.give(state,"fiber",3)
	var fish: Dictionary = F.at_resource(state,"fish")
	state.survival.fishing_random_states[actor] = F.random_state_for(true,0.6)
	main._open_survival_options(fish)
	var fish_button: Button = button(main.survival_panel,"捕鱼 · 纤维饵")
	check(fish_button != null and not fish_button.disabled,"actual fishing control available")
	check(button(main.survival_panel,"双份捕鱼").disabled,"unlearned double fishing visible locked")
	fish_button.pressed.emit()
	check(not paused and main.session.survival_snapshot(actor)["action"].get("type","") == "fish","fish UI resumes and starts authoritative action")
	main.session.advance_world(actor,15,"idle")
	check(main.session.base_snapshot(actor)["skills"]["experience"]["fishing"] == 8,"fishing completion updates skill UI source")
	main._open_skills()
	check(main.skill_panel.visible and button(main.skill_panel,"fishing_1_train",true) == null,"wilderness tree cannot spend base currency")
	main._close_station()
	state = main.session._base_services[actor]._state
	var root_resource: Dictionary = F.at_resource(state,"root")
	main._open_survival_options(root_resource)
	check(main.survival_panel._body.get_children().size() > 0,"plant skill explanation page renders")
	check(button(main.survival_panel,"小套索") != null and not button(main.survival_panel,"小套索").disabled,"learned trap visible available")
	check(button(main.survival_panel,"大型陷阱").disabled and button(main.survival_panel,"制造 炖食").disabled,"advanced recipe locks visible")
	main._close_station()
	check(main.session.submit(WildGameCommand.new(actor,&"survival.abandon")).successful,"failed return through normal flow")
	main._close_station()
	main._open_skills()
	check(main.session.base_snapshot(actor)["skills"]["levels"]["trap"] == 1 and main.session.base_snapshot(actor)["skills"]["experience"]["fishing"] == 8,"UI after loss retains permanent growth")
	main._close_station()
	main.queue_free()
	await process_frame
	var network := WildENetRoom.new()
	root.add_child(network)
	var replica := WildCoopReplicaSession.new()
	replica.configure(network,"guest",CONFIG,CATALOG)
	var personal := WildBaseState.new("guest",CONFIG)
	network.latest = {"skills":WildSkillRules.snapshot(personal.skills,CONFIG.skill_rules),"currency":600,"can_train":true}
	var panel := WildSkillPanel.new()
	panel.configure(replica,CONFIG)
	root.add_child(panel)
	replica.submit(WildGameCommand.new("guest",&"base.open_pause"))
	panel.open("guest")
	check(not paused and not replica.is_paused(),"cooperative skill menu never pauses")
	check(button(panel,"trap_1_train",true) != null,"lobby independent currency learning controls")
	network.latest["can_train"] = false
	panel.refresh()
	check(button(panel,"trap_1_train",true) == null,"cooperative money learning closes after departure")
	var terminal_seen: Dictionary = {"result":0,"ended":0,"code":""}
	network.command_completed.connect(func(_request: String, result: WildOperationResult) -> void:
		terminal_seen["result"] += 1
		terminal_seen["code"] = str(result.code))
	network.room_ended.connect(func() -> void: terminal_seen["ended"] += 1)
	network._pending["terminal-case"] = {}
	var terminal: Dictionary = {"type":"ended","receipts":{"terminal-case":{"type":"result","request_id":"terminal-case","successful":true,"code":"OK","payload":{}}}}
	network._accept_packet(terminal)
	check(network._pending.is_empty() and terminal_seen["result"] == 1 and terminal_seen["code"] == "OK","terminal receipt resolves lost operation result")
	network._accept_packet(terminal)
	check(terminal_seen["result"] == 1 and terminal_seen["ended"] == 1,"repeated ending receipt idempotent")
	network._terminal_received = false
	network._pending["unknown-terminal"] = {}
	network._accept_packet({"type":"ended","receipts":{}})
	check(terminal_seen["code"] == "ROOM_ENDED_PENDING" and network._pending.is_empty(),"unknown terminal outcome explicitly resolved instead of pending forever")
	panel.queue_free()
	network.queue_free()
	await process_frame
	print("P5 UI checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)
